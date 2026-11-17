import SwiftUI

/// Cozy white: pearl white, cream and soft petal pink, with a gentle charcoal for text.
/// One look for Play and Learn.
enum Theme {
    static let paper = Color.white
    static let cream = Color(red: 0.992, green: 0.980, blue: 0.976)
    static let sand = Color(red: 0.937, green: 0.922, blue: 0.929)
    static let latte = Color(red: 0.792, green: 0.765, blue: 0.871)
    static let blush = Color(red: 0.984, green: 0.863, blue: 0.886)
    static let rose = Color(red: 0.937, green: 0.596, blue: 0.682)
    static let sage = Color(red: 0.600, green: 0.700, blue: 0.600)
    static let ink = Color(red: 0.235, green: 0.231, blue: 0.267)
    static let inkSoft = Color(red: 0.541, green: 0.533, blue: 0.573)

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
            .shadow(color: Theme.ink.opacity(0.10), radius: 14, x: 0, y: 6)
    }

    /// White text that stays readable on top of the camera picture.
    func onCameraText() -> some View {
        self
            .foregroundStyle(Color.white)
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 1)
    }
}

/// Plain white icon, Snapchat style: no background, a soft shadow so it reads on any picture.
struct IconButton: View {
    let systemName: String
    var isOn: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isOn ? Theme.rose : Color.white)
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 1)
                .frame(width: 46, height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Small soft text pill.
struct Pill: View {
    let text: String
    var color: Color = Theme.inkSoft

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
            .foregroundStyle(Color.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.rose.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .shadow(color: Theme.rose.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

/// Soft white capsule button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.6 : 0.85), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.sand, lineWidth: 1))
    }
}
