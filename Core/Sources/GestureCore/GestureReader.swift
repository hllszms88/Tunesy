import Foundation

/// Which fingers of a hand are raised.
public struct FingerState: Equatable, Sendable {
    public var thumb: Bool
    public var index: Bool
    public var middle: Bool
    public var ring: Bool
    public var pinky: Bool

    public init(thumb: Bool = false, index: Bool = false, middle: Bool = false,
                ring: Bool = false, pinky: Bool = false) {
        self.thumb = thumb
        self.index = index
        self.middle = middle
        self.ring = ring
        self.pinky = pinky
    }

    /// Raised fingers, not counting the thumb.
    public var fingerCount: Int {
        var n = 0
        if index { n += 1 }
        if middle { n += 1 }
        if ring { n += 1 }
        if pinky { n += 1 }
        return n
    }

    /// Raised fingers including the thumb.
    public var totalCount: Int { fingerCount + (thumb ? 1 : 0) }
}

/// Everything the instrument needs to know about one hand in one frame.
public struct HandReading: Equatable, Sendable {
    public var fingers: FingerState
    /// How far the hand leans from upright, in degrees. Positive = toward the right of the frame.
    public var leanDegrees: Float
    /// Wrist height: 0 at the bottom of the frame, 1 at the top.
    public var height: Float
    public var wrist: Vec2
}

/// Thresholds for reading a hand. Defaults are starting values to tune on a real device.
public struct GestureTuning: Equatable, Sendable {
    /// A finger counts as raised when its tip is this much farther from the wrist than its middle knuckle.
    public var fingerExtendRatio: Float = 1.12
    /// The thumb counts as out when its tip is this much farther from the pinky knuckle than its own middle joint…
    public var thumbSpreadRatio: Float = 1.05
    /// …and at least this far from the index knuckle, in palm lengths.
    public var thumbMinReach: Float = 0.55
    /// Wrist heights mapped to volume 1 and 0 (normalized y, top = 0).
    public var heightTop: Float = 0.05
    public var heightBottom: Float = 0.95

    public init() {}
}

public enum GestureReader {
    public static func read(_ hand: HandPose, aspect: Float, tuning: GestureTuning = GestureTuning()) -> HandReading {
        // Work in a space where one unit is the same length horizontally and vertically.
        let p = hand.points.map { Vec2($0.x * aspect, $0.y) }

        func d(_ a: Joint, _ b: Joint) -> Float {
            return p[a.rawValue].distance(to: p[b.rawValue])
        }
        func raised(pip: Joint, tip: Joint) -> Bool {
            return d(.wrist, tip) > d(.wrist, pip) * tuning.fingerExtendRatio
        }

        let palm = Swift.max(d(.wrist, .middleMCP), 0.0001)
        let thumbOut = d(.thumbTip, .pinkyMCP) > d(.thumbIP, .pinkyMCP) * tuning.thumbSpreadRatio
            && d(.thumbTip, .indexMCP) > palm * tuning.thumbMinReach

        let fingers = FingerState(
            thumb: thumbOut,
            index: raised(pip: .indexPIP, tip: .indexTip),
            middle: raised(pip: .middlePIP, tip: .middleTip),
            ring: raised(pip: .ringPIP, tip: .ringTip),
            pinky: raised(pip: .pinkyPIP, tip: .pinkyTip)
        )

        let axis = p[Joint.middleMCP.rawValue] - p[Joint.wrist.rawValue]
        let lean = atan2f(axis.x, -axis.y) * 180 / Float.pi

        let wrist = hand[.wrist]
        let span = Swift.max(tuning.heightBottom - tuning.heightTop, 0.0001)
        let height = 1 - (clampValue(wrist.y, tuning.heightTop, tuning.heightBottom) - tuning.heightTop) / span

        return HandReading(fingers: fingers, leanDegrees: lean, height: height, wrist: wrist)
    }

    /// Scale degree chosen by the chord hand.
    ///
    /// 1–5 raised digits (thumb included) select I–V.
    /// Index + pinky ("horns") selects VI; adding the thumb selects VII.
    public static func degree(for fingers: FingerState) -> Int? {
        if fingers.index && fingers.pinky && !fingers.middle && !fingers.ring {
            return fingers.thumb ? 7 : 6
        }
        let count = fingers.totalCount
        return (1...5).contains(count) ? count : nil
    }

    /// The finger pattern that produces a degree, for teaching diagrams.
    public static func fingers(forDegree degree: Int) -> FingerState {
        switch degree {
        case 1: return FingerState(index: true)
        case 2: return FingerState(index: true, middle: true)
        case 3: return FingerState(index: true, middle: true, ring: true)
        case 4: return FingerState(index: true, middle: true, ring: true, pinky: true)
        case 5: return FingerState(thumb: true, index: true, middle: true, ring: true, pinky: true)
        case 6: return FingerState(index: true, pinky: true)
        default: return FingerState(thumb: true, index: true, pinky: true)
        }
    }

    /// The expression-hand pattern for a quality (1–4 fingers) and octave (thumb out = one octave down).
    public static func fingers(forQuality quality: Int, thumbOut: Bool) -> FingerState {
        return FingerState(thumb: thumbOut, index: quality >= 1, middle: quality >= 2,
                           ring: quality >= 3, pinky: quality >= 4)
    }
}
