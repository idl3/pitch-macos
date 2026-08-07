import SwiftUI
import AppKit
import CoreGraphics

@main
struct KBearApp: App {
    @NSApplicationDelegateAdaptor(KBearAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

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
    var shouldReopenPopoverAfterPermission = false
    var audio: KBearAudio { KBearAudio.shared }

    func applicationDidFinishLaunching(_ notification: Notification) {
        audio.permissionPromptHandler = { [weak self] in
            self?.shouldReopenPopoverAfterPermission = self?.popover?.isShown ?? false
            NSApp.activate(ignoringOtherApps: true)
        }
        audio.permissionGrantedHandler = { [weak self] in
            guard self?.shouldReopenPopoverAfterPermission == true else { return }
            self?.shouldReopenPopoverAfterPermission = false
            self?.showPopover(nil)
        }
        MenuBarVisibilityRepair.repairHiddenVisibilityDefaults(for: "codes.ernest.tonos")
        createStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        audio.cleanup()
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
        shouldReopenPopoverAfterPermission = false
    }

    func restartApp() {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return }
        let relauncher = "sleep 0.5; open -na \"\(bundlePath)\""
        let task = Process()
        task.launchPath = "/usr/bin/nohup"
        task.arguments = ["/bin/sh", "-c", relauncher]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        NSApp.terminate(nil)
    }

}
