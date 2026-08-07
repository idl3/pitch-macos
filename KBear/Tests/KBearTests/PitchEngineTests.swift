import XCTest
import AVFoundation

final class PitchEngineTests: XCTestCase {
    func testPitchShiftUpOneOctave() throws {
        let sampleRate: Double = 44100
        let inputFreq: Double = 440
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        let engine = AVAudioEngine()
        let timePitch = AVAudioUnitTimePitch()
        timePitch.pitch = 1200
        timePitch.rate = 1.0

        let source = AVAudioSourceNode(format: format) { _, time, frames, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            guard list.count >= 2,
                  let left = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = list[1].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let sampleTime = time.pointee.mSampleTime
            for i in 0..<Int(frames) {
                let t = (sampleTime + Double(i)) / sampleRate
                let value = Float(sin(2.0 * .pi * inputFreq * t))
                left[i] = value
                right[i] = value
            }
            return noErr
        }

        engine.attach(source)
        engine.attach(timePitch)
        engine.connect(source, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        let needed = Int(sampleRate * 2)
        var samples: [Float] = []

        while samples.count < needed {
            let status = try engine.renderOffline(4096, to: buffer)
            guard status == .success else { break }
            guard let left = buffer.floatChannelData?[0] else { break }
            for i in 0..<Int(buffer.frameLength) {
                samples.append(left[i])
            }
        }

        engine.stop()

        XCTAssertGreaterThan(samples.count, needed / 2, "Not enough samples rendered")

        let skip = min(8192, samples.count / 4)
        let signal = Array(samples[skip...])
        let measured = PitchEngineTests.estimateFrequency(signal, sampleRate: sampleRate)

        XCTAssertEqual(measured, inputFreq * 2.0, accuracy: 20.0,
                      "Expected ~\(inputFreq * 2.0) Hz after 1200 cent pitch shift, got \(measured) Hz")
    }

    private static func estimateFrequency(_ samples: [Float], sampleRate: Double) -> Double {
        let minLag = max(1, Int(sampleRate / 1200))
        let maxLag = Int(sampleRate / 200)
        var bestLag = minLag
        var maxCorr: Float = -Float.infinity

        var previous = samples[0]
        var zeroCrossings = 0
        for sample in samples.dropFirst() {
            if (previous < 0 && sample >= 0) || (previous >= 0 && sample < 0) {
                zeroCrossings += 1
            }
            previous = sample
        }

        let duration = Double(samples.count) / sampleRate
        let zeroCrossFreq = Double(zeroCrossings) / (2.0 * duration)

        for lag in minLag...maxLag {
            var corr: Float = 0
            for i in 0..<(samples.count - lag) {
                corr += samples[i] * samples[i + lag]
            }
            if corr > maxCorr {
                maxCorr = corr
                bestLag = lag
            }
        }

        let autocorrFreq = sampleRate / Double(bestLag)

        return (zeroCrossFreq + autocorrFreq) / 2.0
    }
}
