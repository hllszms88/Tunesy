# Project structure

One repository, one Swift package, two targets, two thin build descriptions (xtool for local builds, XcodeGen for CI) that point at the same sources.

```
handtone/
├── CLAUDE.md                         Agent rules for this repo (content in OPUS-HANDOFF.md §9)
├── README.md                         Build/install instructions for humans
├── Package.swift                     SwiftPM manifest: HandtoneCore (library), Handtone (app library), tests
├── xtool.yml                         xtool app config: bundle ID, product, Info.plist path, icon
├── project.yml                       XcodeGen spec used only by CI
├── .gitignore                        .build/, xtool/, *.xcodeproj, build/, Payload/, *.ipa
│
├── App/
│   ├── Info.plist                    NSCameraUsageDescription, portrait-only, UIRequiredDeviceCapabilities
│   └── AppIcon.png                   1024×1024
│
├── Sources/
│   ├── HandtoneCore/                 PURE SWIFT — Foundation + Synchronization only. Builds on Linux.
│   │   ├── Models/
│   │   │   ├── Joint.swift               21-case enum
│   │   │   ├── HandFrame.swift           Landmark, Hand, HandFrame, HandSlot, TrackedFrame
│   │   │   └── NoteEvent.swift           NoteEvent, NoteID
│   │   ├── Filtering/
│   │   │   ├── OneEuroFilter.swift
│   │   │   └── LandmarkSmoother.swift    21×2 filters per slot
│   │   ├── Tracking/
│   │   │   ├── HandSlotAssigner.swift    stable left/right identity with hysteresis
│   │   │   └── HandPresenceTracker.swift grace period, loss handling
│   │   ├── Gestures/
│   │   │   └── PinchDetector.swift       per-finger state machine
│   │   ├── Music/
│   │   │   ├── Pitch.swift               MIDI ↔ frequency, note names
│   │   │   ├── Scale.swift               major, minor pentatonic, major pentatonic
│   │   │   ├── InteractionConfig.swift   all tunables, Codable
│   │   │   ├── InteractionMode.swift     protocol
│   │   │   └── PinchScaleMode.swift      MVP mode
│   │   ├── Pipeline/
│   │   │   └── GesturePipeline.swift     HandFrame → (TrackedFrame, [NoteEvent]); the single entry point
│   │   └── Synth/
│   │       ├── Envelope.swift
│   │       ├── Voice.swift
│   │       ├── SynthPreset.swift
│   │       └── SynthCore.swift           voice pool, atomics, render(into:sampleRate:)
│   │
│   └── Handtone/                     APP — Apple frameworks. Builds only for iOS.
│       ├── HandtoneApp.swift             @main
│       ├── AppModel.swift                @MainActor @Observable; owns everything
│       ├── Settings.swift                Codable settings + UserDefaults persistence
│       ├── Camera/
│       │   ├── CameraController.swift    session, devices, switching, delegate
│       │   └── CameraPreviewView.swift   UIViewRepresentable + coordinate transform
│       ├── Tracking/
│       │   ├── HandTracker.swift         protocol
│       │   └── VisionHandTracker.swift   VNDetectHumanHandPoseRequest adapter
│       ├── Audio/
│       │   └── AudioEngine.swift         AVAudioSession + AVAudioEngine + AVAudioSourceNode hosting SynthCore
│       ├── Pipeline/
│       │   └── PerformancePipeline.swift video-queue glue: frame → tracker → GesturePipeline → synth + AppModel
│       ├── UI/
│       │   ├── MainScreen.swift
│       │   ├── HandOverlayView.swift
│       │   ├── NoteFeedbackView.swift
│       │   ├── ControlsBar.swift
│       │   ├── SettingsSheet.swift
│       │   ├── PermissionView.swift
│       │   └── DebugHUD.swift
│       └── Debug/
│           ├── PerfStats.swift           rolling fps / ms statistics
│           └── LandmarkRecorder.swift    writes HandFrame JSON-lines to Documents, share-sheet export
│
├── Tests/
│   └── HandtoneCoreTests/
│       ├── OneEuroFilterTests.swift
│       ├── HandSlotAssignerTests.swift
│       ├── PinchDetectorTests.swift
│       ├── PresenceTrackerTests.swift
│       ├── PinchScaleModeTests.swift
│       ├── PitchScaleTests.swift
│       ├── SynthCoreTests.swift
│       ├── GesturePipelineReplayTests.swift   replays recorded fixtures
│       └── Fixtures/                          *.jsonl landmark recordings from the real device
│
├── .github/workflows/
│   ├── core-tests.yml                ubuntu-latest: swift test (fast, cheap, every push)
│   └── ios-build.yml                 macos-26: xcodegen → xcodebuild (unsigned) → upload Handtone.ipa
│
└── docs/                             PRD.md, ARCHITECTURE.md, ROADMAP.md, TESTING.md, … (these documents)
```

