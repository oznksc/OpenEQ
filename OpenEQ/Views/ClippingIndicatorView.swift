 //
//  ClippingIndicatorView.swift
//  OpenEQ
//
//  Created by Ozan
//

import SwiftUI

struct ClippingIndicatorView: View {
    let isClipping: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isClipping ? Color.orange : Color.secondary.opacity(0.28))
                .frame(width: 7, height: 7)

            Text(isClipping ? "Clipping" : "Headroom OK")
                .font(.caption.weight(.medium))
                .foregroundStyle(isClipping ? .orange : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background((isClipping ? Color.orange : Color.secondary).opacity(isClipping ? 0.12 : 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(isClipping ? "Signal is clipping. Lower preamp or band gain." : "No clipping detected.")
        .accessibilityLabel(isClipping ? "Signal is clipping. Lower preamp or band gain." : "No clipping detected.")
    }
}

#Preview {
    VStack {
        ClippingIndicatorView(isClipping: false)
        ClippingIndicatorView(isClipping: true)
    }
    .padding()
}
