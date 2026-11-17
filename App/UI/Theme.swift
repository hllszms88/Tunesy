import SwiftUI

/// Colours, type and small shared controls. One look for Play and Learn.
enum Theme {
    static let mint = Color(red: 0.36, green: 0.95, blue: 0.78)
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.40)
    static let violet = Color(red: 0.56, green: 0.49, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.36)
    static let ink = Color(red: 0.05, green: 0.06, blue: 0.09)

    /// One colour per scale degree, so a chord is recognisable at a glance.
    static func degreeColor(_ degree: Int) -> Color {
        switch degree {
        case 1: return mint
        case 2: return coral
        case 3: return gold
        case 4: return Color(red: 0.47, green: 0.82, blue: 1.0)
        case 5: return Color(red: 1.0, green: 0.62, blue: 0.30)
        case 6: return Color(red: 1.0, green: 0.42, blue: 0.62)
        default: return violet
        }
    }

    static func display(_ size: CGFloat) -> Font {
        return .system(size: size, weight: .heavy, design: .rounded)
    }

    static func label(_ size: CGFloat = 13, weight: Font.Weight = .semibold) -> Font {
        return .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Frosted panel used for every floating control.
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

/// Round frosted icon button.
struct IconButton: View {
    let systemName: String
    var isOn: Bool = false
    var tint: Color = Theme.mint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isOn ? Theme.ink : Color.white)
                .frame(width: 44, height: 44)
                .background {
                    if isOn {
                        Circle().fill(tint)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Small frosted text pill.
struct Pill: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(Theme.label(12, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 1))
    }
}

/// Filled capsule button for primary actions.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.mint

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(16, weight: .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 22)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
    }
}

/// Outlined capsule button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(14, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.22 : 0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
    }
}
