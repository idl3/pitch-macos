import AVFAudio
import CoreAudio
import AudioToolbox
import Darwin
import Foundation
import SwiftUI
import TPCircularBuffer

struct OutputDevice: Identifiable, Hashable {
    let audioID: AudioDeviceID
    let uid: String
    let name: String
    var id: AudioDeviceID { audioID }
}

enum PitchControlMode: String, CaseIterable {
    case semitones = "Semitones"
    case cents = "Cents"
}

enum VocalRemovalMode: String, CaseIterable {
    case off = "Off"
    case monoCut = "Mono cut"
    case karaoke = "Karaoke"
    case wide = "Wide"
}

/// Lock-protected parameters read from the real-time audio render thread.
final class AudioParameters: @unchecked Sendable {
    private let lock = NSLock()
    private var _volume: Float = 1.0
    private var _vocalRemovalMode: String = VocalRemovalMode.off.rawValue

    var volume: Float {
        lock.lock()
        defer { lock.unlock() }
        return _volume
    }

    func setVolume(_ value: Float) {
        lock.lock()
        _volume = value
        lock.unlock()
    }

    var vocalRemovalMode: VocalRemovalMode {
        lock.lock()
        defer { lock.unlock() }
        return VocalRemovalMode(rawValue: _vocalRemovalMode) ?? .off
    }

    func setVocalRemovalMode(_ value: VocalRemovalMode) {
        lock.lock()
        _vocalRemovalMode = value.rawValue
        lock.unlock()
    }
}

@MainActor
final class PitchSystemAudio: ObservableObject {
    static let shared = PitchSystemAudio()
    @Published var isEnabled = false
    @Published var pitchCents: Float = 0 {
        didSet { timePitch?.pitch = pitchCents }
    }
    @Published var pitchSemitones: Int = 0 {
        didSet {
            if pitchControlMode == .semitones {
                pitchCents = Float(pitchSemitones) * 100
            }
        }
    }
    @Published var pitchControlMode: PitchControlMode = .semitones {
        didSet { syncPitchForMode() }
    }
    @Published var volume: Float = 1.0 {
        didSet { audioParams.setVolume(volume) }
    }
    @Published var vocalRemovalMode: VocalRemovalMode = .off {
        didSet { audioParams.setVocalRemovalMode(vocalRemovalMode) }
    }
    @Published var outputDevices: [OutputDevice] = []
    @Published var selectedOutputID: AudioDeviceID? = nil {
        didSet { if selectedOutputID != oldValue { applySelectedOutput() } }
    }
    @Published var statusText = ""

    private var engine: AVAudioEngine?
    private var timePitch: AVAudioUnitTimePitch?
    private var sourceNode: AVAudioSourceNode?
    private var ringBuffer: RingBuffer?
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var asbd = AudioStreamBasicDescription()
    private let ioQueue = DispatchQueue(label: "codes.ernest.tonos.io", qos: .userInteractive)
    private let ringCapacity = UInt32(1 << 19)
    private let audioParams = AudioParameters()
    private var deviceListener: AudioObjectPropertyListenerBlock?

