import SwiftUI

struct ClippingIndicatorView: View {
    let isClipping: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isClipping ? Color.orange : Color.secondary.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(isClipping ? "Clip" : "OK")
                .font(.caption)
                .foregroundStyle(isClipping ? Color.orange : Color.secondary.opacity(0.7))
        }
        .help(isClipping ? "Signal is clipping" : "Headroom OK")
        .accessibilityLabel(isClipping ? "Clipping" : "Headroom OK")
    }
}
