# KBear

A menu-bar macOS app that transposes system audio in real time and removes vocals.

- Captures system-wide audio using `CoreAudio Process Tap`.
- Routes it through `AVAudioEngine` + `AVAudioUnitTimePitch`.
- Plays it back to the selected output device.
- Removes vocals with blendable Mono/Karaoke side processing.

## Requirements

- macOS 14.2+
- Swift 5.9+ / Xcode 15+
- First launch will ask for **Screen & System Audio Recording** TCC permission.

## Build

```bash
cd KBear
swift build
```

## Run from source

```bash
cd KBear
./scripts/run.sh
```

`run.sh` builds the executable, packages it into a `.app` bundle, copies the `Info.plist`, ad-hoc signs it, and opens it.

## Manual packaging

```bash
cd KBear
./scripts/package_app.sh release
# Produces KBear.app in the package root.
```

## Distribution

```bash
cd KBear
./scripts/create_dmg.sh
# Produces KBear.dmg.
```

## Testing plan

1. **Functional**: play a known tone or song; verify transposition with a tuner or FFT analyser.
2. **Device scenarios**: switch default output, connect/disconnect Bluetooth headphones, answer a call (HFP mode), and switch sample rates.
3. **Permissions**: verify the first-run TCC prompt for Screen & System Audio Recording; graceful handling when denied.
4. **Performance**: round-trip latency, CPU usage, and dropout checking at various buffer sizes.

## Important caveats

- `KBear` creates a private aggregate device and temporarily mutes the original process output while the tap is active. Toggle the app off to restore normal audio.
- `AVAudioUnitTimePitch` is not the highest-quality pitch shifter but is free and good enough for casual use.
- This app uses system-wide audio capture and cannot be distributed through the Mac App Store. Use an Apple Developer ID to code-sign and notarize the DMG for direct distribution.

## Vendored code

`KBear` includes `TPCircularBuffer` by Michael Tyson (zlib-style licence) for a lock-free producer/consumer ring buffer between the Core Audio IOProc and `AVAudioSourceNode`.

## License

Prototype code is provided as-is for evaluation. See individual vendored file headers for their licences.
