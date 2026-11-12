# PRD — Handtone (working title)

A camera-based virtual instrument for iPhone: the user holds their hands in front of the camera and plays notes with finger gestures.

> **Status of the reference video.** The video did not reach the research session; only the written brief did. Everything in this PRD that describes the *exact* musical interaction is therefore an explicit assumption (section 4), isolated behind one swappable module so it can be corrected after the video is reviewed without touching camera, tracking or audio code.

## 1. Goal

Reproduce one core experience: **move your fingers in the air, hear a note immediately, see it acknowledged on screen.** Nothing else matters until that feels good.

## 2. Target user and context

- One person, holding or propping an iPhone, hands 30–70 cm from the camera.
- Front camera by default (phone propped, user sees themselves); rear camera as an option (phone held by someone else or on a stand facing the player).
- Indoor lighting. No account, no network, no setup.

## 3. Product principles

1. **Responsiveness over features.** A late note is a wrong note.
2. **One screen.** Camera preview is the app. Controls float on top.
3. **On-device only.** No backend, no analytics, no network calls.
4. **Forgiving.** Tracking loss must never leave a stuck note or a burst of accidental notes.

## 4. Core interaction (assumption — to confirm against the video)

**Default mode: "Pinch Scale".**

- Touching the thumb tip to another fingertip of the same hand ("pinch") starts a note. Opening the pinch releases it.
- Each hand offers 4 pinches (index, middle, ring, little). Two hands give 8 notes: one octave of a scale (default C major, C4–C5).
- The hand on the left of the screen plays the lower four notes, the hand on the right the upper four. With one hand visible, the half of the screen it is in decides which four it plays.
- Several pinches at once produce a chord.

Why this default: a pinch is the most reliable gesture obtainable from 2D hand landmarks (it is a single distance between two well-tracked points, independent of depth), it gives the player physical feedback (fingers touch), and it has a clear on/off state that prevents accidental repeats.

**If the video shows something else** (for example fingertips striking on-screen zones, or a theremin-style continuous pitch), only `InteractionMode` in the core package changes. Both alternatives are listed under future improvements and the architecture already accommodates them.

## 5. MVP — functional requirements

| ID | Requirement |
|----|-------------|
| F1 | Full-screen live camera preview, front camera by default, mirrored like a selfie. |
| F2 | One button switches between front and rear cameras without restarting the app. |
| F3 | Detect up to two hands and 21 landmarks per hand in real time. |
| F4 | Draw a light overlay of fingertips/skeleton aligned with the preview. |
| F5 | Pinch Scale mode triggers note-on / note-off as described in section 4. |
| F6 | Built-in synthesizer, polyphonic (8 voices), no audio files required. |
| F7 | Visual feedback on trigger: the pinching fingertip pulses and the note name appears briefly. |
| F8 | Mute toggle and volume slider. |
| F9 | Minimal settings sheet: scale (major / minor pentatonic / major pentatonic), root note, sound preset (2 presets), show/hide skeleton. |
| F10 | Camera permission flow with a clear screen when access is denied. |
| F11 | Notes stop cleanly when a hand leaves the frame, the app goes to background, or audio is interrupted (call, Siri). |

## 6. MVP — non-functional requirements

| ID | Requirement | Target |
|----|-------------|--------|
| N1 | Gesture-to-sound latency (finger contact to audible onset, built-in speaker) | ≤ 100 ms median, ≤ 140 ms p95 |
| N2 | Hand-tracking rate with two hands | ≥ 25 fps sustained |
| N3 | Touch-to-sound latency of the synth alone (test button) | ≤ 30 ms |
| N4 | False triggers while hands rest open in view | 0 in 60 s |
| N5 | Stuck notes after tracking loss | 0 |
| N6 | Audio glitches (clicks, dropouts) in 5 min of play | 0 audible |
| N7 | Runs 10 min without thermal throttling making N2 fail | pass on the test device |
| N8 | Works offline, no network entitlement | required |

Targets N1–N2 are engineering targets to be measured in milestones M1 and M3 (see TESTING.md); they are not vendor-published figures.

**Platform:** iPhone, iOS 18.0 or later, portrait only. iOS 18 supports the same iPhones as iOS 17 and unlocks the `Synchronization` module used by the audio thread.

## 7. Explicitly out of the MVP (future improvements)

- Additional interaction modes: fingertip "air zones", theremin (continuous pitch/volume), chord mode.
- Velocity from pinch speed; pitch bend or vibrato from hand movement.
- Sampled instruments (SoundFont via `AVAudioUnitSampler`), effects (reverb, delay).
- Recording, export, sharing, MIDI out, Bluetooth MIDI, Audio Unit extension.
- Custom scale editor, per-finger note assignment UI, presets.
- Landscape and iPad layouts.
- Onboarding tutorial, haptics, themes.
- MediaPipe tracker backend (kept as a documented fallback, not built unless M3's performance gate fails).
- App Store release, TestFlight distribution (requires the paid Apple Developer Program).
- Android.

## 8. Success criteria for the MVP

1. A first-time user plays a recognisable 8-note scale within 30 seconds of opening the app, without instructions beyond one hint line.
2. N1–N6 pass on the test iPhone.
3. The app is installed on a real iPhone from a Windows machine, with no Mac involved and no paid service.

## 9. Open questions for the product owner

1. What does the video actually show — pinches, strikes on zones, continuous pitch, something else?
2. Which iPhone model and iOS version will be used for testing? (Determines 60 fps camera availability and the performance gate.)
3. Is App Store publication a goal, or is personal use on your own phone enough? (Decides whether the $99/year Apple Developer Program is ever needed.)
