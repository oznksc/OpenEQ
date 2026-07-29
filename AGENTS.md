# OpenEQ — AI Agent Instructions

## Project Overview

OpenEQ is a macOS audio equalizer.

- **Local playback (production):** `AVAudioEngine` + `AVAudioPlayerNode` + `AVAudioUnitEQ` + peak limiter
- **System-wide EQ (experimental):** Core Audio process tap (`CATapDescription`) + aggregate device + manual biquad DSP + peak limiter
- **External loopback (advanced):** BlackHole-style virtual input via `AVAudioEngine`

**Do not oversell system-wide EQ** in UI copy or README. Local EQ is the stable core.

## Architecture

MVVM with `@Observable`:
- `OpenEQViewModel` — single source of truth; unified EQ/bypass policy for all engines
- `SystemAudioManager` — system modes, device snapshot, safe mode
- `AudioEngineController` — local file playback
- `SystemAudioEQEngine` — tap + aggregate + biquad DSP (track **physical** output, never rebuild using our own aggregate as destination)
- `ExternalLoopbackEngine` — BlackHole loopback
- `PeakLimiterConfigurator` — shared Apple peak-limiter defaults
- `FeedbackGuard` — sustained hot-signal mute for howling protection
- `DeviceProfileStore` — per-device UID → preset map
- `AUv3PluginHost` — local-graph effect insert only (not system-wide)
- Interactive `EQCurveView` — drag nodes; scroll Q in parametric mode
- `AutoEQCatalog` + `CalibrationImporter` — headphone library and AutoEQ/REW import
- Do **not** claim a shipped virtual HAL/DriverKit device; CATap is the primary system path (see `docs/virtual-driver.md`)
- Do **not** claim full iOS/visionOS apps or 5.1 per-channel EQ until those targets exist (`docs/platform.md`)

## Audio Formats

- Core Audio process taps provide **non-interleaved** Float32 audio (separate AudioBuffer per channel)
- Local playback uses AVAudioEngine's default interleaved format
- `handleIO` in `SystemAudioEQEngine` must copy per-channel (not from `.first` buffer)
- Keep the peak limiter engaged when EQ is bypassed

## Build & Test

```bash
# Build
xcodebuild -project OpenEQ.xcodeproj -scheme OpenEQ -destination 'platform=macOS' build

# Test
xcodebuild test -project OpenEQ.xcodeproj -scheme OpenEQ -destination 'platform=macOS'

# Run
open OpenEQ.xcodeproj  # then press Cmd+R
```

## Code Conventions

- PascalCase for types, camelCase for vars/funcs
- No comments in production code (unless explaining WHY, not WHAT)
- One type per file, grouped by layer
- No allocations/locks in audio callbacks
- Use `@Observable` for all view models
- Keep docs (`README`, `docs/*`) aligned with real behavior (Phase 0 rule)

## System Audio Permissions

System-wide EQ requires macOS 14.2+ and Screen & System Audio Recording permission. First tap creation triggers the system prompt. On failure, surface permission recovery (System Settings link) and safe mode restore of the original default output.
