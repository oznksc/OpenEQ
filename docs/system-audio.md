# System Audio Beta

OpenEQ V1 is built around local audio file playback. Files are decoded in the app, processed through the EQ graph, visualized locally, and played through the app output path.

System Audio Beta is the foundation for future system-audio workflows. It does not ship a virtual audio driver and should not be described as true system-wide EQ yet.

## Modes

- Disabled: OpenEQ uses local file playback only.
- Monitor Only: OpenEQ can inspect a selected input device for analysis-style workflows.
- External Loopback: OpenEQ expects the user to route macOS output through a virtual audio device such as BlackHole, then select that device as OpenEQ input.
- Native Tap Experimental: A future exploration path for Core Audio process/system taps. This is not production routing in V1.

## Why System-Wide EQ Is Experimental

macOS system-wide EQ requires capturing or routing audio that normally belongs to other apps, processing it in real time, then sending it back to an output device with stable latency and no feedback loop. A production-quality implementation usually needs careful Core Audio routing, permission handling, device-change handling, latency compensation, and in some designs a virtual audio driver.

OpenEQ V1 intentionally avoids claiming this is complete.

## Safest V1 Approach

External loopback is the safest V1 path because routing is explicit and reversible:

1. Install a virtual audio device such as BlackHole.
2. Route macOS or app output to that virtual device.
3. Select the virtual device as OpenEQ's system input.
4. Select the desired physical output device for monitoring.

This keeps driver responsibility outside OpenEQ while giving the app a clean path to process incoming audio.

## Privacy

Audio is processed locally on the Mac. OpenEQ does not send captured audio to analytics, cloud services, or external servers.
