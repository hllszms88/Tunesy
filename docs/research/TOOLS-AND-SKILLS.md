# Tools, libraries, MCP servers and skills

Only items that earn their place are recommended. Each entry says what it is, whether it runs on Windows, and how confident the research is. "Verified" means the source was read during this research (10 Nov 2026); "prior knowledge" means it should be re-checked at install time.

## 1. Summary

| Category | Recommended | Skipped, and why |
|----------|-------------|------------------|
| Frameworks (in iOS) | SwiftUI, AVFoundation, Vision, AVFAudio, Synchronization | — |
| Third-party libraries | **None in the MVP** | MediaPipe (fallback only), AudioKit (not needed) |
| Build tools | xtool, WSL2, usbipd-win, Swift toolchain (in WSL), XcodeGen, GitHub Actions, GitHub CLI | Fastlane, CocoaPods, EAS, Codemagic |
| Install tools | xtool, Sideloadly | AltStore (equivalent; one is enough) |
| MCP servers | sosumi (Apple docs) | XcodeBuildMCP, Apple `mcpbridge`, iOS Simulator MCPs — all require macOS |
| Claude skills | SwiftUI Pro, Swift Concurrency skill, xtool plugin | Generic "iOS expert" prompt packs |

## 2. Apple frameworks (ship with iOS; nothing to install)

| Framework | Use | Documentation |
|-----------|-----|---------------|
| AVFoundation (capture) | `AVCaptureSession`, `AVCaptureVideoDataOutput`, `AVCaptureVideoPreviewLayer` | https://developer.apple.com/documentation/avfoundation/capture-setup |
| Vision | `VNDetectHumanHandPoseRequest`, `VNHumanHandPoseObservation` (iOS 14+; `chirality` iOS 15+). The newer Swift-only `DetectHumanHandPoseRequest` (iOS 18+) is equivalent; use the `VN` API because it is synchronous and has far more published examples. | https://developer.apple.com/documentation/vision/vndetecthumanhandposerequest · WWDC20 "Detect Body and Hand Pose with Vision": https://developer.apple.com/videos/play/wwdc2020/10653/ |
| AVFAudio | `AVAudioEngine`, `AVAudioSourceNode`, `AVAudioSession` | https://developer.apple.com/documentation/avfaudio/avaudiosourcenode · https://developer.apple.com/documentation/avfaudio/avaudiosession |
| Synchronization | `Atomic` for lock-free control→audio handoff (iOS 18+) | https://developer.apple.com/documentation/synchronization |
| SwiftUI + Observation | UI, `@Observable` model | https://developer.apple.com/documentation/swiftui |

## 3. Build and install tools

### 3.1 xtool — build tool (primary inner loop)

- **What:** open-source "cross-platform Xcode replacement": builds a SwiftPM package into an iOS app, signs it, installs it on a connected iPhone. CLI subcommands include `setup`, `auth`, `sdk`, `new`, `dev`, `devices`, `install`.
- **Repository:** https://github.com/xtool-org/xtool · docs https://xtool.sh
- **Why:** the only way to compile iOS Swift on your own machine. It gives Claude Opus compiler errors in seconds instead of a CI round trip, and installs to the phone over USB.
- **Windows:** via **WSL2** (Linux). Not native Windows.
- **Maintenance:** very active — v1.24.0 on 26 Oct 2026; recent releases track Swift 6.4 and Xcode 27 (verified from the releases page).
- **Apple account:** free Apple ID works using password login, which the docs describe as using private Apple APIs; the docs themselves suggest a throwaway Apple ID for caution. Paid accounts can use an App Store Connect API key instead. (Verified.)
- **Install (inside WSL Ubuntu; verified from the official Linux/Windows guide):**
  1. Install the Swift toolchain for your distro from https://www.swift.org/install/linux/ and check `swift --version` (docs expect 6.4).
  2. `sudo apt-get install usbmuxd`
  3. In a browser, download `Xcode.xip` (docs name Xcode 27.1) from https://developer.apple.com/download/all/ — requires signing in with an Apple ID; the file is several GB. Note its path (reachable from WSL under `/mnt/c/...`).
  4. Download the xtool AppImage for your architecture from GitHub Releases, `chmod +x`, rename to `xtool`, move to `/usr/local/bin/`.
  5. `xtool setup` — choose login mode, give the `Xcode.xip` path; xtool extracts an iOS SDK. Verify with `swift sdk list`.
