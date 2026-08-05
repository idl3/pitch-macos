import SwiftUI

@main
struct PitchSystemApp: App {
    @StateObject private var audio = PitchSystemAudio()

    var body: some Scene {
        WindowGroup("PitchSystem") {
            MenuView(audio: audio)
                .frame(minWidth: 320, minHeight: 240)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("PitchSystem", systemImage: "slider.horizontal.below.rectangle") {
            MenuView(audio: audio)
        }
        .menuBarExtraStyle(.window)
    }
}
