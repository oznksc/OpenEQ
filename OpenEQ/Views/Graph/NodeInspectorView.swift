import SwiftUI

struct NodeInspectorView: View {
    @Bindable var store: GraphStore
    @Bindable var viewModel: OpenEQViewModel
    var targetNodeID: UUID? = nil
    var onClose: (() -> Void)? = nil

    private var activeNode: GraphNode? {
        if let targetNodeID {
            return store.document.node(id: targetNodeID)
        }
        return store.selectedNode
    }

    var body: some View {
        Group {
            if let node = activeNode {
                VStack(alignment: .leading, spacing: 12) {
                    header(node)
                    Divider().opacity(0.12)

                    if case .equalizer = node.config {
                        ScrollView {
                            content(for: node)
                        }
                        .frame(maxHeight: 280)
                    } else {
                        content(for: node)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("Select a node to edit its settings.")
                )
                .padding(14)
            }
        }
    }

    private func header(_ node: GraphNode) -> some View {
        HStack(spacing: 10) {
            Image(systemName: node.kind.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GraphTheme.accent(for: node.kind))
                .frame(width: 26, height: 26)
                .background(GraphTheme.accent(for: node.kind).opacity(0.15), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(.system(size: 13, weight: .bold))
                Text(node.kind.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func content(for node: GraphNode) -> some View {
        switch node.config {
        case .equalizer(let eq):
            equalizerInspector(nodeID: node.id, eq: eq)
        case .appSource(let app):
            appSourceInspector(nodeID: node.id, app: app)
        case .systemSource:
            systemSourceInspector()
        case .inputSource(let input):
            inputSourceInspector(nodeID: node.id, input: input)
        case .fileSource:
            fileSourceInspector()
        case .output(let output):
            outputInspector(nodeID: node.id, output: output)
        case .dynamics(let dyn):
            dynamicsInspector(nodeID: node.id, dyn: dyn)
        case .monitor:
            Text("Attaches analysis only. Does not change the audio path.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func equalizerInspector(nodeID: UUID, eq: GraphNodeConfig.EqualizerConfig) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("EQ Enabled", isOn: Binding(
                get: { eq.isEnabled },
                set: { enabled in
                    store.updateEqualizer(nodeID: nodeID) { $0.isEnabled = enabled }
                    syncLegacyEQ(from: store.document.node(id: nodeID))
                }
            ))
            .toggleStyle(.switch)

            StudioSegmentedPicker(
                selection: Binding(
                    get: { eq.mode },
                    set: { mode in
                        store.updateEqualizer(nodeID: nodeID) { $0.mode = mode }
                        syncLegacyEQ(from: store.document.node(id: nodeID))
                    }
                ),
                items: EQMode.allCases,
                titleFor: { $0.title }
            )

            EQCurveView(
                bands: eq.bands,
                mode: eq.mode,
                preamp: eq.preamp,
                selectedBandID: viewModel.selectedBandID,
                isInteractive: eq.isEnabled,
                onSelectBand: { viewModel.selectBand(id: $0) },
                onBandChanged: { index, band in
                    store.updateEqualizer(nodeID: nodeID) { config in
                        guard config.bands.indices.contains(index) else { return }
                        config.bands[index] = band
                        config.presetName = "Custom"
                    }
                    syncLegacyEQ(from: store.document.node(id: nodeID))
                }
            )
            .frame(height: 160)

            HStack {
                Text("Preamp")
                Slider(
                    value: Binding(
                        get: { Double(eq.preamp) },
                        set: { value in
                            store.updateEqualizer(nodeID: nodeID) {
                                $0.preamp = Float(value)
                                $0.presetName = "Custom"
                            }
                            syncLegacyEQ(from: store.document.node(id: nodeID))
                        }
                    ),
                    in: Double(EQBand.gainRange.lowerBound)...Double(EQBand.gainRange.upperBound)
                )
                Text(String(format: "%+.1f dB", eq.preamp))
                    .font(.caption.monospacedDigit())
                    .frame(width: 64, alignment: .trailing)
            }

            if eq.mode == .graphic {
                graphicBandList(nodeID: nodeID, bands: eq.bands)
            } else {
                Text("Drag nodes on the curve · scroll for Q in the main parametric editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func graphicBandList(nodeID: UUID, bands: [EQBand]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(bands.enumerated()), id: \.element.id) { index, band in
                HStack {
                    Text(band.label)
                        .font(.caption.monospaced())
                        .frame(width: 48, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(band.gain) },
                            set: { value in
                                store.updateEqualizer(nodeID: nodeID) { config in
                                    guard config.bands.indices.contains(index) else { return }
                                    config.bands[index].gain = Float(value)
                                    config.presetName = "Custom"
                                }
                                syncLegacyEQ(from: store.document.node(id: nodeID))
                            }
                        ),
                        in: Double(EQBand.gainRange.lowerBound)...Double(EQBand.gainRange.upperBound)
                    )
                    Text(String(format: "%+.0f", band.gain))
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
    }

    private func systemSourceInspector() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Experimental · System-wide", systemImage: "waveform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)

            Text("Captures all system audio (except OpenEQ) with a Core Audio process tap. Requires Screen & System Audio Recording permission. Press Run Graph to apply.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if viewModel.isSystemEQActive {
                Text("Live — rewiring the graph restarts the chain automatically.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func appSourceInspector(nodeID: UUID, app: GraphNodeConfig.AppSourceConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Experimental · Per-app output", systemImage: "app.badge")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.cyan)

            Text("Routes this app’s output through OpenEQ. Other apps keep their normal path when the system allows. Requires Screen & System Audio Recording.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if !viewModel.audioProcesses.isEmpty {
                Picker("Application", selection: Binding(
                    get: { app.bundleID ?? (app.pid.map { "pid-\($0)" } ?? "") },
                    set: { key in
                        guard let process = viewModel.audioProcesses.first(where: {
                            ($0.bundleID ?? "pid-\($0.pid)") == key
                        }) else { return }
                        store.updateConfig(
                            nodeID: nodeID,
                            config: .appSource(
                                .init(
                                    bundleID: process.bundleID,
                                    processObjectID: process.objectID,
                                    displayName: process.name,
                                    pid: process.pid
                                )
                            )
                        )
                    }
                )) {
                    Text("Select…").tag("")
                    ForEach(viewModel.audioProcesses) { process in
                        Text(process.name).tag(process.bundleID ?? "pid-\(process.pid)")
                    }
                }

                Button("Refresh App List") {
                    viewModel.refreshAudioProcesses()
                }
                .buttonStyle(.bordered)
            } else {
                Text(app.displayName)
                    .font(.body.weight(.medium))
                Text("Launch apps that play audio, then refresh the list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Refresh App List") {
                    viewModel.refreshAudioProcesses()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func inputSourceInspector(nodeID: UUID, input: GraphNodeConfig.InputSourceConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Monitor path · not a virtual mic", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)

            Text("Equalizes the selected microphone and plays it to the Output node so you can hear it. Apps like Teams or Zoom cannot select OpenEQ as their input until a virtual audio device ships.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Picker("Input Device", selection: Binding(
                get: { input.deviceUID ?? "" },
                set: { uid in
                    let device = viewModel.availableInputDevices.first { ($0.uid ?? $0.profileKey) == uid }
                    store.updateConfig(
                        nodeID: nodeID,
                        config: .inputSource(
                            .init(
                                deviceUID: device?.uid ?? device?.profileKey,
                                deviceName: device?.name ?? "Default Input"
                            )
                        )
                    )
                }
            )) {
                Text("System Default").tag("")
                ForEach(viewModel.availableInputDevices) { device in
                    Text(device.name).tag(device.uid ?? device.profileKey)
                }
            }
        }
    }

    private func fileSourceInspector() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.selectedFileName)
                .font(.body.weight(.medium))
            Button("Open Audio File…") {
                viewModel.openAudioFile()
            }
            .buttonStyle(.borderedProminent)
            if viewModel.selectedFileURL != nil {
                Text("Wire File → Equalizer → Output to hear local playback through the graph.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func outputInspector(nodeID: UUID, output: GraphNodeConfig.OutputConfig) -> some View {
        Picker("Output Device", selection: Binding(
            get: { output.deviceUID ?? "" },
            set: { uid in
                let device = viewModel.availableOutputDevices.first { ($0.uid ?? $0.profileKey) == uid }
                store.updateConfig(
                    nodeID: nodeID,
                    config: .output(
                        .init(
                            deviceUID: device?.uid ?? device?.profileKey,
                            deviceName: device?.name ?? "System Default"
                        )
                    )
                )
            }
        )) {
            Text("System Default").tag("")
            ForEach(viewModel.availableOutputDevices) { device in
                Text(device.name).tag(device.uid ?? device.profileKey)
            }
        }
    }

    private func dynamicsInspector(nodeID: UUID, dyn: GraphNodeConfig.DynamicsConfig) -> some View {
        Toggle("Compressor", isOn: Binding(
            get: { dyn.settings.isCompressorEnabled },
            set: { enabled in
                var settings = dyn.settings
                settings.isCompressorEnabled = enabled
                store.updateConfig(nodeID: nodeID, config: .dynamics(.init(settings: settings)))
                viewModel.setCompressorEnabled(enabled)
            }
        ))
    }

    private func syncLegacyEQ(from node: GraphNode?) {
        guard let node, case .equalizer(let eq) = node.config else { return }
        viewModel.applyGraphEqualizer(eq)
    }
}
