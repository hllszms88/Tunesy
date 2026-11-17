import Foundation

public enum InstrumentMode: String, Codable, Sendable, CaseIterable {
    /// Left hand picks the chord, right hand shapes it.
    case chords
    /// Right hand height = pitch, left hand height = volume.
    case theremin
}

/// How major/minor is chosen.
public enum ModeControl: String, Codable, Sendable, CaseIterable {
    case tilt, major, minor
}

public struct InstrumentConfig: Equatable, Sendable {
    public var mode: InstrumentMode = .chords
    public var key: MusicalKey = .c
    public var modeControl: ModeControl = .tilt
    /// 1...4 locks the chord quality; nil lets the expression hand's fingers choose.
    public var fixedQuality: Int? = nil
    /// -2...2 locks the octave; nil lets the expression hand's thumb drop one octave.
    public var fixedOctave: Int? = nil

    public var tuning = GestureTuning()
    /// The chord hand must lean past this to switch to minor…
    public var minorOnDegrees: Float = 14
    /// …and come back under this to return to major.
    public var minorOffDegrees: Float = 8
    /// Expression-hand lean below this leaves the tone untouched.
    public var toneDeadZoneDegrees: Float = 8
    /// Expression-hand lean that gives a full tone sweep.
    public var toneFullScaleDegrees: Float = 40

    /// A gesture must hold this long before it changes the chord.
    public var stableTime: Double = 0.10
    /// When the fingers change while the hand is still leaning from the previous minor chord,
    /// the new chord must stay minor this long before it sounds. Gives the wrist time to
    /// straighten, so Bm → D does not flash Dm on the way.
    public var carriedMinorTime: Double = 0.30
    /// Straightening the chord hand faster than this (degrees per second) switches back
    /// to major at once, before the lean drops under `minorOffDegrees`.
    public var minorReturnSpeed: Float = 60
    /// The chord hand may vanish this long before the chord is dropped.
    public var dropoutTolerance: Double = 0.12
    /// The expression hand may vanish this long before the sound is cut.
    public var handGrace: Double = 0.15

    public var thereminLowHz: Float = 65
    public var thereminHighHz: Float = 1200

    public init() {}
}

/// The debounced reading of both hands in chord mode.
public struct ChordGesture: Equatable, Sendable {
    public var degree: Int
    public var isMajor: Bool
    /// 0 when the expression hand shows no fingers (silent), otherwise 1...4.
    public var quality: Int
    public var thumbOut: Bool

    public init(degree: Int, isMajor: Bool, quality: Int, thumbOut: Bool) {
        self.degree = degree
        self.isMajor = isMajor
        self.quality = quality
        self.thumbOut = thumbOut
    }
}

/// What the instrument is doing right now. Produced once per camera frame.
public struct InstrumentState: Equatable, Sendable {
    public var mode: InstrumentMode = .chords
    public var gesture: ChordGesture? = nil
    /// The sounding chord, or nil when silent.
    public var chord: ChordSpec? = nil
    public var frequencies: [Float] = []
    public var octaveShift: Int = 0
    /// 0...1
    public var volume: Float = 0
    /// -1 (dark) ... 1 (bright)
    public var tone: Float = 0
    public var pitchHz: Float = 0
    public var thereminGain: Float = 0
    /// Index into the frame's hands of the hand playing each role.
    public var chordHandIndex: Int? = nil
    public var expressionHandIndex: Int? = nil

    public init() {}

    public var isSounding: Bool {
        switch mode {
        case .chords: return !frequencies.isEmpty && volume > 0.001
        case .theremin: return thereminGain > 0.001
        }
    }
}

/// Requires a gesture to stay unchanged briefly before committing it,
/// and bridges very short dropouts. Prevents chord flicker.
struct GestureDebouncer {
    private var committed: ChordGesture?
    private var candidate: ChordGesture?
    private var candidateSince: Double = 0
    private var lastSeen: Double = -1000

    mutating func reset() {
        committed = nil
        candidate = nil
    }

    mutating func update(_ raw: ChordGesture?, time: Double,
                         stableTime: Double, dropoutTolerance: Double) -> ChordGesture? {
        var sample = raw
        if raw != nil {
            lastSeen = time
        } else if time - lastSeen < dropoutTolerance {
            sample = candidate
        }
        if sample != candidate {
            candidate = sample
            candidateSince = time
        }
        if time - candidateSince >= stableTime {
            committed = candidate
        }
        return committed
    }
}

