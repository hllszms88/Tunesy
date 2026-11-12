# Technology comparison

Research date: 10 November 2026. Claims marked **[verified]** were checked against the linked source during this research. Claims marked **[prior knowledge]** come from general engineering knowledge and should be re-checked by the implementer when they matter.

## 1. Verdict

**Build it natively in Swift (SwiftUI + AVFoundation + Apple Vision hand pose + AVAudioEngine), with zero third-party runtime dependencies, compiled without a Mac through two complementary routes:**

1. **xtool inside WSL2** on the Windows machine — local compile and install to the iPhone over USB, signed with a free Apple ID. This is the fast loop and it lets the coding agent see compiler errors itself.
2. **GitHub Actions macOS runner** — builds an unsigned `.ipa` with real Xcode; **Sideloadly** on Windows signs and installs it with a free Apple ID. This is the reference build and the fallback if xtool misbehaves.

Expected cash cost: **$0**. The paid Apple Developer Program ($99/year) becomes necessary only for TestFlight or the App Store.

The reasoning, in one paragraph: the two hard parts of this app — per-frame hand tracking and real-time audio — are native on every stack. React Native and Flutter do not remove that native work; they add a bridge on top of it, and the bridge packages that exist for iOS hand tracking are thin, Android-first or unmaintained. Without a Mac, every native problem inside a cross-platform framework has to be debugged through a cloud build, in two languages. A pure Swift app has one language, first-party frameworks with first-party documentation, and — because Apple Vision ships in the OS — nothing to integrate.

## 2. What actually requires macOS

| Task | Needs macOS? | How it is covered without a Mac |
|------|--------------|---------------------------------|
| Writing Swift code | No | Any editor on Windows; Claude Opus writes it. |
| Compiling for iOS with Xcode/`xcodebuild` | Yes | GitHub Actions macOS runners (free for public repositories **[verified]**). |
| Compiling for iOS without Xcode | No | xtool builds SwiftPM-based iOS apps on Linux/WSL using an iOS SDK extracted from `Xcode.xip` **[verified]**. |
| iOS Simulator | Yes | Not available. Irrelevant here: the Simulator has no camera, so this app needs a real device even on a Mac **[prior knowledge]**. |
| Signing and installing on a device | Officially yes (Xcode) | xtool or Sideloadly sign with a free Apple ID from Windows/WSL **[verified]**. |
| Debugger (LLDB attached to device), Instruments | Yes | Not available. Replaced by an in-app debug HUD, `os.Logger` output, and recorded landmark fixtures. |
| TestFlight / App Store upload | Mac not strictly needed; paid program is | CI can upload using an App Store Connect API key. Out of MVP scope. |
| SwiftUI previews | Yes | Not available. UI is simple enough to verify on device. |

Free Apple ID limits **[verified, Apple "Choosing a Membership" and Sideloadly FAQ]**: provisioning profiles expire after 7 days (re-install weekly), up to 10 App IDs per 7 days, up to 3 sideloaded apps on a device. Camera and audio need no special capability, so free provisioning is sufficient for this app.

## 3. Approach A — Native iOS (Swift, SwiftUI, AVFoundation, Vision or MediaPipe, AVAudioEngine)

