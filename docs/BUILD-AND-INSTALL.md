# Build, install and release — from Windows

You do not need to own a Mac. A Mac is still required to compile iOS apps, so the build runs on a GitHub-hosted macOS machine. **Cloud builds do not remove Apple's signing requirement**: an app must be signed with an Apple ID before an iPhone will run it. The cloud build produces an *unsigned* app; you sign it on Windows when installing.

## 1. One-time setup on Windows

| Tool | Why | Install |
|------|-----|---------|
| Git | push the code | already installed on this machine |
| GitHub account | hosts the code and runs the builds | https://github.com/signup |
| GitHub CLI (optional) | watch builds and download results from the terminal | `winget install GitHub.cli` then `gh auth login` |
| iTunes and iCloud, **web versions** | Sideloadly needs Apple's device drivers; the Microsoft Store versions do not work | apple.com downloads |
| Sideloadly | signs and installs the app on your iPhone | https://sideloadly.io |

A second Apple ID used only for sideloading is a sensible precaution, because Sideloadly signs in to Apple on your behalf.

## 2. Put the code on GitHub

Create an empty repository on github.com (a **public** repository gets free macOS build minutes; a private one has a limited monthly allowance). Then, in this folder:

```bash
git init -b main
```

```bash
git add .
```

```bash
git commit -m "Handtone: initial app"
```

```bash
git remote add origin https://github.com/YOUR-NAME/handtone.git
```

```bash
git push -u origin main
```

## 3. The cloud build

Every push to `main` starts the workflow in `.github/workflows/build.yml`. It has two jobs:

- **Core logic tests** (Linux): runs `swift test` on the gesture, music, lesson and synth code.
- **iOS app** (macOS): installs XcodeGen, generates the Xcode project from `project.yml`, and builds the app with Xcode without signing.

Results appear under the repository's **Actions** tab.

- If the build fails, open the run: the **Summary** page lists the compiler errors, and the full log is attached as the `xcodebuild-log` artifact. Give those errors to Claude to fix, push again.
- If it succeeds, download the `Handtone-ipa` artifact (a zip containing `Handtone-unsigned.ipa`).

With the GitHub CLI:

```bash
gh run watch
```

```bash
gh run view --log-failed
```

```bash
gh run download -n Handtone-ipa
```

**Expect the first builds to fail.** This code has never been compiled (see TESTING-REPORT.md). Fixing the first round of compiler errors is the next step of the project, not a sign that something went wrong with the setup.

## 4. Install on your iPhone (free Apple ID)

1. Connect the iPhone by USB and tap **Trust** on the phone.
2. Open Sideloadly, drag in `Handtone-unsigned.ipa`, enter your Apple ID, press **Start**.
3. On the iPhone: **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**.
4. On the iPhone: **Settings → Privacy & Security → Developer Mode** → on (the phone restarts). This switch appears only after the first install.
5. Open Handtone and allow the camera.

Limits of a free Apple ID (Apple's rules, not Sideloadly's):

- The app stops opening after **7 days**; install it again to renew. Sideloadly can refresh automatically when the phone is nearby.
- At most 3 sideloaded apps on a device, and 10 new app identifiers per week. Keep the bundle identifier `com.handtone.app` unchanged so you do not use these up. If Apple reports that identifier as taken, change it once in `project.yml` to something unique such as `com.yourname.handtone`.

## 5. What needs a paid Apple Developer account ($99/year)

| Goal | Free Apple ID | Paid programme |
|------|---------------|----------------|
| Run on your own iPhone | Yes, renew every 7 days | Yes, valid for 1 year |
| TestFlight (share with testers) | No | Yes |
| App Store | No | Yes |

### Preparing for TestFlight and the App Store (later)

1. Enrol at https://developer.apple.com/programs/ and create the app record in App Store Connect with your bundle identifier.
2. Create an App Store Connect API key (Users and Access → Integrations). Store the key, its ID and the issuer ID as GitHub **repository secrets** — never in the code.
3. Add a signed "archive and upload" job to the workflow: `xcodebuild archive` with automatic signing (`-allowProvisioningUpdates` plus the API key options), then `xcodebuild -exportArchive` with an export options file for App Store Connect. This job is not included yet because it cannot be tested without the account.
4. App Store listing needs: screenshots from a real device, a description, a privacy policy URL, and the privacy questionnaire. This app collects no data, so the answer is "Data Not Collected".
5. Review notes should explain that the camera is used on-device for hand and face tracking and that nothing is recorded or uploaded.

Before submitting, also review the app's similarity to the product that inspired its interaction. The code, artwork, name, songs and sound presets here are original, but the gesture scheme follows gesturesynth.com; it is worth contacting its author or differentiating further before a commercial release.

## 6. Faster iteration (optional)

`xtool` (https://github.com/xtool-org/xtool) can compile and install iOS apps from Windows through WSL, which shortens the edit-build-try loop from about ten minutes to one or two. It needs a SwiftPM-shaped project and its own setup; this repository is not configured for it yet. The research notes in `docs/research/TOOLS-AND-SKILLS.md` describe the setup.

## 7. Day-to-day workflow with Claude

1. Describe the change or paste the build errors.
2. Claude edits the code and you push.
3. Wait for the Actions run; on failure, paste the summary back.
4. On success, install the new `.ipa` and try it. Report what you see using the checklist in TESTING-REPORT.md.
