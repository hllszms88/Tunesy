import XCTest
@testable import GestureCore

final class MusicTheoryTests: XCTestCase {
    func testKeyRoots() {
        XCTAssertEqual(MusicalKey.c.rootHz, 261.63, accuracy: 0.05)
        XCTAssertEqual(MusicalKey.a.rootHz, 220.0, accuracy: 0.05)
        XCTAssertEqual(MusicalKey.g.rootHz, 196.0, accuracy: 0.05)
    }

    func testMajorTriadVoicing() {
        let chord = ChordSpec(degree: 1, isMajor: true, quality: 1)
        let f = chord.frequencies(key: .a)
        XCTAssertEqual(f.count, 4)
        XCTAssertEqual(f[0], 220, accuracy: 0.1)           // root
        XCTAssertEqual(f[1], 329.63, accuracy: 0.2)        // fifth
        XCTAssertEqual(f[2], 440, accuracy: 0.2)           // octave
        XCTAssertEqual(f[3], 554.37, accuracy: 0.3)        // major tenth
    }

    func testMinorThirdAndOctaveDrop() {
        let chord = ChordSpec(degree: 6, isMajor: false, quality: 3, octaveShift: -1)
        let f = chord.frequencies(key: .c)
        // Degree VI of C is A (440 Hz), one octave down = 220.
        XCTAssertEqual(f[0], 220, accuracy: 0.2)
        XCTAssertEqual(f[1], 261.63, accuracy: 0.2)        // minor third = C
    }

    func testSeventhDegreeSitsBelowRoot() {
        let f = ChordSpec(degree: 7, isMajor: true, quality: 1).frequencies(key: .c)
        XCTAssertEqual(f[0], 246.94, accuracy: 0.2)        // B below middle C
    }

    func testChordNames() {
        XCTAssertEqual(ChordSpec(degree: 1, isMajor: true, quality: 1).name(key: .c), "C")
        XCTAssertEqual(ChordSpec(degree: 6, isMajor: false, quality: 1).name(key: .c), "Am")
        XCTAssertEqual(ChordSpec(degree: 5, isMajor: true, quality: 4).name(key: .c), "G7")
        XCTAssertEqual(ChordSpec(degree: 4, isMajor: true, quality: 3).name(key: .c), "Fmaj7")
        XCTAssertEqual(ChordSpec(degree: 1, isMajor: true, quality: 2).name(key: .c), "C/E")
        XCTAssertEqual(ChordSpec(degree: 6, isMajor: false, quality: 1).roman, "vi")
    }
}

final class GestureReaderTests: XCTestCase {
    func testFingerCountsMapToDegrees() {
        for degree in 1...7 {
            let fingers = GestureReader.fingers(forDegree: degree)
            XCTAssertEqual(GestureReader.degree(for: fingers), degree, "degree \(degree)")
        }
        XCTAssertNil(GestureReader.degree(for: FingerState()))
    }

    func testReadsSyntheticFingers() {
        for degree in 1...7 {
            let wanted = GestureReader.fingers(forDegree: degree)
            let hand = SyntheticHand.make(wristX: 0.3, wristY: 0.6, fingers: wanted)
            let reading = GestureReader.read(hand, aspect: 0.5625)
            XCTAssertEqual(reading.fingers, wanted, "degree \(degree)")
        }
        let fist = SyntheticHand.make(wristX: 0.3, wristY: 0.6, fingers: FingerState())
        XCTAssertEqual(GestureReader.read(fist, aspect: 0.5625).fingers, FingerState())
    }

    func testFingersSurviveLean() {
        let wanted = FingerState(index: true, middle: true)
        for lean: Float in [-30, -15, 15, 30] {
            let hand = SyntheticHand.make(wristX: 0.5, wristY: 0.6, fingers: wanted, leanDegrees: lean)
            let reading = GestureReader.read(hand, aspect: 0.5625)
            XCTAssertEqual(reading.fingers, wanted, "lean \(lean)")
            XCTAssertEqual(reading.leanDegrees, lean, accuracy: 4)
        }
    }

