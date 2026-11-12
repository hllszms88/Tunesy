# Handoff to Claude Opus

You are implementing **Handtone**, an iPhone app that turns hand gestures seen by the camera into musical notes. This document tells you what is decided, what is assumed, what was verified, and how to work given the unusual constraint: **the developer has Windows 11 and an iPhone, and no Mac.**

Read in this order: this file → PRD.md → ARCHITECTURE.md → PROJECT-STRUCTURE.md → ROADMAP.md → TESTING.md. TOOLS-AND-SKILLS.md and TECHNOLOGY-COMPARISON.md are reference.

## 1. The situation

- The developer knows React/Next.js/Node well and is new to Swift. Explain Swift- or iOS-specific decisions briefly when you make them; do not assume they can spot an iOS bug by reading the code.
- You cannot run the app. Nobody can run it in a simulator (no Mac; and the Simulator has no camera anyway). The only runtime is the developer's physical iPhone. **The developer is your eyes and ears** for anything involving camera, tracking quality or sound.
- You *can* compile and unit-test the pure-logic package in WSL, and — if xtool was set up successfully in M0 — compile the whole app locally. Otherwise the compiler is a GitHub Actions macOS runner, 5–10 minutes per round trip.
- Every build that needs a human check costs the developer several minutes. Batch changes sensibly, and never ask for a device test of something a unit test could have decided.

## 2. Decisions that are final (do not revisit without a failed gate)

| Decision | Reason |
|----------|--------|
| Native Swift + SwiftUI. No React Native, Expo, Flutter, Capacitor. | The two critical components are native on every stack; cross-platform layers add bridges and, for Expo, a mandatory $99/year. See TECHNOLOGY-COMPARISON.md. |
| Apple Vision (`VNDetectHumanHandPoseRequest`) for hand tracking, behind a `HandTracker` protocol. | Built into iOS: no package, no model file, nothing that can fail to link under xtool or CI. |
| MediaPipe only if milestone M3's performance gate fails. | Adds a binary dependency with a known SwiftPM `unsafeFlags` complication. |
| Custom synth on `AVAudioEngine` + `AVAudioSourceNode`. No AudioKit. | ~150 lines of DSP; shortest path to the speaker; testable on Linux. |
| Zero third-party runtime dependencies in the MVP. | Each dependency is a build failure that can't be debugged locally. |
| No CocoaPods, ever. | Trunk becomes read-only on 2 Dec 2026. |
| iOS 18.0 minimum, iPhone only, portrait only. | Same device coverage as iOS 17; enables `Synchronization.Atomic`. |
| Two modules: `HandtoneCore` (pure, Linux-testable) and `Handtone` (Apple-framework adapters). | The no-Mac constraint: put logic where it can be tested. |
| No backend, no network, no analytics, no accounts. | Product requirement. |

## 3. Assumptions you must treat as provisional

1. **The musical interaction.** The reference video was not available to the research session. "Pinch Scale" (PRD §4) is a reasoned default, not a transcription of the video. Before M4, ask the developer to confirm or describe what the video shows. Whatever the answer, only `InteractionMode` and its tests change.
2. **Thresholds** (pinch on 0.22 / off 0.34, refractory 60 ms, grace 150 ms, One Euro 1.5 Hz / 0.05) are starting points. Final values come from fixtures and on-device slider tuning in M5.
3. **Latency and fps figures** in ARCHITECTURE.md §6.5 are estimates. M1, M3 and M5 measure them.
4. **`xtool.yml` key names** come from secondary sources. Generate a project with `xtool new` and copy its real structure.
5. **The iPhone model is unknown.** Ask. It decides whether a 60 fps front-camera format exists and how much headroom Vision has.

## 4. Verified facts you can rely on (as of 10 Nov 2026)

- xtool builds SwiftPM iOS apps on Linux/WSL, signs and installs with a free Apple ID (password login mode); v1.24.0 released 26 Oct 2026; docs expect Swift 6.4 and Xcode 27.1's `Xcode.xip` for the SDK. https://github.com/xtool-org/xtool
- Standard GitHub-hosted runners are free for public repositories; `macos-26` / `macos-latest` are current arm64 images. https://github.com/actions/runner-images
- Sideloadly on Windows signs and installs IPAs with a free Apple ID; 7-day validity; needs web (non-Store) iTunes. https://sideloadly.io/faq
- Free Apple ID: profiles expire in 7 days, 10 App IDs per 7 days. Keep **one stable bundle identifier** — do not change it casually or you burn App IDs. https://developer.apple.com/support/compare-memberships/
- Vision hand pose: request has `maximumHandCount`; observation exposes joints and `chirality`. https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest
- MediaPipe iOS now distributes via SwiftPM (`MediaPipeTasksVision`, v1.2.2, iOS 15+), with `unsafeFlags` in its manifest. https://github.com/google-ai-edge/mediapipe/blob/master/Package.swift

