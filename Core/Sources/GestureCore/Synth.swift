import Foundation

/// A sound preset: up to two sawtooth partials per note, optional drive, and a low-pass filter.
public struct SynthVoice: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var blurb: String
    public var ratio0: Float
    public var detune0: Float   // cents
    public var gain0: Float
    public var ratio1: Float
    public var detune1: Float
    public var gain1: Float     // 0 = no second partial
    public var drive: Float
    public var filterBase: Float
    public var filterQ: Float

    public static let all: [SynthVoice] = [
        SynthVoice(id: "classic", name: "Classic", blurb: "One clean saw.",
                   ratio0: 1, detune0: 0, gain0: 1, ratio1: 1, detune1: 0, gain1: 0,
                   drive: 0, filterBase: 1200, filterQ: 0.7),
        SynthVoice(id: "warm", name: "Warm", blurb: "Two saws, slightly apart.",
                   ratio0: 1, detune0: -8, gain0: 0.5, ratio1: 1, detune1: 8, gain1: 0.5,
                   drive: 0, filterBase: 900, filterQ: 0.6),
        SynthVoice(id: "stack", name: "Stack", blurb: "A saw with an octave underneath.",
                   ratio0: 1, detune0: 0, gain0: 0.68, ratio1: 0.5, detune1: 0, gain1: 0.32,
                   drive: 0, filterBase: 800, filterQ: 0.65),
        SynthVoice(id: "bright", name: "Bright", blurb: "A saw with a thin octave on top.",
                   ratio0: 1, detune0: -4, gain0: 0.72, ratio1: 2, detune1: 4, gain1: 0.22,
                   drive: 0, filterBase: 1600, filterQ: 0.75),
        SynthVoice(id: "grit", name: "Grit", blurb: "A saw pushed a little harder.",
                   ratio0: 1, detune0: 0, gain0: 0.62, ratio1: 1, detune1: 0, gain1: 0,
                   drive: 0.42, filterBase: 1400, filterQ: 0.9)
    ]

    public static func named(_ id: String) -> SynthVoice {
        return all.first { $0.id == id } ?? all[0]
    }
}

public enum SynthMode: UInt8, Sendable {
    case silent, chord, theremin
}

/// Everything the audio thread needs, as plain values (no arrays, no references),
/// so it can be copied across threads without allocation.
public struct SynthParams: Sendable {
    public var mode: SynthMode = .silent
    public var noteCount: Int = 0
    public var freq0: Float = 0
    public var freq1: Float = 0
    public var freq2: Float = 0
    public var freq3: Float = 0
    /// Chord level 0...1 (hand height).
    public var volume: Float = 0
    /// -1...1 filter sweep.
    public var tone: Float = 0
    public var thereminHz: Float = 220
    public var thereminGain: Float = 0
    /// Overall output level 0...1 (volume slider / mute).
    public var masterGain: Float = 0.8

    public var ratio0: Float = 1
    public var detune0: Float = 0
    public var gain0: Float = 1
    public var ratio1: Float = 1
    public var detune1: Float = 0
    public var gain1: Float = 0
    public var drive: Float = 0
    public var filterBase: Float = 1200
    public var filterQ: Float = 0.7

    public init() {}

    public mutating func setVoice(_ voice: SynthVoice) {
        ratio0 = voice.ratio0
        detune0 = voice.detune0
        gain0 = voice.gain0
        ratio1 = voice.ratio1
        detune1 = voice.detune1
        gain1 = voice.gain1
        drive = voice.drive
        filterBase = voice.filterBase
        filterQ = voice.filterQ
    }

    public mutating func setChord(_ frequencies: [Float], volume: Float) {
        noteCount = Swift.min(frequencies.count, 4)
        if noteCount > 0 { freq0 = frequencies[0] }
        if noteCount > 1 { freq1 = frequencies[1] }
        if noteCount > 2 { freq2 = frequencies[2] }
        if noteCount > 3 { freq3 = frequencies[3] }
        self.volume = volume
        mode = noteCount > 0 ? .chord : .silent
    }

    /// Builds parameters from the instrument state, keeping voice and master gain.
    public mutating func apply(_ state: InstrumentState) {
        tone = state.tone
        switch state.mode {
        case .chords:
            thereminGain = 0
            if state.frequencies.isEmpty {
                mode = .silent
                noteCount = 0
                volume = 0
            } else {
                setChord(state.frequencies, volume: state.volume)
            }
        case .theremin:
            noteCount = 0
            volume = 0
            if state.thereminGain > 0 {
                mode = .theremin
                thereminHz = state.pitchHz
                thereminGain = state.thereminGain
            } else {
                mode = .silent
                thereminGain = 0
            }
        }
    }
}

/// The synthesizer's signal path: sawtooth oscillators → drive → resonant low-pass → output.
/// `render` is safe to call on a real-time audio thread: it never allocates or locks.
public struct SynthDSP {
    public var sampleRate: Float = 48_000

    private var phases: [Float] = [Float](repeating: 0, count: 8)
    private var noteFreqs: [Float] = [Float](repeating: 220, count: 4)
    private var noteGains: [Float] = [Float](repeating: 0, count: 4)
    private var chordLevel: Float = 0
    private var masterLevel: Float = 0
    private var thereminPhase: Float = 0
    private var thereminFreq: Float = 220
    private var thereminLevel: Float = 0
    private var cutoff: Float = 1200
    private var resonance: Float = 0.7
    private var ic1: Float = 0
    private var ic2: Float = 0

