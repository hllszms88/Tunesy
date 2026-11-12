import Foundation
@testable import GestureCore

/// Builds an artificial hand for tests: wrist position, which fingers are raised, and lean.
enum SyntheticHand {
    static func make(wristX: Float, wristY: Float, fingers: FingerState,
                     leanDegrees: Float = 0, aspect: Float = 0.5625) -> HandPose {
        // Offsets from the wrist in "metric" units (same scale on both axes), y up = negative.
        var offsets = [Vec2](repeating: Vec2(0, 0), count: 21)

        func set(_ joint: Joint, _ x: Float, _ y: Float) {
            offsets[joint.rawValue] = Vec2(x, y)
        }

        // Thumb sits on the left side of this hand.
        set(.thumbCMC, -0.030, -0.020)
        set(.thumbMCP, -0.050, -0.050)
        if fingers.thumb {
            set(.thumbIP, -0.080, -0.070)
            set(.thumbTip, -0.110, -0.090)
        } else {
            set(.thumbIP, -0.040, -0.070)
            set(.thumbTip, -0.010, -0.080)
        }

        func finger(_ mcp: Joint, _ pip: Joint, _ dip: Joint, _ tip: Joint, x: Float, up: Bool) {
            set(mcp, x, -0.100)
            if up {
                set(pip, x, -0.150)
                set(dip, x, -0.190)
                set(tip, x, -0.230)
            } else {
                set(pip, x, -0.130)
                set(dip, x, -0.100)
                set(tip, x, -0.070)
            }
        }
        finger(.indexMCP, .indexPIP, .indexDIP, .indexTip, x: -0.030, up: fingers.index)
        finger(.middleMCP, .middlePIP, .middleDIP, .middleTip, x: -0.005, up: fingers.middle)
        finger(.ringMCP, .ringPIP, .ringDIP, .ringTip, x: 0.020, up: fingers.ring)
        finger(.pinkyMCP, .pinkyPIP, .pinkyDIP, .pinkyTip, x: 0.040, up: fingers.pinky)

        let angle = leanDegrees * Float.pi / 180
        let c = cosf(angle)
        let s = sinf(angle)
        let points: [Vec2] = offsets.map { o in
            let rx = o.x * c - o.y * s
            let ry = o.x * s + o.y * c
            return Vec2(wristX + rx / aspect, wristY + ry)
        }
        return HandPose(points: points)!
    }

    /// A two-hand frame: chord hand on the left, expression hand on the right.
    static func frame(time: Double, chord: FingerState?, chordLean: Float = 0,
                      expression: FingerState?, expressionHeight: Float = 0.5,
                      expressionLean: Float = 0, aspect: Float = 0.5625) -> HandFrame {
        var hands: [HandPose] = []
        if let chord = chord {
            hands.append(make(wristX: 0.25, wristY: 0.6, fingers: chord, leanDegrees: chordLean, aspect: aspect))
        }
        if let expression = expression {
            // height 1 = top of frame (y 0.05), height 0 = bottom (y 0.95)
            let y = 0.95 - expressionHeight * 0.9
            hands.append(make(wristX: 0.75, wristY: y, fingers: expression,
                              leanDegrees: expressionLean, aspect: aspect))
        }
        return HandFrame(time: time, aspect: aspect, hands: hands)
    }
}
