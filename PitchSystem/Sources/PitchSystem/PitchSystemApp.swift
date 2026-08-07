import SwiftUI
import AppKit
import CoreGraphics

final class TonosHostingController: NSHostingController<MenuView> {
    weak var popover: NSPopover?

    override func viewDidLayout() {
        super.viewDidLayout()
        let size = view.fittingSize
        guard let popover = popover, size.height > 0 else { return }
        let current = popover.contentSize
        if abs(current.height - size.height) > 4 || abs(current.width - size.width) > 4 {
            popover.contentSize = size
        }
    }
}

@MainActor
final class TonosAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var fallbackWindow: NSWindow?
    var visibilityTimer: Timer?
    var popoverIsOpen = false
    var audio: PitchSystemAudio { PitchSystemAudio.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAudioPermissionIfNeeded()
        MenuBarVisibilityRepair.repairHiddenVisibilityDefaults()
        createFallbackWindow()
        createStatusItem()
        scheduleVisibilityCheck()
    }

    private func requestAudioPermissionIfNeeded() {
        if #available(macOS 11.0, *) {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        syncFallbackWindowVisibility()
    }

    func applicationWillTerminate(_ notification: Notification) {
        visibilityTimer?.invalidate()
    }

    func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "codes.ernest.tonos"
        item.behavior = .terminationOnRemoval
        if let button = item.button {
            button.image = statusBarIcon() ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Tonos")
            button.toolTip = "Tonos"
            button.action = #selector(showPopover(_:))
            button.target = self
        }
        statusItem = item
        MenuBarVisibilityRepair.clearVisibilityDefault(for: "codes.ernest.tonos")
    }

    private func statusBarIcon() -> NSImage? {
        return rotatedSymbolIcon(name: "mic.fill", size: 22, rotation: .pi / 4)
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Tonos")
    }

    private func rotatedSymbolIcon(name: String, size: CGFloat, rotation: CGFloat) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Tonos") else { return nil }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }
        let symbolSize = size * 0.7
        let inset = (size - symbolSize) / 2
        let symbolRect = NSRect(x: inset, y: inset, width: symbolSize, height: symbolSize)
        ctx.translateBy(x: size / 2, y: size / 2)
        ctx.rotate(by: rotation)
        ctx.translateBy(x: -size / 2, y: -size / 2)
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        image.isTemplate = true
        return image
    }

    @objc func showPopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover == nil {
            let p = NSPopover()
            p.behavior = .transient
            let hosting = TonosHostingController(rootView: MenuView(audio: audio))
            hosting.popover = p
            p.contentViewController = hosting
            p.delegate = self
            popover = p
        }
        popoverIsOpen = true
        syncFallbackWindowVisibility()
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        if let popoverWindow = popover?.contentViewController?.view.window {
            popoverWindow.makeKeyAndOrderFront(nil)
        }
    }

    func closePopover() {
        popover?.close()
    }

    func popoverDidClose(_ notification: Notification) {
        popoverIsOpen = false
        syncFallbackWindowVisibility()
    }

    func createFallbackWindow() {
        guard fallbackWindow == nil else { return }
        let hostingController = NSHostingController(rootView: MenuView(audio: audio))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Tonos"
        window.setContentSize(NSSize(width: 360, height: 520))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        fallbackWindow = window
    }

    func scheduleVisibilityCheck() {
        // Wait briefly for the status item to materialize before deciding to show the fallback window.
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncFallbackWindowVisibility()
            }
        }
    }

    func syncFallbackWindowVisibility() {
        if popoverIsOpen {
            fallbackWindow?.orderOut(nil)
            return
        }
        guard let item = statusItem, item.isOnScreen else {
            showFallbackWindow()
            return
        }
        fallbackWindow?.orderOut(nil)
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

    var body: some Scene {
        Settings {
            MenuView(audio: PitchSystemAudio.shared)
                .frame(width: 320)
        }
    }
}
