import SwiftUI
import AppKit
import CoreAudio

struct MenuView: View {
    @ObservedObject var audio: PitchSystemAudio

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable pitch shift", isOn: $audio.isEnabled)
                .onChange(of: audio.isEnabled) { _, active in
                    active ? audio.start() : audio.stop()
                }

            HStack {
                Text("Pitch")
                Slider(value: $audio.pitchCents, in: -2400...2400, step: 100)
                Text("\(Int(audio.pitchCents)) c")
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }

            HStack {
                Text("Volume")
                Slider(value: $audio.volume, in: 0...2)
                Text(String(format: "%.1fx", audio.volume))
                    .frame(width: 40, alignment: .trailing)
            }

            Picker("Output", selection: $audio.selectedOutputID) {
                Text("System default").tag(nil as AudioDeviceID?)
                ForEach(audio.outputDevices) { device in
                    Text(device.name).tag(device.audioID as AudioDeviceID?)
                }
            }
            .pickerStyle(.menu)

            Text(audio.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
