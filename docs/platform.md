# Cross-Platform Expansion (Phase 4)

## Current shipping platform

| Platform | Status |
|----------|--------|
| **macOS 14+** | Production — local EQ, system EQ (14.2+), AutoEQ import, AUv3 insert |
| iOS / iPadOS | Planned — shared models + SwiftUI; system-wide EQ not available like macOS |
| visionOS | Planned — UI adaptation of the same SwiftUI shell |

## Shared core candidates

Already portable (no macOS-only APIs):

- `EQBand`, `EQPreset`, `DynamicsSettings`, `HeadphoneProfile`
- `CalibrationImporter` (AutoEQ / REW text)
- `AutoEQCatalog` + `autoeq_catalog.json`
- Spectrum math ideas in `SpectrumAnalyzer` (Accelerate is cross-Apple)

macOS-only today:

- `SystemAudioEQEngine` / process taps / aggregate devices
- Menu bar extra, `NSOpenPanel`/`NSWorkspace` privacy deep links
- External BlackHole loopback device selection

## iOS / iPadOS approach

1. Extract models + importers into a shared Swift package (optional later).
2. Keep `AudioEngineController`-style local playback with `AVAudioEngine`.
3. Replace system EQ with Inter-App Audio / AUv3 host consumer role (different product surface).
4. Use document picker for AutoEQ / REW imports.
5. iCloud sync for `presets.json` + device profiles.

## visionOS approach

- Reuse SwiftUI views with larger hit targets for parametric nodes.
- Spatial audio channel layouts map to future `ChannelLayout.multiChannel` work.

## Multi-channel (foundation only)

`ChannelLayout` distinguishes stereo (supported) from multi-channel (placeholder).  
Per-channel 5.1/7.1 EQ requires:

- Output ASBD channel maps
- Independent biquad state per channel (system DSP already multi-channel capable for stereo)
- UI for channel selection

Not claimed as complete in Phase 4.

## Honesty

Do not market “OpenEQ on iPhone with system-wide EQ” until a real target and pipeline exist. macOS system-wide remains the differentiator.
