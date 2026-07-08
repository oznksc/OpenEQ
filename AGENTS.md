# OpenEQ — AI Agent Instructions

## Project Overview

OpenEQ is a macOS audio equalizer that processes both local files and system-wide audio. It uses two separate audio pipelines:

- **Local playback**: `AVAudioEngine` + `AVAudioPlayerNode` + `AVAudioUnitEQ`
- **System-wide EQ**: Core Audio process tap (`CATapDescription`) + aggregate device + manual biquad DSP via vDSP

## Architecture

MVVM with `@Observable`:
- `OpenEQViewModel` — single source of truth for UI state
- `SystemAudioManager` — orchestrates system audio modes
- `AudioEngineController` — local file playback engine
- `SystemAudioEQEngine` — Core Audio tap + manual biquad EQ
- `ExternalLoopbackEngine` — BlackHole-based loopback via AVAudioEngine

## Audio Formats

- Core Audio process taps provide **non-interleaved** Float32 audio (separate AudioBuffer per channel)
- Local playback uses AVAudioEngine's default interleaved format
- `handleIO` in `SystemAudioEQEngine` must copy per-channel (not from `.first` buffer)

## Build & Test

```bash
# Build
xcodebuild -project OpenEQ.xcodeproj -scheme OpenEQ build

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

## System Audio Permissions

System-wide EQ requires macOS 14.2+ and Screen/System Audio Recording permission. First tap creation triggers system prompt.
