# System Audio

OpenEQ can process system-wide audio on macOS 14.2+ using a Core Audio process tap and a private aggregate device. External loopback (BlackHole) remains available as an advanced fallback.

**Primary UX:** one-click **Start System EQ** (header, menu bar, or System Audio sheet). No virtual driver install.

## Modes

- **Disabled**: EQ applies only to local file playback.
- **System-Wide EQ** (primary): Private aggregate owns the physical speakers + a process tap. System default output is briefly redirected to that aggregate while System EQ runs (restored on stop). Tap uses `mutedWhenTapped` so dry audio is silenced only while OpenEQ is reading/processing the stream.
- **Per-app EQ** (routing graph): Same engine with `CATapDescription` mixdown of selected process object IDs or (macOS 26+) bundle IDs. Only the selected app is captured/muted-when-tapped; other apps keep their normal path when the HAL allows.
- **Microphone monitor** (routing graph): Hardware input → EQ → output via the loopback engine. **Does not** inject into Teams/Zoom as a virtual mic (that needs a HAL/DriverKit device — deferred).
- **External Loopback** (advanced): User routes macOS output through a virtual device such as BlackHole; OpenEQ processes that input with `AVAudioEngine`.

## Routing graph

The main window is a node canvas. **Run Graph** (toolbar or status bar) compiles a simple chain:

`App | System Audio | Microphone → Equalizer → Output`

| Action | Behavior |
|--------|----------|
| Run Graph | Preferred chain: app/system process tap first, else mic monitor |
| System EQ toolbar | Ensures System → EQ → Output exists, then runs process path |
| Live rewire | Topology/source/output edits debounce ~450 ms and re-run if live |
| EQ slider / curve | Live `updateEQ` without full restart |
| Stop / Safe Mode | Tears down engines and restores default output |

v1 runs **one** process-tap chain or **one** input monitor at a time (not both). File playback still uses the local `AVAudioEngine` path.

### Keyboard (canvas)

- `Delete` / `Backspace` — remove selection  
- `Esc` — clear selection  
- `+` / `-` — zoom  
- `⌘0` — reset zoom/pan  
- `⌘↩` — Run / Stop graph  

### Honesty labels

- **App / System** nodes: experimental process tap; needs Screen & System Audio Recording  
- **Microphone** node: monitor-only path (you hear processed mic); not injectable into Teams/Zoom without a virtual device

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
