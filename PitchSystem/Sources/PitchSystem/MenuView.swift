import SwiftUI
import AppKit
import CoreAudio

struct MenuView: View {
    @ObservedObject var audio: KBearAudio
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
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Main panel

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            settingRow(label: "Change pitch") {
                Toggle(isOn: $audio.pitchEnabled) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if audio.pitchEnabled {
                pitchControls
            }

            settingRow(label: "Remove vocals") {
                Toggle(isOn: $audio.removeVocalsEnabled) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if audio.removeVocalsEnabled {
                vocalControls
            }

            if !audio.statusText.isEmpty {
                Text(audio.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.ultraThickMaterial)
    }

    private var pitchControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingRow(label: "Mode") {
                Picker("", selection: $audio.pitchControlMode) {
                    ForEach(PitchControlMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

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
    }

    private var vocalControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $audio.vocalRemovalMode) {
                ForEach([VocalRemovalMode.mono, .wide, .karaoke, .aggressive, .custom], id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)

            if audio.vocalRemovalMode == .custom {
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
            }

            settingRow(label: "Mono out") {
                Toggle(isOn: $audio.dualMonoOutput) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Text("KBear")
                .font(.headline)
            Spacer()

            outputMenu

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
            .help("Quit KBear")
        }
    }

    private var outputMenu: some View {
        Menu {
            Button {
                audio.selectedOutputID = nil
            } label: {
                outputRowLabel(name: "System default", selected: audio.selectedOutputID == nil)
            }
            Divider()
            ForEach(audio.outputDevices) { device in
                Button {
                    audio.selectedOutputID = device.audioID
                } label: {
                    outputRowLabel(name: device.name, selected: audio.selectedOutputID == device.audioID)
                }
            }
        } label: {
            Image(systemName: "airplayaudio")
                .font(.system(size: 14, weight: .medium))
        }
        .buttonStyle(.borderless)
        .help("Play through")
    }

    private func outputRowLabel(name: String, selected: Bool) -> some View {
        HStack {
            if selected {
                Image(systemName: "checkmark")
            }
            Text(name)
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
