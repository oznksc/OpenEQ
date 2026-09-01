<p align="center">
  <img src="openeq-app-icon.png" alt="OpenEQ Logo" width="200" />
</p>

# OpenEQ

An open-source macOS audio equalizer built with **SwiftUI**, **AVFoundation**, **Core Audio**, and **Accelerate (vDSP)**.

OpenEQ is a lightweight desktop EQ for:

1. **Local files** (production-ready) — open a track, shape it, A/B with bypass  
2. **System-wide audio** (experimental) — process other apps after granting Screen & System Audio Recording permission  

## What works today (V1)

### Local equalizer (stable)
- **10-band & 31-band** graphic EQ (ISO frequencies)
- **5-band parametric EQ** with **interactive curve** (drag nodes, scroll for Q, double-click for direct numerical entry with `k`/`Hz` suffixes)
- **Layered EQ Architecture:** 3-tier cascade (**Calibration** $\rightarrow$ **Target Curve** $\rightarrow$ **Session Tuning**)
- **Level-Matched A/B Comparison:** Automatic RMS offset detection with click-free crossfades to eliminate loudness bias
- **True-Peak (dBTP) Metering:** ITU-R BS.1770 compliant 4x polyphase oversampling for inter-sample peak detection
- **Auto Headroom:** Dynamic anti-clipping preamp attenuation control (Auto/Manual)
- **Undo / Redo & A/B/C Snapshot Slots:** Complete parameter history stack and 3 instant comparative recall slots
- Preamp (`-24` … `+24` dB), EQ bypass, volume boost up to 200%
- **Dynamics:** compressor + stereo balance; peak limiter always on
- **AUv3 insert** on the local playback chain (effect plugins)
- **Headphone library** (AutoEQ-style) + import AutoEQ / REW calibration files
- Real-time **64-band FFT spectrum** (Canvas + vDSP)
- **Comfort Guard:** local-only listening-load tracking from live peak/spectrum data, with break guidance and optional reversible treble relief
- Built-in presets + custom save/import/export (JSON)
- **Normal, Menu Bar, and Both app modes:** the compact menu-bar panel controls System Audio, EQ bypass, output status, and every built-in preset without opening the main window

### System audio (driverless, experimental-hardened)
Requires **macOS 14.2+** and **Screen & System Audio Recording** permission.

| Mode | What it does | Notes |
|------|----------------|-------|
| **System-Wide EQ** | One-click process tap → biquad EQ + limiter → private aggregate | **No driver install**; primary path |
| **External Loopback** | Process a virtual input (e.g. BlackHole) through OpenEQ | Advanced fallback |
| **Disabled** | Local files only | Default |

**Phase 2 safety:** feedback/howling mute, sleep/wake recovery, per-device EQ profiles, emergency safe mode, permission recovery.

**Not claimed:** bundled HAL/DriverKit virtual device (researched, deferred — [docs/virtual-driver.md](docs/virtual-driver.md)), zero-latency on all hardware, multi-channel Atmos calibration.

Details: [docs/system-audio.md](docs/system-audio.md).

### Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘O` | Open audio file |
| `⌘R` | Reset EQ |
| `⌘B` | Toggle EQ bypass |
| `⌘⇧V` | Toggle volume boost |
| `Space` | Play / pause |

## Architecture

```
SwiftUI Views → OpenEQViewModel → AudioEngineController   (local files)
                               → SystemAudioManager
                                    ├─ SystemAudioEQEngine      (process tap + aggregate)
                                    └─ ExternalLoopbackEngine   (BlackHole path)
```

- Local path: `AVAudioEngine` + `AVAudioPlayerNode` + `AVAudioUnitEQ` + peak limiter  
- System path: `CATapDescription` + aggregate device + manual biquad DSP + peak limiter  
- Spectrum: vDSP FFT, Hanning window, decay smoothing  
- Comfort Guard: explainable relative load score from output peak and high-frequency energy; it is not a calibrated SPL or medical measurement

See [docs/architecture.md](docs/architecture.md), [docs/ROADMAP.md](docs/ROADMAP.md).

## Install (DMG)

1. Download **`OpenEQ-1.0.0.dmg`** from [Releases](https://github.com/oznksc/OpenEQ/releases).
2. Open the DMG and drag **OpenEQ** into **Applications**.
3. Launch from Applications. If Gatekeeper blocks the app, use **right-click → Open** (or allow it under **Privacy & Security**).

Full notes and permission setup: [CHANGELOG.md](CHANGELOG.md).

## Requirements

- macOS **14.0+** (local EQ)
- macOS **14.2+** (system-wide EQ)
- Xcode 15+ (or matching command-line tools) to build from source

## Build

```bash
# Xcode
open OpenEQ.xcodeproj   # scheme OpenEQ → My Mac → ⌘R

# CLI
xcodebuild -project OpenEQ.xcodeproj -scheme OpenEQ -destination 'platform=macOS' build
xcodebuild test -project OpenEQ.xcodeproj -scheme OpenEQ -destination 'platform=macOS'

# Release DMG → dist/OpenEQ-<version>.dmg
./scripts/build-dmg.sh
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [AGENTS.md](AGENTS.md) for agent/contributor conventions.

## License

MIT — see [LICENSE](LICENSE).