    func testHeight() {
        let high = SyntheticHand.make(wristX: 0.5, wristY: 0.05, fingers: FingerState(index: true))
        let low = SyntheticHand.make(wristX: 0.5, wristY: 0.95, fingers: FingerState(index: true))
        XCTAssertEqual(GestureReader.read(high, aspect: 0.5625).height, 1, accuracy: 0.01)
        XCTAssertEqual(GestureReader.read(low, aspect: 0.5625).height, 0, accuracy: 0.01)
    }
}

final class InstrumentEngineTests: XCTestCase {
    /// Feeds the same frame for a while at 30 fps and returns the last state.
    private func run(_ engine: inout InstrumentEngine, from start: Double, seconds: Double,
                     lessonMode: Bool = false, _ make: (Double) -> HandFrame) -> InstrumentState {
        var state = InstrumentState()
        var t = start
        while t < start + seconds {
            state = engine.process(make(t), lessonMode: lessonMode)
            t += 1.0 / 30.0
        }
        return state
    }

    func testChordNeedsBothHands() {
        var engine = InstrumentEngine()
        let state = run(&engine, from: 0, seconds: 0.5) { t in
            SyntheticHand.frame(time: t, chord: FingerState(index: true), expression: nil)
        }
        XCTAssertEqual(state.gesture?.degree, 1)
        XCTAssertTrue(state.frequencies.isEmpty)
        XCTAssertFalse(state.isSounding)
    }

    func testPlaysMajorTriad() {
        var engine = InstrumentEngine()
        let state = run(&engine, from: 0, seconds: 0.5) { t in
            SyntheticHand.frame(time: t, chord: GestureReader.fingers(forDegree: 4),
                                expression: FingerState(index: true), expressionHeight: 0.8)
        }
        XCTAssertEqual(state.chord, ChordSpec(degree: 4, isMajor: true, quality: 1))
        XCTAssertEqual(state.frequencies.count, 4)
        XCTAssertEqual(state.volume, 0.8, accuracy: 0.05)
        XCTAssertTrue(state.isSounding)
    }

    func testLeanGivesMinorAndThumbDropsOctave() {
        var engine = InstrumentEngine()
        let state = run(&engine, from: 0, seconds: 0.5) { t in
            SyntheticHand.frame(time: t, chord: GestureReader.fingers(forDegree: 6), chordLean: 25,
                                expression: FingerState(thumb: true, index: true, middle: true, ring: true))
        }
        XCTAssertEqual(state.chord, ChordSpec(degree: 6, isMajor: false, quality: 3, octaveShift: -1))
    }

    func testFistOnExpressionHandIsSilent() {
        var engine = InstrumentEngine()
        let state = run(&engine, from: 0, seconds: 0.5) { t in
            SyntheticHand.frame(time: t, chord: FingerState(index: true), expression: FingerState())
        }
        XCTAssertEqual(state.gesture?.quality, 0)
        XCTAssertFalse(state.isSounding)
    }

    func testGestureIsDebounced() {
        var engine = InstrumentEngine()
        _ = run(&engine, from: 0, seconds: 0.5) { t in
            SyntheticHand.frame(time: t, chord: GestureReader.fingers(forDegree: 1),
                                expression: FingerState(index: true))
        }
        // One stray frame of a different shape must not change the chord.
        let stray = engine.process(SyntheticHand.frame(
            time: 0.52, chord: GestureReader.fingers(forDegree: 3), expression: FingerState(index: true)))
        XCTAssertEqual(stray.gesture?.degree, 1)
        // Held long enough, it does.
        let changed = run(&engine, from: 0.55, seconds: 0.3) { t in
            SyntheticHand.frame(time: t, chord: GestureReader.fingers(forDegree: 3),
                                expression: FingerState(index: true))
        }
        XCTAssertEqual(changed.gesture?.degree, 3)
    }

