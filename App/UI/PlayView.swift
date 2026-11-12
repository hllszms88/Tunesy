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
                .padding(.top, 22)

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                Spacer()
                LevelMeter(live: model.live)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if model.settings.mode == .chords {
                DegreeStrip(live: model.live, key: model.settings.key)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.bottom, 84)
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
            IconButton(systemName: model.settings.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       isOn: model.settings.muted, tint: Theme.coral) {
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
                .font(Theme.label(13, weight: .bold))
                .foregroundStyle(selected ? Theme.ink : Color.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(Color.white)
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
        VStack(spacing: 8) {
            if state.mode == .theremin {
                thereminReadout(state)
            } else {
                chordReadout(state)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.12), value: state.chord)
    }

    @ViewBuilder
    private func chordReadout(_ state: InstrumentState) -> some View {
        if let chord = state.chord {
            Text(chord.name(key: key))
                .font(Theme.display(84))
                .foregroundStyle(Theme.degreeColor(chord.degree))
                .shadow(color: Theme.degreeColor(chord.degree).opacity(0.55), radius: 22)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\(chord.roman) · \(chord.qualityName)")
                .font(Theme.label(15))
                .foregroundStyle(Color.white.opacity(0.8))
            if state.octaveShift != 0 {
                Pill(text: octaveText(state.octaveShift), color: Theme.coral)
            }
        } else if let gesture = state.gesture {
            Text(Music.roman(degree: gesture.degree, isMajor: gesture.isMajor))
                .font(Theme.display(84))
                .foregroundStyle(Color.white.opacity(0.35))
            Text("Raise your right hand and show 1–4 fingers")
                .font(Theme.label(14))
                .foregroundStyle(Color.white.opacity(0.75))
        } else {
            Text("—")
                .font(Theme.display(84))
                .foregroundStyle(Color.white.opacity(0.25))
            Text("Show both hands to the camera")
                .font(Theme.label(14))
                .foregroundStyle(Color.white.opacity(0.75))
        }
    }

    @ViewBuilder
    private func thereminReadout(_ state: InstrumentState) -> some View {
        Text(state.thereminGain > 0 ? "\(Int(state.pitchHz.rounded())) Hz" : "—")
            .font(Theme.display(68))
            .foregroundStyle(state.thereminGain > 0 ? Theme.coral : Color.white.opacity(0.25))
            .shadow(color: Theme.coral.opacity(state.thereminGain > 0 ? 0.5 : 0), radius: 20)
            .monospacedDigit()
        Text("Right hand height = pitch · Left hand height = volume")
            .font(Theme.label(13))
            .foregroundStyle(Color.white.opacity(0.75))
    }

    private func octaveText(_ shift: Int) -> String {
        if shift == -1 { return "One octave down" }
        if shift == 1 { return "One octave up" }
        return shift < 0 ? "\(-shift) octaves down" : "\(shift) octaves up"
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
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.coral, Theme.gold], startPoint: .bottom, endPoint: .top))
                    .frame(height: max(10, 150 * level))
                    .opacity(level > 0.01 ? 1 : 0)
            }
            .frame(width: 10, height: 150)
            Text("VOL")
                .font(Theme.label(10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
            if state.mode == .chords {
                Text(toneText(state.tone))
                    .font(Theme.label(10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
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

/// The seven chords of the key with the hand shape that plays each; the active one lights up.
struct DegreeStrip: View {
    @ObservedObject var live: LiveState
    let key: MusicalKey

    private static let hints = ["1", "2", "3", "4", "5", "🤘", "🤘+👍"]

    var body: some View {
        let gesture = live.frame.instrument.gesture
        HStack(spacing: 5) {
            ForEach(1...7, id: \.self) { degree in
                let active = gesture?.degree == degree
                let color = Theme.degreeColor(degree)
                VStack(spacing: 3) {
                    Text(Music.noteName(degree: degree, key: key))
                        .font(Theme.label(15, weight: .heavy))
                        .foregroundStyle(active ? Theme.ink : Color.white)
                    Text(Music.romanNumerals[degree - 1])
                        .font(Theme.label(10, weight: .bold))
                        .foregroundStyle(active ? Theme.ink.opacity(0.7) : Color.white.opacity(0.55))
                    Text(DegreeStrip.hints[degree - 1])
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(active ? Theme.ink.opacity(0.7) : Color.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(active ? color : Color.white.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(color.opacity(active ? 0 : 0.45), lineWidth: 1)
                }
            }
        }
        .padding(6)
        .glassCard(cornerRadius: 18)
    }
}
