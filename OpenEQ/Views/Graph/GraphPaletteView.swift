import SwiftUI

struct GraphPaletteView: View {
    @Bindable var store: GraphStore
    var processes: [AudioProcessInfo] = []
    var inputDevices: [AudioDevice] = []
    var outputDevices: [AudioDevice] = []
    var onOpenFile: (() -> Void)?

    var body: some View {
        List {
            Section {
                paletteButton(kind: .systemSource)
                paletteButton(kind: .appSource)
                paletteButton(kind: .inputSource)
                paletteButton(kind: .fileSource) {
                    onOpenFile?()
                    let id = store.addNode(kind: .fileSource, at: spawnPoint())
                    store.selectNode(id)
                }
            } header: {
                OpenEQSectionTitle(title: "Sources")
            }

            Section {
                paletteButton(kind: .equalizer)
                paletteButton(kind: .dynamics)
            } header: {
                OpenEQSectionTitle(title: "Processors")
            }

            Section {
                paletteButton(kind: .output)
                paletteButton(kind: .monitor)
            } header: {
                OpenEQSectionTitle(title: "Outputs")
            }

            if !processes.isEmpty {
                Section {
                    ForEach(processes.prefix(12)) { process in
                        Button {
                            let id = store.addNode(
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
                            store.selectNode(id)
                        } label: {
                            HStack(spacing: 8) {
                                if let icon = process.icon {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "app")
                                        .frame(width: 16)
                                }
                                Text(process.name)
                                    .lineLimit(1)
                                Spacer()
                                if process.isRunningOutput {
                                    Circle().fill(.green).frame(width: 6, height: 6)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    OpenEQSectionTitle(title: "Live Apps")
                }
            }

            Section {
                Button("Reset Graph") {
                    store.resetToStarter()
                }
                .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func paletteButton(kind: GraphNodeKind, action: (() -> Void)? = nil) -> some View {
        Button {
            if let action {
                action()
            } else {
                store.addNode(kind: kind, at: spawnPoint())
            }
        } label: {
            Label(kind.title, systemImage: kind.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .draggable(kind.rawValue) {
            Label(kind.title, systemImage: kind.systemImage)
                .padding(8)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
    }

    private func spawnPoint() -> CGPoint {
        let baseX: CGFloat = 120 + CGFloat(store.document.nodes.count % 4) * 28
        let baseY: CGFloat = 120 + CGFloat(store.document.nodes.count % 5) * 24
        return CGPoint(x: baseX, y: baseY)
    }
}
