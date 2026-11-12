# Handtone — notes for the coding agent

Native iPhone app: camera hand tracking → chords and theremin (Play), song lessons (Learn), camera effects (Filters). Swift, SwiftUI, AVFoundation, Vision, AVAudioEngine, Core Image. No third-party dependencies. No network.

The developer works on Windows with no Mac. You cannot run the app; only GitHub Actions can compile it and only the developer's iPhone can run it.

## Layout
- `Core/` — Swift package `GestureCore`. Pure logic and DSP; imports Foundation only; must build on Linux. Gesture reading, music theory, instrument engine, synth, songs, lesson engine. Has unit tests.
- `App/` — iOS adapters and SwiftUI. Keep decision logic out of here.
- `project.yml` — XcodeGen spec. The `.xcodeproj` and `App/Info.plist` are generated; do not commit or hand-edit them.
- `docs/` — BUILD-AND-INSTALL, REFERENCE-ANALYSIS, TESTING-REPORT, and the earlier research in `docs/research/`.

## Commands
- Build and test: push, then `gh run watch`; on failure `gh run view --log-failed` (or read the run's Summary page).
- Get the app: `gh run download -n Handtone-ipa`.
- There is no local Swift toolchain. Do not claim something compiles or passes unless a CI run showed it.

## Rules
- Audio render block (`AudioEngine`): no allocation, no blocking locks, no logging, no object captures. Parameters cross threads only as the `SynthParams` value under a try-lock.
- Sound path: video queue → `FramePipeline` → `AudioEngine.set`. Never route note decisions through the main thread.
- `FramePipeline`'s engine and lesson state are touched only on the camera's video queue.
- New gesture, timing or music behaviour goes in `Core/` with a unit test. Thresholds live in `GestureTuning` / `InstrumentConfig`, not as literals.
- Gesture logic uses the player's point of view; the pipeline mirrors rear-camera coordinates before the engine sees them. Overlays use display coordinates.
- Tracking always reads the original pixel buffer; filters affect only what is displayed.
- The app target uses Swift 5 language mode with minimal concurrency checking, on purpose.
- Keep the bundle identifier stable (free Apple IDs have a weekly identifier limit).
- Never ask for or store Apple ID credentials or signing keys in the repository.
- Songs must be public domain, original, or licensed. Do not copy assets, code or text from gesturesynth.com, Snapchat or TikTok.
- When reporting status, separate: verified by CI, verified on device by the developer, and unverified.
