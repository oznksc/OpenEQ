# Virtual Driver / HAL Plug-in Research (Phase 2)

## Decision for Phase 2

**Ship the driverless Core Audio process-tap path as the primary System-Wide EQ.**  
A bundled HAL plug-in or DriverKit audio driver is **researched and deferred**, not faked.

| Approach | User friction | Effort | Latency | Status in OpenEQ |
|----------|---------------|--------|---------|------------------|
| **CATap + aggregate** (current) | Permission only | Done | Buffer-bound | **Primary** |
| BlackHole / external loopback | Install + routing | Done | Higher | Advanced fallback |
| Core Audio HAL plug-in | Install once + code sign | High | Lower possible | Deferred |
| DriverKit Audio | Notarization + dext | Very high | Lowest possible | Deferred |

## Why CATap is the Phase 2 product path

1. No third-party driver install (matches “one click” UX).
2. Works on macOS 14.2+ with Screen & System Audio Recording permission.
3. OpenEQ already owns tap → DSP → aggregate → physical output restore.
4. Shipping a virtual device without a real installer, entitlements, and notarization would be dishonest (Phase 0 rule).

## When to build a real virtual device (Phase 2.5+)

- Users need OpenEQ to appear as a selectable system output in every app’s device menu.
- Multi-app aggregate routing that process taps cannot express cleanly.
- Target latency below what the tap/aggregate path can guarantee.

### HAL plug-in outline

1. Implement `AudioServerPlugIn` / `AudioHardwarePlugInInterface` virtual device.
2. Package as `.driver` under `/Library/Audio/Plug-Ins/HAL/`.
3. Installer (or privileged helper) + unload/reload Core Audio.
4. OpenEQ routes: apps → OpenEQ Virtual Out → engine → physical out.
5. Developer ID + notarization; careful sleep/wake and sample-rate handling.

### DriverKit outline

1. `IOUserAudioDriver` dext with entitlement `com.apple.developer.driverkit.family.audio`.
2. System Extension activation UX.
3. Higher review surface; justified only if HAL is insufficient.

## Phase 2 safety stack (shipped)

- Feedback / howling protection (`FeedbackGuard`) with immediate mute
- Sleep/wake recovery of system EQ
- Device-specific EQ profiles (UID → preset)
- One-click System EQ + onboarding
- Emergency safe mode restores default output

## References

- Apple: Audio Device Driver design (HAL)
- Apple: DriverKit Audio
- OpenEQ: `SystemAudioEQEngine`, `docs/system-audio.md`
