# Architecture

Stack: Swift 6 toolchain, SwiftUI, AVFoundation (capture), Vision (hand pose), AVFAudio (`AVAudioEngine`), `Synchronization` (atomics). iOS 18.0+, iPhone, portrait. No third-party runtime dependencies. No network.

## 1. Shape of the system

Two Swift modules:

- **`HandtoneCore`** — pure Swift, imports only `Foundation` and `Synchronization`. Holds every decision the app makes: smoothing, gesture detection, note mapping, and the synthesizer's DSP. Compiles and unit-tests on Linux (WSL), so it can be verified without an iPhone.
- **`Handtone`** (app) — thin adapters around Apple frameworks: camera, Vision, audio I/O, SwiftUI. Contains as little logic as possible, because it can only be tested on the device.

This split is the main architectural response to having no Mac: anything that can be wrong in a subtle way lives where it can be tested on Windows.

```
 Camera (AVCaptureSession)
        │  CVPixelBuffer + timestamp        [video queue, serial]
        ▼
 HandTracker (Vision)                       [video queue]
        │  HandFrame (0–2 hands × 21 points, normalized, upright, mirrored-as-displayed)
        ▼
 ┌──────────────── HandtoneCore ────────────────┐
 │ LandmarkSmoother → PinchDetector → InteractionMode │   [video queue]
 │            │                         │              │
 │            │ smoothed HandFrame      │ [NoteEvent]  │
 └────────────┼─────────────────────────┼──────────────┘
              │                         ├──────────────► SynthCore voice slots (atomics)
              ▼                         ▼                        │
        AppModel (@MainActor, @Observable)                       ▼
              │                                   AVAudioSourceNode render block
              ▼                                   [real-time audio thread] → speaker
        SwiftUI overlay + feedback
```

**Key property:** a note event goes from the video queue straight into the synth's atomic voice slots. It never waits for the main thread. The UI is informed in parallel and may lag by a frame without affecting sound.

## 2. Threads

| Thread | Runs | Rules |
|--------|------|-------|
| Video queue (serial `DispatchQueue`, `.userInteractive`) | capture delegate, Vision request, smoothing, gesture detection, mapping, writing note events | One frame at a time. If a frame is still being processed, the next is dropped by AVFoundation. |
| Audio render thread (system, real-time) | `SynthCore.render` | No allocation, no locks, no Swift runtime calls that can block, no logging, no `async`. Reads atomics only. |
| Main actor | SwiftUI, `AppModel`, settings | Receives throttled snapshots (latest hand frame, active notes, stats). Never on the audio path. |
| Session queue (serial) | `AVCaptureSession` configuration, start/stop, camera switch | Apple requires session mutations off the main thread. |

## 3. Camera layer

`CameraController` (app module).