| # | Question | Answer |
|---|----------|--------|
| 1 | Develop mostly on Windows? | Yes for editing. Pure-logic code (gesture detection, note mapping, DSP) is plain Swift and can be compiled and unit-tested in WSL with `swift test`. Camera, Vision and audio I/O can only run on the iPhone. |
| 2 | Build without owning a Mac? | Yes — xtool in WSL, or a cloud macOS runner. |
| 3 | What needs macOS/Xcode? | The official toolchain (`xcodebuild`), Simulator, debugger, Instruments. See section 2. |
| 4 | Do cloud builds solve it? | Yes for compiling. GitHub Actions `macos-26`/`macos-latest` runners are free on public repos; on private repos GitHub Free includes a monthly allowance that covers roughly 190 macOS minutes at $0.062/min **[verified, GitHub billing docs]**. A build of this app should take 3–8 minutes. |
| 5 | Hand-tracking integration difficulty | **Low with Apple Vision**: `VNDetectHumanHandPoseRequest` is built into iOS, takes a `CVPixelBuffer` straight from the camera callback, returns 21 joints per hand with confidences, supports `maximumHandCount` and chirality **[verified, Apple docs]**. No model file, no package. **Moderate with MediaPipe**: Google's guide now lists Swift Package Manager (`https://github.com/google-ai-edge/mediapipe` → `MediaPipeTasksVision`, binary xcframeworks v1.2.2, iOS 15+) **[verified]**, plus a bundled `hand_landmarker.task` model. Risk: its `Package.swift` uses `unsafeFlags` (`-all_load`), which SwiftPM rejects for version-pinned dependencies **[verified, Swift forums]** — may need a revision pin or local wrapper, and is untested under xtool. |
| 6 | Low-latency audio | Best available. `AVAudioEngine` + `AVAudioSourceNode` gives a real-time render callback; `AVAudioSession.setPreferredIOBufferDuration(0.005)` requests ~5 ms buffers **[verified, Apple forums/docs]**. No bridge between the gesture decision and the audio thread. |
| 7 | Device-testing limits | No Simulator, no attached debugger, 7-day re-sign cycle, compile-install loop of ~1–2 min (xtool) or ~8–12 min (CI + Sideloadly). |
| 8 | Cost | $0. Optional $99/year for TestFlight/App Store. |
| 9 | Fit for Claude Opus | Strong. One language, small codebase (~2,000 lines), Apple APIs that are stable and heavily documented. Main weakness: Opus cannot run the app, so it depends on compiler output (available via xtool or `gh run view --log-failed`) and on the user's device observations. |

## 4. Approach B — React Native (Expo or bare)

