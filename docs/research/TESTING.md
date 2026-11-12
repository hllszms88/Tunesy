# Testing strategy

There is no Simulator, no debugger and no Instruments in this workflow. Testing is built around three substitutes:

1. **Unit tests of pure logic on Linux/WSL** — everything in `HandtoneCore`.
2. **Recorded landmark fixtures** — real hand data captured once on the iPhone, replayed forever in tests.
3. **An in-app debug HUD plus short manual checklists** — the user is the test runner for anything that touches camera, Vision or the speaker, so each check must take under a minute and have an unambiguous pass/fail.

## 1. Test levels

| Level | What | Where | When |
|-------|------|-------|------|
| Unit | Filters, slot assignment, pinch state machine, presence, mapping, pitch math, synth DSP | `swift test` in WSL; `core-tests.yml` on `ubuntu-latest` | Every push |
| Replay | Whole `GesturePipeline` over recorded `.jsonl` fixtures | Same | Every push |
| Compile | App target builds for iOS | xtool locally; `ios-build.yml` on macOS runner | Every push to main / before each device test |
| Device checklist | Camera, tracking alignment, audio, lifecycle | iPhone, by the user | At each milestone gate |
| Measurement | Latency, fps, thermal | iPhone + HUD + slow-motion video | M1, M3, M5, M7 |

## 2. Debug HUD (the "instrument panel")

Toggled by triple-tap. Shows, updated twice per second:

- Build identifier (git short hash).
- Camera: position, resolution, configured fps, measured fps.
- Tracking: fps, hands detected, inference ms p50/p95.
- Pipeline: ms from frame timestamp to note-on dispatch, p50/p95 over the last 50 notes.
- Audio: sample rate, IO buffer duration (ms), output route name, active voices.
- Per finger: normalized pinch distance `d` as eight small bars with the on/off thresholds marked.
- Sliders: on threshold, off threshold, One Euro `minCutoff` and `beta`.
- Buttons: **Record landmarks** (start/stop + share), **Copy stats** (puts a text summary on the clipboard so the user can paste it to the agent), **Test pads**.

"Copy stats" is important: it turns "it feels laggy" into numbers the coding agent can act on.

## 3. Reporting protocol between user and agent

For every device check the agent states: the build hash to expect, numbered steps, and the exact observation that counts as pass. The user replies with pass/fail per step and, on failure, pastes "Copy stats" output and — where visual — a screenshot or screen recording. The agent must not mark a device-verified acceptance criterion as done without that report.

## 4. Unit and replay test cases (HandtoneCore)

**OneEuroFilter** — constant input returns the constant; step input converges; noisy constant input has output variance below input variance; fast ramp lags by less than a set bound; irregular timestamps handled; first sample passes through.

**HandSlotAssigner** — two hands ordered by x; single hand keeps its previous slot when it moves across centre; single new hand assigned by screen half; brief x-order crossing (< hysteresis) does not swap; sustained crossing swaps; hand disappearing and another appearing far away is treated as a new hand.

**PinchDetector** — distance below on-threshold triggers once; distance oscillating between the thresholds causes no extra events; release only above off-threshold; refractory period blocks immediate re-trigger; closest-finger rule when two fingertips are near the thumb; low-confidence tips never trigger; scale invariance (same hand at half size gives same result).

**HandPresenceTracker** — loss shorter than grace keeps the note; longer loss emits note-off exactly once; hand reappearing already pinched does not trigger until seen open.

**PinchScaleMode / Scale / Pitch** — (slot, finger) → MIDI note for each scale and root; MIDI 69 = 440 Hz, MIDI 60 ≈ 261.63 Hz; note names; `reset()` returns offs for all sounding notes; changing config mid-note releases the old pitch, not the new one.

**SynthCore** — rendered pitch within ±1 cent for several notes at 44.1 and 48 kHz; output always within [−1, 1]; no NaN/Inf; 8 simultaneous notes do not clip; note-off reaches silence (< −80 dBFS) within release time + margin; note-on/off produces no sample-to-sample jump above a small bound (click test); voice stealing with 9 notes; master gain change is ramped; rendering 10 s of audio performs no allocation (assert via a simple allocation-free code review rule and, where possible, by running under a debug allocator hook — otherwise review only).

**GesturePipeline replay** — see fixture table below.

## 5. Fixtures to record on the device (during M3)

Each is a `.jsonl` file of `HandFrame`s, 10–30 s, recorded with the HUD. Name, content, and the assertion the replay test makes:

| File | Recording | Assertion after M4 |
|------|-----------|--------------------|
| `rest_two_hands.jsonl` | Both hands open, relaxed, small natural movement, 30 s | 0 note-on |
| `scale_up_two_hands.jsonl` | Deliberately pinch index→little on the left hand, then the right, ~1 per second | exactly 8 note-on, 8 note-off, in ascending pitch order |
| `fast_repeats_index.jsonl` | One finger, 10 quick pinches | exactly 10 note-on |
| `chord.jsonl` | Pinch two fingers of different hands simultaneously, hold 2 s, release | 2 note-on within 100 ms of each other, 2 note-off |
| `leave_while_pinching.jsonl` | Pinch and hold, move the hand out of frame | note-off within grace + one frame; nothing sounding at end |
| `enter_fist.jsonl` | Bring a closed fist into frame, then open it | 0 note-on |
| `hands_cross_centre.jsonl` | One hand moving left↔right across the centre while pinching index repeatedly | every note-on has the same pitch class set expected by the slot rule; no slot flip-flop (at most one change per crossing) |
| `one_hand_each_side.jsonl` | Single hand on the left half pinching all four, then on the right half | degrees 0–3 then 4–7 |
| `rear_camera_scale.jsonl` | Same as the scale, rear camera | exactly 8 note-on |
| `low_light.jsonl` | Scale in dim light | informational; record miss count, do not gate |

