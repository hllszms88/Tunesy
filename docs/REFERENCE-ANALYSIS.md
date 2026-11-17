# Reference analysis — gesturesynth.com

## How this was studied, and its limits

The site is a single-page web app that needs a webcam. Opening it in the built-in browser was declined, so it was **not** used interactively. Instead the site's public HTML and JavaScript bundle were downloaded and read (11 Nov 2026). That shows precisely how gestures are turned into music, but it means:

- The running interface was never seen. Layout and visual style of the original are known only from the code (text, colours, drawing routines), not from screenshots.
- The Learn Songs catalogue is loaded from the site's server at run time and was not retrieved. Its *mechanics* are in the bundle and are described below; its *songs* are not known, apart from one built-in example that is a commercial pop song.
- Which physical direction counts as "leaning right" depends on camera mirroring that could not be confirmed from code alone. The app defines directions from the player's own point of view and they must be checked on a device.

Nothing was copied from the site: no code, artwork, fonts, text or songs. Only the interaction concept was followed.

## What the reference does

Its own description: play chords and theremin tones with your hands using webcam tracking. Hand tracking is MediaPipe Hand Landmarker (two hands, 21 landmarks each), running in the browser.

### Chord mode (the main instrument)

**Left hand — which chord**

| Shape | Chord |
|-------|-------|
| 1, 2, 3, 4, 5 raised digits (thumb counts) | I, II, III, IV, V |
| index + pinky | VI |
| index + pinky + thumb | VII |
| wrist tilt | major ↔ minor |

A finger counts as raised when its tip is above its middle knuckle. The root of each chord is the major-scale degree of the chosen key; VII is voiced one semitone *below* the key root.

**Right hand — how it sounds**

| Control | Effect |
|---------|--------|
| wrist height | volume |
| 1 / 2 / 3 / 4 raised fingers | triad / first inversion / major-or-minor 7th / dominant-or-diminished 7th |
| no fingers, or hand absent | silence |
| thumb out | one octave down |
| wrist tilt | low-pass filter sweep (darker one way, brighter and more resonant the other) |

A gesture must stay unchanged for about 100 ms before the chord changes, and dropouts shorter than about 50 ms are ignored.

**Voicings** (four notes): triad = root, fifth, octave, tenth; inversion = third, fifth, octave, tenth; sevenths = root, third, fifth, seventh; minor quality 4 = diminished seventh.

**Sound:** sawtooth oscillators per note through a waveshaper and a resonant low-pass filter, with five presets differing in detune, octave layering and drive.

**Options:** key selector; left hand can be locked to major or minor; chord quality can be locked; octave can be locked instead of using the thumb.

### Theremin mode

Right hand height sets pitch on an exponential scale from 65 Hz to 1200 Hz; left hand height sets volume. Both hands must be visible. Sine tone.

### Learn Songs ("guided practice")

- A song has a title, artist, key, tempo and a list of chord events grouped into sections. Each event specifies degree, major/minor, quality and octave.
- The screen shows the current chord name, position ("section x/y · chord x/y"), a diagram of the required left-hand shape with its tilt, a diagram of the required right-hand shape, and four indicators — degree, mode, quality, octave — that show which parts are currently right.
- The player must **hold the correct shape** until a ring completes; then the lesson advances. The instruction reads "hold the shape until it clicks".
- The instrument only sounds when the shape is fully correct.
- Controls: skip this chord, repeat this section, exit; a completion screen reports how many chords were matched and skipped.
- An optional metronome starts on the first correct chord.
- Gesture locks from free play are ignored during a lesson.

### Other features of the site (not carried over)

A four-track loop recorder with a beat grid, video recording of performances, microphone monitoring, song sharing and a public song list backed by a server. These fall outside the three experiences requested and would need a backend or substantial extra work.

## How the iPhone app maps to it

| Reference | Handtone |
|-----------|----------|
| MediaPipe in the browser | Apple Vision hand pose, on device |
| Finger raised: tip above knuckle | Tip farther from the wrist than the middle knuckle — works when the hand leans |
| Thumb out: horizontal comparison | Thumb tip spread away from the palm — independent of which hand and of mirroring |
| Tilt flips major/minor at a threshold | Same, with separate on/off angles (14° / 8°) so it does not flicker |
| 100 ms / 50 ms debounce | 100 ms / 120 ms, plus a 150 ms grace period for the right hand |
| Web Audio saw oscillators + filter | Own synthesizer on AVAudioEngine: band-limited saws, drive, state-variable low-pass |
| Five sound presets | Five presets with the same roles |
| Guided practice | Learn tab: same hold-to-advance mechanic, four indicators, skip / repeat part / restart, completion screen, progress saved per song |
| Server-hosted song library | Seven built-in lessons (traditional melodies and original pieces, original chord charts), extensible by JSON |
| Metronome in lessons | Not included |
| Loop recorder, recording, sharing | Not included |
| — | Filters tab: built, then removed on 17 Nov 2026 at the developer's request |

## Assumptions to confirm on a device

1. Lean direction for minor (right, from the player's view) and for brighter tone feel natural; if not, the sign is one line in `InstrumentEngine`.
2. The 0.55-second hold time in lessons feels right; the reference's exact value was not determined.
3. Apple Vision resolves raised/lowered fingers as reliably as MediaPipe at arm's length.

## What changed from the earlier research documents

The eight research documents (copied to `docs/research/`) were written before the reference was known. Where they differ, this build takes precedence:

- **Interaction:** thumb-to-finger "pinch scale" is replaced by the reference's two-hand chord scheme and theremin.
- **Scope:** Learn Songs and Filters are now part of the first version.
- **Minimum iOS:** 17.0 instead of 18.0. The audio thread hand-off uses a try-lock instead of the `Synchronization` module, so iOS 18 is not required.
- **Preview:** the standard camera preview layer is used everywhere; a Metal view is added only for whole-picture colour filters.
- **Build:** GitHub Actions + XcodeGen + Sideloadly is the supported route. The xtool route is documented but not configured.
- **Unchanged:** native Swift/SwiftUI, Apple Vision, AVAudioEngine, no third-party dependencies, logic separated into a testable package, everything on-device.
