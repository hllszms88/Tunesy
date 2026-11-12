import Foundation

/// One chord to play in a lesson.
public struct ChordEvent: Equatable, Codable, Sendable {
    /// Scale degree 1...7.
    public var degree: Int
    public var minor: Bool
    /// Chord quality 1...4 (see `ChordSpec`).
    public var quality: Int
    /// One octave down (expression-hand thumb out).
    public var low: Bool
    /// Optional words sung on this chord.
    public var lyric: String?

    public init(degree: Int, minor: Bool = false, quality: Int = 1, low: Bool = false, lyric: String? = nil) {
        self.degree = degree
        self.minor = minor
        self.quality = quality
        self.low = low
        self.lyric = lyric
    }

    public var spec: ChordSpec {
        return ChordSpec(degree: degree, isMajor: !minor, quality: quality, octaveShift: low ? -1 : 0)
    }
}

public struct SongSection: Equatable, Codable, Sendable {
    public var name: String
    public var events: [ChordEvent]

    public init(name: String, events: [ChordEvent]) {
        self.name = name
        self.events = events
    }
}

/// A lesson: a chord chart split into short sections. Songs are plain data and can be
/// decoded from JSON, so more can be added without touching code.
public struct Song: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var credit: String
    public var key: MusicalKey
    public var bpm: Int
    /// 1 = first steps, 2 = adds minor chords, 3 = adds sevenths, inversions, low octave.
    public var level: Int
    public var blurb: String
    public var sections: [SongSection]

    public init(id: String, title: String, credit: String, key: MusicalKey, bpm: Int,
                level: Int, blurb: String, sections: [SongSection]) {
        self.id = id
        self.title = title
        self.credit = credit
        self.key = key
        self.bpm = bpm
        self.level = level
        self.blurb = blurb
        self.sections = sections
    }

    public var chordCount: Int {
        return sections.reduce(0) { $0 + $1.events.count }
    }

    /// True when every chord can actually be played and every section has something in it.
    public var isPlayable: Bool {
        guard !sections.isEmpty else { return false }
        for section in sections {
            if section.events.isEmpty { return false }
            for event in section.events {
                if !(1...7).contains(event.degree) || !(1...4).contains(event.quality) { return false }
            }
        }
        return true
    }
}

// Shorthand used only to keep the built-in charts readable.
private func M(_ degree: Int, _ lyric: String? = nil, q: Int = 1, low: Bool = false) -> ChordEvent {
    return ChordEvent(degree: degree, minor: false, quality: q, low: low, lyric: lyric)
}

private func m(_ degree: Int, _ lyric: String? = nil, q: Int = 1, low: Bool = false) -> ChordEvent {
    return ChordEvent(degree: degree, minor: true, quality: q, low: low, lyric: lyric)
}

