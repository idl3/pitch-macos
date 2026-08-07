import SwiftUI
import AppKit
import CoreAudio

struct MenuView: View {
    @ObservedObject var audio: PitchSystemAudio
    @State private var showingPresets = false

    var body: some View {
        ZStack {
            mainPanel

            if showingPresets {
                presetsPanel
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingPresets)
        .frame(width: 360)
    }

    // MARK: - Main panel

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            settingRow(label: "Enable pitch shift") {
                Toggle(isOn: Binding(
                    get: { audio.isEnabled },
                    set: { audio.setEnabled($0) }
                )) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
            }

            settingRow(label: "Vocal removal") {
                Picker("", selection: $audio.vocalRemovalMode) {
                    ForEach(VocalRemovalMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }

            vocalSliders

            settingRow(label: "Mode") {
                Picker("", selection: $audio.pitchControlMode) {
                    ForEach(PitchControlMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            pitchRow

            settingRow(label: "Volume") {
                HStack(spacing: 8) {
                    Slider(value: $audio.volume, in: 0...1)
                        .frame(width: 100)
                    Text(String(format: "%d%%", Int(audio.volume * 100)))
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }

            settingRow(label: "Play through") {
                Picker(selection: $audio.selectedOutputID) {
                    Text("System default").tag(nil as AudioDeviceID?)
                    ForEach(audio.outputDevices) { device in
                        Text(device.name).tag(device.audioID as AudioDeviceID?)
                    }
                } label: {
                    Label("Play through", systemImage: "speaker.wave.2")
                        .labelStyle(.iconOnly)
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }

            if !audio.statusText.isEmpty {
                Text(audio.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding()
        .background(.ultraThickMaterial)
    }

    private var headerBar: some View {
        HStack {
            Text("Tonos")
                .font(.headline)
            Spacer()

            Button {
                withAnimation { showingPresets.toggle() }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Song presets")

            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.MenuBarSettings") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Open Menu Bar Settings")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Quit Tonos")
        }
    }

    @ViewBuilder
    private var vocalSliders: some View {
        HStack {
            Text("Mono")
            Spacer()
            Slider(value: $audio.vocalMono, in: 0...1)
                .frame(width: 150)
            Text(String(format: "%d%%", Int(audio.vocalMono * 100)))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }

        HStack {
            Text("Karaoke")
            Spacer()
            Slider(value: $audio.vocalKaraoke, in: 0...1)
                .frame(width: 150)
            Text(String(format: "%d%%", Int(audio.vocalKaraoke * 100)))
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }

        settingRow(label: "Mono out") {
            Toggle(isOn: $audio.dualMonoOutput) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var pitchRow: some View {
        if audio.pitchControlMode == .semitones {
            HStack {
                Text("Pitch")
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        audio.pitchSemitones = max(-12, audio.pitchSemitones - 1)
                    } label: {
                        Text("−").frame(width: 24)
                    }
                    Text("\(audio.pitchSemitones) st")
                        .monospacedDigit()
                        .frame(width: 50)
                    Button {
                        audio.pitchSemitones = min(12, audio.pitchSemitones + 1)
                    } label: {
                        Text("+").frame(width: 24)
                    }
                }
            }
        } else {
            settingRow(label: "Pitch") {
                HStack(spacing: 8) {
                    Slider(value: $audio.pitchCents, in: -2400...2400, step: 100)
                        .frame(width: 120)
                    Text("\(Int(audio.pitchCents)) c")
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }

    // MARK: - Presets panel

    private var presetsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    withAnimation { showingPresets = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.system(size: 14))
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("Presets")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 8) {
                TextField("Preset name", text: $audio.newPresetName)
                    .textFieldStyle(.roundedBorder)
                Button("Save") {
                    audio.savePreset(name: audio.newPresetName)
                    audio.newPresetName = ""
                }
                .disabled(audio.newPresetName.isEmpty)
            }

            if audio.presets.isEmpty {
                Text("No presets yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(audio.presets) { preset in
                            HStack {
                                Button {
                                    audio.loadPreset(preset)
                                } label: {
                                    Text(preset.name)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button {
                                    audio.deletePreset(preset)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 6)
                            .background(audio.selectedPresetID == preset.id ? Color.accentColor.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(.ultraThickMaterial)
    }

    @ViewBuilder
    private func settingRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
            Spacer()
            content()
        }
    }
}
