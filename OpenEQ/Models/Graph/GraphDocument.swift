import Foundation
import CoreGraphics

struct GraphDocument: Codable, Equatable {
    var nodes: [GraphNode]
    var edges: [GraphEdge]
    var schemaVersion: Int

    static let currentSchemaVersion = 1

    init(
        nodes: [GraphNode] = [],
        edges: [GraphEdge] = [],
        schemaVersion: Int = GraphDocument.currentSchemaVersion
    ) {
        self.nodes = nodes
        self.edges = edges
        self.schemaVersion = schemaVersion
    }

    func node(id: UUID) -> GraphNode? {
        nodes.first { $0.id == id }
    }

    mutating func updateNode(id: UUID, _ body: (inout GraphNode) -> Void) {
        guard let index = nodes.firstIndex(where: { $0.id == id }) else { return }
        body(&nodes[index])
    }

    func edges(from nodeID: UUID) -> [GraphEdge] {
        edges.filter { $0.from.nodeID == nodeID }
    }

    func edges(to nodeID: UUID) -> [GraphEdge] {
        edges.filter { $0.to.nodeID == nodeID }
    }

    /// Default workspace: System Audio → EQ → Output, plus a File source ready to wire.
    static func starterTemplate() -> GraphDocument {
        let systemID = UUID()
        let eqID = UUID()
        let outputID = UUID()
        let fileID = UUID()

        let system = GraphNode(
            id: systemID,
            kind: .systemSource,
            title: "System Audio",
            position: CGPoint(x: 64, y: 140)
        )
        let eq = GraphNode(
            id: eqID,
            kind: .equalizer,
            title: "Equalizer",
            position: CGPoint(x: 300, y: 120)
        )
        let output = GraphNode(
            id: outputID,
            kind: .output,
            title: "Speakers",
            position: CGPoint(x: 560, y: 140)
        )
        let file = GraphNode(
            id: fileID,
            kind: .fileSource,
            title: "File",
            position: CGPoint(x: 64, y: 260)
        )

        let edges = [
            GraphEdge(
                from: GraphPortID(nodeID: systemID, name: "out"),
                to: GraphPortID(nodeID: eqID, name: "in")
            ),
            GraphEdge(
                from: GraphPortID(nodeID: eqID, name: "out"),
                to: GraphPortID(nodeID: outputID, name: "in")
            )
        ]

        return GraphDocument(nodes: [system, eq, output, file], edges: edges)
    }
}
