import SwiftUI

@main
struct PitchYouTubeApp: App {
    @StateObject private var player = YouTubeAudioPlayer()

    var body: some Scene {
        WindowGroup("PitchYouTube") {
            MenuView(player: player)
                .frame(minWidth: 360, minHeight: 280)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("PitchYouTube", systemImage: "play.rectangle.on.rectangle") {
            MenuView(player: player)
        }
        .menuBarExtraStyle(.window)
    }
}
