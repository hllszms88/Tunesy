import CoreImage
import CoreVideo
import SwiftUI

/// Every camera effect in the Filters tab. Add a case here, give it a title/icon/kind,
/// and implement it in `ColorFilterRenderer` (colour) or `FaceArt` (face accessory).
enum CameraFilter: String, CaseIterable, Identifiable {
    case original
    case puppy, kitty, shades, sweetheart, crown
    case fourTone, neon, dream, glitch, comic, noir

    enum Kind {
        case none
        /// Drawn on top of the camera, attached to the face.
        case face
        /// Recolours the whole picture.
        case color
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .puppy: return "Puppy"
        case .kitty: return "Kitty"
        case .shades: return "Shades"
        case .sweetheart: return "Sweetheart"
        case .crown: return "Royal"
        case .fourTone: return "Four Tone"
        case .neon: return "Neon"
        case .dream: return "Dream"
        case .glitch: return "Glitch"
        case .comic: return "Comic"
        case .noir: return "Noir"
        }
    }

    var symbol: String {
        switch self {
        case .original: return "circle.slash"
        case .puppy: return "dog.fill"
        case .kitty: return "cat.fill"
        case .shades: return "sunglasses.fill"
        case .sweetheart: return "heart.fill"
        case .crown: return "crown.fill"
        case .fourTone: return "circle.hexagongrid.fill"
        case .neon: return "bolt.fill"
        case .dream: return "sparkles"
        case .glitch: return "waveform.path"
        case .comic: return "book.fill"
        case .noir: return "moon.fill"
        }
    }

    var kind: Kind {
        switch self {
        case .original: return .none
        case .puppy, .kitty, .shades, .sweetheart, .crown: return .face
        case .fourTone, .neon, .dream, .glitch, .comic, .noir: return .color
        }
    }

    /// Two colours for the filter's button.
    var swatch: [Color] {
        switch self {
        case .original: return [Color(white: 0.35), Color(white: 0.2)]
        case .puppy: return [Color(red: 0.76, green: 0.52, blue: 0.30), Color(red: 0.45, green: 0.28, blue: 0.14)]
        case .kitty: return [Color(red: 1.0, green: 0.72, blue: 0.80), Color(red: 0.85, green: 0.45, blue: 0.62)]
        case .shades: return [Color(red: 0.56, green: 0.49, blue: 1.0), Color(red: 1.0, green: 0.45, blue: 0.62)]
        case .sweetheart: return [Color(red: 1.0, green: 0.42, blue: 0.55), Color(red: 0.86, green: 0.16, blue: 0.38)]
        case .crown: return [Color(red: 1.0, green: 0.84, blue: 0.35), Color(red: 0.90, green: 0.58, blue: 0.10)]
        case .fourTone: return [Color(red: 0.25, green: 0.85, blue: 1.0), Color(red: 1.0, green: 0.35, blue: 0.75)]
        case .neon: return [Color(red: 0.2, green: 1.0, blue: 0.75), Color(red: 0.5, green: 0.2, blue: 1.0)]
        case .dream: return [Color(red: 1.0, green: 0.80, blue: 0.86), Color(red: 0.70, green: 0.62, blue: 1.0)]
        case .glitch: return [Color(red: 1.0, green: 0.2, blue: 0.3), Color(red: 0.1, green: 0.8, blue: 1.0)]
        case .comic: return [Color(red: 1.0, green: 0.85, blue: 0.2), Color(red: 1.0, green: 0.45, blue: 0.2)]
        case .noir: return [Color(white: 0.85), Color(white: 0.15)]
        }
    }
}

/// Recolours camera frames with Core Image. The original pixel buffer is never modified,
/// so tracking always sees the untouched picture.
final class ColorFilterRenderer {
    private struct Palette {
        let dark: (CGFloat, CGFloat, CGFloat)
        let light: (CGFloat, CGFloat, CGFloat)
    }

