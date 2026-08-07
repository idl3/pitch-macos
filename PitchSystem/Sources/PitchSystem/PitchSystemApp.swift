import SwiftUI
import AppKit
import MenuBarExtraAccess

@MainActor
final class TonosAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var fallbackWindow: NSWindow?
    var visibilityTimer: Timer?
    var audio: PitchSystemAudio { PitchSystemAudio.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarVisibilityRepair.repairHiddenVisibilityDefaults()
        createFallbackWindow()
        scheduleVisibilityCheck()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        syncFallbackWindowVisibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        visibilityTimer?.invalidate()
    }

    func createFallbackWindow() {
        guard fallbackWindow == nil else { return }
        let hostingController = NSHostingController(rootView: MenuView(audio: audio))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Tonos"
        window.setContentSize(NSSize(width: 360, height: 300))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        fallbackWindow = window
    }

    func scheduleVisibilityCheck() {
        // Show the window immediately; the first timer tick will decide whether to hide it.
        showFallbackWindow()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncFallbackWindowVisibility()
            }
        }
    }

    func syncFallbackWindowVisibility() {
        guard let item = statusItem else {
            showFallbackWindow()
            return
        }
        if item.isOnScreen {
            fallbackWindow?.orderOut(nil)
        } else {
            showFallbackWindow()
        }
    }

    func showFallbackWindow() {
        NSApp.activate(ignoringOtherApps: true)
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
    @State private var isMenuPresented = false
    @State private var isMenuEnabled = true

    var body: some Scene {
        MenuBarExtra {
            MenuView(audio: PitchSystemAudio.shared)
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

            appDelegate.statusItem = statusItem

            // If macOS parks the menu-bar icon off-screen (Tahoe/Sequoia), keep the fallback window visible.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                appDelegate.syncFallbackWindowVisibility()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
