import SwiftUI
import AppKit
import CoreAudio

struct MenuView: View {
    @ObservedObject var audio: PitchSystemAudio

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Enable pitch shift", isOn: Binding(
                get: { audio.isEnabled },
                set: { audio.setEnabled($0) }
            ))
            .toggleStyle(.switch)

            Picker("Vocal removal", selection: $audio.vocalRemovalMode) {
                ForEach(VocalRemovalMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Picker("Mode", selection: $audio.pitchControlMode) {
                ForEach(PitchControlMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if audio.pitchControlMode == .semitones {
                HStack {
                    Text("Pitch")
                    Spacer()
                    Button {
                        audio.pitchSemitones = max(-12, audio.pitchSemitones - 1)
                    } label: {
                        Text("−").frame(minWidth: 24)
                    }
                    Text("\(audio.pitchSemitones) st")
                        .monospacedDigit()
                        .frame(width: 55, alignment: .center)
                    Button {
                        audio.pitchSemitones = min(12, audio.pitchSemitones + 1)
                    } label: {
                        Text("+").frame(minWidth: 24)
                    }
                }
            } else {
                HStack {
                    Text("Pitch")
                    Slider(value: $audio.pitchCents, in: -2400...2400, step: 100)
                    Text("\(Int(audio.pitchCents)) c")
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                }
            }

            HStack {
                Text("Volume")
                Slider(value: $audio.volume, in: 0...2)
                Text(String(format: "%d%%", Int(audio.volume * 100)))
                    .frame(width: 40, alignment: .trailing)
            }

            Picker("Play through", selection: $audio.selectedOutputID) {
                Text("System default").tag(nil as AudioDeviceID?)
                ForEach(audio.outputDevices) { device in
                    Text(device.name).tag(device.audioID as AudioDeviceID?)
                }
            }
            .pickerStyle(.menu)

            if !audio.statusText.isEmpty {
                Text(audio.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Open Menu Bar Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.MenuBarSettings") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