/// Turns hand frames into musical state. Pure logic: no camera, no audio.
public struct InstrumentEngine: Sendable {
    public var config = InstrumentConfig()

    private var debouncer = GestureDebouncer()
    private var minorLatched = false
    /// The chord (scale degree) that was being played when minor was switched on.
    private var latchDegree: Int?
    private var leanFilter = OneEuroFilter(minCutoff: 3.0, beta: 0.05)
    private var lastLean: Float?
    private var lastLeanTime: Double = 0
    /// Smoothed lean speed in degrees per second; negative = straightening toward upright.
    private var leanVelocity: Float = 0

    private var volumeFilter = OneEuroFilter(minCutoff: 2.0, beta: 0.4)
    private var toneFilter = OneEuroFilter(minCutoff: 1.5, beta: 0.3)
    private var secondHeightFilter = OneEuroFilter(minCutoff: 2.0, beta: 0.4)

    private var lastExpression: (height: Float, tone: Float, fingers: FingerState)?
    private var lastExpressionTime: Double = -1000

    private var lastChordWrist: Vec2?
    private var lastExpressionWrist: Vec2?
    private var lastRoleTime: Double = -1000

    public init() {}

    public mutating func reset() {
        debouncer.reset()
        minorLatched = false
        latchDegree = nil
        resetLean()
        volumeFilter.reset()
        toneFilter.reset()
        secondHeightFilter.reset()
        lastExpression = nil
        lastChordWrist = nil
        lastExpressionWrist = nil
    }

    /// - Parameter lessonMode: when true, the quality/mode/octave locks are ignored so a
    ///   lesson can ask for any chord.
    public mutating func process(_ frame: HandFrame, lessonMode: Bool = false) -> InstrumentState {
        let time = frame.time
        let roles = assignRoles(frame)

        var state = InstrumentState()
        state.mode = config.mode
        state.chordHandIndex = roles.chord
        state.expressionHandIndex = roles.expression

        let chordReading = roles.chord.map {
            GestureReader.read(frame.hands[$0], aspect: frame.aspect, tuning: config.tuning)
        }
        let expressionReading = roles.expression.map {
            GestureReader.read(frame.hands[$0], aspect: frame.aspect, tuning: config.tuning)
        }

        // Expression hand: smooth it, and keep its last value through short dropouts.
        var expression: (height: Float, tone: Float, fingers: FingerState)?
        if let reading = expressionReading {
            let height = volumeFilter.filter(reading.height, time: time)
            let tone = toneFilter.filter(mapTone(reading.leanDegrees), time: time)
            expression = (clampValue(height, 0, 1), clampValue(tone, -1, 1), reading.fingers)
            lastExpression = expression
            lastExpressionTime = time
        } else if let last = lastExpression, time - lastExpressionTime < config.handGrace {
            expression = last
        } else {
            lastExpression = nil
            volumeFilter.reset()
            toneFilter.reset()
        }

        switch config.mode {
        case .chords:
            var raw: ChordGesture?
            var carriedMinor = false
            if let reading = chordReading {
                let lean = trackLean(reading.leanDegrees, time: time)
                if let degree = GestureReader.degree(for: reading.fingers) {
                    if minorLatched {
                        if lean < config.minorOffDegrees || leanVelocity < -config.minorReturnSpeed {
                            minorLatched = false
                            latchDegree = nil
                        }
                    } else if lean > config.minorOnDegrees && leanVelocity > -config.minorReturnSpeed / 3 {
                        minorLatched = true
                        latchDegree = degree
                    }
                    let tiltDecides = lessonMode || config.modeControl == .tilt
                    let isMajor: Bool
                    if tiltDecides {
                        isMajor = !minorLatched
                        carriedMinor = minorLatched && latchDegree != degree
                    } else {
                        isMajor = config.modeControl == .major
                    }
                    let lockedQuality = lessonMode ? nil : config.fixedQuality
                    let quality = lockedQuality ?? (expression?.fingers.fingerCount ?? 0)
                    raw = ChordGesture(degree: degree, isMajor: isMajor, quality: quality,
                                       thumbOut: expression?.fingers.thumb ?? false)
                }
            } else {
                resetLean()
            }

            let gesture = debouncer.update(raw, time: time,
                                           stableTime: carriedMinor ? config.carriedMinorTime : config.stableTime,
                                           dropoutTolerance: config.dropoutTolerance)
            if carriedMinor, let raw = raw, gesture == raw {
                // The new minor chord has been held long enough: it is deliberate.
                latchDegree = raw.degree
            }
            state.gesture = gesture
            state.tone = expression?.tone ?? 0

            if let gesture = gesture {
                let lockedOctave = lessonMode ? nil : config.fixedOctave
                state.octaveShift = lockedOctave ?? (gesture.thumbOut ? -1 : 0)
                if let expression = expression, gesture.quality >= 1 {
                    let spec = ChordSpec(degree: gesture.degree, isMajor: gesture.isMajor,
                                         quality: gesture.quality, octaveShift: state.octaveShift)
                    state.chord = spec
                    state.frequencies = spec.frequencies(key: config.key)
                    state.volume = expression.height
                }
            }

        case .theremin:
            debouncer.reset()
            if let expression = expression {
                let ratio = config.thereminHighHz / config.thereminLowHz
                state.pitchHz = config.thereminLowHz * powf(ratio, expression.height)
            }
            if let reading = chordReading {
                let level = clampValue(secondHeightFilter.filter(reading.height, time: time), 0, 1)
                state.volume = level
                if expression != nil && level > 0.02 {
                    state.thereminGain = level * 0.55
                }
            } else {
                secondHeightFilter.reset()
            }
        }
        return state
    }