| # | Question | Answer |
|---|----------|--------|
| 1 | Develop mostly on Windows? | Yes for JS/TS, with fast refresh onto the phone through a development build. This is the best iteration loop of the three — for the JavaScript parts only. |
| 2 | Build without a Mac? | Yes via EAS Build. |
| 3 | What needs macOS? | Same native toolchain underneath; EAS runs it for you. Local iOS builds need a Mac. |
| 4 | Cloud builds | EAS free plan: up to 15 iOS builds/month, low-priority queue **[verified via third-party summaries of expo.dev/pricing]**. **Every EAS build that runs on a physical iPhone requires a paid Apple Developer account** **[verified, Expo docs: "ios-development-build-for-devices"]**. Expo Go cannot be used because the app needs custom native code. |
| 5 | Hand tracking | **Hard.** Requires `react-native-vision-camera` with a native frame-processor plugin. The only hand-landmark package found, `expo-vision-camera-v4-mediapipe`, describes Android (Kotlin) features; iOS support and New Architecture compatibility were not confirmed **[verified as "not confirmed"]**. Maintained MediaPipe plugins found were pose-only. Realistically you write and maintain your own Swift frame-processor plugin — i.e. the native work of Approach A, plus plugin glue, plus worklet marshalling of 42 landmarks per frame into JS. |
| 6 | Audio | `react-native-audio-api` (Software Mansion) implements the Web Audio API natively and is actively released (0.12.x in 2026) **[verified]**; oscillators and gain envelopes are available. It is pre-1.0 and no latency figures were found. Note decisions made on the JS thread add scheduling jitter that a native path does not have **[prior knowledge]**. |
| 7 | Device-testing limits | Any change to native code consumes one of 15 monthly builds and a queue wait. Native crashes are diagnosed from cloud logs. |
| 8 | Cost | **$99/year minimum** to get onto a real iPhone through EAS. (A bare RN project could use the same unsigned-IPA + Sideloadly trick as Approach A, but then loses EAS's convenience and needs CocoaPods-era build plumbing.) |
| 9 | Fit for Claude Opus | Good for the UI, weak where it counts: three layers (TS, worklets, Swift plugin), version-coupled packages (RN, VisionCamera, worklets, audio), and the CocoaPods trunk going read-only on 2 December 2026 **[verified]** is shaking the RN iOS dependency ecosystem right now. |

**Assessment:** your React experience helps with roughly 15% of this app (one screen and a settings sheet). The remaining 85% is native regardless.

## 5. Approach C — Flutter

| # | Question | Answer |
|---|----------|--------|
| 1 | Develop mostly on Windows? | Yes for Dart; hot reload works only against a device build produced on macOS. |
| 2 | Build without a Mac? | Yes via Codemagic or GitHub Actions. |
| 3 | What needs macOS? | iOS compile, signing, Simulator. |
| 4 | Cloud builds | Codemagic: 500 free macOS M2 minutes/month on personal accounts **[verified, Codemagic docs]**. |
| 5 | Hand tracking | **Hard.** `hand_landmarker` on pub.dev is Android-only; `hand_landmarker_mediapipe` and `mediapipeline_flutter` list iOS as to-do/"coming soon" **[verified]**. `hand_detection` (pure TFLite, lists iOS Metal acceleration) is the only ready-made option and is not MediaPipe Tasks. Otherwise: write a Swift platform plugin and ship landmarks over a platform channel. The official Google `mediapipe` Flutter packages do not cover vision tasks **[prior knowledge]**. |
| 6 | Audio | `flutter_soloud` (SoLoud + miniaudio, real-time waveforms) and `flutter_pcm_sound` (PCM feed callback, ~100 Hz on iOS, i.e. ~10 ms granularity) exist and support iOS **[verified]**. Workable; no measured iOS latency published. |
| 7 | Device-testing limits | Same as B without the hot-reload-from-Windows advantage (no Mac to host the debug session; wireless debugging from Windows to an iOS device is not supported **[prior knowledge]**). |
| 8 | Cost | $0 possible (unsigned IPA + Sideloadly), $99/year for Codemagic's automatic signing/TestFlight path. |
| 9 | Fit for Claude Opus | Fine for Dart UI; same split-brain problem as B for the native plugin. You have no Dart background, so the cross-platform layer buys nothing. |

**Assessment:** Flutter adds a rendering engine and a language you don't know in order to host a camera preview and four buttons.

## 6. Side-by-side

| Criterion | A. Native Swift | B. React Native / Expo | C. Flutter |
|-----------|-----------------|------------------------|------------|
| Hand tracking on iOS | Built into the OS (Vision) | Custom native plugin | Custom native plugin or lone TFLite package |
| Audio latency path | Direct, real-time thread | Native engine driven from JS | Native engine driven from Dart |
| Third-party runtime dependencies | 0 | 4+ tightly version-coupled | 3+ |
| Languages in the repo | 1 | 2–3 | 2 |
| Build without Mac | xtool (local) or CI | EAS | Codemagic / CI |
| Local compile feedback on Windows | Yes (xtool, WSL) | JS only | Dart only |
| Minimum cost to reach a real iPhone | $0 | $99/year (EAS) | $0–$99 |
| Hot reload | No | Yes (JS only) | No (without a Mac) |
| Android later | Rewrite | Partly shared | Partly shared |
| Risk concentrated in | Build/install tooling | Native plugin + package drift | Native plugin + package drift |

## 7. The option not on the list: a web app

Worth stating honestly because of your background: MediaPipe Hand Landmarker has an official web build (`@mediapipe/tasks-vision`) **[verified, listed in Google's guide]**, and Safari on iOS supports camera capture and Web Audio **[prior knowledge]**. A single-page web app would need no Mac, no Apple ID, no signing, and would run on your Windows webcam during development.

It is not the recommendation because you asked for an iOS application, and because browser audio output latency and WebAssembly inference speed on iPhone are both worse and less controllable than native **[prior knowledge; not measured in this research]**. But it has one legitimate use here: an **optional, throwaway half-day prototype** to settle the musical interaction (which gesture, which thresholds) with a ten-second edit-refresh loop before committing it to Swift. ROADMAP.md lists this as optional milestone M0.5.

## 8. Apple Vision vs MediaPipe inside the native approach

| | Apple Vision (`VNDetectHumanHandPoseRequest`) | MediaPipe Hand Landmarker |
|---|---|---|
| Install | None (system framework) | SwiftPM binary package + `.task` model file |
| Landmarks | 21 joints, 2D normalized, per-joint confidence | 21 landmarks, 2D normalized + relative z, plus world landmarks in metres |
| Hands | `maximumHandCount` | `numHands` |
| Handedness | `chirality` | `handedness` |
| Async/live mode | Synchronous per frame on your queue | `detectAsync` live-stream mode, drops frames when busy |
| Works with xtool | Yes (it's in the SDK) | Unverified (binary xcframeworks + unsafe flags) |
| Same model on Android/Web | No | Yes |
| Published iPhone performance | None found | None found for iPhone (Pixel 6: 17 ms CPU / 12 ms GPU **[verified]**) |

Decision: **Vision first**, behind a `HandTracker` protocol. Milestone M3 has a measurable gate (≥ 25 fps with two hands, acceptable pinch reliability). MediaPipe is the documented fallback if the gate fails. Depth (z) is the main thing MediaPipe would add, and the default pinch interaction does not need it.

## 9. Sources

- MediaPipe Hand Landmarker, iOS guide — https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/ios
- MediaPipe `Package.swift` — https://github.com/google-ai-edge/mediapipe/blob/master/Package.swift
- SwiftPM unsafe flags restriction — https://forums.swift.org/t/confused-by-unsafe-flags-being-disallowed-in-dependencies/27359
- Apple Vision hand pose — https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest , https://developer.apple.com/documentation/vision/detecthumanhandposerequest , https://developer.apple.com/documentation/vision/humanhandposeobservation
- xtool — https://github.com/xtool-org/xtool , releases https://github.com/xtool-org/xtool/releases , Linux/WSL install https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md
- xtool on WSL walkthrough (community) — https://zenn.dev/mnonamer/articles/ios-dev-on-wsl-with-xtool
- Sideloadly FAQ — https://sideloadly.io/faq
- Apple membership comparison — https://developer.apple.com/support/compare-memberships/
- GitHub Actions billing — https://docs.github.com/en/billing/concepts/product-billing/github-actions
- GitHub runner images — https://github.com/actions/runner-images
- CocoaPods trunk read-only plan — https://blog.cocoapods.org/CocoaPods-Specs-Repo/
- Expo: device builds need a paid account — https://docs.expo.dev/tutorial/eas/ios-development-build-for-devices/ , https://docs.expo.dev/develop/development-builds/create-a-build/ , https://expo.dev/blog/apple-developer-program-explained-free-vs-paid
- `expo-vision-camera-v4-mediapipe` — https://www.jsdelivr.com/package/npm/expo-vision-camera-v4-mediapipe
- VisionCamera — https://github.com/mrousavy/react-native-vision-camera
- react-native-audio-api — https://docs.swmansion.com/react-native-audio-api/
- Flutter packages — https://pub.dev/packages/hand_landmarker , https://pub.dev/packages/hand_landmarker_mediapipe , https://pub.dev/packages/mediapipeline_flutter , https://pub.dev/documentation/hand_detection/3.5.0/ , https://pub.dev/packages/flutter_soloud , https://github.com/chipweinberger/flutter_pcm_sound
- Codemagic pricing — https://docs.codemagic.io/billing/pricing/
