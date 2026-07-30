# pitch-macos

Two SwiftUI menu-bar prototypes for macOS that demonstrate real-time audio pitch shifting:

- **PitchSystem** captures system-wide audio using `CoreAudio Process Tap`, routes it through `AVAudioEngine` + `AVAudioUnitTimePitch`, and plays it back to the selected output device. Transposes anything playing on your Mac without touching individual apps.
- **PitchYouTube** downloads the audio track from a YouTube URL with `yt-dlp` and plays it through `AVAudioEngine` + `AVAudioUnitTimePitch` with pitch/volume controls.

## Feasibility

- **macOS 14.2+**: feasible. `CATapDescription` + `AudioHardwareCreateProcessTap` + a private tap-only aggregate device can capture system output, and `AVAudioUnitTimePitch` shifts pitch independently of tempo.
- **iOS**: not feasible on stock iOS. System-wide audio capture/modification is blocked by the sandbox; `CATapDescription` is macOS-only.

## Requirements

- macOS 14.2+
- Swift 5.9+ / Xcode 15+
- `yt-dlp` installed (for PitchYouTube only). Common Homebrew paths are tried automatically.
- For PitchSystem, the first launch will ask for **Screen & System Audio Recording** TCC permission.

## Build

Each app is a separate SwiftPM package.

```bash
cd PitchSystem
swift build

cd ../PitchYouTube
swift build
```

## Run from source

```bash
cd PitchSystem
./scripts/run.sh

cd ../PitchYouTube
./scripts/run.sh
```

`run.sh` builds the executable, packages it into a `.app` bundle, copies the `Info.plist`, ad-hoc signs it, and opens it.

## Manual packaging

```bash
cd PitchSystem
./scripts/package_app.sh release
# Produces PitchSystem.app in the package root.
```

## Testing plan

1. **Functional**: play a known tone or song; verify transposition with a tuner or FFT analyser.
2. **Device scenarios**: switch default output, connect/disconnect Bluetooth headphones, answer a call (HFP mode), and switch sample rates.
3. **Permissions**: verify the first-run TCC prompt for Screen & System Audio Recording; graceful handling when denied.
4. **Performance**: round-trip latency, CPU usage, and dropout checking at various buffer sizes.

## Important caveats

- `PitchSystem` creates a private aggregate device and temporarily mutes the original process output while the tap is active. Toggle the app off to restore normal audio.
- `AVAudioUnitTimePitch` is not the highest-quality pitch shifter but is free and good enough for casual use.
- `PitchYouTube` uses `yt-dlp` to obtain audio streams. This is a **prototype** only: extracting audio from YouTube may violate YouTube\'s Terms of Service, the URLs expire, and the extraction logic breaks when YouTube changes signatures. Do not ship this in an App Store product.
- No commercial redistribution is planned for either prototype.

## Vendored code

`PitchSystem` includes `TPCircularBuffer` by Michael Tyson (zlib-style licence) for a lock-free producer/consumer ring buffer between the Core Audio IOProc and `AVAudioSourceNode`.

## License

Prototype code is provided as-is for evaluation. See individual vendored file headers for their licences.