    func testSoundStopsWhenHandsLeave() {
        var engine = InstrumentEngine()
        _ = run(&engine, from: 0, seconds: 0.5) { t in
            SyntheticHand.frame(time: t, chord: FingerState(index: true), expression: FingerState(index: true))
        }
        let gone = run(&engine, from: 0.5, seconds: 0.5) { t in
            SyntheticHand.frame(time: t, chord: nil, expression: nil)
        }
        XCTAssertNil(gone.gesture)
        XCTAssertFalse(gone.isSounding)
    }

    func testLocksAreIgnoredInLessons() {
        var engine = InstrumentEngine()
        engine.config.fixedQuality = 4
        engine.config.modeControl = .minor
        let free = run(&engine, from: 0, seconds: 0.5) { t in
            SyntheticHand.frame(time: t, chord: FingerState(index: true), expression: FingerState(index: true))
        }
        XCTAssertEqual(free.chord, ChordSpec(degree: 1, isMajor: false, quality: 4))
        engine.reset()
        let lesson = run(&engine, from: 1, seconds: 0.5, lessonMode: true) { t in
            SyntheticHand.frame(time: t, chord: FingerState(index: true), expression: FingerState(index: true))
        }
        XCTAssertEqual(lesson.chord, ChordSpec(degree: 1, isMajor: true, quality: 1))
    }

    func testTheremin() {
        var engine = InstrumentEngine()
        engine.config.mode = .theremin
        let state = run(&engine, from: 0, seconds: 0.5) { t in
            SyntheticHand.frame(time: t, chord: FingerState(index: true),
                                expression: FingerState(index: true), expressionHeight: 1)
        }
        XCTAssertEqual(state.pitchHz, 1200, accuracy: 30)
        XCTAssertGreaterThan(state.thereminGain, 0)
        XCTAssertTrue(state.frequencies.isEmpty)
    }
}

final class LessonEngineTests: XCTestCase {
    private func state(for event: ChordEvent, sounding: Bool = true) -> InstrumentState {
        var s = InstrumentState()
        s.gesture = ChordGesture(degree: event.degree, isMajor: !event.minor,
                                 quality: event.quality, thumbOut: event.low)
        if sounding {
            s.frequencies = event.spec.frequencies(key: .c)
            s.volume = 0.7
        }
        return s
    }

    func testBuiltInSongsArePlayable() {
        XCTAssertFalse(SongLibrary.builtIn.isEmpty)
        for song in SongLibrary.builtIn {
            XCTAssertTrue(song.isPlayable, song.id)
        }
        XCTAssertEqual(Set(SongLibrary.builtIn.map { $0.id }).count, SongLibrary.builtIn.count)
    }

