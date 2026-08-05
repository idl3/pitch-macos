import SwiftUI

@main
struct TonosApp: App {
    @StateObject private var audio = PitchSystemAudio()

    var body: some Scene {
        WindowGroup("Tonos") {
            MenuView(audio: audio)
                .frame(minWidth: 320, minHeight: 240)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuView(audio: audio)
        } label: {
            Image(systemName: "slider.horizontal.below.rectangle")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
    }
}