Anything about Apple API signatures in these documents was written from memory, not compiled. **Check current signatures through the sosumi MCP server (or `https://sosumi.ai/documentation/...`) before writing adapter code** — particularly `AVCaptureConnection.videoRotationAngle`, `AVCaptureDevice.Format` frame-rate ranges, `VNHumanHandPoseObservation.recognizedPoints`, `AVAudioSourceNode` initialisers, and `Atomic`.

## 5. Engineering rules

### Real-time audio thread (the render block)
- No allocation, no locks, no `DispatchQueue`, no `print`/`Logger`, no Swift `Array` growth, no class reference counting traffic, no `async`.
- Capture only a pointer to preallocated synth state. Do not capture `self`.
- Communication in: `Atomic` values written by the control side. Communication out: none needed in the MVP (the UI derives "active notes" from note events, not from the audio thread).
- Every gain change is ramped. Every note starts and ends through the envelope.

### Video queue
- One serial queue does: Vision → `GesturePipeline` → synth `noteOn/noteOff`. Note events must **not** pass through the main actor on their way to the synth.
- Publish to `AppModel` with coalescing: if a UI update is still pending, replace its payload rather than queueing another.

### Concurrency language mode
- `HandtoneCore`: Swift 6 language mode, all types `Sendable` value types.
- `Handtone` (app): Swift 5 language mode (`.swiftLanguageMode(.v5)`). AVFoundation delegate callbacks, `CVPixelBuffer` and the audio render block generate strict-concurrency diagnostics that are slow to resolve through cloud builds. This is a deliberate trade to protect iteration time; revisit after the MVP.
- Still mark `AppModel` `@MainActor` and keep queue ownership explicit in comments (`// video queue`, `// session queue`).

### General
- Logic goes in `HandtoneCore` with a test. If you are about to write an `if` about gestures, notes or timing in the app target, stop and move it.
- No force unwraps or `try!` in adapter code. Surface setup errors as text in the HUD.
- No speculative abstractions: one tracker, one mode, one synth. The protocols `HandTracker` and `InteractionMode` are the only extension seams.
- Tunables live in `InteractionConfig`, never as literals in logic.
- Use timestamps for all time-based behaviour, not frame counts.
- Don't add features outside the PRD's MVP list. Propose them for "after v0.1.0" instead.

## 6. Workflow

### Per milestone
1. Restate the milestone's objective and acceptance criteria from ROADMAP.md.
2. Implement Core parts test-first; run `swift test` in WSL until green.
3. Compile the app: `xtool dev build` (or the equivalent current command — check `xtool dev --help`) if Route A works; otherwise push and `gh run watch`, then `gh run view --log-failed` on failure.
4. Only when it compiles, hand the developer a **device test request** in this exact form:
   - Build to install: `<git short hash>` and how to get it (xtool install, or `gh run download` + Sideloadly).
   - Checks: the relevant IDs from TESTING.md, each with steps and the pass observation.
   - What to send back: pass/fail per check, "Copy stats" text, screenshot/recording if visual.
5. Fix, repeat. Mark the milestone done only with the developer's report in hand. Commit with a message naming the milestone.

### Compile-error economy
Without xtool, each compile attempt costs minutes. Before pushing: re-read new adapter code against the fetched API docs, check every `import`, and check availability annotations. Fix all errors reported in one CI log in one commit rather than one at a time.

### Build identity
Show the git short hash in the HUD. A large share of "it still doesn't work" reports in sideloading workflows are stale builds.

### What the developer must do personally (you cannot)
- Download `Xcode.xip` (Apple ID login in a browser), install WSL/usbipd/iTunes/Sideloadly, type Apple ID credentials into xtool or Sideloadly. **Never ask for Apple ID credentials in chat and never write them to a file.**
- Trust the computer, trust the developer profile, enable Developer Mode on the iPhone.
- Re-install every 7 days while on a free Apple ID.
- All device observations and recordings.

## 7. Known traps

