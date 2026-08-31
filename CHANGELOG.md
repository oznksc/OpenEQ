# Changelog

All notable changes to OpenEQ are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Comfort Guard** — a privacy-preserving, local-only listening-load monitor using the existing FFT and peak data. It provides break guidance and an optional, reversible gentle-relief EQ adjustment.

### Notes

- Comfort Guard reports a relative signal-derived load, not calibrated sound pressure or medical advice.

## [1.0.0] — 2026-07-29

First public release.

### Install from DMG

1. Open the latest release on GitHub:  
   **https://github.com/oznksc/OpenEQ/releases**
2. Download **`OpenEQ-1.0.0.dmg`**.
3. Open the DMG and drag **OpenEQ** into **Applications**.
4. Eject the disk image.
5. Launch **OpenEQ** from Applications (or Spotlight).

#### First launch (Gatekeeper)

If macOS says the app can’t be opened because it is from an unidentified developer:

1. Open **System Settings → Privacy & Security**.
2. Scroll to the message about OpenEQ and choose **Open Anyway**,  
   **or** right-click the app in Finder → **Open** → **Open**.

Developer ID notarization may be added in a later release. Building from source always works (see README).

#### System-wide EQ permission

For system-wide EQ (macOS 14.2+):

1. Start **System EQ** once from the toolbar or System Audio sheet.
2. Grant **Screen & System Audio Recording** when prompted.
3. If audio fails, open **System Settings → Privacy & Security → Screen & System Audio Recording** and enable **every** OpenEQ entry (Xcode builds can appear separately from the DMG app).

### Added

- **Local EQ pipeline** — 10/31-band graphic EQ, 5-band parametric EQ with interactive curve, preamp, bypass, volume boost.
- **System-wide EQ** — driverless Core Audio process tap + aggregate path (no BlackHole required for the primary mode).
- **Dynamics** — compressor, stereo balance; peak limiter always on.
- **AUv3 insert** on the local playback chain.
- **Headphone library** — AutoEQ-style catalog + import AutoEQ / REW calibration files.
- **Device EQ profiles** — remember preset per output device.
- **Safety** — feedback/howling protection, emergency safe mode, sleep/wake recovery.
- **UI** — Liquid Glass shell: `NavigationSplitView`, system toolbar, sidebar search, minimal flat content, glass player bar.
- **Menu bar extra** — bypass, presets, system EQ shortcuts.

### Fixed

- System EQ silence / wrong aggregate ownership and tap attachment.
- False “permission required” wall when Core Audio failed for other reasons.
- Feedback guard false trips on loud (non-feedback) music.
- Sidebar search and content sitting under window traffic lights / toolbar.

### Notes

- **Local file EQ** is the production-ready path.
- **System-wide EQ** is experimental-hardened: works on supported setups; conflicting HAL plugins (e.g. Boom, DeskFx) can still break process taps.
- Bundled virtual driver is **not** included (see `docs/virtual-driver.md`).

### Build DMG from source

```bash
./scripts/build-dmg.sh
# → dist/OpenEQ-1.0.0.dmg
```

---

[1.0.0]: https://github.com/oznksc/OpenEQ/releases/tag/v1.0.0
