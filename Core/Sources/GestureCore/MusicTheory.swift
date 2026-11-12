import Foundation

/// The twelve keys the instrument can be set to.
public enum MusicalKey: Int, CaseIterable, Codable, Sendable, Identifiable {
    case c = 0, dFlat, d, eFlat, e, f, fSharp, g, aFlat, a, bFlat, b

    public var id: Int { rawValue }

    public var name: String { Music.noteName(pitchClass: rawValue, flats: prefersFlats) }

    /// Keys conventionally written with flats.
    public var prefersFlats: Bool {
        switch self {
        case .dFlat, .eFlat, .f, .aFlat, .bFlat: return true
        default: return false
        }
    }

    /// Frequency of the key's root. C…F♯ sit in octave 4, G…B in octave 3,
    /// which keeps every key in a comfortable chord register.
    public var rootHz: Float {
        let middleC: Float = 261.6256
        let hz = middleC * powf(2, Float(rawValue) / 12)
        return rawValue >= MusicalKey.g.rawValue ? hz / 2 : hz
    }
}

public enum Music {
    /// Semitone offset of scale degrees I…VII from the key root.
    /// VII is voiced one semitone *below* the root (a leading-tone chord),
    /// matching the reference instrument.
    public static let degreeSemitones: [Int] = [0, 2, 4, 5, 7, 9, -1]

    public static let romanNumerals: [String] = ["I", "II", "III", "IV", "V", "VI", "VII"]

    private static let sharpNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    private static let flatNames = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]

    public static func noteName(pitchClass: Int, flats: Bool) -> String {
        let pc = ((pitchClass % 12) + 12) % 12
        return flats ? flatNames[pc] : sharpNames[pc]
    }

    /// Note name of a scale degree (1…7) in a key.
    public static func noteName(degree: Int, key: MusicalKey) -> String {
        let index = clampDegree(degree) - 1
        return noteName(pitchClass: key.rawValue + degreeSemitones[index], flats: key.prefersFlats)
    }

    public static func roman(degree: Int, isMajor: Bool) -> String {
        let numeral = romanNumerals[clampDegree(degree) - 1]
        return isMajor ? numeral : numeral.lowercased()
    }

    public static func qualityName(_ quality: Int, isMajor: Bool) -> String {
        if isMajor {
            switch quality {
            case 1: return "Major"
            case 2: return "Major · 1st inversion"
            case 3: return "Major 7th"
            case 4: return "Dominant 7th"
            default: return "—"
            }
        }
        switch quality {
        case 1: return "Minor"
        case 2: return "Minor · 1st inversion"
        case 3: return "Minor 7th"
        case 4: return "Diminished 7th"
        default: return "—"
        }
    }

    static func clampDegree(_ degree: Int) -> Int { Swift.max(1, Swift.min(7, degree)) }

    @inline(__always)
    static func semitones(_ n: Float) -> Float { powf(2, n / 12) }
}

/// A fully specified chord: which scale degree, major or minor, which voicing, which octave.
public struct ChordSpec: Equatable, Sendable {
    public var degree: Int        // 1...7
    public var isMajor: Bool
    public var quality: Int       // 1...4
    public var octaveShift: Int   // -2...2

    public init(degree: Int, isMajor: Bool, quality: Int, octaveShift: Int = 0) {
        self.degree = Music.clampDegree(degree)
        self.isMajor = isMajor
        self.quality = Swift.max(1, Swift.min(4, quality))
        self.octaveShift = Swift.max(-2, Swift.min(2, octaveShift))
    }

    /// The four frequencies of the chord voicing.
    ///
    /// Quality 1: open triad (root, fifth, octave, tenth)
    /// Quality 2: first inversion (third in the bass)
    /// Quality 3: major 7th (major) / minor 7th (minor)
    /// Quality 4: dominant 7th (major) / diminished 7th (minor)
    public func frequencies(key: MusicalKey) -> [Float] {
        let root = key.rootHz * Music.semitones(Float(Music.degreeSemitones[degree - 1]))
        let third = root * Music.semitones(isMajor ? 4 : 3)
        let fifth = root * Music.semitones(7)
        var notes: [Float]
        switch quality {
        case 2:
            notes = [third, fifth, root * 2, third * 2]
        case 3:
            notes = [root, third, fifth, root * Music.semitones(isMajor ? 11 : 10)]
        case 4:
            if isMajor {
                notes = [root, third, fifth, root * Music.semitones(10)]
            } else {
                notes = [root, third, root * Music.semitones(6), root * Music.semitones(9)]
            }
        default:
            notes = [root, fifth, root * 2, third * 2]
        }
        if octaveShift != 0 {
            let factor = powf(2, Float(octaveShift))
            notes = notes.map { $0 * factor }
        }
        return notes
    }

    /// Chord symbol, e.g. "C", "Am", "G7", "Fmaj7", "C/E", "B°7".
    public func name(key: MusicalKey) -> String {
        let rootPC = key.rawValue + Music.degreeSemitones[degree - 1]
        let root = Music.noteName(pitchClass: rootPC, flats: key.prefersFlats)
        let minor = isMajor ? "" : "m"
        switch quality {
        case 2:
            let bass = Music.noteName(pitchClass: rootPC + (isMajor ? 4 : 3), flats: key.prefersFlats)
            return "\(root)\(minor)/\(bass)"
        case 3:
            return isMajor ? "\(root)maj7" : "\(root)m7"
        case 4:
            return isMajor ? "\(root)7" : "\(root)°7"
        default:
            return "\(root)\(minor)"
        }
    }

    public var roman: String { Music.roman(degree: degree, isMajor: isMajor) }
    public var qualityName: String { Music.qualityName(quality, isMajor: isMajor) }
}