    func testSongsRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(SongLibrary.builtIn)
        XCTAssertEqual(SongLibrary.decode(data), SongLibrary.builtIn)
    }

    func testHoldingCorrectShapeAdvances() {
        let song = SongLibrary.builtIn[0]
        var lesson = LessonEngine(song: song, holdDuration: 0.5)
        let first = lesson.target!
        XCTAssertTrue(lesson.update(state(for: first), time: 0))
        XCTAssertEqual(lesson.snapshot().eventIndex, 0)
        XCTAssertTrue(lesson.update(state(for: first), time: 0.3))
        XCTAssertEqual(lesson.snapshot().holdProgress, 0.6, accuracy: 0.01)
        _ = lesson.update(state(for: first), time: 0.55)
        let snap = lesson.snapshot()
        XCTAssertEqual(snap.eventIndex, 1)
        XCTAssertEqual(snap.matched, 1)
        XCTAssertEqual(snap.pulse, 1)
    }

    func testWrongShapeDoesNotAdvanceAndReportsFlags() {
        var lesson = LessonEngine(song: SongLibrary.builtIn[0], holdDuration: 0.5)
        let target = lesson.target!
        var wrong = target
        wrong.degree = target.degree == 1 ? 2 : 1
        XCTAssertFalse(lesson.update(state(for: wrong), time: 0))
        XCTAssertFalse(lesson.update(state(for: wrong), time: 2))
        let snap = lesson.snapshot()
        XCTAssertEqual(snap.eventIndex, 0)
        XCTAssertEqual(snap.flags, MatchFlags(degree: false, mode: true, quality: true, octave: true))
    }

    func testInterruptedHoldStartsOver() {
        var lesson = LessonEngine(song: SongLibrary.builtIn[0], holdDuration: 0.5)
        let target = lesson.target!
        _ = lesson.update(state(for: target), time: 0)
        _ = lesson.update(InstrumentState(), time: 0.3)
        _ = lesson.update(state(for: target), time: 0.4)
        _ = lesson.update(state(for: target), time: 0.7)
        XCTAssertEqual(lesson.snapshot().eventIndex, 0)
        _ = lesson.update(state(for: target), time: 0.95)
        XCTAssertEqual(lesson.snapshot().eventIndex, 1)
    }

    func testSkipRepeatRestartAndCompletion() {
        let song = SongLibrary.builtIn[0]
        var lesson = LessonEngine(song: song, holdDuration: 0.1)
        lesson.skip()
        XCTAssertEqual(lesson.snapshot().skipped, 1)
        lesson.repeatSection()
        XCTAssertEqual(lesson.snapshot().skipped, 0)
        XCTAssertEqual(lesson.snapshot().eventIndex, 0)

        var t = 0.0
        var guardCounter = 0
        while let target = lesson.target, guardCounter < 1000 {
            _ = lesson.update(state(for: target), time: t)
            t += 0.05
            guardCounter += 1
        }
        let done = lesson.snapshot()
        XCTAssertEqual(done.phase, .complete)
        XCTAssertEqual(done.matched, song.chordCount)
        XCTAssertEqual(done.fractionDone, 1, accuracy: 0.001)

        lesson.restart()
        XCTAssertEqual(lesson.snapshot().phase, .playing)
        XCTAssertEqual(lesson.snapshot().matched, 0)
    }
}

final class SynthTests: XCTestCase {
    private func render(_ dsp: inout SynthDSP, _ params: SynthParams, frames: Int) -> [Float] {
        var buffer = [Float](repeating: 0, count: frames)
        buffer.withUnsafeMutableBufferPointer { pointer in
            var offset = 0
            while offset < frames {
                let n = Swift.min(256, frames - offset)
                dsp.render(into: pointer.baseAddress! + offset, count: n, params: params)
                offset += n
            }
        }
        return buffer
    }

    func testSilentByDefault() {
        var dsp = SynthDSP()
        let out = render(&dsp, SynthParams(), frames: 4800)
        XCTAssertEqual(out.map { abs($0) }.max() ?? 1, 0, accuracy: 0.0001)
    }

    func testChordIsAudibleBoundedAndFinite() {
        var dsp = SynthDSP()
        var params = SynthParams()
        params.setVoice(SynthVoice.named("grit"))
        params.setChord(ChordSpec(degree: 1, isMajor: true, quality: 1).frequencies(key: .c), volume: 1)
        params.tone = 1
        params.masterGain = 1
        let out = render(&dsp, params, frames: 48_000)
        let peak = out.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertLessThanOrEqual(peak, 1.0)
        XCTAssertTrue(out.allSatisfy { $0.isFinite })
    }

    func testReleaseFadesToSilenceWithoutAClick() {
        var dsp = SynthDSP()
        var params = SynthParams()
        params.setChord([220, 330, 440, 554], volume: 1)
        _ = render(&dsp, params, frames: 24_000)
        params.setChord([], volume: 0)
        let tail = render(&dsp, params, frames: 48_000)
        // No instant drop to zero…
        XCTAssertGreaterThan(abs(tail[0]) + abs(tail[1]) + abs(tail[2]) + abs(tail[3]), 0)
        // …and silence one second later.
        let end = tail.suffix(2400).map { abs($0) }.max() ?? 1
        XCTAssertLessThan(end, 0.001)
    }

    func testThereminPitch() {
        var dsp = SynthDSP()
        var params = SynthParams()
        params.mode = .theremin
        params.thereminHz = 440
        params.thereminGain = 0.5
        params.filterBase = 8000
        _ = render(&dsp, params, frames: 48_000)       // let the glide settle
        let out = render(&dsp, params, frames: 48_000)
        var crossings = 0
        for i in 1..<out.count where out[i - 1] <= 0 && out[i] > 0 {
            crossings += 1
        }
        XCTAssertEqual(Double(crossings), 440, accuracy: 3)
    }

