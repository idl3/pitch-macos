import SwiftUI
import AppKit

struct MenuView: View {
    @ObservedObject var player: YouTubeAudioPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PitchYouTube").font(.headline)

            TextField("YouTube URL", text: $player.urlString)
                .textFieldStyle(.roundedBorder)

            Button("Load / Download") {
                player.load()
            }

            HStack {
                Button(player.isPlaying ? "Pause" : "Play") {
                    player.togglePlay()
                }
                Button("Stop") {
                    player.stop()
                }
            }

            HStack {
                Text("Pitch")
                Slider(value: $player.pitchCents, in: -1200...1200, step: 100)
                    .onChange(of: player.pitchCents) { _, _ in player.updatePitch() }
                Text("\(Int(player.pitchCents)) c")
                    .monospacedDigit()
                    .frame(width: 55, alignment: .trailing)
            }

            HStack {
                Text("Volume")
                Slider(value: $player.volume, in: 0...2)
                    .onChange(of: player.volume) { _, _ in player.updateVolume() }
                Text(String(format: "%.1fx", player.volume))
                    .frame(width: 40, alignment: .trailing)
            }

            Text(player.status)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("For personal use only. Downloading audio from YouTube may violate YouTube Terms of Service and is not suitable for distribution.")
                .font(.caption)
                .foregroundStyle(.red)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
