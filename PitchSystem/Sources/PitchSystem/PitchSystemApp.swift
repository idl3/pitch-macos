import SwiftUI
import AppKit
import MenuBarExtraAccess

@MainActor
final class TonosAppDelegate: NSObject, NSApplicationDelegate {
    var audio: PitchSystemAudio?
    var statusItem: NSStatusItem?
    var fallbackWindow: NSWindow?

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let item = statusItem, !item.isOnScreen else { return }
        showFallbackWindow()
    }

    func showFallbackWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if fallbackWindow == nil, let audio = audio {
            let hostingController = NSHostingController(rootView: MenuView(audio: audio))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Tonos"
            window.setContentSize(NSSize(width: 360, height: 260))
            window.styleMask = [.titled, .closable, .miniaturizable]
            fallbackWindow = window
        }
        fallbackWindow?.makeKeyAndOrderFront(nil)
    }
}

extension NSStatusItem {
    @MainActor
    var isOnScreen: Bool {
        guard isVisible else { return false }
        let frame = button?.window?.frame ?? .null
        guard frame != .null else { return false }
        return frame.minX >= 0 && frame.minY >= 0
    }
}

@main
struct TonosApp: App {
    @NSApplicationDelegateAdaptor(TonosAppDelegate.self) var appDelegate
    @StateObject private var audio = PitchSystemAudio()
    @State private var isMenuPresented = false
    @State private var isMenuEnabled = true

    init() {
        MenuBarVisibilityRepair.repairHiddenVisibilityDefaults()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(audio: audio)
        } label: {
            Image(systemName: "slider.horizontal.below.rectangle")
                .renderingMode(.template)
        }
        .menuBarExtraAccess(
            isPresented: $isMenuPresented,
            isEnabled: $isMenuEnabled
        ) { statusItem in
            statusItem.autosaveName = "codes.ernest.tonos"
            statusItem.behavior = .terminationOnRemoval
            MenuBarVisibilityRepair.clearVisibilityDefault(for: "codes.ernest.tonos")

            appDelegate.audio = audio
            appDelegate.statusItem = statusItem

            // macOS Tahoe 26.5 can park third-party menu-bar icons off-screen.
            // Open a fallback window if the icon isn't actually on-screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard let item = appDelegate.statusItem, !item.isOnScreen else { return }
                appDelegate.showFallbackWindow()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