    func testOneEuroFilterSmoothsNoise() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        var last: Float = 0
        for i in 0..<120 {
            let noisy: Float = 0.5 + (i % 2 == 0 ? 0.05 : -0.05)
            last = filter.filter(noisy, time: Double(i) / 60)
        }
        XCTAssertEqual(last, 0.5, accuracy: 0.02)
    }
}

final class ChordTransitionTests: XCTestCase {
    private let horns = GestureReader.fingers(forDegree: 6)
    private let one = GestureReader.fingers(forDegree: 1)
    private let three = GestureReader.fingers(forDegree: 3)
    private let rightHand = FingerState(index: true)
    private let dt = 1.0 / 30.0

    private func play(_ engine: inout InstrumentEngine, at time: Double,
                      _ fingers: FingerState, lean: Float) -> InstrumentState {
        return engine.process(SyntheticHand.frame(time: time, chord: fingers, chordLean: lean,
                                                  expression: rightHand))
    }

    /// Bm → D: the fingers change first and the wrist straightens a moment later.
    /// D minor must never sound in between.
    func testMinorToMajorDoesNotFlashMinor() {
        var engine = InstrumentEngine()
        engine.config.key = .d
        var names: [String] = []
        var t = 0.0
        while t < 0.6 {
            names.append(play(&engine, at: t, horns, lean: 25).chord?.name(key: .d) ?? "-")
            t += dt
        }
        XCTAssertEqual(names.last, "Bm")

        let change = t
        while t < change + 0.1 {
            names.append(play(&engine, at: t, one, lean: 25).chord?.name(key: .d) ?? "-")
            t += dt
        }
        let turn = t
        while t < turn + 0.2 {
            let lean = 25 - 25 * Float((t - turn) / 0.2)
            names.append(play(&engine, at: t, one, lean: lean).chord?.name(key: .d) ?? "-")
            t += dt
        }
        while t < turn + 0.8 {
            names.append(play(&engine, at: t, one, lean: 0).chord?.name(key: .d) ?? "-")
            t += dt
        }
        XCTAssertFalse(names.contains("Dm"), "\(names)")
        XCTAssertEqual(names.last, "D")
    }

    /// Bm → F♯m with the hand kept leaning: a deliberate minor-to-minor change still works.
    func testMinorToMinorStillWorks() {
        var engine = InstrumentEngine()
        engine.config.key = .d
        var t = 0.0
        var last = InstrumentState()
        while t < 0.6 {
            last = play(&engine, at: t, horns, lean: 25)
            t += dt
        }
        let change = t
        while t < change + 0.6 {
            last = play(&engine, at: t, three, lean: 25)
            t += dt
        }
        XCTAssertEqual(last.chord?.name(key: .d), "F♯m")
    }

    /// Slowly leaning a held chord turns it minor.
    func testSlowLeanMakesMinor() {
        var engine = InstrumentEngine()
        engine.config.key = .d
        var t = 0.0
        var last = InstrumentState()
        while t < 1.2 {
            let lean = Float(min(1, t / 0.6)) * 25
            last = play(&engine, at: t, one, lean: lean)
            t += dt
        }
        XCTAssertEqual(last.chord?.name(key: .d), "Dm")
    }

    /// A steady minor chord with tracking jitter (±3°) must not flicker to major.
    func testJitterDoesNotDropMinor() {
        var engine = InstrumentEngine()
        var seed: UInt32 = 12_345
        var t = 0.0
        var majorFrames = 0
        while t < 3.0 {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = (Float(seed >> 8) / Float(1 << 24) - 0.5) * 6
            let state = play(&engine, at: t, horns, lean: 24 + noise)
            if t > 0.5, let chord = state.chord, chord.isMajor {
                majorFrames += 1
            }
            t += dt
        }
        XCTAssertEqual(majorFrames, 0)
    }
}
