import Foundation

enum GraphValidationIssue: Equatable {
    case cycle
    case multipleProcessSources
    case fanIn(nodeID: UUID, title: String)
    case danglingEdge(edgeID: UUID)
    case typeMismatch(edgeID: UUID)
    case noRunnableChain

    var message: String {
        switch self {
        case .cycle:
            return "Graph contains a cycle."
        case .multipleProcessSources:
            return "Only one System/App audio chain can run at a time."
        case .fanIn(_, let title):
            return "“\(title)” can only accept one input in v1."
        case .danglingEdge:
            return "A connection points to a missing node or port."
        case .typeMismatch:
            return "Invalid connection between these ports."
        case .noRunnableChain:
            return "Connect a source through Equalizer to Output to run."
        }
    }
}

struct GraphChain: Equatable {
    enum SourceKind: Equatable {
        case system
        case app
        case input
        case file
    }

    var sourceID: UUID
    var sourceKind: SourceKind
    var equalizerID: UUID?
    var dynamicsID: UUID?
    var outputID: UUID
    var nodeIDs: [UUID]
}

enum GraphValidation {
    static func issues(in document: GraphDocument) -> [GraphValidationIssue] {
        var issues: [GraphValidationIssue] = []

        let nodeIDs = Set(document.nodes.map(\.id))
        for edge in document.edges {
            guard nodeIDs.contains(edge.from.nodeID), nodeIDs.contains(edge.to.nodeID) else {
                issues.append(.danglingEdge(edgeID: edge.id))
                continue
            }
            guard let fromNode = document.node(id: edge.from.nodeID),
                  let toNode = document.node(id: edge.to.nodeID) else {
                issues.append(.danglingEdge(edgeID: edge.id))
                continue
            }
            if !fromNode.kind.outputPortNames.contains(edge.from.name)
                || !toNode.kind.inputPortNames.contains(edge.to.name) {
                issues.append(.typeMismatch(edgeID: edge.id))
            }
        }

        if hasCycle(document) {
            issues.append(.cycle)
        }

        var incoming: [UUID: Int] = [:]
        for edge in document.edges {
            incoming[edge.to.nodeID, default: 0] += 1
        }
        for node in document.nodes where (incoming[node.id] ?? 0) > 1 {
            if node.kind == .equalizer || node.kind == .dynamics || node.kind == .output {
                issues.append(.fanIn(nodeID: node.id, title: node.title))
            }
        }

        let processSources = document.nodes.filter {
            $0.kind == .appSource || $0.kind == .systemSource
        }
        let processChains = compileChains(document).filter {
            $0.sourceKind == .app || $0.sourceKind == .system
        }
        if processChains.count > 1 || (processSources.count > 1 && processChains.count > 1) {
            issues.append(.multipleProcessSources)
        }

        if compileChains(document).isEmpty {
            issues.append(.noRunnableChain)
        }

        return issues
    }

    static func compileChains(_ document: GraphDocument) -> [GraphChain] {
        let sources = document.nodes.filter(\.kind.isSource)
        var chains: [GraphChain] = []

        for source in sources {
            var path: [UUID] = [source.id]
            var current = source.id
            var equalizerID: UUID?
            var dynamicsID: UUID?
            var outputID: UUID?
            var visited = Set<UUID>([source.id])

            while let nextEdge = document.edges.first(where: { $0.from.nodeID == current }),
                  let next = document.node(id: nextEdge.to.nodeID),
                  !visited.contains(next.id) {
                visited.insert(next.id)
                path.append(next.id)
                switch next.kind {
                case .equalizer:
                    equalizerID = next.id
                case .dynamics:
                    dynamicsID = next.id
                case .output:
                    outputID = next.id
                case .monitor:
                    break
                default:
                    break
                }
                current = next.id
                if next.kind == .output { break }
            }

            guard let outputID else { continue }

            let sourceKind: GraphChain.SourceKind
            switch source.kind {
            case .systemSource: sourceKind = .system
            case .appSource: sourceKind = .app
            case .inputSource: sourceKind = .input
            case .fileSource: sourceKind = .file
            default: continue
            }

            chains.append(
                GraphChain(
                    sourceID: source.id,
                    sourceKind: sourceKind,
                    equalizerID: equalizerID,
                    dynamicsID: dynamicsID,
                    outputID: outputID,
                    nodeIDs: path
                )
            )
        }

        return chains
    }

    static func canConnect(
        from: GraphPortID,
        to: GraphPortID,
        in document: GraphDocument
    ) -> Bool {
        guard from.nodeID != to.nodeID else { return false }
        guard let fromNode = document.node(id: from.nodeID),
              let toNode = document.node(id: to.nodeID) else {
            return false
        }
        guard fromNode.kind.outputPortNames.contains(from.name),
              toNode.kind.inputPortNames.contains(to.name) else {
            return false
        }
        if document.edges.contains(where: { $0.to == to }) {
            return false
        }
        var probe = document
        probe.edges.append(GraphEdge(from: from, to: to))
        return !hasCycle(probe)
    }

    private static func hasCycle(_ document: GraphDocument) -> Bool {
        var adj: [UUID: [UUID]] = [:]
        for edge in document.edges {
            adj[edge.from.nodeID, default: []].append(edge.to.nodeID)
        }

        var visiting = Set<UUID>()
        var visited = Set<UUID>()

        func dfs(_ node: UUID) -> Bool {
            if visiting.contains(node) { return true }
            if visited.contains(node) { return false }
            visiting.insert(node)
            for next in adj[node, default: []] {
                if dfs(next) { return true }
            }
            visiting.remove(node)
            visited.insert(node)
            return false
        }

        for node in document.nodes {
            if dfs(node.id) { return true }
        }
        return false
    }
}
