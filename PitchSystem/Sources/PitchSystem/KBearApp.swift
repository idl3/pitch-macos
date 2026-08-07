import SwiftUI
import AppKit
import CoreGraphics

final class KBearHostingController: NSHostingController<MenuView> {
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
final class KBearAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var fallbackWindow: NSWindow?
    var visibilityTimer: Timer?
    var popoverIsOpen = false
    var shouldReopenPopoverAfterPermission = false
    var audio: KBearAudio { KBearAudio.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        audio.permissionPromptHandler = { [weak self] in
            self?.shouldReopenPopoverAfterPermission = self?.popoverIsOpen ?? false
        }
        audio.permissionGrantedHandler = { [weak self] in
            guard self?.shouldReopenPopoverAfterPermission == true else { return }
            self?.shouldReopenPopoverAfterPermission = false
            self?.showPopover(nil)
        }
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
            button.image = statusBarIcon() ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "KBear")
            button.toolTip = "KBear"
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item
        MenuBarVisibilityRepair.clearVisibilityDefault(for: "codes.ernest.tonos")
    }

    private func statusBarIcon() -> NSImage? {
        if let image = Bundle.main.image(forResource: "menu_bar_icon") {
            image.isTemplate = true
            image.size = NSSize(width: 14, height: 14)
            return image
        }
        return rotatedSymbolIcon(name: "mic.fill", size: 22, rotation: .pi / 4)
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "KBear")
    }

    private func rotatedSymbolIcon(name: String, size: CGFloat, rotation: CGFloat) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "KBear") else { return nil }
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

    @objc func togglePopover(_ sender: Any?) {
        guard statusItem?.button != nil else { return }
        if popover?.isShown == true {
            closePopover()
            return
        }
        showPopover(sender)
    }

    @objc func showPopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover == nil {
            let p = NSPopover()
            p.behavior = .transient
            let hosting = KBearHostingController(rootView: MenuView(audio: audio))
            hosting.popover = p
            p.contentViewController = hosting
            p.delegate = self
            popover = p
        }
        shouldReopenPopoverAfterPermission = false
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
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "KBear"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentViewController = hostingController
        fallbackWindow = panel
    }

    func scheduleVisibilityCheck() {
        // Give the status item a moment to appear; show the fallback panel once if it doesn't.
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncFallbackWindowVisibility()
                self?.visibilityTimer?.invalidate()
                self?.visibilityTimer = nil
            }
        }
    }

    func syncFallbackWindowVisibility() {
        if popoverIsOpen {
            fallbackWindow?.orderOut(nil)
            return
        }
        guard let item = statusItem, item.isOnScreen else {
            showFallbackWindowIfNeeded()
            return
        }
        fallbackWindow?.orderOut(nil)
    }

    private var hasShownFallback = false

    func showFallbackWindowIfNeeded() {
        guard !hasShownFallback, fallbackWindow?.isVisible != true else { return }
        hasShownFallback = true
        fallbackWindow?.orderFrontRegardless()
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
struct KBearApp: App {
    @NSApplicationDelegateAdaptor(KBearAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            MenuView(audio: KBearAudio.shared)
                .frame(width: 320)
        }
    }
}
