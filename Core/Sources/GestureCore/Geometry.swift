import Foundation

/// A 2D point or vector. In hand data: x grows to the right, y grows downward.
public struct Vec2: Equatable, Codable, Sendable {
    public var x: Float
    public var y: Float

    public init(_ x: Float, _ y: Float) {
        self.x = x
        self.y = y
    }

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }

    public var length: Float { (x * x + y * y).squareRoot() }

    public func distance(to other: Vec2) -> Float { (self - other).length }
}

/// The 21 hand joints, in the order used throughout the app.
public enum Joint: Int, CaseIterable, Sendable {
    case wrist = 0
    case thumbCMC, thumbMCP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case pinkyMCP, pinkyPIP, pinkyDIP, pinkyTip
}

/// One detected hand: 21 points normalized to 0...1 of the camera frame,
/// expressed from the player's point of view (as in a mirror).
public struct HandPose: Equatable, Sendable {
    public var points: [Vec2]

    public init?(points: [Vec2]) {
        guard points.count == Joint.allCases.count else { return nil }
        self.points = points
    }

    public subscript(joint: Joint) -> Vec2 { points[joint.rawValue] }
}

/// All hands seen in one camera frame.
public struct HandFrame: Sendable {
    /// Seconds, monotonically increasing.
    public var time: Double
    /// Frame width divided by frame height. Needed because normalized
    /// coordinates distort angles and distances on non-square frames.
    public var aspect: Float
    public var hands: [HandPose]

    public init(time: Double, aspect: Float, hands: [HandPose]) {
        self.time = time
        self.aspect = aspect
        self.hands = hands
    }
}

@inline(__always)
func clampValue(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
    return Swift.max(lo, Swift.min(hi, v))
}
