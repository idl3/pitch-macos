import XCTest
@testable import KBearLib

final class VocalRemovalTests: XCTestCase {
    func testPassthroughWhenDisabled() {
        let params = VocalBlendParameters(mono: 0, karaoke: 0, dualMono: false, volume: 1.0)
        let out = processStereoSample(l: 0.5, r: -0.3, params: params)
        XCTAssertEqual(out.left, 0.5, accuracy: 1e-5)
        XCTAssertEqual(out.right, -0.3, accuracy: 1e-5)
    }

    func testMonoCutCancelsCenter() {
        // A centered vocal is identical in both channels.
        let params = VocalBlendParameters(mono: 1.0, karaoke: 0.0, dualMono: false, volume: 1.0)
        let out = processStereoSample(l: 0.5, r: 0.5, params: params)
        XCTAssertEqual(out.left, 0.0, accuracy: 1e-5)
        XCTAssertEqual(out.right, 0.0, accuracy: 1e-5)
    }

    func testKaraokeKeepsStereoDifference() {
        // Left-only signal: l=1, r=0. Karaoke should keep side signal in both channels.
        let params = VocalBlendParameters(mono: 0.0, karaoke: 1.0, dualMono: false, volume: 1.0)
        let out = processStereoSample(l: 1.0, r: 0.0, params: params)
        XCTAssertEqual(out.left, 0.5, accuracy: 1e-5)
        XCTAssertEqual(out.right, -0.5, accuracy: 1e-5)
    }

    func testDualMonoMirrorsLeft() {
        let params = VocalBlendParameters(mono: 0.0, karaoke: 1.0, dualMono: true, volume: 1.0)
        let out = processStereoSample(l: 1.0, r: 0.0, params: params)
        XCTAssertEqual(out.left, 0.5, accuracy: 1e-5)
        XCTAssertEqual(out.right, 0.5, accuracy: 1e-5)
    }

    func testBlendScalingDoesNotClip() {
        let params = VocalBlendParameters(mono: 1.0, karaoke: 1.0, dualMono: false, volume: 1.0)
        let out = processStereoSample(l: 1.0, r: -1.0, params: params)
        XCTAssertEqual(out.left, 1.0, accuracy: 1e-5)
        XCTAssertEqual(out.right, 0.0, accuracy: 1e-5)
    }
}
