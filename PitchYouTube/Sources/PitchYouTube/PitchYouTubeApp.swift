import SwiftUI
import AppKit

@main
struct PitchYouTubeApp: App {
    @StateObject private var player = YouTubeAudioPlayer()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("PitchYouTube", systemImage: "play.rectangle.on.rectangle") {
            MenuView(player: player)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
