# Handtone

A native iPhone app with two camera experiences:

- **Play** — a hand-controlled chord instrument and theremin.
- **Learn** — song lessons that use the same live hand tracking and sound.

Everything runs on the device. There is no backend, no account, and no network use. Camera frames and hand landmarks never leave the phone.

> **Status: early device testing.** The app builds in GitHub Actions and has been installed on one iPhone. Most behaviour is still unverified on a device. See [docs/TESTING-REPORT.md](docs/TESTING-REPORT.md) for exactly what has and has not been checked.

## How you play

| | Left hand (chord) | Right hand (expression) |
|---|---|---|
| Raised fingers | 1–5 fingers → chords I–V. Index + pinky → VI. Add thumb → VII. | 1–4 fingers → triad, 1st inversion, 7th, dominant/diminished 7th. No fingers → silent. |
| Lean | Lean right → minor | Lean → tone filter darker / brighter |
| Height | — | Higher → louder |
| Thumb | counts as a finger | Out → one octave down |

Theremin mode: right hand height = pitch (65–1200 Hz), left hand height = volume.

This interaction follows the reference product, gesturesynth.com. See [docs/REFERENCE-ANALYSIS.md](docs/REFERENCE-ANALYSIS.md).

## Layout

```
Core/                     Swift package "GestureCore": pure logic, no Apple UI frameworks
  Sources/GestureCore/    geometry, finger reading, music theory, instrument engine,
                          synthesizer DSP, songs, lesson engine
  Tests/                  unit tests (run on Linux in CI)
App/                      the iOS app
  AppModel.swift          app state
  Camera/                 capture session and live preview
  Tracking/               Vision hand tracking
  Audio/                  AVAudioEngine host for the synth
  Pipeline/               per-frame glue: camera → tracking → logic → sound
  Stores/                 settings and lesson progress (UserDefaults)
  UI/                     SwiftUI screens
  Assets.xcassets/        app icon and colours
project.yml               XcodeGen description of the Xcode project
.github/workflows/        cloud build
docs/                     build/install guide, reference analysis, testing report
```

The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) during the cloud build. There is deliberately no hand-written `.xcodeproj` in the repository.

## Build and install

You need a Mac only in the cloud. Full steps are in [docs/BUILD-AND-INSTALL.md](docs/BUILD-AND-INSTALL.md). In short:

1. Push this folder to a GitHub repository.
2. GitHub Actions runs the logic tests on Linux and builds an unsigned `.ipa` on a macOS runner.
3. Download the `.ipa` and install it on your iPhone from Windows with Sideloadly, signed with your Apple ID.

## Adding content

- **Songs:** add an entry to `SongLibrary.builtIn` in `Core/Sources/GestureCore/Song.swift`, or ship a `Songs.json` file (an array of songs in the same shape) in the app bundle.
- **Sounds:** add an entry to `SynthVoice.all`.
