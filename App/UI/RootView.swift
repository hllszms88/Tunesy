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

/// The whole app: one camera surface, three experiences layered on top of it.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.cameraAccess {
            case .authorized:
                experience
            case .unknown:
                PermissionView(denied: false)
            case .denied:
                PermissionView(denied: true)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.mint)
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

            if model.tab == .filters && model.filter.kind == .color {
                FilteredPreview(store: model.pipeline.filterStore)
                    .ignoresSafeArea()
            }
            if model.tab == .filters && model.filter.kind == .face {
                FaceAccessoryLayer(live: model.live, filter: model.filter)
                    .ignoresSafeArea()
            }
            if showsHands && model.settings.showSkeleton {
                HandOverlay(live: model.live)
                    .ignoresSafeArea()
            }

            // Darken the top and bottom edges so controls stay readable over any scene.
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
                Spacer()
                LinearGradient(colors: [.clear, Color.black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 260)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            switch model.tab {
            case .play:
                PlayView()
            case .learn:
                LearnView()
            case .filters:
                FiltersView()
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

/// Floating three-way switch between the experiences.
struct TabBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            item(.play, title: "Play", symbol: "hand.raised.fill")
            item(.learn, title: "Learn", symbol: "music.note.list")
            item(.filters, title: "Filters", symbol: "camera.filters")
        }
        .padding(5)
        .glassCard(cornerRadius: 30)
        .padding(.horizontal, 28)
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
            .foregroundStyle(selected ? Theme.ink : Color.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if selected {
                    Capsule().fill(Theme.mint)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Shown before camera access is granted, and when it has been refused.
struct PermissionView: View {
    @EnvironmentObject private var model: AppModel
    let denied: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.ink, Color(red: 0.10, green: 0.08, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "hand.raised.fingers.spread.fill")
                    .font(.system(size: 76, weight: .regular))
                    .foregroundStyle(LinearGradient(colors: [Theme.mint, Theme.violet],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("Handtone")
                    .font(Theme.display(40))
                Text(denied
                     ? "Handtone needs the camera to see your hands. Turn on Camera for Handtone in Settings."
                     : "Play chords in the air. Handtone watches your hands through the camera and turns their shapes into music.")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                Label("Video never leaves your iPhone", systemImage: "lock.fill")
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.mint)
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
