# Testing report

Date: 11 November 2026. Environment: Windows 11, no Swift toolchain, no WSL, no Docker, no Mac, no iPhone attached, no GitHub credentials.

## Device feedback log

- **17 Nov 2026, first install (build 98da421).** Built and installed via Sideloadly. Reported: camera picture sideways; camera colours unattractive, a softer/misty look preferred; filters judged too poor to keep.
  - Changes in the next build: preview orientation re-applied on every layout pass and when the session starts, with a one-time repair if frames arrive sideways; Settings → Diagnostics now shows camera frame size and preview rotation; new "Soft camera" setting (on by default); Filters tab, face tracking, colour effects and favourites removed. None of this has been tried on the device yet.
- **17 Nov 2026, build 87338c5.** Reported: camera picture still sideways; sound plays; the correct chord box lights up for finger counts. Conclusion: tracking frames are usable, only the preview layer was misoriented.
  - Change in the next build: the on-screen picture is now the tracked frames themselves (AVSampleBufferDisplayLayer) instead of a separate preview layer. Not yet tried on the device.

## Summary

**No Swift code in this repository has been compiled or run.** Every feature below is "implemented, not verified" unless stated otherwise. The first cloud build is expected to surface compile errors, and the first device run is expected to surface behaviour that needs tuning.

## What was actually executed

| Check | Result |
|-------|--------|
| Bracket/parenthesis balance of all 27 Swift files (script) | Passed |
| Finger-detection geometry (raised fingers, thumb, lean angle) ported to Python and run against synthetic hands for all seven chord shapes plus fist and a right-hand shape, at six lean angles from −30° to +30° | 54 of 54 cases correct |
| App icon generated and viewed | Looks as intended |
| Reference site's script read to extract the gesture rules | Done (see REFERENCE-ANALYSIS.md) |

That is the complete list. In particular, the Swift unit tests in `Core/Tests` were written but **not run**.

## Status by area

Legend — **Written**: code exists, never compiled. **Needs device**: can only be judged on an iPhone. **Blocked**: cannot proceed without something you must supply.

| Area | Status | Notes |
|------|--------|-------|
| Project configuration (`project.yml`, asset catalog, workflow) | Written | Not validated by XcodeGen or Xcode. YAML was not machine-validated. |
| Swift compilation | Not attempted | No compiler available here. Blocked until the code is pushed to GitHub. |
| Core unit tests (music theory, gesture reading, engine, lessons, synth) | Written, not run | Run automatically by the workflow on Linux. |
| Camera permission flow | Written · needs device | |
| Front/rear switching | Written · needs device | Orientation and mirroring are the most likely things to be wrong on first run. |
| One- and two-hand detection (Vision) | Written · needs device | |
| Gesture recognition | Geometry checked in Python; Swift written | Thresholds are estimates. |
| Chord and theremin triggering | Written | Covered by unit tests once they run. |
| Note release, no stuck notes | Written | Sound is cut when hands leave, on tab change, on background, on audio interruption. |
| Tracking loss handling | Written | 120–150 ms grace, covered by unit tests once they run. |
| Audio engine, latency | Written · needs device | Latency has not been measured. |
| Lesson progression, correct/incorrect feedback | Written | Engine covered by unit tests once they run; screen needs device. |
| Lesson progress persistence | Written · needs device | |
| App lifecycle (background, interruptions, route changes) | Written · needs device | |
| Signed build / install on iPhone | Blocked | Needs your Apple ID and your iPhone (BUILD-AND-INSTALL.md §4). |
| TestFlight / App Store | Blocked | Needs the paid Apple Developer Program. No upload job exists yet. |

## Known risks, most likely first

1. **Compile errors.** About 4,800 lines written without a compiler. Likely places: SwiftUI `Canvas`/`GraphicsContext` calls in `FaceArt.swift`, AVFoundation connection settings in `CameraController.swift`, the audio render block in `AudioEngine.swift`, Core Image render destination in `CameraPreview.swift`.
2. **Orientation/mirroring.** Camera frames are requested upright and mirrored for the front camera. If the preview or overlays are rotated, mirrored or offset, the fix is in `CameraController.configure` and `AspectFill`.
3. **Lean direction.** "Lean right = minor" and "lean = brighter tone" are defined from the player's view and may feel reversed.
4. **Gesture thresholds.** Finger-raised ratio (1.12), thumb reach (0.55), minor angle (14°/8°), tone range (8°–40°) and lesson hold time (0.55 s) are starting values in `GestureTuning`, `InstrumentConfig` and `LessonEngine`.
5. **Performance.** Vision hand tracking speed on your iPhone model is unknown. The Settings sheet shows tracking fps. Camera runs at the default 30 fps; 60 fps was not configured.
7. **Rear camera in Play/Learn.** Hand roles are mirrored for the rear camera so the *player's* left hand stays the chord hand. Untested.

## Device checklist for the first working build

Report each as pass/fail. Settings → Diagnostics shows fps, audio buffer and sample rate.

**Camera**
1. First launch shows the welcome screen; "Allow Camera" shows the system prompt; allowing shows the preview.
2. Front preview is upright and mirrored like a selfie.
3. Camera-flip button switches to the rear camera and back, five times.
4. Denying camera access (reinstall to retest) shows the "Open Settings" screen.

**Play**
5. Coloured skeleton sits on your hands, including near screen edges. Left hand mint, right hand coral.
6. Left hand 1–5 fingers lights I–V in the bottom strip; index + pinky lights VI; adding the thumb lights VII.
7. With the right hand showing one finger, a chord sounds; raising the right hand makes it louder; a right-hand fist is silent.
8. Right hand 2, 3, 4 fingers changes the chord shape named under the chord.
9. Right thumb out shows "One octave down".
10. Leaning the left hand right makes the chord minor; note which direction it actually takes.
11. Leaning the right hand changes the tone; note which direction is brighter.
12. Removing both hands stops the sound within a moment; nothing keeps ringing.
13. Theremin: right hand height changes pitch, left hand height changes volume.
14. Sound works with the ring/silent switch set to silent.
15. Settings → Diagnostics: tracking fps and audio buffer values (please report the numbers).

**Learn**
16. Song list shows seven songs; tapping one opens the lesson.
17. The four indicators turn green as each part of the shape becomes right; the ring fills while holding; the lesson advances with a tap of haptic feedback.
18. The chord is silent while the shape is wrong and sounds when it is right.
19. Skip chord, Repeat part and Restart behave as named; finishing shows the completion card.
20. After leaving, the song's progress ring in the list reflects the result, and survives quitting the app.

**Lifecycle**
25. Switching tabs never leaves a note sounding.
26. Backgrounding and returning restores camera and sound.
27. A phone call or Siri interrupts and the app recovers afterwards.
28. Plugging in or removing wired headphones keeps sound working.

## Not built

- Metronome in lessons, loop recorder, video recording and song sharing from the reference site.
- 60 fps camera configuration.
- A signed-build or TestFlight upload job.
- xtool configuration for local Windows builds.
- UI automation tests.
