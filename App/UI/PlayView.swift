import GestureCore
import SwiftUI

/// The instrument. Left hand picks the chord, right hand shapes the sound.
struct PlayView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 6)

            ChordDisplay(live: model.live, key: model.settings.key)
                .padding(.top, 26)

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                if model.settings.mode == .chords {
                    NoteColumn(live: model.live, key: model.settings.key)
                }
                Spacer()
                LevelMeter(live: model.live)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 92)
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $showHelp) {
            HelpSheet()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            modeSwitch
            Spacer(minLength: 0)
            IconButton(systemName: "questionmark") { showHelp = true }
            IconButton(systemName: model.settings.muted ? "speaker.slash" : "speaker.wave.2",
                       isOn: model.settings.muted) {
                model.settings.muted.toggle()
            }
            IconButton(systemName: "slider.horizontal.3") { showSettings = true }
            IconButton(systemName: "arrow.triangle.2.circlepath.camera") { model.switchCamera() }
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 2) {
            modeButton(.chords, title: "Chords")
            modeButton(.theremin, title: "Theremin")
        }
        .padding(4)
        .glassCard(cornerRadius: 24)
    }

    private func modeButton(_ mode: InstrumentMode, title: String) -> some View {
        let selected = model.settings.mode == mode
        return Button {
            withAnimation(.snappy(duration: 0.2)) {
                model.settings.mode = mode
            }
        } label: {
            Text(title)
                .font(Theme.label(13, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(selected ? Theme.cream : Theme.cocoaSoft)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(Theme.cocoa)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

/// The big readout in the middle of the screen: what is sounding right now.
struct ChordDisplay: View {
    @ObservedObject var live: LiveState
    let key: MusicalKey

    var body: some View {
        let state = live.frame.instrument
        VStack(spacing: 6) {
            if state.mode == .theremin {
                thereminReadout(state)
            } else {
                chordReadout(state)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: state.chord)
    }

    @ViewBuilder
    private func chordReadout(_ state: InstrumentState) -> some View {
        if let chord = state.chord {
            Text(chord.name(key: key))
                .font(Theme.display(88))
                .onCameraText()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\(chord.roman) · \(chord.qualityName)")
                .font(Theme.label(15, weight: .medium))
                .onCameraText()
            if state.octaveShift != 0 {
                Text(octaveText(state.octaveShift))
                    .font(Theme.label(12, weight: .semibold))
                    .foregroundStyle(Theme.cocoa)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.85), in: Capsule())
                    .padding(.top, 4)
            }
        } else if let gesture = state.gesture {
            Text(Music.roman(degree: gesture.degree, isMajor: gesture.isMajor))
                .font(Theme.display(88))
                .onCameraText()
                .opacity(0.55)
            Text("Raise your right hand and show 1–4 fingers")
                .font(Theme.label(14, weight: .medium))
                .onCameraText()
        } else {
            Text("Show both hands")
                .font(Theme.display(34))
                .onCameraText()
            Text("Left hand picks the chord · right hand plays it")
                .font(Theme.label(14, weight: .medium))
                .onCameraText()
        }
    }

    @ViewBuilder
    private func thereminReadout(_ state: InstrumentState) -> some View {
        Text(state.thereminGain > 0 ? "\(Int(state.pitchHz.rounded())) Hz" : "—")
            .font(Theme.display(68))
            .monospacedDigit()
            .onCameraText()
        Text("Right hand height = pitch · Left hand height = volume")
            .font(Theme.label(13, weight: .medium))
            .onCameraText()
    }

    private func octaveText(_ shift: Int) -> String {
        if shift == -1 { return "One octave down" }
        if shift == 1 { return "One octave up" }
        return shift < 0 ? "\(-shift) octaves down" : "\(shift) octaves up"
    }
}

/// The seven notes of the key, written down the side of the screen. The one being played glows.
struct NoteColumn: View {
    @ObservedObject var live: LiveState
    let key: MusicalKey

    var body: some View {
        let active = live.frame.instrument.gesture?.degree
        VStack(alignment: .leading, spacing: 4) {
            ForEach(1...7, id: \.self) { degree in
                let isActive = active == degree
                HStack(spacing: 8) {
                    Text(Music.noteName(degree: degree, key: key))
                        .font(Theme.display(isActive ? 26 : 21))
                        .foregroundStyle(isActive ? Theme.cocoa : Color.white)
                        .frame(width: 40, height: 40)
                        .background {
                            if isActive {
                                Circle()
                                    .fill(Color.white)
                                    .shadow(color: Color.white.opacity(0.9), radius: 12)
                            }
                        }
                    Text(Music.romanNumerals[degree - 1])
                        .font(Theme.label(11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(isActive ? 1 : 0.8))
                }
                .shadow(color: Theme.cocoa.opacity(isActive ? 0 : 0.45), radius: 5, x: 0, y: 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isActive)
            }
        }
    }
}

/// Volume (bar) and tone (label) from the expression hand.
struct LevelMeter: View {
    @ObservedObject var live: LiveState

    var body: some View {
        let state = live.frame.instrument
        let level = CGFloat(max(0, min(1, state.volume)))
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Theme.sand)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.rose, Theme.blush], startPoint: .bottom, endPoint: .top))
                    .frame(height: max(10, 150 * level))
                    .opacity(level > 0.01 ? 1 : 0)
            }
            .frame(width: 8, height: 150)
            Text("VOL")
                .font(Theme.label(10, weight: .semibold))
                .foregroundStyle(Theme.cocoaSoft)
            if state.mode == .chords {
                Text(toneText(state.tone))
                    .font(Theme.label(10, weight: .semibold))
                    .foregroundStyle(Theme.cocoaSoft)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .glassCard(cornerRadius: 18)
    }

    private func toneText(_ tone: Float) -> String {
        let percent = Int((tone * 100).rounded())
        if percent == 0 { return "TONE 0" }
        return percent > 0 ? "TONE +\(percent)" : "TONE \(percent)"
    }
}
