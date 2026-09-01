import SwiftUI
import AppKit

struct HeadphoneLibraryView: View {
    @Bindable var viewModel: OpenEQViewModel
    @Binding var searchText: String

    private var filtered: [HeadphoneProfile] {
        viewModel.filteredHeadphoneProfiles(query: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if filtered.isEmpty {
                        Text(searchText.isEmpty ? "No profiles loaded" : "No matching models")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filtered.prefix(30)) { profile in
                            let selected = profile.id == viewModel.selectedHeadphoneProfileID

                            Button {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                    viewModel.applyHeadphoneProfile(profile)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "headphones")
                                        .font(.system(size: 11))
                                        .foregroundStyle(selected ? OpenEQTheme.accentCyan : .secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(profile.displayName)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(profile.target)
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)

                                    if selected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(OpenEQTheme.accentCyan)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    selected
                                        ? OpenEQTheme.accentCyan.opacity(0.12)
                                        : OpenEQTheme.recessedSlotBg.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selected ? OpenEQTheme.accentCyan.opacity(0.35) : .clear, lineWidth: 0.8)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(TactileButtonStyle())
                            .accessibilityValue(selected ? "Applied" : "Not applied")
                        }
                    }
                }
            }
            .frame(maxHeight: 140)

            Divider().opacity(0.15)

            HStack(spacing: 12) {
                Button {
                    viewModel.importCalibrationFile()
                } label: {
                    Label("Import AutoEQ / REW", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)

                Button {
                    if let url = URL(string: "https://autoeq.app") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("AutoEQ.app", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
                .help("Open autoeq.app in browser")
            }
            .font(.system(size: 11, weight: .medium))

            if let message = viewModel.calibrationImportMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { viewModel.loadHeadphoneCatalogIfNeeded() }
    }
}
