import SwiftUI

/// Layout tokens & studio design system — refined, matte pro-audio workstation aesthetics.
enum OpenEQTheme {
    static let pagePadding: CGFloat = 16
    static let blockSpacing: CGFloat = 20
    static let sectionSpacing: CGFloat = 14
    static let controlSpacing: CGFloat = 10
    static let playerBarCornerRadius: CGFloat = 16
    /// Locked sidebar width — min==max prevents list content from shoving the detail.
    static let sidebarWidth: CGFloat = 268
    static let minSidebarWidth: CGFloat = 268
    static let idealSidebarWidth: CGFloat = 268
    static let maxSidebarWidth: CGFloat = 268
    // The full tab workspace is designed around this fixed macOS window size.
    static let minWindowWidth: CGFloat = 1100
    static let minWindowHeight: CGFloat = 720
    static let inspectorMinWidth: CGFloat = 300
    static let inspectorIdealWidth: CGFloat = 320
    static let inspectorMaxWidth: CGFloat = 380

    // MARK: - Studio Palette (Matte Slate / Precision Pro-Audio)
    static let chassisBg = Color(red: 0.08, green: 0.086, blue: 0.096)
    static let cardBg = Color(red: 0.11, green: 0.118, blue: 0.130)
    static let cardBgElevated = Color(red: 0.135, green: 0.144, blue: 0.158)
    static let recessedSlotBg = Color(red: 0.055, green: 0.058, blue: 0.066)
    
    static let accentCyan = Color(red: 0.20, green: 0.72, blue: 0.88)
    static let accentAmber = Color(red: 0.95, green: 0.58, blue: 0.18)
    static let accentGreen = Color(red: 0.24, green: 0.76, blue: 0.44)
    static let accentRed = Color(red: 0.92, green: 0.30, blue: 0.32)
    static let accentPurple = Color(red: 0.65, green: 0.45, blue: 0.88)
    static let accentGold = Color(red: 0.90, green: 0.72, blue: 0.22)

    /// Subtle color spectrum for parametric EQ bands
    static func bandColor(at index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.90, green: 0.42, blue: 0.42), // Coral
            Color(red: 0.92, green: 0.60, blue: 0.24), // Amber
            Color(red: 0.88, green: 0.76, blue: 0.28), // Gold
            Color(red: 0.30, green: 0.75, blue: 0.52), // Mint
            Color(red: 0.22, green: 0.74, blue: 0.88), // Cyan
            Color(red: 0.35, green: 0.62, blue: 0.90), // Slate Blue
            Color(red: 0.68, green: 0.48, blue: 0.88), // Violet
            Color(red: 0.88, green: 0.45, blue: 0.70)  // Rose
        ]
        return colors[index % colors.count]
    }
}

// MARK: - Studio Chassis Card Modifier
struct StudioChassisCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 10
    var elevation: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                shape.fill(elevation ? OpenEQTheme.cardBgElevated : OpenEQTheme.cardBg)
            }
            .overlay {
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func studioCard(cornerRadius: CGFloat = 10, elevation: Bool = false) -> some View {
        modifier(StudioChassisCardModifier(cornerRadius: cornerRadius, elevation: elevation))
    }
}

// MARK: - Crisp Hardware LED Indicator
struct StudioLED: View {
    let isOn: Bool
    var activeColor: Color = OpenEQTheme.accentGreen
    var inactiveColor: Color = Color.white.opacity(0.12)
    var size: CGFloat = 6.5

    var body: some View {
        Circle()
            .fill(isOn ? activeColor : inactiveColor)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - OpenEQStatusDot
struct OpenEQStatusDot: View {
    enum Kind {
        case idle, ready, active, warning, error, bypassed

        var color: Color {
            switch self {
            case .idle: return .secondary.opacity(0.4)
            case .ready: return OpenEQTheme.accentCyan
            case .active: return OpenEQTheme.accentGreen
            case .warning: return OpenEQTheme.accentAmber
            case .error: return OpenEQTheme.accentRed
            case .bypassed: return OpenEQTheme.accentAmber
            }
        }
    }

    let kind: Kind
    var size: CGFloat = 7

    var body: some View {
        StudioLED(isOn: kind != .idle, activeColor: kind.color, inactiveColor: .secondary.opacity(0.25), size: size)
    }
}

// MARK: - Section Title
struct OpenEQSectionTitle: View {
    let title: String
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tactile Press Button Style
struct TactileButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.75), value: configuration.isPressed)
    }
}


