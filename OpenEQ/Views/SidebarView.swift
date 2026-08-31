import SwiftUI

/// Palette-first sidebar — fixed column width; content must not force horizontal growth.
struct SidebarView: View {
    @Bindable var viewModel: OpenEQViewModel
    @State private var headphoneQuery = ""
    @State private var showLibrary = false

    private var graphStore: GraphStore { viewModel.graphStore }

    var body: some View {
        List {
            Section("Sources") {
                paletteRow(.systemSource)
                paletteRow(.appSource)
                paletteRow(.inputSource)
                Button {
                    viewModel.openAudioFile()
                    _ = graphStore.addNode(kind: .fileSource, at: spawnPoint())
                } label: {
                    Label("File", systemImage: GraphNodeKind.fileSource.systemImage)
                }
                .buttonStyle(.plain)
            }

            Section("Process") {
                paletteRow(.equalizer)
                paletteRow(.dynamics)
                paletteRow(.output)
            }

            if !viewModel.audioProcesses.isEmpty {
                Section("Apps") {
                    ForEach(viewModel.audioProcesses.prefix(10)) { process in
                        Button {
                            let id = graphStore.addNode(
                                kind: .appSource,
                                at: spawnPoint(),
                                title: process.name,
                                config: .appSource(
                                    .init(
                                        bundleID: process.bundleID,
                                        processObjectID: process.objectID,
                                        displayName: process.name,
                                        pid: process.pid
                                    )
                                )
                            )
                            graphStore.selectNode(id)
                            viewModel.showGraphInspector = true
                        } label: {
                            HStack(spacing: 8) {
                                if let icon = process.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .interpolation(.medium)
                                        .frame(width: 16, height: 16)
                                        .cornerRadius(3)
                                } else {
                                    Image(systemName: "app.fill")
                                        .font(.caption)
                                        .frame(width: 16)
                                }
                                Text(process.name)
                                    .font(.body)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                                if process.isRunningOutput {
                                    Circle().fill(.green).frame(width: 6, height: 6)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                DisclosureGroup("Library", isExpanded: $showLibrary) {
                    PresetPanelView(viewModel: viewModel)
                        .padding(.vertical, 4)
                    HeadphoneLibraryView(viewModel: viewModel, searchText: $headphoneQuery)
                        .padding(.vertical, 4)
                    DynamicsPanelView(viewModel: viewModel)
                        .padding(.vertical, 4)
                    AUv3PanelView(viewModel: viewModel)
                        .padding(.vertical, 4)
                }
            }

            Section {
                Button("Reset Graph") {
                    graphStore.resetToStarter()
                }
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        // Clip horizontal growth from long app names / nested panels.
        .frame(maxWidth: .infinity, alignment: .leading)
        .navigationTitle("OpenEQ")
        .searchable(text: $headphoneQuery, placement: .sidebar, prompt: "Headphones")
        .onAppear {
            viewModel.refreshAudioProcesses()
        }
    }

    private func paletteRow(_ kind: GraphNodeKind) -> some View {
        Button {
            let id = graphStore.addNode(kind: kind, at: spawnPoint())
            graphStore.selectNode(id)
            viewModel.showGraphInspector = true
        } label: {
            Label(kind.title, systemImage: kind.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .draggable(kind.rawValue) {
            Label(kind.title, systemImage: kind.systemImage)
                .padding(8)
        }
        .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
    }

    private func spawnPoint() -> CGPoint {
        let n = graphStore.document.nodes.count
        return CGPoint(x: 72 + CGFloat(n % 4) * 24, y: 72 + CGFloat(n % 5) * 22)
    }
}
