import SwiftUI

struct GraphCanvasView: View {
    @Bindable var store: GraphStore
    @Bindable var viewModel: OpenEQViewModel
    var runningNodeIDs: Set<UUID> = []

    /// Live drag — document is only written on mouse-up so the graph stays 60fps.
    @State private var nodeDrag: NodeDragSession?
    @State private var wireDrag: WireDragSession?
    @State private var panSession: PanSession?
    @State private var isCanvasFocused = false
    @State private var magnifyBase: CGFloat = 1
    @State private var pendingConnectionFrom: GraphPortID?

    private struct NodeDragSession: Equatable {
        let id: UUID
        let startOrigin: CGPoint
        var currentOrigin: CGPoint
    }

    private struct WireDragSession {
        let fromPort: GraphPortID
        let fromPoint: CGPoint
        var currentPoint: CGPoint
    }

    private struct PanSession {
        let startOffset: CGSize
    }

    private var livePositions: [UUID: CGPoint] {
        guard let nodeDrag else { return [:] }
        return [nodeDrag.id: nodeDrag.currentOrigin]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                OpenEQTheme.chassisBg
                    .ignoresSafeArea()

                // Document space lives inside the scaled/offset container.
                ZStack(alignment: .topLeading) {
                    GraphGridBackground(size: geo.size)
                        .contentShape(Rectangle())
                        .gesture(backgroundPanGesture)
                        .onTapGesture {
                            store.clearSelection()
                            viewModel.showGraphInspector = false
                            pendingConnectionFrom = nil
                            isCanvasFocused = true
                        }

                    GraphEdgeLayer(
                        document: store.document,
                        selectedEdgeIDs: store.selectedEdgeIDs,
                        draftFrom: wireDrag?.fromPoint,
                        draftTo: wireDrag?.currentPoint,
                        livePositions: livePositions,
                        store: store
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .allowsHitTesting(false)

                    ForEach(store.document.nodes) { node in
                        nodeLayer(node)
                    }

                    if store.document.nodes.isEmpty {
                        ContentUnavailableView {
                            Label("Empty Graph", systemImage: "point.3.connected.trianglepath.dotted")
                        } description: {
                            Text("Add sources from the bottom Nodes menu.")
                        } actions: {
                            Button("Starter") { store.resetToStarter() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .coordinateSpace(name: GraphCanvasSpace.document)
                .scaleEffect(store.canvasScale, anchor: .topLeading)
                .offset(store.canvasOffset)
            }
            .coordinateSpace(name: GraphCanvasSpace.viewport)
            .contentShape(Rectangle())
            .gesture(canvasMagnifyGesture)
            .onTapGesture(count: 2) { location in
                // location is in the post-transform view; convert to document.
                selectEdge(atDocumentPoint: viewToDocument(location))
            }
            .dropDestination(for: String.self) { items, location in
                guard let raw = items.first,
                      let kind = GraphNodeKind(rawValue: raw) else { return false }
                store.addNode(kind: kind, at: viewToDocument(location))
                return true
            }
            .focusable(isCanvasFocused)
            .focusEffectDisabled()
            .onKeyPress(.delete) {
                store.deleteSelection()
                return .handled
            }
            .onKeyPress(.init("\u{8}")) {
                store.deleteSelection()
                return .handled
            }
            .onKeyPress(.escape) {
                cancelLiveDrag()
                store.clearSelection()
                viewModel.showGraphInspector = false
                pendingConnectionFrom = nil
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "+=")) { _ in
                store.canvasScale = min(2.0, store.canvasScale + 0.1)
                magnifyBase = store.canvasScale
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "-_")) { _ in
                store.canvasScale = max(0.45, store.canvasScale - 0.1)
                magnifyBase = store.canvasScale
                return .handled
            }
            .onKeyPress(characters: CharacterSet(charactersIn: "0")) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                store.canvasScale = 1
                store.canvasOffset = .zero
                magnifyBase = 1
                return .handled
            }
            .onAppear { magnifyBase = store.canvasScale }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .clipped()
    }

    // MARK: - Nodes

    @ViewBuilder
    private func nodeLayer(_ node: GraphNode) -> some View {
        let origin = livePositions[node.id] ?? node.cgPosition
        let size = node.size
        let isDragging = nodeDrag?.id == node.id

        ZStack(alignment: .top) {
            GraphNodeView(
                node: node,
                isSelected: store.selectedNodeIDs.contains(node.id) || isDragging,
                isRunning: runningNodeIDs.contains(node.id),
                onInspect: {
                    store.selectNode(node.id)
                    viewModel.showGraphInspector = true
                }
            )
            .equatable()
            .contextMenu {
                Button {
                    store.selectNode(node.id)
                    viewModel.showGraphInspector = true
                } label: {
                    Label("Inspect Details...", systemImage: "slider.horizontal.3")
                }

                if case .equalizer(let eq) = node.config {
                    Button {
                        store.updateEqualizer(nodeID: node.id) { $0.isEnabled.toggle() }
                    } label: {
                        Label(eq.isEnabled ? "Bypass EQ" : "Enable EQ", systemImage: eq.isEnabled ? "power" : "power.circle")
                    }
                } else if case .dynamics(let dyn) = node.config {
                    Button {
                        var updated = dyn
                        updated.settings.isCompressorEnabled.toggle()
                        store.updateConfig(nodeID: node.id, config: .dynamics(updated))
                    } label: {
                        Label(dyn.settings.isCompressorEnabled ? "Bypass Compressor" : "Enable Compressor", systemImage: "waveform.path.ecg")
                    }
                }

                Button {
                    store.disconnectAll(nodeID: node.id)
                } label: {
                    Label("Disconnect Cables", systemImage: "cable.connector.slash")
                }

                Button {
                    if let newID = store.duplicateNode(node.id) {
                        store.selectNode(newID)
                    }
                } label: {
                    Label("Duplicate Node", systemImage: "plus.square.on.square")
                }

                Divider()

                Button(role: .destructive) {
                    store.removeNode(node.id)
                } label: {
                    Label("Delete Node", systemImage: "trash")
                }
            }
            .overlay(alignment: .leading) {
                if !node.kind.inputPortNames.isEmpty {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                        .highPriorityGesture(inputPortTapGesture(for: node))
                        .offset(x: -4)
                        .help("Click to connect")
                }
            }
            .overlay(alignment: .trailing) {
                if !node.kind.outputPortNames.isEmpty {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                        .highPriorityGesture(wireGesture(for: node))
                        .simultaneousGesture(outputPortTapGesture(for: node))
                        .offset(x: 4)
                        .help("Drag or click to connect")
                }
            }
            .gesture(nodeMoveGesture(for: node))
        }
        .frame(width: size.width, height: size.height)
        .position(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }

    private func nodeMoveGesture(for node: GraphNode) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(GraphCanvasSpace.document))
            .onChanged { value in
                isCanvasFocused = true
                // Tiny movement still counts as select; real drag starts after ~2pt.
                if nodeDrag == nil {
                    store.selectNode(node.id)
                }
                let dx = value.translation.width
                let dy = value.translation.height
                if nodeDrag == nil, hypot(dx, dy) < 2 {
                    return
                }
                if nodeDrag?.id != node.id {
                    nodeDrag = NodeDragSession(
                        id: node.id,
                        startOrigin: node.cgPosition,
                        currentOrigin: node.cgPosition
                    )
                }
                guard var session = nodeDrag, session.id == node.id else { return }
                // Translation is already in document space (pre-scale coordinate space).
                session.currentOrigin = CGPoint(
                    x: session.startOrigin.x + dx,
                    y: session.startOrigin.y + dy
                )
                nodeDrag = session
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // Pure click: already selected in onChanged.
                if nodeDrag == nil || hypot(dx, dy) < 2 {
                    nodeDrag = nil
                    return
                }
                guard let session = nodeDrag, session.id == node.id else {
                    nodeDrag = nil
                    return
                }
                store.moveNode(id: session.id, to: session.currentOrigin)
                store.finishMove()
                nodeDrag = nil
            }
    }

