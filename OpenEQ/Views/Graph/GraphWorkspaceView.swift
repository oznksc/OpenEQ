import SwiftUI
import Combine

struct GraphWorkspaceView: View {
    @Bindable var viewModel: OpenEQViewModel
    @Bindable var store: GraphStore

    /// Display-throttled levels so audio analysis does not invalidate the canvas every buffer.
    @State private var displayLeft: Float = 0
    @State private var displayRight: Float = 0

    var body: some View {
        VStack(spacing: 0) {
            // Canvas intentionally does NOT take live levels — keeps node tree stable.
            GraphCanvasView(
                store: store,
                runningNodeIDs: viewModel.runningGraphNodeIDs
            )
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .layoutPriority(1)

            statusBar

            if shouldShowPlayer {
                PlayerControlsView(viewModel: viewModel)
                    .padding(.horizontal, OpenEQTheme.pagePadding)
                    .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        // ~12 Hz UI sample of meters (status bar only).
        .onReceive(Timer.publish(every: 1.0 / 12.0, on: .main, in: .common).autoconnect()) { _ in
            let l = quantize(viewModel.leftLevel)
            let r = quantize(viewModel.rightLevel)
            if l != displayLeft { displayLeft = l }
            if r != displayRight { displayRight = r }
        }
    }

    private var shouldShowPlayer: Bool {
        viewModel.selectedFileURL != nil
            || store.selectedNode?.kind == .fileSource
            || store.document.nodes.contains { $0.kind == .fileSource && viewModel.selectedFileURL != nil }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            OpenEQStatusDot(kind: statusKind, size: 7)
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let issue = store.lastValidationIssues.first(where: {
                if case .noRunnableChain = $0 { return false }
                return true
            }) {
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isRunning {
                CompactLevelMeter(left: displayLeft, right: displayRight)
                if let latency = viewModel.systemAudioLatency ?? viewModel.externalLoopbackLatency {
                    Text(String(format: "%.0f ms", latency * 1000))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            Text("\(store.runnableChainCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .help("Runnable chains")
        }
        .padding(.horizontal, OpenEQTheme.pagePadding)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var isRunning: Bool {
        viewModel.isSystemEQActive || viewModel.isExternalLoopbackActive
    }

    private var statusText: String {
        if viewModel.didTripFeedbackProtection { return "Feedback" }
        if let label = viewModel.graphRuntimeLabel, isRunning { return label }
        if viewModel.isSystemEQActive { return "System EQ" }
        if viewModel.isExternalLoopbackActive { return "Mic monitor" }
        if case .playing = viewModel.playbackState { return "Playing" }
        if store.runnableChainCount == 0 { return "Wire a chain" }
        return "Ready"
    }

    private var statusKind: OpenEQStatusDot.Kind {
        if viewModel.didTripFeedbackProtection { return .warning }
        if isRunning { return .active }
        if case .playing = viewModel.playbackState { return .active }
        if store.runnableChainCount == 0 { return .idle }
        return .ready
    }

    /// 1/16 steps — fewer SwiftUI identity changes under live audio.
    private func quantize(_ value: Float) -> Float {
        (value * 16).rounded() / 16
    }
}
