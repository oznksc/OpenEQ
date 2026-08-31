import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
final class GraphStore {
    var document: GraphDocument
    var selectedNodeIDs: Set<UUID> = []
    var selectedEdgeIDs: Set<UUID> = []
    var canvasOffset: CGSize = .zero
    var canvasScale: CGFloat = 1.0
    var lastValidationIssues: [GraphValidationIssue] = []
    /// Cached on revalidate — avoid recompiling chains every SwiftUI body pass.
    private(set) var runnableChains: [GraphChain] = []
    private(set) var runnableChainCount: Int = 0
    var isDirty = false
    /// Fired when connections, source/output config, or node membership change (not EQ slider drags).
    var onTopologyChanged: (() -> Void)?

    private let fileManager = FileManager.default
    private let logger = AppLogger(category: "GraphStore")
    private var saveTask: Task<Void, Never>?

    var selectedNode: GraphNode? {
        guard let id = selectedNodeIDs.first else { return nil }
        return document.node(id: id)
    }

    init(document: GraphDocument? = nil) {
        if let document {
            self.document = document
        } else if let loaded = Self.loadFromDisk() {
            self.document = loaded
        } else {
            self.document = .starterTemplate()
        }
        revalidate()
    }

    // MARK: - Selection

    func selectNode(_ id: UUID?, exclusive: Bool = true) {
        if exclusive {
            selectedNodeIDs = id.map { [$0] } ?? []
            selectedEdgeIDs = []
        } else if let id {
            if selectedNodeIDs.contains(id) {
                selectedNodeIDs.remove(id)
            } else {
                selectedNodeIDs.insert(id)
            }
        }
    }

    func selectEdge(_ id: UUID?) {
        selectedEdgeIDs = id.map { [$0] } ?? []
        selectedNodeIDs = []
    }

    func clearSelection() {
        selectedNodeIDs = []
        selectedEdgeIDs = []
    }

    // MARK: - Mutations

    @discardableResult
    func addNode(kind: GraphNodeKind, at position: CGPoint, title: String? = nil, config: GraphNodeConfig? = nil) -> UUID {
        let node = GraphNode(kind: kind, title: title, position: position, config: config)
        document.nodes.append(node)
        selectNode(node.id)
        markDirty(topologyChanged: true)
        return node.id
    }

    /// Lightweight position write during/after drag — no revalidate, no topology callback.
    func moveNode(id: UUID, to position: CGPoint) {
        guard let index = document.nodes.firstIndex(where: { $0.id == id }) else { return }
        let snapped = CGPoint(
            x: position.x.rounded(),
            y: position.y.rounded()
        )
        let current = document.nodes[index].cgPosition
        if abs(current.x - snapped.x) < 0.5, abs(current.y - snapped.y) < 0.5 {
            return
        }
        document.nodes[index].cgPosition = snapped
    }

    func finishMove() {
        isDirty = true
        scheduleSave()
    }

    /// Port location in document space, optionally overriding a node’s live drag position.
    func portPosition(_ port: GraphPortID, livePositions: [UUID: CGPoint] = [:]) -> CGPoint? {
        guard let node = document.node(id: port.nodeID) else { return nil }
        let origin = livePositions[node.id] ?? node.cgPosition
        let frame = CGRect(origin: origin, size: node.size)
        let isOutput = node.kind.outputPortNames.contains(port.name)
        return CGPoint(x: isOutput ? frame.maxX : frame.minX, y: frame.midY)
    }

    func updateConfig(nodeID: UUID, config: GraphNodeConfig) {
        document.updateNode(id: nodeID) { node in
            node.config = config
            if case .appSource(let app) = config {
                node.title = app.displayName
            } else if case .inputSource(let input) = config {
                node.title = input.deviceName
            } else if case .output(let output) = config {
                node.title = output.deviceName
            }
        }
        // Source / output routing changes require engine rebuild when running.
        let topology = document.node(id: nodeID).map {
            $0.kind.isSource || $0.kind == .output || $0.kind == .dynamics
        } ?? true
        markDirty(topologyChanged: topology)
    }

    func updateEqualizer(nodeID: UUID, _ body: (inout GraphNodeConfig.EqualizerConfig) -> Void) {
        document.updateNode(id: nodeID) { node in
            guard case .equalizer(var eq) = node.config else { return }
            body(&eq)
            node.config = .equalizer(eq)
        }
        markDirty(topologyChanged: false)
    }

    @discardableResult
    func connect(from: GraphPortID, to: GraphPortID) -> Bool {
        guard GraphValidation.canConnect(from: from, to: to, in: document) else {
            return false
        }
        document.edges.append(GraphEdge(from: from, to: to))
        markDirty(topologyChanged: true)
        return true
    }

    func disconnect(edgeID: UUID) {
        document.edges.removeAll { $0.id == edgeID }
        selectedEdgeIDs.remove(edgeID)
        markDirty(topologyChanged: true)
    }

    func deleteSelection() {
        if !selectedEdgeIDs.isEmpty {
            document.edges.removeAll { selectedEdgeIDs.contains($0.id) }
            selectedEdgeIDs = []
            markDirty(topologyChanged: true)
            return
        }
        guard !selectedNodeIDs.isEmpty else { return }
        let remove = selectedNodeIDs
        document.nodes.removeAll { remove.contains($0.id) }
        document.edges.removeAll {
            remove.contains($0.from.nodeID) || remove.contains($0.to.nodeID)
        }
        selectedNodeIDs = []
        markDirty(topologyChanged: true)
    }

    func resetToStarter() {
        document = .starterTemplate()
        clearSelection()
        markDirty(topologyChanged: true)
    }

    func applyPreset(_ preset: EQPreset, to nodeID: UUID? = nil) {
        let targetID = nodeID
            ?? selectedNodeIDs.first(where: { document.node(id: $0)?.kind == .equalizer })
            ?? document.nodes.first(where: { $0.kind == .equalizer })?.id
        guard let targetID else { return }
        updateEqualizer(nodeID: targetID) { eq in
            eq.mode = preset.mode
            eq.bands = preset.bands
            eq.preamp = preset.preamp
            eq.presetName = preset.name
            eq.isEnabled = true
        }
        selectNode(targetID)
    }

    // MARK: - Validation / persistence

    func revalidate() {
        lastValidationIssues = GraphValidation.issues(in: document)
        runnableChains = GraphValidation.compileChains(document)
        runnableChainCount = runnableChains.count
    }

    private func markDirty(autosave: Bool = true, topologyChanged: Bool = false) {
        isDirty = true
        revalidate()
        if autosave {
            scheduleSave()
        }
        if topologyChanged {
            onTopologyChanged?()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            self.saveToDisk()
        }
    }

    func saveToDisk() {
        guard let url = Self.graphFileURL() else { return }
        do {
            let data = try JSONEncoder().encode(document)
            try data.write(to: url, options: .atomic)
            isDirty = false
            logger.info("Graph saved (\(document.nodes.count) nodes).")
        } catch {
            logger.error("Failed to save graph: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk() -> GraphDocument? {
        guard let url = graphFileURL(),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(GraphDocument.self, from: data)
        } catch {
            return nil
        }
    }

    private static func graphFileURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent("OpenEQ/graphs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("default.json")
    }

    // MARK: - Geometry helpers

    func nodeFrame(_ node: GraphNode) -> CGRect {
        CGRect(origin: node.cgPosition, size: node.size)
    }
}
