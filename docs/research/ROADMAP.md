# Roadmap

Nine small milestones. Each ends with something observable on the iPhone or a green test run. The order front-loads the three risks: **can we get a build onto the phone at all (M0), is audio fast (M1), is tracking fast and accurate (M3)**. UI polish comes last.

Legend — **Where it is verified:** `WSL` = `swift test` on the Windows machine; `CI` = GitHub Actions; `Device` = the user observes on the iPhone and reports back.

| # | Milestone | Risk retired | Verified |
|---|-----------|--------------|----------|
| M0 | Toolchain: empty app on the iPhone | Build + install without a Mac | Device |
| M0.5 | *(optional)* Browser prototype of the interaction | Wrong interaction design | Browser |
| M1 | Synth + audio engine with on-screen test pads | Audio latency, glitches | WSL + Device |
| M2 | Camera preview and switching | Capture, permission, orientation | Device |
| M3 | Hand tracking + overlay + performance HUD | Tracking speed and alignment | Device |
| M4 | Core gesture logic (smoothing, slots, pinch, mapping) | False/duplicate triggers | WSL |
| M5 | Integration: pinch plays notes | End-to-end latency | Device |
| M6 | Visual feedback and controls | Usability | Device |
| M7 | Settings, robustness, lifecycle | Stuck notes, interruptions | Device |
| M8 | *(optional)* Distribution hardening | 7-day expiry | — |

M4 does not depend on M2/M3 and can be developed in parallel with them or while waiting for device feedback.

---

## M0 — Toolchain: an empty app on the iPhone

- **Objective:** a SwiftUI "Hello" screen, built without a Mac, running on the user's iPhone. Establish both build routes and pick the daily one.
- **Files:** `Package.swift`, `xtool.yml`, `project.yml`, `App/Info.plist`, `Sources/Handtone/HandtoneApp.swift`, `Sources/HandtoneCore/Placeholder.swift`, one trivial test, `.github/workflows/core-tests.yml`, `.github/workflows/ios-build.yml`, `.gitignore`, `README.md`, `CLAUDE.md`.
- **Implementation:**
  1. Create the GitHub repository (public keeps macOS minutes free) and push the skeleton.
  2. **Route B first (lowest setup risk):** `ios-build.yml` on `macos-26`: checkout → select Xcode → `brew install xcodegen` → `xcodegen generate` → unsigned `xcodebuild` → package `Payload/` into `Handtone.ipa` → upload artifact. User downloads it (`gh run download`) and installs with Sideloadly.
  3. **Route A (timebox: half a day):** WSL2 + Swift toolchain + usbmuxd + usbipd-win + xtool per TOOLS-AND-SKILLS.md §3.1–3.2. Run `xtool new` in a scratch directory to see the canonical layout, then make this repo match. `xtool dev` to build and install.
  4. `core-tests.yml` on `ubuntu-latest`: `swift test`.
- **Dependencies:** GitHub account, Apple ID (a secondary one is advisable), USB cable, iTunes/iCloud web versions (for Sideloadly).
- **Potential problems:** SwiftPM tries to compile the iOS-only target on Linux (split into two packages — see PROJECT-STRUCTURE.md); usbipd "Device busy"; xtool `muxError` (use the iTunes relay workaround from the xtool docs); xtool Apple ID login errors (update xtool — recent releases fix exactly these); Xcode version on the runner too old for iOS 18 SDK features (select a newer Xcode); Developer Mode toggle not visible until first install; "Untrusted Developer" until the profile is trusted.
- **Testing:** launch the app on the phone; it shows "Handtone" and the build's git short hash (inject at build time or hard-code per milestone) so the user can always confirm which build is installed.
- **Acceptance:** (a) app launches on the iPhone from a Route B build; (b) `swift test` green in WSL and CI; (c) Route A either works end-to-end or is documented as abandoned with the reason. The README states which route is the daily loop.
- **Gate:** do not proceed until (a) and (b) hold. Route A is desirable, not mandatory.

## M0.5 — Optional: browser prototype of the interaction (timebox: 3 hours)

- **Objective:** settle *which gesture feels right* before writing Swift. Throwaway code.
- **Files:** `prototype/index.html` (single file, not shipped).
- **Implementation:** `@mediapipe/tasks-vision` Hand Landmarker (web) + Web Audio oscillators; implement pinch-scale with on-screen threshold sliders; run in the desktop browser with the PC webcam.
- **Why optional:** it uses a different tracker (MediaPipe) than the app (Vision), so thresholds will not transfer exactly — only the interaction design does. Skip it if the video makes the interaction unambiguous.
- **Acceptance:** the product owner says "yes, pinches" or "no, it should be X", and PRD §4 is updated.

## M1 — Synth and audio engine

