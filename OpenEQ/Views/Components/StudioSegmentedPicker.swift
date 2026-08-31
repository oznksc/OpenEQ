import SwiftUI

/// A full-rounded glass segmented control designed for the OpenEQ dark studio aesthetic.
struct StudioSegmentedPicker<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let items: [T]
    let titleFor: (T) -> String
    var iconFor: ((T) -> String?)? = nil

    @State private var hoveredItem: T? = nil

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = selection == item
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                        selection = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let iconFor, let icon = iconFor(item) {
                            Image(systemName: icon)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text(titleFor(item))
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .overlay {
                                Capsule()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            }
                    } else if hoveredItem == item {
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    }
                }
                .onHover { isHovered in
                    hoveredItem = isHovered ? item : nil
                }
                .accessibilityLabel(titleFor(item))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2.5)
        .background {
            Capsule()
                .fill(OpenEQTheme.recessedSlotBg)
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }
}
