import Foundation

/// Which parts of the target chord the player currently has right.
public struct MatchFlags: Equatable, Sendable {
    public var degree: Bool
    public var mode: Bool
    public var quality: Bool
    public var octave: Bool

    public init(degree: Bool, mode: Bool, quality: Bool, octave: Bool) {
        self.degree = degree
        self.mode = mode
        self.quality = quality
        self.octave = octave
    }

    public var all: Bool { degree && mode && quality && octave }

    /// Compares the player's gesture with a lesson chord.
    public static func compare(_ gesture: ChordGesture, to target: ChordEvent) -> MatchFlags {
        return MatchFlags(
            degree: gesture.degree == target.degree,
            mode: gesture.isMajor == !target.minor,
            quality: gesture.quality == target.quality,
            octave: gesture.thumbOut == target.low
        )
    }
}

public enum LessonPhase: Equatable, Sendable {
    case playing, complete
}

/// A read-only picture of the lesson for the UI.
public struct LessonSnapshot: Equatable, Sendable {
    public var songID: String
    public var phase: LessonPhase
    public var sectionIndex: Int
    public var sectionCount: Int
    public var sectionName: String
    public var eventIndex: Int
    public var eventCount: Int
    public var target: ChordEvent?
    public var nextTarget: ChordEvent?
    /// nil while no chord-hand gesture is visible.
    public var flags: MatchFlags?
    /// 0...1 — how long the correct shape has been held.
    public var holdProgress: Float
    public var matched: Int
    public var skipped: Int
    public var total: Int
    /// Goes up by one every time a chord is completed; lets the UI animate the "click".
    public var pulse: Int

    /// Share of the song already dealt with, 0...1.
    public var fractionDone: Float {
        return total > 0 ? Float(matched + skipped) / Float(total) : 0
    }
}

/// Steps through a song one chord at a time. A chord is completed when the player holds
/// the exact shape for `holdDuration`. Pure logic — fed by `InstrumentState`.
public struct LessonEngine: Sendable {
    private enum Outcome: Sendable { case matched, skipped }

    public let song: Song
    public var holdDuration: Double

    private var sectionIndex = 0
    private var eventIndex = 0
    private var phase: LessonPhase = .playing
    private var outcomes: [[Outcome?]]
    private var holdStart: Double?
    private var holdProgress: Float = 0
    private var flags: MatchFlags?
    private var pulse = 0

    public init(song: Song, holdDuration: Double = 0.55) {
        self.song = song
        self.holdDuration = holdDuration
        self.outcomes = song.sections.map { [Outcome?](repeating: nil, count: $0.events.count) }
        if !song.isPlayable { phase = .complete }
    }

    public var target: ChordEvent? {
        guard phase == .playing else { return nil }
        return song.sections[sectionIndex].events[eventIndex]
    }

    /// Feeds one frame. Returns true when the player's gesture matches the target,
    /// which is when the instrument should sound.
    public mutating func update(_ state: InstrumentState, time: Double) -> Bool {
        guard let target = target, let gesture = state.gesture else {
            flags = nil
            holdStart = nil
            holdProgress = 0
            return false
        }
        let current = MatchFlags.compare(gesture, to: target)
        flags = current

        guard current.all, state.isSounding else {
            holdStart = nil
            holdProgress = 0
            return current.all
        }

        let start = holdStart ?? time
        holdStart = start
        let progress = holdDuration > 0 ? (time - start) / holdDuration : 1
        holdProgress = Float(Swift.min(1, Swift.max(0, progress)))
        if progress >= 1 {
            outcomes[sectionIndex][eventIndex] = .matched
            pulse += 1
            advance()
        }
        return true
    }

    public mutating func skip() {
        guard phase == .playing else { return }
        outcomes[sectionIndex][eventIndex] = .skipped
        advance()
    }

    /// Goes back to the start of the current section and forgets its results.
    public mutating func repeatSection() {
        guard !song.sections.isEmpty, song.isPlayable else { return }
        outcomes[sectionIndex] = [Outcome?](repeating: nil, count: song.sections[sectionIndex].events.count)
        eventIndex = 0
        phase = .playing
        clearHold()
    }

    public mutating func restart() {
        guard song.isPlayable else { return }
        outcomes = song.sections.map { [Outcome?](repeating: nil, count: $0.events.count) }
        sectionIndex = 0
        eventIndex = 0
        phase = .playing
        clearHold()
    }

    public func snapshot() -> LessonSnapshot {
        var matched = 0
        var skipped = 0
        for section in outcomes {
            for outcome in section {
                if outcome == .matched { matched += 1 }
                if outcome == .skipped { skipped += 1 }
            }
        }
        let hasSections = !song.sections.isEmpty
        let section = hasSections ? song.sections[sectionIndex] : nil
        return LessonSnapshot(
            songID: song.id,
            phase: phase,
            sectionIndex: sectionIndex,
            sectionCount: song.sections.count,
            sectionName: section?.name ?? "",
            eventIndex: eventIndex,
            eventCount: section?.events.count ?? 0,
            target: target,
            nextTarget: peekNext(),
            flags: flags,
            holdProgress: holdProgress,
            matched: matched,
            skipped: skipped,
            total: song.chordCount,
            pulse: pulse
        )
    }

    private mutating func clearHold() {
        holdStart = nil
        holdProgress = 0
        flags = nil
    }

    private func peekNext() -> ChordEvent? {
        guard phase == .playing else { return nil }
        let events = song.sections[sectionIndex].events
        if eventIndex + 1 < events.count { return events[eventIndex + 1] }
        if sectionIndex + 1 < song.sections.count { return song.sections[sectionIndex + 1].events.first }
        return nil
    }

    private mutating func advance() {
        clearHold()
        if eventIndex + 1 < song.sections[sectionIndex].events.count {
            eventIndex += 1
        } else if sectionIndex + 1 < song.sections.count {
            sectionIndex += 1
            eventIndex = 0
        } else {
            phase = .complete
        }
    }
}