    init() {
        refreshOutputDevices()
        startListeningForDeviceChanges()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            do {
                try setup()
                try engine?.start()
                isEnabled = true
                statusText = ""
            } catch {
                cleanup()
                statusText = "Error: \(error.localizedDescription)"
                isEnabled = false
            }
        } else {
            cleanup()
            isEnabled = false
            statusText = ""
        }
    }

    func refreshOutputDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        guard sizeStatus == noErr, size > 0 else { outputDevices = []; return }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        guard status == noErr else { outputDevices = []; return }

        var devices: [OutputDevice] = []
        for id in ids {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            let streamStatus = AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize)
            guard streamStatus == noErr, streamSize >= MemoryLayout<AudioBufferList>.size else { continue }
            let name = deviceString(for: id, selector: kAudioObjectPropertyName)
            let uid = deviceString(for: id, selector: kAudioDevicePropertyDeviceUID)
            devices.append(OutputDevice(audioID: id, uid: uid, name: name))
        }
        outputDevices = devices
    }

    private func deviceString(for id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        guard status == noErr, let result = value?.takeRetainedValue() else { return "Unknown" }
        return result as String
    }

    private func applySelectedOutput() {
        guard let id = selectedOutputID else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &deviceID)
        if err != noErr {
            statusText = "Could not set output (\(err))"
            return
        }
        if isEnabled {
            setEnabled(false)
            setEnabled(true)
        }
    }

    private func startListeningForDeviceChanges() {
        guard deviceListener == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshOutputDevices()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
        if status == noErr {
            deviceListener = listener
        }
    }

    private func stopListeningForDeviceChanges() {
        guard let listener = deviceListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            listener
        )
        deviceListener = nil
    }

    private func syncPitchForMode() {
        switch pitchControlMode {
        case .semitones:
            pitchSemitones = Int(round(pitchCents / 100))
        case .cents:
            break
        }
    }

    private func setup() throws {
        guard #available(macOS 14.2, *) else {
            throw NSError(domain: "PitchSystem", code: -1, userInfo: [NSLocalizedDescriptionKey: "Requires macOS 14.2+"])
        }

        // 1. Tap everything except this process to avoid feedback.
        let ownPID = getpid()
        let excludeIDs = processObjectID(for: ownPID).map { [$0] } ?? []
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludeIDs)
        let tapUUID = UUID()
        tapDescription.uuid = tapUUID
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true
        tapDescription.name = "Tonos Tap"

        var newTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard tapStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(tapStatus))
        }
        tapID = newTapID

        // 2. Read the tap's stream format.
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &formatSize, &asbd)
        guard formatStatus == noErr, asbd.mSampleRate > 0, asbd.mChannelsPerFrame > 0 else {
            throw NSError(domain: "PitchSystem", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read tap format"])
        }

        // 3. Tap-only aggregate device (HFP / sample-rate-change safe).
        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tonos Aggregate",
            kAudioAggregateDeviceUIDKey: "codes.ernest.tonos.tap.\(tapUUID.uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ] as [String: Any]
            ]
        ]
        var newAggregateID: AudioObjectID = 0
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDesc as CFDictionary, &newAggregateID)
        guard aggregateStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(aggregateStatus))
        }
        aggregateID = newAggregateID

        // 4. Build AVAudioEngine: source node -> time pitch -> output.
        engine = AVAudioEngine()
        guard let engine else {
            throw NSError(domain: "PitchSystem", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create engine"])
        }

        let sampleRate = asbd.mSampleRate
        let channels = asbd.mChannelsPerFrame
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            throw NSError(domain: "PitchSystem", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create audio format"])
        }

        timePitch = AVAudioUnitTimePitch()
        timePitch?.pitch = pitchCents
        timePitch?.rate = 1.0
        timePitch?.overlap = 32

        ringBuffer = RingBuffer(capacity: ringCapacity)
        guard let ring = ringBuffer else {
            throw NSError(domain: "PitchSystem", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate ring buffer"])
        }

        let bytesPerFrame = channels * 4

        sourceNode = AVAudioSourceNode(format: format) { [ring, audioParams] silence, time, frameCount, outputData -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(outputData)
            guard list.count >= Int(channels) else { return noErr }
            let left = list[0].mData?.assumingMemoryBound(to: Float.self)
            let right = list[1].mData?.assumingMemoryBound(to: Float.self)
            guard let left, let right else { return noErr }

            var availableBytes: UInt32 = 0
            guard let tail = TPCircularBufferTail(&ring.buffer, &availableBytes) else {
                memset(left, 0, Int(frameCount) * MemoryLayout<Float>.size)
                memset(right, 0, Int(frameCount) * MemoryLayout<Float>.size)
                silence.pointee = false
                return noErr
            }

            let availableFrames = availableBytes / bytesPerFrame
            let framesToCopy = min(frameCount, availableFrames)
            let copyBytes = framesToCopy * bytesPerFrame
            let src = tail.assumingMemoryBound(to: Float.self)
            let vocalMode = audioParams.vocalRemovalMode
            let gain = audioParams.volume
            for i in 0..<Int(framesToCopy) {
                let l = src[i * 2]
                let r = src[i * 2 + 1]
                let (vl, vr): (Float, Float)
                switch vocalMode {
                case .off:
                    vl = l
                    vr = r
                case .monoCut:
                    // Output the stereo-difference signal to both channels.
                    // This strongly removes centered content (vocals/bass) and yields a mono result.
                    let diff = (l - r) * 0.5
                    vl = diff
                    vr = diff
                case .karaoke:
                    // Left-minus-right / right-minus-left keeps a sense of stereo while canceling center.
                    let diff = (l - r) * 0.5
                    vl = diff
                    vr = -diff
                case .wide:
                    // Partial subtraction: reduce centered vocals while preserving more stereo field.
                    vl = l - r * 0.5
                    vr = r - l * 0.5
                }
                left[i] = vl * gain
                right[i] = vr * gain
            }
            TPCircularBufferConsume(&ring.buffer, copyBytes)

            if framesToCopy < frameCount {
                let zeroFrames = frameCount - framesToCopy
                memset(left.advanced(by: Int(framesToCopy)), 0, Int(zeroFrames) * MemoryLayout<Float>.size)
                memset(right.advanced(by: Int(framesToCopy)), 0, Int(zeroFrames) * MemoryLayout<Float>.size)
            }
            silence.pointee = false
            return noErr
        }

        engine.attach(sourceNode!)
        engine.attach(timePitch!)
        engine.connect(sourceNode!, to: timePitch!, format: format)
        engine.connect(timePitch!, to: engine.mainMixerNode, format: format)

        // 5. Feed the ring buffer from the aggregate IOProc.
        let ioBlock: AudioDeviceIOBlock = { [ring] _, inInputData, _, _, _ in
            guard inInputData.pointee.mNumberBuffers > 0 else { return }
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer<AudioBufferList>(mutating: inInputData))
            for buffer in list {
                guard let data = buffer.mData else { continue }
                _ = ring.write(data, length: buffer.mDataByteSize)
            }
        }

        var procID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue, ioBlock)
        guard ioStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(ioStatus))
        }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(startStatus))
        }

        engine.prepare()
    }

    private func cleanup() {
        guard #available(macOS 14.2, *) else { return }
        if let procID = ioProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
        }
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
        engine?.stop()
        engine = nil
        sourceNode = nil
        timePitch = nil
        ringBuffer = nil
    }

    private func processObjectID(for pid: pid_t) -> AudioObjectID? {
        guard #available(macOS 14.2, *) else { return nil }
        var pid = pid
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var objectID: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &objectID)
        return err == noErr ? objectID : nil
    }
}
