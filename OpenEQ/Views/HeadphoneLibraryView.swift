import SwiftUI
import AppKit

struct HeadphoneLibraryView: View {
    @Bindable var viewModel: OpenEQViewModel
    @Binding var searchText: String

    private var filtered: [HeadphoneProfile] {
        viewModel.filteredHeadphoneProfiles(query: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        Text(searchText.isEmpty ? "No profiles" : "No matches")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(filtered.prefix(30)) { profile in
                            Button {
                                viewModel.applyHeadphoneProfile(profile)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(profile.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(profile.target)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 140)

            HStack(spacing: 16) {
                Button("Import AutoEQ / REW") {
                    viewModel.importCalibrationFile()
                }
                .buttonStyle(.borderless)

                Button {
                    if let url = URL(string: "https://autoeq.app") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.borderless)
                .help("autoeq.app")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

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
