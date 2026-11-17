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

            VStack {
                Spacer()
                WaveformView(live: model.live)
                    .frame(height: 90)
                    .padding(.bottom, 118)
            }
            .allowsHitTesting(false)

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
                    // Fixed size: a bare Color.clear would fill the whole height and push the
                    // record button to the middle of the screen.
                    Color.clear.frame(width: 46, height: 46)
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

/// A glowing line along the bottom that ripples with whatever is sounding: its shape follows
/// the notes of the chord (or the theremin pitch) and its height follows the volume.
/// It is drawn from the instrument's state, not from the audio itself.
struct WaveformView: View {
    @ObservedObject var live: LiveState

    var body: some View {
        let state = live.frame.instrument
        let ratios = WaveformView.ratios(for: state)
        let level = state.isSounding ? CGFloat(max(0.15, min(1, state.mode == .chords
                                                               ? state.volume : state.thereminGain / 0.55)))
                                     : 0
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let mid = size.height / 2
                let amplitude = (size.height / 2 - 4) * level
                var path = Path()
                let steps = Int(size.width / 3)
                for step in 0...steps {
                    let x = CGFloat(step) / CGFloat(steps)
                    // Fade the ends so the line melts into the screen edges.
                    let envelope = sin(x * .pi)
                    var y: CGFloat = 0
                    for (index, ratio) in ratios.enumerated() {
                        let phase = time * (2.2 + Double(index) * 0.35)
                        y += CGFloat(sin(Double(x) * 2 * .pi * 2.5 * Double(ratio) - phase))
                    }
                    if !ratios.isEmpty { y /= CGFloat(ratios.count) }
                    let point = CGPoint(x: x * size.width, y: mid - y * amplitude * envelope)
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.addFilter(.shadow(color: Theme.rose.opacity(level > 0 ? 0.9 : 0), radius: 8))
                context.stroke(path, with: .color(Color.white.opacity(level > 0 ? 0.95 : 0.35)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
        }
        .animation(.easeOut(duration: 0.2), value: level)
    }

    /// Frequencies relative to the lowest note, so the wave keeps the chord's shape.
    private static func ratios(for state: InstrumentState) -> [Float] {
        switch state.mode {
        case .chords:
            guard let lowest = state.frequencies.min(), lowest > 0 else { return [1] }
            return state.frequencies.map { $0 / lowest }
        case .theremin:
            return [max(0.5, min(4, state.pitchHz / 220))]
        }
    }
}
