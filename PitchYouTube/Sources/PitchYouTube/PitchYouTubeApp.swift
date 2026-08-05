import SwiftUI

@main
struct PitchYouTubeApp: App {
    @StateObject private var player = YouTubeAudioPlayer()

    var body: some Scene {
        MenuBarExtra("PitchYouTube", systemImage: "play.rectangle.on.rectangle") {
            MenuView(player: player)
        }
        .menuBarExtraStyle(.window)
    }
}