/// The built-in lessons. Melodies are traditional / public domain or written for this app;
/// the chord charts are original, simple arrangements.
public enum SongLibrary {
    public static let builtIn: [Song] = [
        Song(
            id: "first-chords", title: "First Chords", credit: "Warm-up · written for Handtone",
            key: .c, bpm: 80, level: 1,
            blurb: "Three chords, one finger at a time. Start here.",
            sections: [
                SongSection(name: "Meet I, IV and V", events: [M(1), M(4), M(5), M(1)]),
                SongSection(name: "Back and forth", events: [M(1), M(5), M(4), M(1), M(4), M(5), M(1)]),
                SongSection(name: "Tilt for minor", events: [M(1), m(6), M(4), M(5), M(1)])
            ]),
        Song(
            id: "twinkle", title: "Twinkle, Twinkle, Little Star", credit: "Traditional",
            key: .c, bpm: 90, level: 1,
            blurb: "The classic. Only I, IV and V.",
            sections: [
                SongSection(name: "Verse", events: [
                    M(1, "Twinkle, twinkle"), M(4, "little"), M(1, "star"),
                    M(4, "How I"), M(1, "wonder"), M(5, "what you"), M(1, "are")
                ]),
                SongSection(name: "Middle", events: [
                    M(1, "Up a-"), M(4, "bove the"), M(1, "world so"), M(5, "high"),
                    M(1, "Like a"), M(4, "diamond"), M(1, "in the"), M(5, "sky")
                ]),
                SongSection(name: "Verse again", events: [
                    M(1, "Twinkle, twinkle"), M(4, "little"), M(1, "star"),
                    M(4, "How I"), M(1, "wonder"), M(5, "what you"), M(1, "are")
                ])
            ]),
        Song(
            id: "saints", title: "When the Saints Go Marching In", credit: "Traditional",
            key: .f, bpm: 100, level: 1,
            blurb: "A bright march, and your first seventh chord.",
            sections: [
                SongSection(name: "First line", events: [
                    M(1, "Oh when the saints"), M(1, "go marching in"),
                    M(1, "Oh when the saints go"), M(5, "marching in")
                ]),
                SongSection(name: "Second line", events: [
                    M(1, "Lord, I want to"), M(1, "be in that", q: 4), M(4, "number"),
                    M(1, "When the saints go"), M(5, "marching"), M(1, "in")
                ])
            ]),
        Song(
            id: "ode-to-joy", title: "Ode to Joy", credit: "Ludwig van Beethoven",
            key: .d, bpm: 96, level: 2,
            blurb: "Beethoven's theme, with one minor chord.",
            sections: [
                SongSection(name: "Theme", events: [M(1), M(1), M(5), M(1), M(1), M(1), M(5), M(1)]),
                SongSection(name: "Bridge", events: [M(5), M(1), M(5), m(6), M(2, q: 4), M(5)]),
                SongSection(name: "Theme returns", events: [M(1), M(1), M(4), M(1), M(1), M(5), M(1)])
            ]),
        Song(
            id: "amazing-grace", title: "Amazing Grace", credit: "Traditional",
            key: .g, bpm: 72, level: 2,
            blurb: "Slow and open. Practise the dominant seventh.",
            sections: [
                SongSection(name: "Line one", events: [
                    M(1, "Amazing"), M(1, "grace, how", q: 4), M(4, "sweet the"), M(1, "sound")
                ]),
                SongSection(name: "Line two", events: [
                    M(1, "That saved a"), m(6, "wretch like"), M(5, "me"), M(5, q: 4)
                ]),
                SongSection(name: "Line three", events: [
                    M(1, "I once was"), M(1, "lost, but", q: 4), M(4, "now am"), M(1, "found")
                ]),
                SongSection(name: "Line four", events: [
                    m(6, "Was blind, but"), M(5, "now I", q: 4), M(1, "see")
                ])
            ]),
        Song(
            id: "canon", title: "Canon Progression", credit: "After Johann Pachelbel",
            key: .d, bpm: 76, level: 2,
            blurb: "Eight chords that never get old.",
            sections: [
                SongSection(name: "The progression", events: [
                    M(1), M(5), m(6), m(3), M(4), M(1), M(4), M(5)
                ]),
                SongSection(name: "With inversions", events: [
                    M(1), M(5, q: 2), m(6), m(3, q: 2), M(4), M(1, q: 2), M(4), M(5, q: 4)
                ])
            ]),
        Song(
            id: "midnight-walk", title: "Midnight Walk", credit: "Written for Handtone",
            key: .a, bpm: 84, level: 3,
            blurb: "Sevenths, inversions and the low octave together.",
            sections: [
                SongSection(name: "Low and slow", events: [
                    m(6, low: true), M(4, low: true), M(1), M(5)
                ]),
                SongSection(name: "Add colour", events: [
                    m(6, q: 3), M(4, q: 3), M(1, q: 2), M(5, q: 4)
                ]),
                SongSection(name: "Home", events: [
                    m(2, q: 3), M(5, q: 4), M(1, q: 3), m(6, low: true), M(4), M(5, q: 4), M(1)
                ])
            ])
    ]

    /// Decodes extra songs from JSON (an array of `Song`). Unplayable entries are dropped.
    public static func decode(_ data: Data) -> [Song] {
        guard let songs = try? JSONDecoder().decode([Song].self, from: data) else { return [] }
        return songs.filter { $0.isPlayable }
    }
}
