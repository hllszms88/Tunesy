import GestureCore
import SwiftUI

/// Draws the tracked hands over the camera as small white dots, one per joint.
struct HandOverlay: View {
    @ObservedObject var live: LiveState

    var body: some View {
        Canvas { context, size in
            let frame = live.frame
            let map = AspectFill(image: frame.imageSize, view: size)
            for hand in frame.hands where hand.count == 21 {
                for joint in hand {
                    let p = map.point(joint)
                    let dot = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: dot.insetBy(dx: -1.5, dy: -1.5)),
                                 with: .color(Color.black.opacity(0.12)))
                    context.fill(Path(ellipseIn: dot), with: .color(Color.white.opacity(0.95)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A small diagram of a hand showing which fingers to raise, used to teach shapes.
struct HandShapeView: View {
    let fingers: FingerState
    /// Positive leans the hand to the right.
    var tiltDegrees: Double = 0
    var color: Color = Theme.ink
    /// True for the left hand as you see it in the mirror view (thumb toward the middle).
    var thumbOnRight: Bool = false

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / 120, size.height / 132)
            var ctx = context
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: .degrees(tiltDegrees))
            ctx.scaleBy(x: unit, y: unit)
            ctx.translateBy(x: -60, y: -66)

            let palm = Path(roundedRect: CGRect(x: 27, y: 70, width: 66, height: 54), cornerRadius: 20)
            ctx.fill(palm, with: .color(color.opacity(0.20)))
            ctx.stroke(palm, with: .color(color.opacity(0.65)), lineWidth: 2)

            let raised: [Bool] = thumbOnRight
                ? [fingers.pinky, fingers.ring, fingers.middle, fingers.index]
                : [fingers.index, fingers.middle, fingers.ring, fingers.pinky]
            let columns: [CGFloat] = [35, 52, 69, 86]
            for (index, x) in columns.enumerated() {
                if raised[index] {
                    let bar = Path(roundedRect: CGRect(x: x - 6.5, y: 14, width: 13, height: 62), cornerRadius: 6.5)
                    ctx.fill(bar, with: .color(color))
                } else {
                    let stub = Path(roundedRect: CGRect(x: x - 6.5, y: 54, width: 13, height: 22), cornerRadius: 6.5)
                    ctx.stroke(stub, with: .color(Theme.ink.opacity(0.3)), lineWidth: 1.5)
                }
            }

            // Thumb: a bar hinged at the side of the palm, swung outward when raised.
            let side: CGFloat = thumbOnRight ? 1 : -1
            let pivot = CGPoint(x: 60 + side * 31, y: 104)
            let angle: CGFloat = fingers.thumb ? side * 0.95 : side * 0.18
            let length: CGFloat = fingers.thumb ? 44 : 26
            let hinge = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: angle)
            let thumb = Path(roundedRect: CGRect(x: -6.5, y: -length, width: 13, height: length),
                             cornerRadius: 6.5).applying(hinge)
            if fingers.thumb {
                ctx.fill(thumb, with: .color(color))
            } else {
                ctx.stroke(thumb, with: .color(Theme.ink.opacity(0.3)), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}

extension FingerState {
    /// Short words for a chord-hand shape, e.g. "2 fingers" or "index + pinky".
    var chordHandDescription: String {
        if index && pinky && !middle && !ring {
            return thumb ? "index + pinky + thumb" : "index + pinky"
        }
        let count = totalCount
        if count == 5 { return "open hand" }
        return count == 1 ? "1 finger" : "\(count) fingers"
    }
}
