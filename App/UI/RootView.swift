import SwiftUI

@main
struct HandtoneApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

/// The whole app: one camera surface with Play and Learn layered on top of it.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Theme.cream.ignoresSafeArea()
            switch model.cameraAccess {
            case .authorized:
                experience
            case .unknown:
                PermissionView(denied: false)
            case .denied:
                PermissionView(denied: true)
            }
        }
        .preferredColorScheme(.light)
        .tint(Theme.ink)
        .onAppear {
            if scenePhase == .active { model.activate() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.activate()
            } else if phase == .background {
                model.deactivate()
            }
        }
        .alert("Handtone", isPresented: messageBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
    }

    private var messageBinding: Binding<Bool> {
        Binding(get: { model.message != nil },
                set: { showing in if !showing { model.message = nil } })
    }

    private var showsHands: Bool {
        model.tab == .play || (model.tab == .learn && model.activeSong != nil)
    }

    private var experience: some View {
        ZStack {
            CameraPreview(camera: model.camera)
                .ignoresSafeArea()

            if model.settings.softCamera > 0.01 {
                SoftCameraOverlay(strength: Double(model.settings.softCamera))
                    .ignoresSafeArea()
            }
            if showsHands && model.settings.showSkeleton {
                HandOverlay(live: model.live)
                    .ignoresSafeArea()
            }

            switch model.tab {
            case .play:
                PlayView(recorder: model.recorder)
            case .learn:
                LearnView()
            }
        }
    }
}

/// A soft, misty look for the camera picture: part frosted blur, a warm cream tint, and a light haze.
/// Display only — hand tracking always reads the untouched camera frames.
struct SoftCameraOverlay: View {
    /// 0 = plain camera, 1 = fully misty.
    let strength: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.35 * strength)
            LinearGradient(colors: [Theme.cream, Theme.blush],
                           startPoint: .top, endPoint: .bottom)
                .opacity(0.16 * strength)
            Color.white
                .opacity(0.06 * strength)
        }
        .allowsHitTesting(false)
    }
}

/// Shown before camera access is granted, and when it has been refused.
struct PermissionView: View {
    @EnvironmentObject private var model: AppModel
    let denied: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.white, Theme.cream, Theme.sand],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "hand.raised.fingers.spread")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(LinearGradient(colors: [Theme.rose, Theme.latte],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Handtone")
                    .font(Theme.display(42))
                    .foregroundStyle(Theme.ink)
                Text(denied
                     ? "Handtone needs the camera to see your hands. Turn on Camera for Handtone in Settings."
                     : "Play chords in the air. Handtone watches your hands through the camera and turns their shapes into music.")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                Label("Video never leaves your iPhone", systemImage: "lock")
                    .font(Theme.label(13, weight: .medium))
                    .foregroundStyle(Theme.rose)
                Spacer()
                Button(denied ? "Open Settings" : "Allow Camera") {
                    if denied {
                        model.openSystemSettings()
                    } else {
                        model.requestCameraAccess()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 34)
                .padding(.bottom, 30)
            }
        }
    }
}
