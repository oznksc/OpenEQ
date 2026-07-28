# System Audio

OpenEQ can process system-wide audio on macOS 14.2+ using a Core Audio process tap and a private aggregate device. External loopback (BlackHole) remains available as an advanced fallback.

## Modes

- **Disabled**: EQ applies only to local file playback.
- **System-Wide EQ**: Captures system audio via `CATapDescription`, runs OpenEQ biquad EQ + peak limiter, and plays through a private aggregate device that includes the current physical output.
- **External Loopback**: User routes macOS output through a virtual device such as BlackHole, then OpenEQ processes that input with `AVAudioEngine`.

## Permissions

System-Wide EQ requires **Screen & System Audio Recording** permission. The first tap creation triggers the system prompt. If denied, OpenEQ surfaces a recovery path that opens System Settings.

Privacy strings are declared in the app Info.plist:

- `NSAudioCaptureUsageDescription`
- `NSMicrophoneUsageDescription` (external loopback input devices)

## Stability guarantees (Phase 1)

- Aggregate rebuild never treats OpenEQ's own aggregate as the physical destination device.
- Default-output changes (headphones, AirPods, HDMI) rebuild the aggregate against the new physical device.
- Device-list churn is debounced to avoid rebuild storms.
- EQ bypass is unified across local, system, and loopback paths; the peak limiter stays engaged when EQ is bypassed.
- **Emergency Stop / Safe Mode** immediately stops processing and restores the original default output.
- App termination restores the original default output via `shutdown()`.

## Privacy

Audio is processed locally on the Mac. OpenEQ does not send captured audio to analytics, cloud services, or external servers.
