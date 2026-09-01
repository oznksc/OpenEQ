import SwiftUI

/// A full-rounded glass segmented control designed for the OpenEQ dark studio aesthetic.
struct StudioSegmentedPicker<T: Hashable & Identifiable>: View {
    @Binding var selection: T
    let items: [T]
    let titleFor: (T) -> String
    var iconFor: ((T) -> String?)? = nil

    @State private var hoveredItem: T? = nil

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            liquidGlassBody
        } else {
            fallbackBody
        }
    }

    @available(macOS 26.0, *)
    private var liquidGlassBody: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(items) { item in
                    glassSegment(item)
                }
            }
            .padding(2.5)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private var fallbackBody: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                segmentButton(item)
                .background {
                    if selection == item {
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Capsule()
                                    .fill(OpenEQTheme.accentCyan.opacity(0.08))
                            }
                            .overlay {
                                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            }
                    } else if hoveredItem == item {
                        Capsule().fill(.ultraThinMaterial.opacity(0.45))
                    }
                }
            }
        }
        .padding(2.5)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
        }
    }

    @available(macOS 26.0, *)
    private func glassSegment(_ item: T) -> some View {
        segmentButton(item)
            .glassEffect(
                selection == item
                    ? .regular.tint(OpenEQTheme.accentCyan.opacity(0.18)).interactive()
                    : .clear.interactive(),
                in: .capsule
            )
    }

    private func segmentButton(_ item: T) -> some View {
        let isSelected = selection == item

        return Button {
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
        .onHover { isHovered in
            hoveredItem = isHovered ? item : nil
        }
        .accessibilityLabel(titleFor(item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
