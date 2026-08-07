import Foundation
import CoreGraphics

/// Uses the TCC private SPI to check/request system audio capture permission
/// (`kTCCServiceAudioCapture`) used by CoreAudio process taps.
/// Falls back to `CGPreflightScreenCaptureAccess` on systems where the TCC SPI
/// is unavailable and on macOS Tahoe where screen recording also grants audio capture.
@MainActor
final class KBearAudioPermission {
    static let shared = KBearAudioPermission()

    private typealias TCCPreflightFunc = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias TCCRequestFunc = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private var tccPreflight: TCCPreflightFunc?
    private var tccRequest: TCCRequestFunc?

    init() {
        loadTCCSPI()
    }

    private func loadTCCSPI() {
        let tccPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"
        guard let handle = dlopen(tccPath, RTLD_NOW) else { return }

        if let sym = dlsym(handle, "TCCAccessPreflight") {
            tccPreflight = unsafeBitCast(sym, to: TCCPreflightFunc.self)
        }
        if let sym = dlsym(handle, "TCCAccessRequest") {
            tccRequest = unsafeBitCast(sym, to: TCCRequestFunc.self)
        }
    }

    /// 0 = authorized, 1 = denied, 2 = undetermined
    func preflightAudioCapture() -> Int {
        tccPreflight?("kTCCServiceAudioCapture" as CFString, nil) ?? 2
    }

    var isAudioCaptureAuthorized: Bool {
        if preflightAudioCapture() == 0 { return true }
        if #available(macOS 11.0, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return false
    }

    /// Requests system audio capture permission and returns the user's choice.
    func requestAudioCapturePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if let request = tccRequest {
                request("kTCCServiceAudioCapture" as CFString, nil) { granted in
                    continuation.resume(returning: granted)
                }
            } else if #available(macOS 11.0, *) {
                CGRequestScreenCaptureAccess()
                continuation.resume(returning: false)
            } else {
                continuation.resume(returning: false)
            }
        }
    }
}