- `AVCaptureSession`, preset `.hd1280x720`. (Vision downsamples internally; 720p keeps the preview sharp. If M3's fps gate fails, try `.vga640x480` before anything else.)
- Devices: `.builtInWideAngleCamera`, position `.front` (default) or `.back`.
- Frame rate: choose the highest format supporting 60 fps at the session resolution and set `activeVideoMin/MaxFrameDuration` to 1/60; fall back to 30. 60 fps halves the average wait between a gesture and the frame that captures it (≈8 ms vs ≈17 ms).
- `AVCaptureVideoDataOutput`: `alwaysDiscardsLateVideoFrames = true`; pixel format `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`; delegate on the video queue.
- **Orientation, decided once here so nothing downstream thinks about it:** on the data-output connection set `videoRotationAngle = 90` (portrait) and `isVideoMirrored = true` for the front camera. Buffers then arrive upright and already mirrored exactly as displayed. Vision is called with orientation `.up`.
- Preview: `AVCaptureVideoPreviewLayer` in a `UIViewRepresentable`, `videoGravity = .resizeAspectFill`. Mirroring on the preview connection matches the data connection.
- Coordinate conversion: landmarks are normalized to the full video frame; the preview crops it (aspect fill). Convert with `previewLayer.layerPointConverted(fromCaptureDevicePoint:)` or an explicit aspect-fill transform computed from video and view sizes. The overlay must use the same transform — verified visually in M3.
- Switching cameras: on the session queue, `beginConfiguration`, swap the input, reapply rotation/mirroring/frame rate, `commitConfiguration`. Before the swap, send "all notes off" and reset the core pipeline state.
- Lifecycle: stop the session on background, restart on foreground; handle `AVCaptureSession.wasInterruptedNotification` and runtime errors.

## 4. Hand-tracking layer

```swift
protocol HandTracker {
    /// Called on the video queue. Synchronous. Returns nil only on hard failure.
    func detect(in pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) -> HandFrame?
}
```

`VisionHandTracker`: one reused `VNDetectHumanHandPoseRequest` with `maximumHandCount = 2`; per frame a `VNImageRequestHandler(cvPixelBuffer:orientation:.up)`; `perform` synchronously. For each observation read `recognizedPoints(.all)` and map the 21 `VNHumanHandPoseObservation.JointName` cases to the core's `Joint` enum. Vision's origin is bottom-left: convert to top-left (`y = 1 - y`) inside the adapter, so the core only ever sees "x right, y down, 0…1, as displayed".

Core data model (all value types, `Sendable`, `Codable` for fixtures):

```swift
enum Joint: Int, CaseIterable { case wrist, thumbCMC, thumbMP, thumbIP, thumbTip,
    indexMCP, indexPIP, indexDIP, indexTip, middleMCP, middlePIP, middleDIP, middleTip,
    ringMCP, ringPIP, ringDIP, ringTip, littleMCP, littlePIP, littleDIP, littleTip }

struct Landmark { var x: Float; var y: Float; var confidence: Float }
struct Hand { var landmarks: [Landmark] /* 21, indexed by Joint */ }
struct HandFrame { var timestamp: TimeInterval; var hands: [Hand] /* 0…2 */ }
```

### 4.1 Stable hand identity

Vision returns hands in no guaranteed order, and chirality is unreliable under mirroring. The core assigns each hand to a **slot** (`.left` / `.right` *of the screen*) itself:

- Two hands: the one whose wrist has the smaller x is `.left`.
- One hand: keep the slot it had in the previous frame if it was tracked (nearest-wrist match); otherwise assign by which half of the screen the wrist is in.
- Apply hysteresis: two hands swap slots only if their x-order has been reversed for 5 consecutive frames. This prevents a note flip-flop when hands are close together.

### 4.2 Smoothing

Per landmark coordinate, a **One Euro filter** (Casiez et al., https://gery.casiez.net/1euro/): low cutoff when the hand is still (kills jitter), high cutoff when moving (keeps lag small). Starting parameters: `minCutoff = 1.5 Hz`, `beta = 0.05`, `dCutoff = 1.0 Hz`, using real frame timestamps. Landmarks with `confidence < 0.3` do not update the filter (hold last value).

The smoothed frame feeds both the overlay and gesture detection. The pinch detector's hysteresis (below) is the main defence against jitter; the filter is deliberately light so it does not add perceptible latency.

### 4.3 Pinch detection

For hand *h* and finger *f* ∈ {index, middle, ring, little}:

```
handScale = distance(wrist, middleMCP)                 // normalizes for distance from camera
d(f)      = distance(thumbTip, fTip) / handScale
```

State machine per (hand slot, finger):

- `open → pinched` when `d < onThreshold` (start: 0.22) and both tips have confidence ≥ 0.3.
- `pinched → open` when `d > offThreshold` (start: 0.34).
- **Closest-finger rule:** when the thumb is near several fingertips, only the finger with the smallest `d` may enter `pinched` in that frame. Prevents the middle finger firing along with the index.
- **Refractory period:** after a release, the same finger cannot re-trigger for 60 ms.

All four numbers live in `InteractionConfig` and are adjustable at runtime from the debug panel — tuning them must not require a rebuild.

### 4.4 Tracking loss

`HandPresenceTracker` per slot:

- Hand missing for ≤ 150 ms (grace period): keep pinch states frozen; sounding notes continue.
- Missing for longer: emit note-off for every note owned by that slot, reset its filters and pinch states.
- Hand reappears: states start at `open`; a finger that is already pinched on reappearance triggers only after it has been seen open once (prevents a burst of notes when a closed hand enters the frame).

## 5. Musical interaction layer

```swift
struct NoteEvent { enum Kind { case on, off }
    var kind: Kind; var id: NoteID      // (slot, finger) — identifies the gesture, not the pitch
    var midiNote: Int; var velocity: Float; var position: SIMD2<Float> /* fingertip, for UI */ }

protocol InteractionMode {
    mutating func process(_ frame: TrackedFrame, config: InteractionConfig) -> [NoteEvent]
    mutating func reset() -> [NoteEvent]          // returns note-offs for anything sounding
}
```

`PinchScaleMode` (MVP): maps `(slot, finger)` to a scale degree — left slot index→little = degrees 0–3, right slot index→little = degrees 4–7 — then `midiNote = root + scale.semitones(degree)`. With `Scale.major` and root C4 (MIDI 60): C D E F | G A B C.

Frequency: `f = 440 × 2^((midi − 69) / 12)`.

`InteractionConfig` (`Codable`, persisted as JSON in `UserDefaults`): root note, scale, thresholds, refractory, grace period, smoothing parameters. Future modes (air zones, theremin) are new types conforming to `InteractionMode`; nothing upstream or downstream changes. `NoteEvent` would gain a `.bend` kind for continuous modes — not in the MVP.

## 6. Audio layer

### 6.1 Session

`AVAudioSession`: category `.playback` (sounds even with the ring/silent switch on), `setPreferredIOBufferDuration(0.005)`, `setActive(true)`. Read back the actual `sampleRate` and `ioBufferDuration`; never assume 44.1 kHz. Handle `interruptionNotification` (stop voices, restart engine when it ends) and `routeChangeNotification`.

### 6.2 Engine

`AVAudioEngine` → one `AVAudioSourceNode` (mono Float32 at the hardware sample rate) → `mainMixerNode` → output. Master volume and mute are applied inside the synth as a smoothed gain (not via mixer volume changes), to avoid clicks.

### 6.3 SynthCore (in `HandtoneCore`)

- Fixed pool of **8 voices**, preallocated. Each voice: phase accumulator, small additive oscillator (fundamental + 2–3 harmonics chosen by preset), linear ADSR envelope.
- Presets (MVP): **Soft** (attack 8 ms, sustained while pinched, release 250 ms) and **Pluck** (attack 2 ms, exponential decay ~600 ms regardless of hold).
- **Control → audio handoff:** each voice slot has `Atomic` fields: `gate` (generation counter, incremented on note-on), `frequencyBits`, `targetLevel`, `released` flag. The control side (video queue) writes them; the render thread reads them at the start of each buffer. No locks, no queues, no allocation. Because voice allocation is done only by the control side (one writer), the scheme stays trivially correct.
- Voice allocation: `NoteID → voice index` map on the control side; steal the oldest released voice, else the oldest voice.
- **No clicks:** every amplitude change goes through the envelope (minimum 2 ms ramp); voice stealing ramps the old note down over 3 ms before retuning; output is soft-limited (`tanh`-style or simple clip at 0.9 after scaling by 1/√voices).
- The render function has the signature `render(into: UnsafeMutableBufferPointer<Float>, sampleRate: Double)` and is unit-tested on Linux: correct pitch (zero-crossing count), no NaN/denormals, bounded output, silence after release.

### 6.4 Why not AudioKit, a sampler, or MIDI

AudioKit is healthy (5.7.2, March 2026) but would add a dependency to replace about 150 lines of DSP, and it is untested under xtool. `AVAudioUnitSampler` with a SoundFont gives realistic instruments and is the natural **future** upgrade; it needs asset files and its note-on latency should be measured before adopting it.

### 6.5 Latency budget (engineering estimate, to be measured)

| Stage | 60 fps camera | 30 fps camera |
|-------|---------------|---------------|
| Wait for next frame (average) | ~8 ms | ~17 ms |
| Sensor readout + delivery | ~15–30 ms | ~15–35 ms |
| Vision inference | ~10–25 ms | ~10–25 ms |
| Core logic | < 1 ms | < 1 ms |
| Audio buffer + output (speaker) | ~10–15 ms | ~10–15 ms |
| **Total** | **~45–80 ms** | **~55–95 ms** |

Bluetooth headphones add 150–250 ms and make the instrument feel broken; the settings sheet shows a one-line note when a Bluetooth route is active. Wired headphones and the built-in speaker are fine.

## 7. UI layer

One screen (`MainScreen`), a `ZStack`:

1. `CameraPreviewView` — full bleed.
2. `HandOverlayView` — SwiftUI `Canvas` drawing fingertip dots and thin bone lines from the latest smoothed frame. Redraws when `AppModel.handFrame` changes.
3. `NoteFeedbackView` — on note-on, an expanding ring at the fingertip plus the note name; fades in 400 ms. Driven by a short list of recent `NoteEvent`s.
4. `ControlsBar` — bottom, translucent material: camera-flip button, mute button, volume slider, settings button. Nothing else.
5. `SettingsSheet` — scale, root, sound preset, skeleton toggle. Medium-detent sheet.
6. `DebugHUD` (hidden; triple-tap to toggle) — camera fps, tracking fps, inference ms, pipeline ms, audio buffer size, sample rate, per-finger pinch distances, live sliders for thresholds, "record landmarks" button.
7. `PermissionView` — shown instead of the preview when camera access is denied, with a button to open Settings.

`AppModel` (`@MainActor @Observable`) owns the controllers and exposes: `handFrame`, `recentNotes`, `stats`, `settings`, `cameraPosition`, `permission`. The pipeline pushes snapshots to it with `Task { @MainActor in … }`, coalesced so that at most one update is pending.

`UIApplication.shared.isIdleTimerDisabled = true` while the main screen is visible (the user is not touching the screen while playing).

## 8. Configuration and persistence

`Settings` + `InteractionConfig` as one `Codable` struct in `UserDefaults`. No database, no files except optional debug landmark recordings in the app's Documents folder (exported through the share sheet).

## 9. Deliberate simplifications

- Portrait only; no rotation handling.
- One interaction mode, one tracker backend, one synth.
- No dependency-injection framework, no coordinator pattern, no Combine pipelines. Plain classes and one observable model.
- No localization in the MVP (English strings, kept in one file to make it easy later).

## 10. Extension points

| Future need | Where it plugs in |
|-------------|-------------------|
| New gesture/mapping | New `InteractionMode` type |
| MediaPipe tracker | New `HandTracker` conformer; add SwiftPM binary dependency |
| Sampled instruments | Alternative audio backend behind the same `noteOn/noteOff` interface |
| Velocity, pitch bend | Extra fields/kinds on `NoteEvent`; extra atomics per voice |
| MIDI out | Subscriber to the `NoteEvent` stream |