- **Caveats:** unofficial tooling that Apple could break; relies on an SDK you extract yourself from Apple's download (read Apple's Xcode licence terms and decide for yourself — community posts flag this as a grey area); needs tens of GB of free disk during setup. The `xtool.yml` keys used in PROJECT-STRUCTURE.md (`bundleID`, `infoPath`, `resources`, `iconPath`, `entitlementsPath`) come from secondary sources — confirm against the template `xtool new` generates.

### 3.2 WSL2 and usbipd-win — development tools

- **WSL2:** `wsl --install -d Ubuntu-24.04` in an admin PowerShell. https://learn.microsoft.com/windows/wsl/install
- **usbipd-win:** passes the iPhone's USB connection into WSL. https://github.com/dorssel/usbipd-win · `winget install --exact dorssel.usbipd-win` (verified). Then, in admin PowerShell: `usbipd list`, `usbipd bind --busid <id>`, `usbipd attach --wsl --busid <id>`.
- **Known friction (verified from a community walkthrough and the xtool docs):** attach can fail with "Device busy" (re-plug / force bind); if xtool reports `AFCClient.Error.muxError`, the xtool docs describe a workaround that relays the device connection from iTunes on Windows instead of USBIPD.

### 3.3 GitHub Actions + XcodeGen — reference build (works without xtool)

