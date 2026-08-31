import SwiftUI

struct ClippingIndicatorView: View {
    let isClipping: Bool

    var body: some View {
        HStack(spacing: 6) {
            StudioLED(
                isOn: isClipping,
                activeColor: OpenEQTheme.accentRed,
                inactiveColor: Color.white.opacity(0.12),
                size: 7
            )

            Text(isClipping ? "CLIP" : "HEADROOM")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.5)
                .foregroundStyle(isClipping ? OpenEQTheme.accentRed : .secondary.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isClipping ? OpenEQTheme.accentRed.opacity(0.12) : OpenEQTheme.recessedSlotBg.opacity(0.6))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isClipping ? OpenEQTheme.accentRed.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 0.8)
        }
        .animation(.easeInOut(duration: 0.15), value: isClipping)
        .help(isClipping ? "Signal is clipping (over 0 dBFS)" : "Headroom OK")
        .accessibilityLabel(isClipping ? "Clipping" : "Headroom OK")
    }
}

