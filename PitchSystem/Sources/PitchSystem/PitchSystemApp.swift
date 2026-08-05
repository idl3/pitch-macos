import SwiftUI

@main
struct PitchSystemApp: App {
    @StateObject private var audio = PitchSystemAudio()

    var body: some Scene {
        MenuBarExtra("PitchSystem", systemImage: "slider.horizontal.below.rectangle") {
            MenuView(audio: audio)
        }
        .menuBarExtraStyle(.window)
    }
}
