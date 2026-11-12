import GestureCore
import SwiftUI

/// Draws the tracked hands over the camera: mint for the chord hand, coral for the expression hand.
struct HandOverlay: View {
    @ObservedObject var live: LiveState

    private static let chains: [[Int]] = [
        [0, 1, 2, 3, 4],
        [0, 5, 6, 7, 8],
        [5, 9, 13, 17, 0],
        [9, 10, 11, 12],
        [13, 14, 15, 16],
        [17, 18, 19, 20]
    ]
    private static let tips: [Int] = [4, 8, 12, 16, 20]

    var body: some View {
        Canvas { context, size in
            let frame = live.frame
            let map = AspectFill(image: frame.imageSize, view: size)
            for (index, hand) in frame.hands.enumerated() where hand.count == 21 {
                var color = Color.white
                if frame.chordHand == index { color = Theme.mint }
                if frame.expressionHand == index { color = Theme.coral }
                let points = hand.map { map.point($0) }

                var bones = Path()
                for chain in HandOverlay.chains {
                    bones.move(to: points[chain[0]])
                    for joint in chain.dropFirst() {
                        bones.addLine(to: points[joint])
                    }
                }
                context.stroke(bones, with: .color(color.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                for tip in HandOverlay.tips {
                    let p = points[tip]
                    let halo = CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18)
                    context.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.25)))
                    let dot = CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: dot), with: .color(color))
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
    var color: Color = Theme.mint
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
                    ctx.stroke(stub, with: .color(Color.white.opacity(0.4)), lineWidth: 1.5)
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
                ctx.stroke(thumb, with: .color(Color.white.opacity(0.4)), lineWidth: 1.5)
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