- **Objective:** polyphonic synth with measured low latency, driven by eight on-screen pads. No camera yet.
- **Files:** Core `Synth/*`, `Music/Pitch.swift`, `Music/Scale.swift`; App `Audio/AudioEngine.swift`, temporary `UI/TestPadsView.swift`, `Debug/PerfStats.swift`; tests `SynthCoreTests`, `PitchScaleTests`.
- **Implementation:** as ARCHITECTURE.md §6. Write and test `SynthCore.render` on Linux first. Then host it in `AVAudioSourceNode`. Pads call `noteOn/noteOff` on touch-down/up (use a `DragGesture(minimumDistance: 0)`, not `Button`, so the note starts on touch-down). Show actual sample rate and IO buffer duration on screen.
- **Dependencies:** M0.
- **Potential problems:** render block capturing `self` or Swift objects that retain/release on the audio thread (capture an `Unmanaged`/pointer to the synth state instead); assuming 44.1 kHz; buffer duration request ignored (read back the real value); clicks on note start/stop (envelope ramps); silence because the session was never activated or the silent switch (category must be `.playback`); format mismatch between source node and mixer.
- **Testing:** unit tests (pitch within ±1 cent via zero-crossing or autocorrelation, bounded output, no NaN, silence within release time, 8-voice polyphony, voice stealing without discontinuity > threshold). Device: play pads; latency test T-A1 in TESTING.md.
- **Acceptance:** tests green; pads play clean chords of 8 notes; no clicks on rapid repeated taps; reported IO buffer ≤ 10 ms; touch-to-sound feels immediate (N3).
- **Gate:** audible clicks or > 10 ms buffers must be resolved before moving on. Audio problems are far easier to isolate now than under the camera pipeline.

## M2 — Camera preview and switching

- **Objective:** full-screen mirrored front-camera preview, a flip button, correct permission handling.
- **Files:** `Camera/CameraController.swift`, `Camera/CameraPreviewView.swift`, `UI/PermissionView.swift`, `UI/MainScreen.swift` (first version), `AppModel.swift`.
- **Implementation:** ARCHITECTURE.md §3. Request permission on first launch. Add the video data output now (delegate counts frames only) and display camera fps in a corner label.
- **Dependencies:** M0. Independent of M1 — but keep the M1 pads reachable (debug toggle) to confirm camera and audio coexist.
- **Potential problems:** black preview (session started before input added, or configured on main thread); wrong rotation; front preview not mirrored or mirrored twice; 60 fps format not found for front camera (fall back to 30, show which is active); session not restarted after backgrounding; starting capture stalls the audio engine briefly.
- **Testing:** T-C1…T-C5 in TESTING.md.
- **Acceptance:** preview upright and mirrored on front, upright and not mirrored on rear; flip works 10 times in a row; deny-permission path shows `PermissionView`; fps label ≥ 30; audio pads still glitch-free while the camera runs.
- **Gate:** all of the above.

## M3 — Hand tracking, overlay, performance HUD

- **Objective:** 21 landmarks for up to two hands drawn exactly on top of the user's hands, with measured performance. Record fixtures for M4.
- **Files:** Core `Models/*`; App `Tracking/HandTracker.swift`, `Tracking/VisionHandTracker.swift`, `Pipeline/PerformancePipeline.swift`, `UI/HandOverlayView.swift`, `UI/DebugHUD.swift`, `Debug/LandmarkRecorder.swift`.
- **Implementation:** ARCHITECTURE.md §4 (adapter only — no smoothing yet; draw raw points). HUD: camera fps, tracking fps, inference ms (p50/p95 over 2 s), hands detected. Recorder: append each `HandFrame` as one JSON line; export via share sheet (AirDrop is unavailable to Windows — use Mail, Files → iCloud Drive, or any messaging app).
- **Dependencies:** M2.
- **Potential problems:** overlay offset because of aspect-fill cropping (the classic bug — test at screen edges); y-axis flipped; overlay mirrored relative to preview; Vision returning low-confidence garbage points (filter by confidence); performing Vision on the main thread; publishing to the main actor on every frame causing UI backlog (coalesce); thermal throttling after minutes.
- **Testing:** T-H1…T-H6 in TESTING.md. Record the fixture set listed in TESTING.md §5 and commit it under `Tests/HandtoneCoreTests/Fixtures/`.
- **Acceptance (performance gate):** with two hands: tracking ≥ 25 fps sustained for 3 minutes, inference p95 ≤ 35 ms; fingertip dots visually within about one fingertip-width of the real fingertips across the whole screen including edges, on both cameras; fixtures committed.
- **Gate / decision:** if fps fails → try 640×480, then `maximumHandCount = 1` to isolate cost. If still failing, or thumb–finger contact is not resolved reliably (visible in the recorded pinch distances), implement the MediaPipe backend behind `HandTracker` before continuing. Record the decision in the README.

## M4 — Core gesture logic (off-device)

