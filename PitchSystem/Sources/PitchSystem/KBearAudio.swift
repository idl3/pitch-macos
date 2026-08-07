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

enum PitchControlMode: String, CaseIterable, Codable {
    case semitones = "Semitones"
    case cents = "Cents"
}

enum VocalRemovalMode: String, CaseIterable, Codable {
    case off = "Off"
    case mono = "Mono"
    case wide = "Wide"
    case karaoke = "Karaoke"
    case aggressive = "Aggressive"
    case custom = "Custom"
}

struct SongPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var pitchEnabled: Bool
    var pitchSemitones: Int
    var pitchCents: Float
    var pitchControlMode: PitchControlMode
    var removeVocalsEnabled: Bool
    var volume: Float
    var vocalRemovalMode: VocalRemovalMode
    var vocalMono: Float
    var vocalKaraoke: Float
    var dualMonoOutput: Bool
}

/// Lock-protected parameters read from the real-time audio render thread.
final class AudioParameters: @unchecked Sendable {
    private let lock = NSLock()
    private var _volume: Float = 1.0
    private var _vocalMono: Float = 0.0
    private var _vocalKaraoke: Float = 0.0
    private var _dualMonoOutput: Bool = false

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

    var vocalMono: Float {
        lock.lock()
        defer { lock.unlock() }
        return _vocalMono
    }

    var vocalKaraoke: Float {
        lock.lock()
        defer { lock.unlock() }
        return _vocalKaraoke
    }

    var dualMonoOutput: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _dualMonoOutput
    }

    func setVocalBlend(mono: Float, karaoke: Float) {
        lock.lock()
        _vocalMono = mono
        _vocalKaraoke = karaoke
        lock.unlock()
    }

    func setDualMonoOutput(_ value: Bool) {
        lock.lock()
        _dualMonoOutput = value
        lock.unlock()
    }
}

@MainActor
final class KBearAudio: ObservableObject {
    static let shared = KBearAudio()
    @Published var pitchEnabled: Bool = false {
        didSet { updatePitch(); updateEngine() }
    }
    @Published var pitchCents: Float = 0 {
        didSet { updatePitch() }
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
    @Published var removeVocalsEnabled: Bool = false {
        didSet {
            if removeVocalsEnabled {
                if vocalRemovalMode == .off { vocalRemovalMode = .mono }
            } else {
                vocalRemovalMode = .off
            }
            updateEngine()
        }
    }
    @Published var volume: Float = 1.0 {
        didSet { audioParams.setVolume(volume) }
    }
    @Published var vocalRemovalMode: VocalRemovalMode = .off {
        didSet {
            guard !isUpdatingVocalBlend else { return }
            applyVocalRemovalMode(vocalRemovalMode)
        }
    }
    @Published var vocalMono: Float = 0.0 {
        didSet {
            guard !isUpdatingVocalBlend else { return }
            audioParams.setVocalBlend(mono: vocalMono, karaoke: vocalKaraoke)
            markVocalRemovalModeCustomIfNeeded()
        }
    }
    @Published var vocalKaraoke: Float = 0.0 {
        didSet {
            guard !isUpdatingVocalBlend else { return }
            audioParams.setVocalBlend(mono: vocalMono, karaoke: vocalKaraoke)
            markVocalRemovalModeCustomIfNeeded()
        }
    }
    @Published var dualMonoOutput: Bool = true {
        didSet { audioParams.setDualMonoOutput(dualMonoOutput) }
    }
    @Published var outputDevices: [OutputDevice] = []
    @Published var selectedOutputID: AudioDeviceID? = nil {
        didSet { if selectedOutputID != oldValue { applySelectedOutput() } }
    }
    @Published var statusText = ""
    @Published var presets: [SongPreset] = []
    @Published var selectedPresetID: UUID? = nil
    @Published var newPresetName: String = ""

    var permissionPromptHandler: (() -> Void)?
    var permissionGrantedHandler: (() -> Void)?

    private var engine: AVAudioEngine?
    private var timePitch: AVAudioUnitTimePitch?
    private var sourceNode: AVAudioSourceNode?
    private var ringBuffer: RingBuffer?
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var asbd = AudioStreamBasicDescription()
    private let ioQueue = DispatchQueue(label: "codes.ernest.kbear.io", qos: .userInteractive)
    private let ringCapacity = UInt32(1 << 19)
    private let audioParams = AudioParameters()
    private var isUpdatingVocalBlend = false
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private let presetsKey = "codes.ernest.kbear.presets"
    private var isEngineRunning = false
    private var permissionCheckTimer: Timer?
    private var permissionPollAttempts = 0

    init() {
        loadPresets()
        refreshOutputDevices()
        startListeningForDeviceChanges()
    }

    private func updatePitch() {
        timePitch?.pitch = pitchEnabled ? pitchCents : 0
    }

    private func updateEngine() {
        let shouldRun = pitchEnabled || removeVocalsEnabled
        guard shouldRun != isEngineRunning else { return }
        if shouldRun {
            guard requestAudioPermissionIfNeeded() else {
                statusText = "Allow Screen & System Audio Recording to use KBear"
                return
            }
            do {
                try setup()
                try engine?.start()
                isEngineRunning = true
                statusText = ""
            } catch {
                cleanup()
                isEngineRunning = false
                statusText = "Error: \(error.localizedDescription)"
            }
        } else {
            cleanup()
            isEngineRunning = false
            statusText = ""
        }
    }

    private func requestAudioPermissionIfNeeded() -> Bool {
        if #available(macOS 11.0, *) {
            if CGPreflightScreenCaptureAccess() { return true }
            guard permissionCheckTimer == nil else { return false }
            permissionPromptHandler?()
            CGRequestScreenCaptureAccess()
            startPermissionPoll()
            return false
        }
        return true
    }