| Trap | Avoidance |
|------|-----------|
| Overlay drawn in the wrong place | Landmarks are normalized to the *video frame*; the preview is aspect-fill cropped. Use the preview layer's conversion or an explicit transform. Test at screen edges (T-H2). |
| Vision's y axis | Origin is bottom-left. Flip once, in `VisionHandTracker`. |
| Double mirroring on the front camera | Mirror the data-output connection and the preview connection consistently; Vision orientation `.up`. Verify with T-C1 and T-H3. |
| Using Vision chirality to decide left/right | Don't. Use screen position via `HandSlotAssigner`. |
| No sound with the silent switch on | Session category `.playback`. |
| Assuming 44.1 kHz | Read the hardware rate after activating the session; pass it to `SynthCore`. Handle `AVAudioEngineConfigurationChange`. |
| Clicks | Envelope on every start/stop/steal; ramped master gain. |
| Stuck notes | All-notes-off on: hand loss beyond grace, camera switch, background, interruption, config change. |
| Notes burst when a closed hand enters | "Must be seen open first" rule in the presence tracker. |
| Middle finger fires with index | Closest-finger rule. |
| SwiftUI redraw storm lowering fps | Coalesce model updates; draw the overlay in one `Canvas`; check HUD fps before/after UI changes. |
| `Button` pads starting on touch-up | Use a zero-distance `DragGesture` for the M1 test pads. |
| SwiftPM compiling the iOS target on Linux | Resolve in M0 (filter, conditional compilation, or split packages). |
| Burning free App IDs | One bundle ID for the life of the project. |
| Screen dims while playing | `isIdleTimerDisabled = true` on the main screen. |
| Bluetooth latency reported as a bug | Check the route name in "Copy stats" first. |

## 8. Decision points and what to do at each

- **M0, xtool does not work within the timebox:** proceed with CI + Sideloadly only. Compensate by leaning harder on Core tests and API-doc checks before each push.
- **M3, performance gate fails:** 640×480 preset → confirm Vision runs once per frame and off the main thread → one hand to isolate → then MediaPipe backend. For MediaPipe: add the package pinned by revision (unsafe flags), bundle `hand_landmarker.task`, use `.liveStream` mode with `detectAsync`, request BGRA pixel buffers, and map its 21 landmarks to `Joint` (same topology and order as the enum in ARCHITECTURE.md §4). Verify under the CI route first; xtool compatibility is unknown.
- **M5, latency fails:** use the HUD to find the stage. If frame-to-dispatch is high: Vision cost or a hidden main-thread hop. If dispatch is fast but the slow-motion measurement is slow: camera frame rate/exposure (dim rooms lengthen exposure and can halve the frame rate — test in good light) or audio buffer size.
- **Video shows a different interaction:** implement it as a second `InteractionMode`; keep `PinchScaleMode` if cheap. Do not restructure the pipeline.

## 9. `CLAUDE.md` to place in the repository root

```markdown
# Handtone — agent rules

iPhone app: camera hand tracking → notes. Swift, SwiftUI, Vision, AVAudioEngine. No Mac in this workflow.

## Layout
- Sources/HandtoneCore — pure Swift (Foundation + Synchronization only). All logic and DSP. Linux-testable.
- Sources/Handtone — iOS adapters and UI. Keep logic out.
- docs/ — PRD, ARCHITECTURE, ROADMAP, TESTING, OPUS-HANDOFF. ROADMAP defines the current milestone.

## Commands
- Core tests (WSL):      swift test
- Local iOS build (WSL): xtool dev            # if Route A is set up; see README
- CI build:              git push; gh run watch; gh run view --log-failed
- Get IPA:               gh run download -n Handtone-ipa

## Rules
- You cannot run the app. Device behaviour is verified only by the developer's report (docs/TESTING.md IDs).
- Audio render block: no allocation, locks, logging, or object capture. Atomics only.
- Note events go video queue → synth directly. Never via the main actor.
- New gesture/timing/music logic goes in HandtoneCore with a unit test.
- Check Apple API signatures via sosumi before writing adapter code.
- No third-party dependencies without the developer's explicit approval.
- One bundle identifier; never change it.
- Never request or store Apple ID credentials.
- Stay inside the PRD's MVP scope.
```

## 10. First session checklist

1. Ask the developer: (a) what does the video show — confirm or correct "Pinch Scale"; (b) iPhone model and iOS version; (c) is the GitHub repository public or private; (d) do they have a second device that records slow-motion video.
2. Install agent tooling: sosumi MCP; the three skills in TOOLS-AND-SKILLS.md §5 (confirm install commands in each README).
3. Copy the eight documents into `docs/`.
4. Start M0. Route B (CI + Sideloadly) first, Route A (xtool) second.

## 11. Definition of done for the MVP

All acceptance criteria of M0–M7 met with developer reports; `swift test` green in CI; tag `v0.1.0`; README documents how to build, install, re-sign weekly, and the measured latency/fps figures on the test device.
