import GestureCore
import SwiftUI

/// The instrument. Nothing is written on screen: while you play, a calm wave appears above the
/// capture button with the chord name in its middle. Settings and camera flip sit at the top.
struct PlayView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var media: MediaRecorder
    @State private var showSettings = false
    @State private var flash: Double = 0

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if !media.isRecording {
                    HStack(spacing: 6) {
                        Spacer()
                        IconButton(systemName: "gearshape") { showSettings = true }
                        IconButton(systemName: "arrow.triangle.2.circlepath.camera") { model.switchCamera() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .transition(.opacity)
                }
                if let notice = media.notice {
                    Text(notice)
                        .font(Theme.label(13, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.9), in: Capsule())
                        .padding(.top, 8)
                        .transition(.opacity)
                }
                Spacer()
                ChordWave(live: model.live, key: model.settings.key)
                    .frame(height: 90)
                    .padding(.bottom, 10)
                bottomBar
                    .padding(.bottom, 18)
            }

            // White flash when a photo is taken.
            Color.white
                .opacity(flash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.2), value: media.isRecording)
        .animation(.easeInOut(duration: 0.2), value: media.notice)
        .onChange(of: media.photoCount) { _, _ in
            flash = 0.8
            withAnimation(.easeOut(duration: 0.35)) {
                flash = 0
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(model)
        }
    }

    private var bottomBar: some View {
        HStack {
            Group {
                if media.isRecording {
                    // Fixed size, so the capture button stays at the bottom.
                    Color.clear.frame(width: 46, height: 46)
                } else {
                    IconButton(systemName: "music.note.list") { model.tab = .learn }
                }
            }
            .frame(width: 70)
            Spacer()
            CaptureButton(media: media)
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 24)
    }
}

/// Snapchat-style capture: tap for a photo, hold for a video, slide right while holding to
/// lock the video so it keeps going after you let go (tap again to stop).
struct CaptureButton: View {
    @ObservedObject var media: MediaRecorder

    @State private var pressing = false
    @State private var pressID = 0
    @State private var pressBeganLocked = false
    @State private var startedVideo = false
    @State private var locked = false

    private let holdDelay: UInt64 = 350_000_000
    private let lockDistance: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(media.isRecording ? Theme.rose : Color.white, lineWidth: 5)
                .frame(width: 78, height: 78)
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
            RoundedRectangle(cornerRadius: media.isRecording ? 8 : 30, style: .continuous)
                .fill(media.isRecording ? Theme.rose : Color.white.opacity(0.18))
                .frame(width: media.isRecording ? 30 : 60, height: media.isRecording ? 30 : 60)
        }
        .scaleEffect(pressing && !media.isRecording ? 0.92 : (media.isRecording && !locked ? 1.12 : 1))
        .overlay(alignment: .trailing) {
            // While holding a video, a lock appears to the right: slide onto it to lock.
            Image(systemName: locked ? "lock.fill" : "lock.open")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 1)
                .offset(x: 72)
                .opacity(startedVideo && (pressing || locked) ? 1 : 0)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !pressing {
                        pressing = true
                        pressBeganLocked = locked && media.isRecording
                        pressID += 1
                        let id = pressID
                        if !pressBeganLocked {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: holdDelay)
                                if pressing && pressID == id && !media.isRecording {
                                    startedVideo = true
                                    media.startVideo()
                                }
                            }
                        }
                    }
                    if startedVideo && !locked && value.translation.width > lockDistance {
                        locked = true
                    }
                }
                .onEnded { _ in
                    pressing = false
                    if pressBeganLocked {
                        finishVideo()
                    } else if startedVideo {
                        if !locked { finishVideo() }
                    } else {
                        media.takePhoto()
                    }
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: media.isRecording)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: pressing)
        .animation(.easeOut(duration: 0.2), value: locked)
        .onChange(of: media.isRecording) { _, recording in
            if !recording {
                startedVideo = false
                locked = false
            }
        }
        .accessibilityLabel(media.isRecording ? "Stop recording" : "Take a photo, or hold to record a video")
    }

    private func finishVideo() {
        media.stopVideo()
        startedVideo = false
        locked = false
    }
}

/// While something is playing: a calm white wave at a fixed rhythm with the chord name in its
/// middle. Hidden while silent.
struct ChordWave: View {
    @ObservedObject var live: LiveState
    let key: MusicalKey

    var body: some View {
        let label = live.frame.instrument.displayLabel(key: key)
        ZStack {
            if let label = label {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        let font = WaveStyle.uiFont(size: WaveStyle.fontSize)
                        let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
                        let rect = CGRect(origin: .zero, size: size)
                        let path = Path(WaveStyle.path(in: rect, gap: textWidth + WaveStyle.gapPadding, time: time))
                        context.addFilter(.shadow(color: Theme.rose.opacity(0.9), radius: 8))
                        context.stroke(path, with: .color(Color.white.opacity(0.95)),
                                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                }
                .transition(.opacity)

                Text(label)
                    .font(Font(WaveStyle.uiFont(size: WaveStyle.fontSize)))
                    .lineLimit(1)
                    .onCameraText()
                    .id(label)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: label)
    }
}

extension InstrumentState {
    /// What the screen and recordings show: the chord name, or the theremin pitch; nil when silent.
    func displayLabel(key: MusicalKey) -> String? {
        switch mode {
        case .chords:
            return chord?.name(key: key)
        case .theremin:
            return thereminGain > 0 ? "\(Int(pitchHz.rounded())) Hz" : nil
        }
    }
}