    /// Smooths the chord hand's lean and keeps a running estimate of how fast it is changing.
    private mutating func trackLean(_ raw: Float, time: Double) -> Float {
        let lean = leanFilter.filter(raw, time: time)
        if let previous = lastLean, time > lastLeanTime {
            let dt = time - lastLeanTime
            let instant = (lean - previous) / Float(dt)
            let blend = Float(1 - exp(-dt / 0.08))
            leanVelocity += (instant - leanVelocity) * blend
        }
        lastLean = lean
        lastLeanTime = time
        return lean
    }

    private mutating func resetLean() {
        leanFilter.reset()
        lastLean = nil
        leanVelocity = 0
    }

    private func mapTone(_ lean: Float) -> Float {
        let magnitude = abs(lean)
        guard magnitude > config.toneDeadZoneDegrees else { return 0 }
        let span = Swift.max(config.toneFullScaleDegrees - config.toneDeadZoneDegrees, 1)
        let amount = clampValue((magnitude - config.toneDeadZoneDegrees) / span, 0, 1)
        return lean < 0 ? -amount : amount
    }

    /// The hand on the player's left plays chords; the one on the right plays expression.
    /// A lone hand keeps the role it had a moment ago, otherwise the half of the frame decides.
    private mutating func assignRoles(_ frame: HandFrame) -> (chord: Int?, expression: Int?) {
        let hands = frame.hands
        if hands.count >= 2 {
            let a = hands[0][.wrist]
            let b = hands[1][.wrist]
            let chordIndex = a.x <= b.x ? 0 : 1
            let expressionIndex = 1 - chordIndex
            lastChordWrist = hands[chordIndex][.wrist]
            lastExpressionWrist = hands[expressionIndex][.wrist]
            lastRoleTime = frame.time
            let chordRole: Int? = chordIndex
            let expressionRole: Int? = expressionIndex
            return (chordRole, expressionRole)
        }
        guard let hand = hands.first else { return (nil, nil) }
        let wrist = hand[.wrist]

        var isChord = wrist.x < 0.5
        if frame.time - lastRoleTime < 0.5 {
            let toChord = lastChordWrist.map { $0.distance(to: wrist) } ?? Float.greatestFiniteMagnitude
            let toExpression = lastExpressionWrist.map { $0.distance(to: wrist) } ?? Float.greatestFiniteMagnitude
            if Swift.min(toChord, toExpression) < 0.25 {
                isChord = toChord <= toExpression
            }
        }
        if isChord {
            lastChordWrist = wrist
        } else {
            lastExpressionWrist = wrist
        }
        lastRoleTime = frame.time
        return isChord ? (0, nil) : (nil, 0)
    }
}