    /// The four looks that "Four Tone" glides between.
    private let palettes: [Palette] = [
        Palette(dark: (0.05, 0.02, 0.30), light: (0.30, 0.95, 1.00)),   // electric blue
        Palette(dark: (0.28, 0.00, 0.30), light: (1.00, 0.55, 0.85)),   // hot pink
        Palette(dark: (0.30, 0.05, 0.00), light: (1.00, 0.85, 0.35)),   // sunset gold
        Palette(dark: (0.00, 0.20, 0.18), light: (0.55, 1.00, 0.60))    // mint green
    ]

    func render(_ filter: CameraFilter, pixelBuffer: CVPixelBuffer, time: Double) -> CIImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        switch filter {
        case .fourTone:
            return fourTone(image, time: time)
        case .neon:
            return neon(image, extent: extent, time: time)
        case .dream:
            return image.clampedToExtent()
                .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 14.0, kCIInputIntensityKey: 0.85])
                .cropped(to: extent)
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 1.2, kCIInputBrightnessKey: 0.03, kCIInputContrastKey: 0.96
                ])
        case .glitch:
            return glitch(image, extent: extent, time: time)
        case .comic:
            return image.applyingFilter("CIComicEffect", parameters: [:]).cropped(to: extent)
        case .noir:
            return image.applyingFilter("CIPhotoEffectNoir", parameters: [:])
                .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.15])
        default:
            return nil
        }
    }

    private func fourTone(_ image: CIImage, time: Double) -> CIImage {
        // Each colour holds for a moment, then glides smoothly into the next.
        let secondsPerColor = 1.6
        let position = (time / secondsPerColor).truncatingRemainder(dividingBy: 4)
        let index = Int(position) % 4
        let next = (index + 1) % 4
        let fraction = position - Double(Int(position))
        let eased = smoothstep(CGFloat(max(0, (fraction - 0.4) / 0.6)))

        func mix(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat)) -> CIColor {
            return CIColor(red: a.0 + (b.0 - a.0) * eased,
                           green: a.1 + (b.1 - a.1) * eased,
                           blue: a.2 + (b.2 - a.2) * eased)
        }
        let dark = mix(palettes[index].dark, palettes[next].dark)
        let light = mix(palettes[index].light, palettes[next].light)

        let tinted = image.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": dark, "inputColor1": light
        ])
        // Keep some of the real picture so faces stay natural.
        return tinted.applyingFilter("CIDissolveTransition", parameters: [
            kCIInputTargetImageKey: image, kCIInputTimeKey: 0.32
        ])
    }

    private func neon(_ image: CIImage, extent: CGRect, time: Double) -> CIImage {
        let edges = image
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 6.0])
            .applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: time * 1.1])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 2.2, kCIInputBrightnessKey: 0.04, kCIInputContrastKey: 1.4
            ])
        let glow = edges.clampedToExtent()
            .applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: 8.0, kCIInputIntensityKey: 1.0])
            .cropped(to: extent)
        let base = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.55, kCIInputBrightnessKey: -0.26, kCIInputContrastKey: 1.1
        ])
        return glow.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: base])
            .cropped(to: extent)
    }

    private func glitch(_ image: CIImage, extent: CGRect, time: Double) -> CIImage {
        let shift = CGFloat(9 + 6 * sin(time * 3.1))
        let source = image.clampedToExtent()

        func channel(red: CGFloat, green: CGFloat, blue: CGFloat, dx: CGFloat) -> CIImage {
            return source.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            .transformed(by: CGAffineTransform(translationX: dx, y: 0))
            .cropped(to: extent)
        }
        let red = channel(red: 1, green: 0, blue: 0, dx: shift)
        let green = channel(red: 0, green: 1, blue: 0, dx: 0)
        let blue = channel(red: 0, green: 0, blue: 1, dx: -shift)
        return red
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: green])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: blue])
            .cropped(to: extent)
    }

    private func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}