    private func startPermissionPoll() {
        permissionCheckTimer?.invalidate()
        permissionPollAttempts = 0
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPermissionPoll()
            }
        }
    }

    private func checkPermissionPoll() {
        if #available(macOS 11.0, *) {
            if CGPreflightScreenCaptureAccess() {
                permissionCheckTimer?.invalidate()
                permissionCheckTimer = nil
                permissionPollAttempts = 0
                statusText = ""
                permissionGrantedHandler?()
                updateEngine()
                return
            }
        }
        permissionPollAttempts += 1
        if permissionPollAttempts >= 60 {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
            permissionPollAttempts = 0
            statusText = "Permission not granted. Enable in System Settings → Privacy & Security."
        }
    }

    func restartEngineIfNeeded() {
        restartEngine()
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
        if isEngineRunning {
            restartEngine()
        }
    }

    private func restartEngine() {
        if isEngineRunning {
            cleanup()
            isEngineRunning = false
        }
        updateEngine()
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

    // MARK: - Vocal removal blend

    private func applyVocalRemovalMode(_ mode: VocalRemovalMode) {
        isUpdatingVocalBlend = true
        switch mode {
        case .off:
            vocalMono = 0
            vocalKaraoke = 0
        case .mono:
            vocalMono = 1
            vocalKaraoke = 0
        case .wide:
            vocalMono = 0.25
            vocalKaraoke = 0.75
        case .karaoke:
            vocalMono = 0
            vocalKaraoke = 1
        case .aggressive:
            // Mostly karaoke with just enough mono mix to stay audible on mono downmixes.
            vocalMono = 0.2
            vocalKaraoke = 1
        case .custom:
            break
        }
        audioParams.setVocalBlend(mono: vocalMono, karaoke: vocalKaraoke)
        isUpdatingVocalBlend = false
    }

    private func markVocalRemovalModeCustomIfNeeded() {
        if vocalRemovalMode == .custom || vocalRemovalMode == .off { return }
        let (expectedMono, expectedKaraoke) = blendForMode(vocalRemovalMode)
        let tolerance: Float = 0.01
        if abs(vocalMono - expectedMono) <= tolerance && abs(vocalKaraoke - expectedKaraoke) <= tolerance {
            return
        }
        vocalRemovalMode = .custom
    }

    private func blendForMode(_ mode: VocalRemovalMode) -> (Float, Float) {
        switch mode {
        case .off: return (0, 0)
        case .mono: return (1, 0)
        case .wide: return (0.25, 0.75)
        case .karaoke: return (0, 1)
        case .aggressive: return (0.2, 1)
        case .custom: return (vocalMono, vocalKaraoke)
        }
    }

    // MARK: - Song presets

    func savePreset(name: String) {
        guard !name.isEmpty else { return }
        let preset = SongPreset(
            id: UUID(),
            name: name,
            pitchEnabled: pitchEnabled,
            pitchSemitones: pitchSemitones,
            pitchCents: pitchCents,
            pitchControlMode: pitchControlMode,
            removeVocalsEnabled: removeVocalsEnabled,
            volume: volume,
            vocalRemovalMode: vocalRemovalMode,
            vocalMono: vocalMono,
            vocalKaraoke: vocalKaraoke,
            dualMonoOutput: dualMonoOutput
        )
        if let index = presets.firstIndex(where: { $0.name == name }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        storePresets()
    }

    func loadPreset(_ preset: SongPreset) {
        pitchEnabled = preset.pitchEnabled
        pitchControlMode = preset.pitchControlMode
        pitchCents = preset.pitchCents
        pitchSemitones = preset.pitchSemitones
        removeVocalsEnabled = preset.removeVocalsEnabled
        volume = preset.volume
        vocalRemovalMode = preset.vocalRemovalMode
        vocalMono = preset.vocalMono
        vocalKaraoke = preset.vocalKaraoke
        dualMonoOutput = preset.dualMonoOutput
        selectedPresetID = preset.id
    }

    func deletePreset(_ preset: SongPreset) {
        presets.removeAll { $0.id == preset.id }
        if selectedPresetID == preset.id { selectedPresetID = nil }
        storePresets()
    }

    private func storePresets() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: presetsKey)
    }

    private func loadPresets() {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let decoded = try? JSONDecoder().decode([SongPreset].self, from: data) else {
            presets = []
            return
        }
        presets = decoded
    }

    private func setup() throws {
        guard #available(macOS 14.2, *) else {
            throw NSError(domain: "KBear", code: -1, userInfo: [NSLocalizedDescriptionKey: "Requires macOS 14.2+"])
        }

        // 1. Tap everything except this process to avoid feedback.
        let ownPID = getpid()
        let excludeIDs = processObjectID(for: ownPID).map { [$0] } ?? []
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludeIDs)
        let tapUUID = UUID()
        tapDescription.uuid = tapUUID
        tapDescription.muteBehavior = .mutedWhenTapped
        tapDescription.isPrivate = true
        tapDescription.name = "KBear Tap"

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
            throw NSError(domain: "KBear", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read tap format"])
        }

        // 3. Tap-only aggregate device (HFP / sample-rate-change safe).
        let aggregateDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "KBear Aggregate",
            kAudioAggregateDeviceUIDKey: "codes.ernest.kbear.tap.\(tapUUID.uuidString)",
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
            throw NSError(domain: "KBear", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create engine"])
        }

        let sampleRate = asbd.mSampleRate
        let channels = asbd.mChannelsPerFrame
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else {
            throw NSError(domain: "KBear", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create audio format"])
        }

        timePitch = AVAudioUnitTimePitch()
        timePitch?.pitch = pitchCents
        timePitch?.rate = 1.0
        timePitch?.overlap = 32

        ringBuffer = RingBuffer(capacity: ringCapacity)
        guard let ring = ringBuffer else {
            throw NSError(domain: "KBear", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate ring buffer"])
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
            let mono = audioParams.vocalMono
            let karaoke = audioParams.vocalKaraoke
            let total = mono + karaoke
            let dualMono = audioParams.dualMonoOutput
            let blendScale = total > 1.0 ? (1.0 / total) : 1.0
            let gain = audioParams.volume
            for i in 0..<Int(framesToCopy) {
                let l = src[i * 2]
                let r = src[i * 2 + 1]
                let side = (l - r) * 0.5

                // Blend a mono side signal and a karaoke (out-of-phase right) side signal.
                // total > 1 is normalized so the left channel never exceeds the original side amplitude.
                var leftSample = (mono + karaoke) * blendScale * side
                var rightSample = (mono - karaoke) * blendScale * side

                if total <= .leastNormalMagnitude {
                    leftSample = l
                    rightSample = r
                }

                // Dual mono forces both channels to the same vocal-removed signal,
                // fixing left-leaning blends and mono-downmix cancellation.
                if dualMono {
                    rightSample = leftSample
                }

                left[i] = leftSample * gain
                right[i] = rightSample * gain
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
