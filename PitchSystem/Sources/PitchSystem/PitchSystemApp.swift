import SwiftUI
import AppKit

@main
struct PitchSystemApp: App {
    @StateObject private var audio = PitchSystemAudio()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("PitchSystem", systemImage: "slider.horizontal.below.rectangle") {
            MenuView(audio: audio)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