- **GitHub Actions macOS runners:** `macos-26` / `macos-latest` (arm64). Standard runners are free in public repositories; private repositories on GitHub Free get a monthly allowance equal to roughly 190 macOS minutes (verified: https://docs.github.com/en/billing/concepts/product-billing/github-actions , https://github.com/actions/runner-images). Check the image's "included software" page for the exact Xcode version and select it with `sudo xcode-select -s`.
- **XcodeGen** (prior knowledge): generates an `.xcodeproj` from a small `project.yml`, so no Xcode project file is ever hand-edited or committed. https://github.com/yonaskolb/XcodeGen · on the runner: `brew install xcodegen && xcodegen generate`.
- **Unsigned build recipe** (prior knowledge; standard practice):
  ```bash
  xcodebuild -project Handtone.xcodeproj -scheme Handtone -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
  mkdir Payload && cp -R build/Build/Products/Release-iphoneos/Handtone.app Payload/
  zip -r Handtone.ipa Payload
  ```
  Upload `Handtone.ipa` with `actions/upload-artifact`.
- **GitHub CLI (`gh`)** — works on Windows; `winget install GitHub.cli`. Lets Opus drive CI from the terminal: `gh run watch`, `gh run view --log-failed`, `gh run download -n Handtone-ipa`. https://cli.github.com

### 3.4 Sideloadly — install tool (for CI-built IPAs)

- **What:** Windows/macOS desktop app that signs an `.ipa` with your Apple ID and installs it on a connected iPhone.
- **Site:** https://sideloadly.io · FAQ https://sideloadly.io/faq (verified: supports current iOS, free Apple ID with 7-day validity and 3-app limit, optional automatic refresh; credentials are sent only to Apple).
- **Windows requirements:** the *web* (non-Microsoft-Store) versions of iTunes and iCloud from apple.com.
- **Note:** closed-source freeware. Using a secondary Apple ID for sideloading is a reasonable precaution.

### 3.5 One-time iPhone setup (manual, by the user)

1. Connect by USB, tap "Trust This Computer".
2. After the first install: Settings → General → VPN & Device Management → trust the developer profile.
3. Settings → Privacy & Security → Developer Mode → on (appears after the first sideload; requires a restart).

## 4. MCP servers

### 4.1 sosumi — recommended

- **What:** serves Apple Developer documentation, Human Interface Guidelines and WWDC transcripts as Markdown for LLMs. Apple's own doc pages are JavaScript-rendered and hard for agents to read.
- **Site:** https://sosumi.ai (project by NSHipster; not an Apple product).
- **Windows:** yes — it is a remote HTTP MCP server.
- **Install (verified from project listings):** `claude mcp add --transport http sosumi https://sosumi.ai/mcp`
- **Also usable without MCP:** replace `developer.apple.com` with `sosumi.ai` in any documentation URL and fetch it.
- **Why it matters here:** Opus cannot compile-and-see on a whim; reading the exact current signature of `videoRotationAngle`, `VNHumanHandPoseObservation.JointName` or `AVAudioSourceNode` before writing avoids wasted build cycles.

### 4.2 Not usable on Windows (listed so nobody wastes time on them)

| Server | What it does | Why not |
|--------|--------------|---------|
| XcodeBuildMCP (https://github.com/getsentry/XcodeBuildMCP) | Build, test, simulator and LLDB tools over `xcodebuild` | Requires macOS + Xcode. |
| Apple's Xcode MCP bridge (`xcrun mcpbridge`, Xcode 26.3+) | Connects agents to a running Xcode | Requires macOS + Xcode. (Details from a secondary source.) |
| iOS Simulator MCP servers | Drive the Simulator, take screenshots | Requires macOS; and the Simulator has no camera. |

If you ever rent a cloud Mac or borrow one, XcodeBuildMCP is the first thing to add (`claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp`).

## 5. Claude skills (agent instructions)

Skills are instruction packs, not code that ships. Read each repository's README for the current install command — these projects update their install instructions frequently.

| Skill | Repository | Use here | Install (as found; confirm in README) |
|-------|------------|----------|----------------------------------------|
| SwiftUI Pro (Paul Hudson) | https://github.com/twostraws/SwiftUI-Agent-Skill | Steers Opus away from deprecated SwiftUI patterns | Claude Code plugin marketplace: add `twostraws/SwiftUI-Agent-Skill`, then install the plugin |
| Swift Concurrency Expert (Antoine van der Lee) | https://github.com/AvdLee/Swift-Concurrency-Agent-Skill | The capture delegate / audio thread / main actor boundaries are where Swift 6 diagnostics bite | `npx skills add` per README, or marketplace `AvdLee/Swift-Concurrency-Agent-Skill` |
| xtool plugin (2389 Research) | https://github.com/2389-research/claude-plugins | Teaches the agent xtool's project layout and commands | `/plugin marketplace add 2389-research/claude-plugins` then `/plugin install xtool@2389-research` (second command inferred from the marketplace's pattern) |

Directory of further Swift skills: https://github.com/twostraws/Swift-Agent-Skills. Do not install more than these three; overlapping skills give conflicting advice.

**Project-local instructions matter more than any skill:** the repository's `CLAUDE.md` (specified in OPUS-HANDOFF.md) carries the rules specific to this app — real-time audio constraints, the "logic lives in Core" rule, and the build commands.

## 6. Libraries considered and deferred

| Library | Status | Decision |
|---------|--------|----------|
| MediaPipe Tasks Vision for iOS — https://developers.google.com/edge/mediapipe/solutions/vision/hand_landmarker/ios | SwiftPM product `MediaPipeTasksVision` from `https://github.com/google-ai-edge/mediapipe`, v1.2.2 binaries, iOS 15+; needs `hand_landmarker.task` in the bundle (verified) | **Fallback only**, if Vision fails the M3 gate. Known risk: the package manifest uses `unsafeFlags`, which SwiftPM rejects for version-pinned dependencies — pin by revision or vendor the xcframeworks. Untested under xtool. Do not use CocoaPods: trunk goes read-only on 2 Dec 2026. |
| AudioKit — https://github.com/AudioKit/AudioKit | Maintained (5.7.2, Mar 2026) | Not needed for an 8-voice additive synth. Reconsider only for effects or complex instruments. |
| `AVAudioUnitSampler` + SoundFont | System API | Future improvement for realistic instrument sounds. |

## 7. Optional conveniences

- **VS Code + Swift extension** (`swiftlang.swift-vscode`) with the WSL remote: syntax highlighting and SourceKit-LSP for the `HandtoneCore` package. Useful for reading code; not required.
- **A second phone or any camera with slow motion** — for the latency measurement in TESTING.md.