    public init() {}

    @inline(__always)
    private static func polyBlep(_ t: Float, _ dt: Float) -> Float {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        }
        if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }

    public mutating func render(into out: UnsafeMutablePointer<Float>, count: Int, params p: SynthParams) {
        guard count > 0 else { return }
        let sr = Swift.max(sampleRate, 8000)

        // Per-sample smoothing coefficients.
        let levelCoef = 1 - expf(-1 / (0.05 * sr))
        let noteCoef = 1 - expf(-1 / (0.006 * sr))
        let glideCoef = 1 - expf(-1 / (0.03 * sr))

        let chordOn = p.mode == .chord && p.noteCount > 0
        let chordTarget: Float = chordOn ? clampValue(p.volume, 0, 1) : 0
        let thereminOn = p.mode == .theremin
        let thereminTarget: Float = thereminOn ? clampValue(p.thereminGain, 0, 1) : 0
        let thereminFreqTarget = clampValue(p.thereminHz, 20, 4000)
        let masterTarget = clampValue(p.masterGain, 0, 1)

        if chordOn {
            noteFreqs[0] = p.freq0
            if p.noteCount > 1 { noteFreqs[1] = p.freq1 }
            if p.noteCount > 2 { noteFreqs[2] = p.freq2 }
            if p.noteCount > 3 { noteFreqs[3] = p.freq3 }
        }

        // Filter: glide toward the target once per buffer.
        var targetCutoff = p.filterBase
        var targetQ = p.filterQ
        let tone = clampValue(p.tone, -1, 1)
        if tone < 0 {
            targetCutoff = p.filterBase + tone * 950
            targetQ = p.filterQ - tone * 1.5
        } else if tone > 0 {
            targetCutoff = p.filterBase + tone * 3800
            targetQ = p.filterQ + tone * 4.5
        }
        targetCutoff = clampValue(targetCutoff, 40, sr * 0.45)
        let blockCoef = 1 - expf(-Float(count) / (0.04 * sr))
        cutoff += (targetCutoff - cutoff) * blockCoef
        resonance += (targetQ - resonance) * blockCoef

        let g = tanf(Float.pi * cutoff / sr)
        let k = 1 / Swift.max(resonance, 0.3)
        let a1 = 1 / (1 + g * (g + k))
        let a2 = g * a1
        let a3 = g * a2

        // Oscillator increments for 4 notes × 2 partials.
        let mul0 = p.ratio0 * powf(2, p.detune0 / 1200)
        let mul1 = p.ratio1 * powf(2, p.detune1 / 1200)
        let secondPartial = p.gain1 > 0
        let nyquistGuard: Float = 0.45

        let drive = clampValue(p.drive, 0, 1)
        let driveK = drive * 6
        let twoPi = 2 * Float.pi

        for i in 0..<count {
            chordLevel += (chordTarget - chordLevel) * levelCoef
            thereminLevel += (thereminTarget - thereminLevel) * levelCoef
            masterLevel += (masterTarget - masterLevel) * levelCoef
            thereminFreq += (thereminFreqTarget - thereminFreq) * glideCoef

            var mix: Float = 0
            for n in 0..<4 {
                let noteTarget: Float = (chordOn && n < p.noteCount) ? 1 : 0
                noteGains[n] += (noteTarget - noteGains[n]) * noteCoef
                let gain = noteGains[n]
                if gain < 0.0005 { continue }

                let dt0 = Swift.min(noteFreqs[n] * mul0 / sr, nyquistGuard)
                var ph = phases[n * 2] + dt0
                if ph >= 1 { ph -= 1 }
                phases[n * 2] = ph
                var sample = (2 * ph - 1 - SynthDSP.polyBlep(ph, dt0)) * p.gain0

                if secondPartial {
                    let dt1 = Swift.min(noteFreqs[n] * mul1 / sr, nyquistGuard)
                    var ph1 = phases[n * 2 + 1] + dt1
                    if ph1 >= 1 { ph1 -= 1 }
                    phases[n * 2 + 1] = ph1
                    sample += (2 * ph1 - 1 - SynthDSP.polyBlep(ph1, dt1)) * p.gain1
                }
                mix += sample * gain
            }
            mix *= 0.22

            if driveK > 0 {
                mix = (1 + driveK) * mix / (1 + driveK * abs(mix))
            }
            mix *= chordLevel

            if thereminLevel > 0.0005 {
                thereminPhase += thereminFreq / sr
                if thereminPhase >= 1 { thereminPhase -= 1 }
                mix += sinf(twoPi * thereminPhase) * thereminLevel
            }

            // State-variable low-pass (trapezoidal integration).
            let v3 = mix - ic2
            let v1 = a1 * ic1 + a2 * v3
            let v2 = ic2 + a2 * ic1 + a3 * v3
            ic1 = 2 * v1 - ic1
            ic2 = 2 * v2 - ic2

            out[i] = tanhf(v2 * masterLevel * 1.4)
        }

        // Flush denormals so a silent synth costs nothing.
        if abs(ic1) < 1e-15 { ic1 = 0 }
        if abs(ic2) < 1e-15 { ic2 = 0 }
    }
}
