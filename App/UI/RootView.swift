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
        .tint(Theme.cocoa)
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

            // A soft white haze at the top and bottom edges, behind the controls.
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
                Spacer()
                LinearGradient(colors: [.clear, Color.white.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            switch model.tab {
            case .play:
                PlayView()
            case .learn:
                LearnView()
            }

            if model.activeSong == nil {
                VStack {
                    Spacer()
                    TabBar()
                        .padding(.bottom, 6)
                }
            }
        }
    }
}

/// Floating switch between Play and Learn.
struct TabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            item(.play, title: "Play", symbol: "hand.raised.fill")
            item(.learn, title: "Learn", symbol: "music.note.list")
        }
        .padding(5)
        .glassCard(cornerRadius: 30)
        .padding(.horizontal, 60)
    }

    private func item(_ tab: AppModel.Tab, title: String, symbol: String) -> some View {
        let selected = model.tab == tab
        return Button {
            withAnimation(.snappy(duration: 0.25)) {
                model.tab = tab
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(Theme.label(14, weight: .bold))
            }
            .foregroundStyle(selected ? Theme.cream : Theme.cocoaSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if selected {
                    Capsule().fill(Theme.cocoa)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
                    .foregroundStyle(Theme.cocoa)
                Text(denied
                     ? "Handtone needs the camera to see your hands. Turn on Camera for Handtone in Settings."
                     : "Play chords in the air. Handtone watches your hands through the camera and turns their shapes into music.")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.cocoaSoft)
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
