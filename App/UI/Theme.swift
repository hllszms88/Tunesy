import SwiftUI

/// "Cozy white": pearl white, cream, sand, blush and a soft cocoa for text.
/// One look for Play and Learn.
enum Theme {
    static let paper = Color.white
    static let cream = Color(red: 0.984, green: 0.969, blue: 0.949)
    static let sand = Color(red: 0.937, green: 0.902, blue: 0.863)
    static let latte = Color(red: 0.851, green: 0.780, blue: 0.710)
    static let blush = Color(red: 0.929, green: 0.812, blue: 0.788)
    static let rose = Color(red: 0.851, green: 0.655, blue: 0.627)
    static let sage = Color(red: 0.600, green: 0.670, blue: 0.565)
    static let cocoa = Color(red: 0.357, green: 0.294, blue: 0.259)
    static let cocoaSoft = Color(red: 0.549, green: 0.482, blue: 0.439)

    /// Large titles and chord names: an elegant serif.
    static func display(_ size: CGFloat) -> Font {
        return .system(size: size, weight: .semibold, design: .serif)
    }

    static func label(_ size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font {
        return .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Frosted white panel used for every floating control.
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: 1)
            )
            .shadow(color: Theme.cocoa.opacity(0.10), radius: 14, x: 0, y: 6)
    }

    /// White text that stays readable on top of the camera picture.
    func onCameraText() -> some View {
        self
            .foregroundStyle(Color.white)
            .shadow(color: Theme.cocoa.opacity(0.45), radius: 6, x: 0, y: 1)
    }
}

/// Round frosted icon button.
struct IconButton: View {
    let systemName: String
    var isOn: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isOn ? Theme.cream : Theme.cocoa)
                .frame(width: 44, height: 44)
                .background {
                    if isOn {
                        Circle().fill(Theme.cocoa)
                    } else {
                        ZStack {
                            Circle().fill(.ultraThinMaterial)
                            Circle().fill(Color.white.opacity(0.55))
                        }
                    }
                }
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .shadow(color: Theme.cocoa.opacity(0.10), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

/// Small soft text pill.
struct Pill: View {
    let text: String
    var color: Color = Theme.cocoaSoft

    var body: some View {
        Text(text)
            .font(Theme.label(12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Filled capsule button for primary actions.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(16, weight: .semibold))
            .foregroundStyle(Theme.cream)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.cocoa.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .shadow(color: Theme.cocoa.opacity(0.18), radius: 10, x: 0, y: 5)
    }
}

/// Soft white capsule button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(14, weight: .semibold))
            .foregroundStyle(Theme.cocoa)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.6 : 0.85), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.sand, lineWidth: 1))
    }
}