    private func wireGesture(for node: GraphNode) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(GraphCanvasSpace.document))
            .onChanged { value in
                let port = node.portID(name: "out")
                let origin = store.portPosition(port, livePositions: livePositions)
                    ?? CGPoint(
                        x: node.cgPosition.x + node.size.width,
                        y: node.cgPosition.y + node.size.height / 2
                    )
                // fromPoint stays fixed at the port; only the free end follows the cursor.
                let current = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                if let existing = wireDrag {
                    wireDrag = WireDragSession(
                        fromPort: existing.fromPort,
                        fromPoint: existing.fromPoint,
                        currentPoint: current
                    )
                } else {
                    wireDrag = WireDragSession(fromPort: port, fromPoint: origin, currentPoint: current)
                }
            }
            .onEnded { value in
                let port = node.portID(name: "out")
                let origin = wireDrag?.fromPoint
                    ?? store.portPosition(port, livePositions: livePositions)
                    ?? CGPoint(
                        x: node.cgPosition.x + node.size.width,
                        y: node.cgPosition.y + node.size.height / 2
                    )
                let end = CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height
                )
                if let target = hitInputPort(at: end) {
                    _ = store.connect(from: port, to: target)
                }
                pendingConnectionFrom = nil
                wireDrag = nil
            }
    }

    private func outputPortTapGesture(for node: GraphNode) -> some Gesture {
        TapGesture().onEnded {
            let port = node.portID(name: "out")
            pendingConnectionFrom = pendingConnectionFrom == port ? nil : port
            store.selectNode(node.id)
        }
    }

    private func inputPortTapGesture(for node: GraphNode) -> some Gesture {
        TapGesture().onEnded {
            guard let from = pendingConnectionFrom else {
                store.selectNode(node.id)
                return
            }
            _ = store.connect(from: from, to: node.portID(name: "in"))
            pendingConnectionFrom = nil
        }
    }

    // MARK: - Pan / zoom

    private var backgroundPanGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(GraphCanvasSpace.viewport))
            .onChanged { value in
                if panSession == nil {
                    panSession = PanSession(startOffset: store.canvasOffset)
                }
                guard let panSession else { return }
                // 1:1 pan — finger tracks the canvas exactly.
                store.canvasOffset = CGSize(
                    width: panSession.startOffset.width + value.translation.width,
                    height: panSession.startOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                panSession = nil
            }
    }

    private var canvasMagnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                store.canvasScale = min(2.0, max(0.45, magnifyBase * value))
            }
            .onEnded { _ in
                magnifyBase = store.canvasScale
            }
    }

    // MARK: - Helpers

    private func cancelLiveDrag() {
        nodeDrag = nil
        wireDrag = nil
        panSession = nil
        pendingConnectionFrom = nil
    }

    private func hitInputPort(at point: CGPoint) -> GraphPortID? {
        let radius: CGFloat = 24
        var best: (GraphPortID, CGFloat)?
        for node in store.document.nodes {
            for name in node.kind.inputPortNames {
                let port = node.portID(name: name)
                guard let pos = store.portPosition(port, livePositions: livePositions) else { continue }
                let d = hypot(pos.x - point.x, pos.y - point.y)
                if d <= radius, best == nil || d < best!.1 {
                    best = (port, d)
                }
            }
        }
        return best?.0
    }

    private func selectEdge(atDocumentPoint point: CGPoint) {
        for edge in store.document.edges {
            guard let from = store.portPosition(edge.from, livePositions: livePositions),
                  let to = store.portPosition(edge.to, livePositions: livePositions) else { continue }
            if GraphWirePath.hitTest(from: from, to: to, point: point, tolerance: 8) {
                store.selectEdge(edge.id)
                return
            }
        }
    }

    private func viewToDocument(_ location: CGPoint) -> CGPoint {
        let s = max(0.01, store.canvasScale)
        return CGPoint(
            x: (location.x - store.canvasOffset.width) / s,
            y: (location.y - store.canvasOffset.height) / s
        )
    }
}

private enum GraphCanvasSpace {
    static let document = "openeq.graph.document"
    static let viewport = "openeq.graph.viewport"
}

private struct GraphGridBackground: View {
    let size: CGSize

    var body: some View {
        Canvas { context, _ in
            let spacing = GraphTheme.gridSpacing
            let cols = Int(size.width / spacing) + 2
            let rows = Int(size.height / spacing) + 2
            var path = Path()
            for c in 0..<cols {
                for r in 0..<rows {
                    path.addEllipse(in: CGRect(
                        x: CGFloat(c) * spacing,
                        y: CGFloat(r) * spacing,
                        width: 1,
                        height: 1
                    ))
                }
            }
            context.fill(path, with: .color(.primary.opacity(0.07)))
        }
        .background(OpenEQTheme.chassisBg)
    }
}
