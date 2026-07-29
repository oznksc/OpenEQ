# System Audio

OpenEQ can process system-wide audio on macOS 14.2+ using a Core Audio process tap and a private aggregate device. External loopback (BlackHole) remains available as an advanced fallback.

**Primary UX:** one-click **Start System EQ** (header, menu bar, or System Audio sheet). No virtual driver install.

## Modes

- **Disabled**: EQ applies only to local file playback.
- **System-Wide EQ** (primary): Captures system audio via `CATapDescription` (muted at the destination), processes with biquad EQ + peak limiter, and plays through a private aggregate that includes the **physical** output. The system default output stays on the physical device (it is **not** switched to the aggregate — that pattern causes total silence).
- **External Loopback** (advanced): User routes macOS output through a virtual device such as BlackHole; OpenEQ processes that input with `AVAudioEngine`.

## Permissions

System-Wide EQ requires **Screen & System Audio Recording** permission. The first tap creation triggers the system prompt. If denied, OpenEQ surfaces a recovery path that opens System Settings.

Privacy strings are declared in the app Info.plist:

- `NSAudioCaptureUsageDescription`
- `NSMicrophoneUsageDescription` (external loopback input devices)

## Stability & safety (Phase 1 + 2)

- Aggregate rebuild never treats OpenEQ's own aggregate as the physical destination device.
- Default-output changes (headphones, AirPods, HDMI) rebuild the aggregate against the new physical device.
- Device-list churn is debounced to avoid rebuild storms.
- EQ bypass is unified across local, system, and loopback paths; the peak limiter stays engaged when EQ is bypassed.
- **Feedback / howling protection** mutes output on sustained near-clip energy; user must acknowledge to resume.
- **Sleep / wake recovery** restarts System EQ when the user left it enabled.
- **Device-specific profiles** auto-load a saved preset when a known output UID connects.
- **Emergency Stop / Safe Mode** immediately stops processing and restores the original default output.
- App termination restores the original default output via `shutdown()`.

## Virtual driver

A bundled HAL/DriverKit device is **not required** for System-Wide EQ. See [virtual-driver.md](virtual-driver.md) for research and deferral rationale.

## Privacy

Audio is processed locally on the Mac. OpenEQ does not send captured audio to analytics, cloud services, or external servers.
