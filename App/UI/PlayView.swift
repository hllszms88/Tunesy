import GestureCore
import SwiftUI

/// The instrument. Nothing is written on screen: chord names appear in the middle while you
/// play. Settings and camera flip sit at the top; record and Learn at the bottom.
struct PlayView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var recorder: ScreenRecorder
    @State private var showSettings = false

    var body: some View {
        ZStack {
            ChordDisplay(live: model.live, key: model.settings.key)

            VStack(spacing: 0) {
                if !recorder.isRecording {
                    HStack(spacing: 6) {
                        Spacer()
                        IconButton(systemName: "gearshape") { showSettings = true }
                        IconButton(systemName: "arrow.triangle.2.circlepath.camera") { model.switchCamera() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .transition(.opacity)
                }
                Spacer()
                bottomBar
                    .padding(.bottom, 18)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(model)
        }
    }

    private var bottomBar: some View {
        HStack {
            Group {
                if recorder.isRecording {
                    Color.clear
                } else {
                    IconButton(systemName: "music.note.list") { model.tab = .learn }
                }
            }
            .frame(width: 70)
            Spacer()
            RecordButton(isRecording: recorder.isRecording, isBusy: recorder.isBusy) {
                recorder.toggle()
            }
            Spacer()
            Color.clear.frame(width: 70, height: 1)
        }
        .padding(.horizontal, 24)
    }
}

/// Snapchat-style capture button: a white ring; a soft pink square while recording.
struct RecordButton: View {
    let isRecording: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 5)
                    .frame(width: 78, height: 78)
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
                RoundedRectangle(cornerRadius: isRecording ? 8 : 30, style: .continuous)
                    .fill(isRecording ? Theme.rose : Color.white.opacity(0.18))
                    .frame(width: isRecording ? 30 : 60, height: isRecording ? 30 : 60)
            }
            .opacity(isBusy ? 0.5 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isRecording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}

/// The chord (or theremin pitch) being played, in the middle of the screen.
/// Nothing is shown while you are not playing.
struct ChordDisplay: View {
    @ObservedObject var live: LiveState
    let key: MusicalKey

    var body: some View {
        let state = live.frame.instrument
        let text = label(for: state)
        ZStack {
            if let text = text {
                Text(text)
                    .font(Theme.display(84))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .onCameraText()
                    .id(text)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.18), value: text)
    }

    private func label(for state: InstrumentState) -> String? {
        switch state.mode {
        case .chords:
            return state.chord?.name(key: key)
        case .theremin:
            return state.thereminGain > 0 ? "\(Int(state.pitchHz.rounded())) Hz" : nil
        }
    }
}