## Dependency rules

- `HandtoneCore` imports **only** `Foundation` and `Synchronization`. No `CoreGraphics`, no `simd` types in public API unless they compile on Linux (use plain `Float` pairs if in doubt), no `AVFoundation`, no `os`.
- `Handtone` depends on `HandtoneCore`. Never the reverse.
- Files under `Camera/`, `Tracking/`, `Audio/` do not import SwiftUI. Files under `UI/` do not import AVFoundation or Vision (except `CameraPreviewView`).
- `PerformancePipeline` is the only place where camera, tracker, core and synth meet.

## `Package.swift` outline

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "Handtone",
    platforms: [.iOS(.v18)],
    products: [ .library(name: "Handtone", targets: ["Handtone"]) ],
    targets: [
        .target(name: "HandtoneCore"),
        .target(name: "Handtone", dependencies: ["HandtoneCore"],
                swiftSettings: [.swiftLanguageMode(.v5)]),   // see OPUS-HANDOFF §5
        .testTarget(name: "HandtoneCoreTests", dependencies: ["HandtoneCore"],
                    resources: [.copy("Fixtures")]),
    ]
)
```

Notes for the implementer:

- `swift test` on Linux must build only `HandtoneCore` and its tests. The `Handtone` target imports iOS-only frameworks; either guard it (`#if canImport(UIKit)` at file level is clumsy) or — simpler — run tests with `swift test --filter HandtoneCoreTests` after confirming SwiftPM does not try to compile `Handtone` for the host. If it does, split into two packages (`Core/Package.swift` consumed by the root package via `.package(path: "Core")`). Decide in M0 by trying it.
- xtool expects a library product that contains the `@main` app; start from whatever `xtool new` generates and reshape it into this layout rather than writing `xtool.yml` from memory.

## `project.yml` outline (XcodeGen, CI only)

```yaml
name: Handtone
options: { bundleIdPrefix: com.example, deploymentTarget: { iOS: "18.0" } }
packages:
  HandtonePkg: { path: . }
targets:
  Handtone:
    type: application
    platform: iOS
    sources: [Sources/Handtone]
    dependencies: [{ package: HandtonePkg, product: HandtoneCore }]
    info: { path: App/Info.plist }
    settings: { base: { SWIFT_VERSION: "5.0", TARGETED_DEVICE_FAMILY: "1",
                        PRODUCT_BUNDLE_IDENTIFIER: com.example.handtone } }
```

For this to work the package must also expose `HandtoneCore` as a library product. The app target compiles `Sources/Handtone` directly, so the same files serve both build routes.

## `App/Info.plist` required keys

- `NSCameraUsageDescription` — "Handtone uses the camera to see your hands so you can play notes. Video never leaves your device."
- `UISupportedInterfaceOrientations` — portrait only.
- `UIRequiredDeviceCapabilities` — `arm64`.
- `UILaunchScreen` — empty dictionary.
- No microphone key (the app does not record), no network keys.

## What is intentionally absent

No `Podfile`, no `node_modules`, no backend folder, no committed `.xcodeproj`, no assets beyond the icon, no model files.
