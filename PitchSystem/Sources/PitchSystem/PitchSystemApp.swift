import SwiftUI

@main
struct TonosApp: App {
    @StateObject private var audio = PitchSystemAudio()

    var body: some Scene {
        MenuBarExtra {
            MenuView(audio: audio)
        } label: {
            Image(systemName: "slider.horizontal.below.rectangle")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}