- **Objective:** the complete `HandFrame → [NoteEvent]` pipeline, fully unit-tested, including replay of the real fixtures from M3.
- **Files:** Core `Filtering/*`, `Tracking/*`, `Gestures/PinchDetector.swift`, `Music/InteractionConfig.swift`, `Music/InteractionMode.swift`, `Music/PinchScaleMode.swift`, `Pipeline/GesturePipeline.swift`; all matching tests.
- **Implementation:** ARCHITECTURE.md §4.1–4.4 and §5. Test-first: synthetic sequences for each rule, then fixture replays with expected event counts.
- **Dependencies:** `Models/*` (from M3). Synthetic tests can start before fixtures exist.
- **Potential problems:** thresholds tuned on synthetic data that do not match real hands (that is what fixtures are for); frame-rate-dependent behaviour (use timestamps, never frame counts, except the 5-frame slot hysteresis which should also become time-based if fps varies); floating-point comparisons in tests.
- **Testing:** `swift test` in WSL and CI. Cases enumerated in TESTING.md §4.
- **Acceptance:** all tests green; replaying "open hands resting 30 s" yields 0 events; replaying "8 deliberate pinches" yields exactly 8 note-on and 8 note-off in the right order; replaying "hand leaves frame while pinching" ends with no sounding note.
- **Gate:** all of the above.

## M5 — Integration: pinch plays notes

- **Objective:** the instrument works end to end.
- **Files:** `Pipeline/PerformancePipeline.swift` (wire `GesturePipeline` and `SynthCore`), `DebugHUD.swift` (pinch distances + threshold sliders + pipeline latency), remove `TestPadsView` from the main path (keep behind the debug toggle).
- **Implementation:** on the video queue: frame → tracker → `GesturePipeline.process` → for each event call synth `noteOn/noteOff` directly → post snapshot to `AppModel`. Measure and display `now − frame presentation timestamp` at the moment of note-on.
- **Dependencies:** M1, M3, M4.
- **Potential problems:** note events routed through the main actor (adds latency — must not happen); thresholds needing adjustment on the real device (use the sliders, then commit the new defaults); a hand at screen centre hopping between slots; front-camera mirroring making "left" feel wrong (the rule is *screen* left — verify it feels natural, flip if not).
- **Testing:** T-E1…T-E5 and the slow-motion latency measurement T-L1 in TESTING.md.
- **Acceptance:** N1 (≤ 100 ms median gesture-to-sound), N4 (no false triggers in 60 s), N5 (no stuck notes); a C-major scale can be played up and down with two hands at a moderate tempo without missed or doubled notes in 3 consecutive attempts.
- **Gate:** if latency fails, profile by stage using the HUD numbers before changing anything; the budget table in ARCHITECTURE.md §6.5 says where to look.

## M6 — Visual feedback and controls

- **Objective:** the screen described in the PRD: clean overlay, note feedback, controls bar.
- **Files:** `UI/NoteFeedbackView.swift`, `UI/ControlsBar.swift`, `UI/HandOverlayView.swift` (final styling), `UI/MainScreen.swift`.
- **Implementation:** ARCHITECTURE.md §7. Ring pulse + note name at the fingertip on note-on; fingertip dots tinted while their note sounds. Controls: flip, mute, volume slider, settings (sheet stub). One hint line ("Touch thumb to a finger") that disappears after the first note. Idle timer disabled.
- **Dependencies:** M5.
- **Potential problems:** SwiftUI animations or `Canvas` redraws lowering tracking fps (check the HUD before/after); controls unreachable under the home indicator; volume changes clicking (must go through the synth's smoothed gain).
- **Testing:** T-U1…T-U4.
- **Acceptance:** F7, F8 pass; tracking fps drop from adding UI ≤ 2 fps; a new user understands what to do without explanation (try it on one person).
- **Gate:** fps regression must be fixed before M7.

## M7 — Settings, robustness, lifecycle

- **Objective:** survive real-world use.
- **Files:** `UI/SettingsSheet.swift`, `Settings.swift`, lifecycle handling in `AppModel`, `AudioEngine`, `CameraController`.
- **Implementation:** settings per F9 with persistence; all-notes-off on background, camera switch, settings change of scale/root, audio interruption; engine restart after interruption and route change; Bluetooth-route hint; remove debug affordances from the default UI (triple-tap remains).
- **Dependencies:** M6.
- **Potential problems:** engine not restarting after a phone call; `AVAudioEngineConfigurationChange` when plugging headphones (sample rate changes — SynthCore must take the new rate); settings change racing the video queue (swap an immutable config value atomically).
- **Testing:** T-R1…T-R8.
- **Acceptance:** F9–F11 pass; every robustness test passes; 10-minute play session with no glitch, stuck note, or crash (N6, N7).
- **Gate:** this is the MVP. Tag `v0.1.0`.

## M8 — Optional: distribution hardening

Only if wanted. (a) Enable Sideloadly/xtool automatic refresh to soften the 7-day expiry. (b) Or join the Apple Developer Program ($99/year): add signing with an App Store Connect API key to the CI workflow, upload to TestFlight, 90-day builds installable over the air. Requires an app record, privacy answers ("no data collected") and an icon. Not part of the MVP.

---

## After the MVP (do not start before v0.1.0 is tagged)

In suggested order: velocity from pinch closing speed → a second interaction mode chosen from the video → `AVAudioUnitSampler` instrument sounds → reverb → haptics → landscape/iPad.
