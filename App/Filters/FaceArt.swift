import SwiftUI

/// Draws the active face accessory over the camera, following the tracked face.
struct FaceAccessoryLayer: View {
    @ObservedObject var live: LiveState
    let filter: CameraFilter

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let face = live.frame.face else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                FaceArt.draw(filter, face: face, imageSize: live.frame.imageSize,
                             in: &context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Original vector artwork for the face filters. Everything is drawn in "face units":
/// the origin is the midpoint between the eyes, one unit is the distance between them,
/// and the drawing is rotated with the head. Eyes sit at (-0.5, 0) and (0.5, 0); y grows downward.
enum FaceArt {
    static func draw(_ filter: CameraFilter, face: FacePose, imageSize: CGSize,
                     in context: inout GraphicsContext, size: CGSize, time: Double) {
        let map = AspectFill(image: imageSize, view: size)
        let left = map.point(face.leftEye)
        let right = map.point(face.rightEye)
        let mid = CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
        let eyeDistance = hypot(right.x - left.x, right.y - left.y)
        guard eyeDistance > 8 else { return }
        let roll = atan2(right.y - left.y, right.x - left.x)

        // Converts a screen point into face units.
        func local(_ p: CGPoint) -> CGPoint {
            let dx = p.x - mid.x
            let dy = p.y - mid.y
            let c = cos(-roll)
            let s = sin(-roll)
            return CGPoint(x: (dx * c - dy * s) / eyeDistance, y: (dx * s + dy * c) / eyeDistance)
        }
        let nose = local(map.point(face.nose))
        let mouth = local(map.point(face.mouth))

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: Color.black.opacity(0.35), radius: eyeDistance * 0.05,
                                    x: 0, y: eyeDistance * 0.03))
            var ctx = layer
            ctx.translateBy(x: mid.x, y: mid.y)
            ctx.rotate(by: .radians(Double(roll)))
            ctx.scaleBy(x: eyeDistance, y: eyeDistance)

            switch filter {
            case .puppy:
                puppy(&ctx, nose: nose, mouth: mouth, mouthOpen: face.mouthOpen)
            case .kitty:
                kitty(&ctx, nose: nose)
            case .shades:
                shades(&ctx, time: time)
            case .sweetheart:
                sweetheart(&ctx, time: time)
            case .crown:
                crown(&ctx, time: time)
            default:
                break
            }
        }
    }

    // MARK: Helpers

    private static func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat,
                                rotation: CGFloat = 0) -> Path {
        let transform = CGAffineTransform(translationX: cx, y: cy).rotated(by: rotation)
        return Path(ellipseIn: CGRect(x: -w / 2, y: -h / 2, width: w, height: h)).applying(transform)
    }

    private static func gradient(_ colors: [Color], from: CGPoint, to: CGPoint) -> GraphicsContext.Shading {
        return .linearGradient(Gradient(colors: colors), startPoint: from, endPoint: to)
    }

    private static func heart(center: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        let s = size
        path.move(to: CGPoint(x: center.x, y: center.y + s * 0.45))
        path.addCurve(to: CGPoint(x: center.x - s * 0.5, y: center.y - s * 0.12),
                      control1: CGPoint(x: center.x - s * 0.18, y: center.y + s * 0.28),
                      control2: CGPoint(x: center.x - s * 0.5, y: center.y + s * 0.12))
        path.addCurve(to: CGPoint(x: center.x, y: center.y - s * 0.18),
                      control1: CGPoint(x: center.x - s * 0.5, y: center.y - s * 0.5),
                      control2: CGPoint(x: center.x - s * 0.08, y: center.y - s * 0.46))
        path.addCurve(to: CGPoint(x: center.x + s * 0.5, y: center.y - s * 0.12),
                      control1: CGPoint(x: center.x + s * 0.08, y: center.y - s * 0.46),
                      control2: CGPoint(x: center.x + s * 0.5, y: center.y - s * 0.5))
        path.addCurve(to: CGPoint(x: center.x, y: center.y + s * 0.45),
                      control1: CGPoint(x: center.x + s * 0.5, y: center.y + s * 0.12),
                      control2: CGPoint(x: center.x + s * 0.18, y: center.y + s * 0.28))
        path.closeSubpath()
        return path
    }

    /// A four-pointed sparkle.
    private static func sparkle(center: CGPoint, size: CGFloat) -> Path {
        var path = Path()
        let r = size / 2
        let inner = r * 0.22
        path.move(to: CGPoint(x: center.x, y: center.y - r))
        path.addLine(to: CGPoint(x: center.x + inner, y: center.y - inner))
        path.addLine(to: CGPoint(x: center.x + r, y: center.y))
        path.addLine(to: CGPoint(x: center.x + inner, y: center.y + inner))
        path.addLine(to: CGPoint(x: center.x, y: center.y + r))
        path.addLine(to: CGPoint(x: center.x - inner, y: center.y + inner))
        path.addLine(to: CGPoint(x: center.x - r, y: center.y))
        path.addLine(to: CGPoint(x: center.x - inner, y: center.y - inner))
        path.closeSubpath()
        return path
    }

    // MARK: Puppy

    private static func puppy(_ ctx: inout GraphicsContext, nose: CGPoint, mouth: CGPoint, mouthOpen: CGFloat) {
        let furLight = Color(red: 0.72, green: 0.48, blue: 0.27)
        let furDark = Color(red: 0.40, green: 0.24, blue: 0.12)
        let innerEar = Color(red: 0.93, green: 0.66, blue: 0.62)

        for side in [CGFloat(-1), CGFloat(1)] {
            // Floppy ear hanging from the top of the head, flaring outward.
            let cx = side * 1.08
            let cy: CGFloat = -1.05
            let tilt = -side * 0.42
            let outer = ellipse(cx, cy, 0.78, 1.42, rotation: tilt)
            ctx.fill(outer, with: gradient([furLight, furDark],
                                           from: CGPoint(x: cx, y: cy - 0.7), to: CGPoint(x: cx, y: cy + 0.7)))
            let inner = ellipse(cx + side * 0.03, cy + 0.10, 0.42, 0.98, rotation: tilt)
            ctx.fill(inner, with: .color(innerEar.opacity(0.85)))
        }

        // Tongue first, so the nose sits over it.
        if mouthOpen > 0.22 {
            let top = mouth.y + 0.02
            let tongue = Path(roundedRect: CGRect(x: mouth.x - 0.19, y: top, width: 0.38, height: 0.58),
                              cornerSize: CGSize(width: 0.19, height: 0.19))
            ctx.fill(tongue, with: gradient([Color(red: 1.0, green: 0.52, blue: 0.60),
                                             Color(red: 0.93, green: 0.30, blue: 0.42)],
                                            from: CGPoint(x: mouth.x, y: top),
                                            to: CGPoint(x: mouth.x, y: top + 0.58)))
            var crease = Path()
            crease.move(to: CGPoint(x: mouth.x, y: top + 0.08))
            crease.addLine(to: CGPoint(x: mouth.x, y: top + 0.40))
            ctx.stroke(crease, with: .color(Color(red: 0.75, green: 0.2, blue: 0.32)),
                       style: StrokeStyle(lineWidth: 0.025, lineCap: .round))
        }

        // Nose: a soft rounded triangle with a highlight.
        var nosePath = Path()
        nosePath.move(to: CGPoint(x: nose.x - 0.30, y: nose.y - 0.14))
        nosePath.addQuadCurve(to: CGPoint(x: nose.x + 0.30, y: nose.y - 0.14),
                              control: CGPoint(x: nose.x, y: nose.y - 0.30))
        nosePath.addQuadCurve(to: CGPoint(x: nose.x, y: nose.y + 0.22),
                              control: CGPoint(x: nose.x + 0.34, y: nose.y + 0.12))
        nosePath.addQuadCurve(to: CGPoint(x: nose.x - 0.30, y: nose.y - 0.14),
                              control: CGPoint(x: nose.x - 0.34, y: nose.y + 0.12))
        nosePath.closeSubpath()
        ctx.fill(nosePath, with: gradient([Color(white: 0.22), Color(white: 0.04)],
                                          from: CGPoint(x: nose.x, y: nose.y - 0.25),
                                          to: CGPoint(x: nose.x, y: nose.y + 0.22)))
        ctx.fill(ellipse(nose.x - 0.09, nose.y - 0.10, 0.17, 0.08, rotation: -0.2),
                 with: .color(Color.white.opacity(0.55)))

        // Whisker dots on the muzzle.
        for side in [CGFloat(-1), CGFloat(1)] {
            for (dx, dy) in [(CGFloat(0.46), CGFloat(0.20)), (CGFloat(0.62), CGFloat(0.32)), (CGFloat(0.44), CGFloat(0.40))] {
                ctx.fill(ellipse(nose.x + side * dx, nose.y + dy, 0.055, 0.055),
                         with: .color(furDark.opacity(0.85)))
            }
        }
    }

    // MARK: Kitty

    private static func kitty(_ ctx: inout GraphicsContext, nose: CGPoint) {
        let fur = Color(red: 0.98, green: 0.96, blue: 0.94)
        let furShade = Color(red: 0.80, green: 0.76, blue: 0.80)
        let pink = Color(red: 1.0, green: 0.62, blue: 0.74)
        let rounded = StrokeStyle(lineWidth: 0.10, lineCap: .round, lineJoin: .round)

        for side in [CGFloat(-1), CGFloat(1)] {
            var ear = Path()
            ear.move(to: CGPoint(x: side * 0.38, y: -1.22))
            ear.addLine(to: CGPoint(x: side * 1.02, y: -2.10))
            ear.addLine(to: CGPoint(x: side * 1.30, y: -1.06))
            ear.closeSubpath()
            let shading = gradient([fur, furShade], from: CGPoint(x: 0, y: -2.1), to: CGPoint(x: 0, y: -1.0))
            ctx.fill(ear, with: shading)
            ctx.stroke(ear, with: shading, style: rounded)

            var inner = Path()
            inner.move(to: CGPoint(x: side * 0.62, y: -1.30))
            inner.addLine(to: CGPoint(x: side * 0.98, y: -1.84))
            inner.addLine(to: CGPoint(x: side * 1.14, y: -1.22))
            inner.closeSubpath()
            ctx.fill(inner, with: .color(pink))
            ctx.stroke(inner, with: .color(pink), style: StrokeStyle(lineWidth: 0.05, lineCap: .round, lineJoin: .round))
        }

        // Small heart-shaped nose.
        ctx.fill(heart(center: CGPoint(x: nose.x, y: nose.y - 0.02), size: 0.34), with: .color(pink))
        ctx.fill(ellipse(nose.x - 0.06, nose.y - 0.08, 0.09, 0.05), with: .color(Color.white.opacity(0.7)))

        // Whiskers.
        let whisker = StrokeStyle(lineWidth: 0.028, lineCap: .round)
        for side in [CGFloat(-1), CGFloat(1)] {
            for lift in [CGFloat(-0.16), CGFloat(0.04), CGFloat(0.24)] {
                var line = Path()
                line.move(to: CGPoint(x: nose.x + side * 0.42, y: nose.y + 0.12 + lift * 0.3))
                line.addQuadCurve(to: CGPoint(x: nose.x + side * 1.42, y: nose.y + 0.10 + lift),
                                  control: CGPoint(x: nose.x + side * 0.9, y: nose.y + 0.02 + lift * 0.5))
                ctx.stroke(line, with: .color(Color.white.opacity(0.95)), style: whisker)
            }
        }
    }

    // MARK: Shades

    private static func shades(_ ctx: inout GraphicsContext, time: Double) {
        let frame = Color(red: 0.10, green: 0.10, blue: 0.14)
        let lensWidth: CGFloat = 0.90
        let lensHeight: CGFloat = 0.64
        // The lens colours drift slowly so the glasses feel alive.
        let drift = CGFloat((sin(time * 0.8) + 1) / 2)
        let lensColors = [
            Color(red: 0.55 + 0.25 * drift, green: 0.40, blue: 1.0).opacity(0.88),
            Color(red: 1.0, green: 0.40 + 0.2 * drift, blue: 0.70).opacity(0.88),
            Color(red: 1.0, green: 0.75, blue: 0.35 + 0.2 * drift).opacity(0.88)
        ]

        for side in [CGFloat(-1), CGFloat(1)] {
            let cx = side * 0.5
            let rect = CGRect(x: cx - lensWidth / 2, y: 0.02 - lensHeight / 2, width: lensWidth, height: lensHeight)
            let lens = Path(roundedRect: rect, cornerSize: CGSize(width: 0.24, height: 0.24))
            ctx.fill(lens, with: gradient(lensColors, from: CGPoint(x: rect.minX, y: rect.minY),
                                          to: CGPoint(x: rect.maxX, y: rect.maxY)))
            ctx.stroke(lens, with: .color(frame), lineWidth: 0.075)

            // Reflection.
            var shine = Path()
            shine.move(to: CGPoint(x: rect.minX + 0.14, y: rect.minY + 0.34))
            shine.addLine(to: CGPoint(x: rect.minX + 0.36, y: rect.minY + 0.12))
            shine.move(to: CGPoint(x: rect.minX + 0.26, y: rect.minY + 0.40))
            shine.addLine(to: CGPoint(x: rect.minX + 0.46, y: rect.minY + 0.20))
            ctx.stroke(shine, with: .color(Color.white.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 0.045, lineCap: .round))

            // Arm toward the ear.
            var arm = Path()
            arm.move(to: CGPoint(x: side * (0.5 + lensWidth / 2), y: -0.10))
            arm.addLine(to: CGPoint(x: side * 1.32, y: -0.16))
            ctx.stroke(arm, with: .color(frame), style: StrokeStyle(lineWidth: 0.075, lineCap: .round))
        }

        var bridge = Path()
        bridge.move(to: CGPoint(x: -0.06, y: -0.04))
        bridge.addQuadCurve(to: CGPoint(x: 0.06, y: -0.04), control: CGPoint(x: 0, y: -0.14))
        ctx.stroke(bridge, with: .color(frame), style: StrokeStyle(lineWidth: 0.075, lineCap: .round))
    }

    // MARK: Sweetheart

    private static func sweetheart(_ ctx: inout GraphicsContext, time: Double) {
        let blush = Color(red: 1.0, green: 0.42, blue: 0.58)
        for side in [CGFloat(-1), CGFloat(1)] {
            let center = CGPoint(x: side * 0.86, y: 0.62)
            ctx.fill(ellipse(center.x, center.y, 0.62, 0.40),
                     with: .radialGradient(Gradient(colors: [blush.opacity(0.62), blush.opacity(0)]),
                                           center: center, startRadius: 0, endRadius: 0.32))
            ctx.fill(heart(center: CGPoint(x: side * 0.90, y: 0.56), size: 0.16), with: .color(blush.opacity(0.9)))
        }

        // A halo of hearts drifting above the head.
        let count = 7
        for index in 0..<count {
            let spread = Double(index) / Double(count - 1)            // 0...1 across the head
            let angle = Double.pi * (1.08 - 1.16 * spread) + sin(time * 0.6) * 0.05
            let bob = sin(time * 2.0 + Double(index) * 1.3) * 0.07
            let radius = 1.95 + (index % 2 == 0 ? 0.0 : 0.22)
            let center = CGPoint(x: CGFloat(cos(angle) * radius), y: CGFloat(0.25 - sin(angle) * radius + bob))
            let size = CGFloat(0.30 + 0.10 * sin(time * 1.6 + Double(index)))
            let tone = Double(index % 3) * 0.12
            let color = Color(red: 1.0, green: 0.30 + tone, blue: 0.50 + tone)
            let shape = heart(center: center, size: size)
            ctx.fill(shape, with: gradient([color, Color(red: 0.90, green: 0.12, blue: 0.36)],
                                           from: CGPoint(x: center.x, y: center.y - size / 2),
                                           to: CGPoint(x: center.x, y: center.y + size / 2)))
            ctx.fill(ellipse(center.x - size * 0.18, center.y - size * 0.14, size * 0.16, size * 0.10, rotation: -0.5),
                     with: .color(Color.white.opacity(0.6)))
        }
    }

    // MARK: Crown

    private static func crown(_ ctx: inout GraphicsContext, time: Double) {
        let goldLight = Color(red: 1.0, green: 0.90, blue: 0.50)
        let goldDark = Color(red: 0.88, green: 0.56, blue: 0.10)
        let base: CGFloat = -1.42
        let band: CGFloat = 0.24

        var body = Path()
        body.move(to: CGPoint(x: -0.98, y: base))
        body.addLine(to: CGPoint(x: -1.08, y: base - 0.78))
        body.addLine(to: CGPoint(x: -0.52, y: base - 0.36))
        body.addLine(to: CGPoint(x: 0, y: base - 1.00))
        body.addLine(to: CGPoint(x: 0.52, y: base - 0.36))
        body.addLine(to: CGPoint(x: 1.08, y: base - 0.78))
        body.addLine(to: CGPoint(x: 0.98, y: base))
        body.closeSubpath()
        let shading = gradient([goldLight, goldDark], from: CGPoint(x: 0, y: base - 1.0), to: CGPoint(x: 0, y: base))
        ctx.fill(body, with: shading)
        ctx.stroke(body, with: .color(goldDark), style: StrokeStyle(lineWidth: 0.05, lineJoin: .round))

        let bandRect = CGRect(x: -0.98, y: base - band, width: 1.96, height: band)
        ctx.fill(Path(roundedRect: bandRect, cornerSize: CGSize(width: 0.06, height: 0.06)),
                 with: gradient([goldDark, goldLight, goldDark], from: CGPoint(x: -0.98, y: 0), to: CGPoint(x: 0.98, y: 0)))

        // Gems: on the three points and along the band.
        let gems: [(CGFloat, CGFloat, CGFloat, Color)] = [
            (-1.08, base - 0.80, 0.16, Color(red: 0.35, green: 0.75, blue: 1.0)),
            (0, base - 1.02, 0.20, Color(red: 1.0, green: 0.30, blue: 0.42)),
            (1.08, base - 0.80, 0.16, Color(red: 0.35, green: 0.75, blue: 1.0)),
            (-0.56, base - band / 2, 0.13, Color(red: 0.45, green: 0.95, blue: 0.65)),
            (0, base - band / 2, 0.15, Color(red: 0.70, green: 0.50, blue: 1.0)),
            (0.56, base - band / 2, 0.13, Color(red: 0.45, green: 0.95, blue: 0.65))
        ]
        for (x, y, size, color) in gems {
            ctx.fill(ellipse(x, y, size, size), with: .color(color))
            ctx.fill(ellipse(x - size * 0.18, y - size * 0.18, size * 0.32, size * 0.32),
                     with: .color(Color.white.opacity(0.8)))
        }

        // Twinkling sparkles around the crown.
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (-1.55, -2.10, 0.30), (1.50, -2.25, 0.36), (-0.70, -2.65, 0.24),
            (0.78, -2.70, 0.22), (-1.75, -1.35, 0.20), (1.78, -1.45, 0.24)
        ]
        for (index, spot) in spots.enumerated() {
            let twinkle = (sin(time * 3.0 + Double(index) * 1.7) + 1) / 2
            let size = spot.2 * CGFloat(0.55 + 0.45 * twinkle)
            ctx.fill(sparkle(center: CGPoint(x: spot.0, y: spot.1), size: size),
                     with: .color(Color.white.opacity(0.35 + 0.65 * twinkle)))
        }
    }
}