Record expected counts aloud or in the filename when recording; ground truth comes from what the user intended to do.

## 6. Device checklists

### Audio (M1)
- **T-A1 Latency (touch):** HUD shows IO buffer ≤ 10 ms. Tap a pad sharply with a fingernail while recording with another device; in an audio editor (Audacity, free, Windows) measure the gap between the nail-tap click and the tone onset. Pass ≤ 30 ms.
- **T-A2 Polyphony:** hold all eight pads. Clean, no distortion.
- **T-A3 Clicks:** tap one pad rapidly 30 times. No clicks or pops.
- **T-A4 Silent switch:** with the ring/silent switch on silent, sound still plays.
- **T-A5 Routes:** plug in wired headphones mid-note and unplug. Audio continues on the new route within a second, no crash.

### Camera (M2)
- **T-C1** Front preview is upright and mirrored (raise your right hand; it appears on the right side of the screen).
- **T-C2** Rear preview is upright and not mirrored (text in the scene is readable).
- **T-C3** Flip 10 times quickly; preview always recovers; no crash.
- **T-C4** Deny permission on first launch → `PermissionView` with a working "Open Settings" button; granting in Settings and returning shows the preview.
- **T-C5** Background the app for 10 s and return; preview resumes. Camera fps label ≥ 30.

### Hand tracking (M3)
- **T-H1 Alignment centre:** open hand at screen centre; all five fingertip dots sit on the fingertips.
- **T-H2 Alignment edges:** move the hand to each edge and corner; dots stay on the fingertips (this catches aspect-fill transform errors).
- **T-H3 Mirroring:** move the hand left; the dots move left with it, on both cameras.
- **T-H4 Two hands:** both tracked simultaneously; HUD says 2.
- **T-H5 Performance:** two hands in view for 3 minutes; paste "Copy stats" at 0:30 and 3:00. Pass: tracking ≥ 25 fps, inference p95 ≤ 35 ms at both times.
- **T-H6 Range:** find the nearest and farthest distance at which tracking holds; note them. Expect roughly 25–80 cm.

### End to end (M5)
- **T-E1** Scale up and down with two hands, three attempts; no missed or doubled notes.
- **T-E2** Rest both open hands in view for 60 s; zero notes.
- **T-E3** Pinch and hold; move the hand out of frame; the note stops within about a quarter second.
- **T-E4** Bring a fist into frame; no note. Open it; no note.
- **T-E5** Hold a pinch for 10 s without moving; the note sustains without re-triggering (Soft preset).

### Latency, end to end (M5)
- **T-L1 Slow-motion measurement:** prop the iPhone so its screen and the player's hand are both visible to a second camera recording at 240 fps *with sound* (most phones' slow-motion mode). Perform 10 sharp pinches. On Windows, open the clip in an editor that shows frames and waveform (DaVinci Resolve free, or extract audio with ffmpeg and view both). For each pinch: count frames from first thumb–finger contact to the audio onset; latency = frames / 240 s. Subtract ~1 ms per 34 cm between phone speaker and recording microphone if far apart. Pass: median ≤ 100 ms, worst of 10 ≤ 140 ms.
- **T-L2 Internal consistency:** HUD pipeline p50 (frame timestamp → note dispatch) should be roughly T-L1 minus 25–45 ms (sensor exposure/readout before the timestamp, plus audio output). A large disagreement means a hidden queue somewhere.

If no second camera is available: T-L2 alone plus subjective judgement ("does a pinch feel like it makes the sound?") is acceptable for the MVP, but note in the README that N1 was not objectively measured.

### UI (M6)
- **T-U1** Each note-on shows a pulse at the correct fingertip with the correct note name.
- **T-U2** Mute silences immediately without a click; unmute restores.
- **T-U3** Volume slider changes loudness smoothly, no zipper noise.
- **T-U4** Tracking fps with final UI is within 2 fps of the M5 figure.

### Robustness (M7)
- **T-R1** Receive a phone call (or trigger Siri) while a note is sounding; note stops; after dismissing, the instrument works without relaunch.
- **T-R2** Lock the phone while pinching; unlock; no stuck note, preview resumes.
- **T-R3** Flip camera while holding a pinch; the note stops; playing works on the other camera.
- **T-R4** Change scale and root while holding a pinch; old note stops; new pinches use the new scale.
- **T-R5** Settings persist across force-quit and relaunch.
- **T-R6** Connect Bluetooth headphones; the latency hint appears in settings.
- **T-R7** 10-minute continuous session: no glitch, no stuck note, no crash; paste stats at the end (fps still ≥ 25).
- **T-R8** Cover the camera with a finger for 5 s, uncover; tracking resumes; nothing stuck.

## 7. What is not tested in the MVP

UI automation (needs XCUITest on macOS), accessibility audit, multiple device models, low-power mode behaviour beyond T-R7, localisation. If a second iPhone model is available, run T-H5 and T-L1 on it and record the figures.

## 8. Crash and log diagnosis without Xcode

- Use `os.Logger` with a single subsystem. With xtool attached over USB, device logs can be streamed from WSL using libimobiledevice's `idevicesyslog` (prior knowledge — verify availability via `apt install libimobiledevice-utils`).
- Crash reports: Settings → Privacy & Security → Analytics & Improvements → Analytics Data → find `Handtone-…` → share the `.ips` file. Addresses will be unsymbolicated without the dSYM; keep the CI build's dSYM as a workflow artifact so a crash can be symbolicated later on a macOS runner if ever necessary.
- Prefer prevention: wrap session/engine setup in `do/catch`, surface the error text in the HUD, and never `try!` or force-unwrap in adapter code.
