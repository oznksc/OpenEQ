import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct HeadphoneLibraryView: View {
    @Bindable var viewModel: OpenEQViewModel
    @State private var searchText = ""

    private var filtered: [HeadphoneProfile] {
        viewModel.filteredHeadphoneProfiles(query: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Headphone EQ", systemImage: "headphones")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(filtered.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextField("Search headphones…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            Text("Curated AutoEQ-style starters. Import measurement-accurate files from AutoEQ or REW for best results.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(filtered.prefix(40)) { profile in
                        Button {
                            viewModel.applyHeadphoneProfile(profile)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(profile.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(profile.target) · \(profile.source)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.03))
                        )
                    }
                }
            }
            .frame(maxHeight: 160)

            HStack(spacing: 8) {
                Button {
                    viewModel.importCalibrationFile()
                } label: {
                    Label("Import AutoEQ / REW", systemImage: "square.and.arrow.down")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    if let url = URL(string: "https://autoeq.app") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open autoeq.app for full database")
            }

            if let message = viewModel.calibrationImportMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .cornerRadius(10)
        .onAppear {
            viewModel.loadHeadphoneCatalogIfNeeded()
        }
    }
}
