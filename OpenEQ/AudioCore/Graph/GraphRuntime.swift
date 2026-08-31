import Foundation
import Observation

/// Compiles a `GraphDocument` into live audio sessions (process tap / input monitor).
/// v1: one process chain OR one input monitor chain (exclusive); file uses the local engine.
@MainActor
@Observable
final class GraphRuntime {
    private(set) var isRunning = false
    private(set) var activeNodeIDs: Set<UUID> = []
    private(set) var activePathDescription: String?
    private(set) var lastError: String?

    enum RunKind: Equatable {
        case process(ProcessTapTarget, outputUID: String?, label: String)
        case input(inputUID: String?, outputUID: String?, label: String)
    }

    /// Chooses the primary runnable chain from the document.
    /// Prefers app/system process chains over input monitor.
    static func preferredRun(from document: GraphDocument) -> (chain: GraphChain, kind: RunKind)? {
        let chains = GraphValidation.compileChains(document)
        if let process = chains.first(where: { $0.sourceKind == .system || $0.sourceKind == .app }) {
            if let kind = resolveProcessKind(chain: process, document: document) {
                return (process, kind)
            }
        }
        if let input = chains.first(where: { $0.sourceKind == .input }) {
            if let kind = resolveInputKind(chain: input, document: document) {
                return (input, kind)
            }
        }
        return nil
    }

    static func resolveProcessKind(chain: GraphChain, document: GraphDocument) -> RunKind? {
        guard let source = document.node(id: chain.sourceID) else { return nil }
        let outputUID = outputUID(from: document, chain: chain)

        switch source.config {
        case .systemSource:
            return .process(.systemExcludingSelf, outputUID: outputUID, label: "System Audio")
        case .appSource(let app):
            if let bundle = app.bundleID, !bundle.isEmpty {
                return .process(.bundleIDs([bundle]), outputUID: outputUID, label: app.displayName)
            }
            if let objectID = app.processObjectID, objectID != 0 {
                return .process(.processes([objectID]), outputUID: outputUID, label: app.displayName)
            }
            return nil
        default:
            return nil
        }
    }

    static func resolveInputKind(chain: GraphChain, document: GraphDocument) -> RunKind? {
        guard let source = document.node(id: chain.sourceID),
              case .inputSource(let input) = source.config else {
            return nil
        }
        let outputUID = outputUID(from: document, chain: chain)
        return .input(
            inputUID: input.deviceUID,
            outputUID: outputUID,
            label: input.deviceName
        )
    }

    static func equalizerPreset(for chain: GraphChain, document: GraphDocument, fallback: EQPreset) -> EQPreset {
        guard let eqID = chain.equalizerID,
              let node = document.node(id: eqID),
              case .equalizer(let eq) = node.config else {
            return fallback
        }
        return eq.asPreset
    }

    static func isEqualizerEnabled(for chain: GraphChain, document: GraphDocument) -> Bool {
        guard let eqID = chain.equalizerID,
              let node = document.node(id: eqID),
              case .equalizer(let eq) = node.config else {
            return true
        }
        return eq.isEnabled
    }

    private static func outputUID(from document: GraphDocument, chain: GraphChain) -> String? {
        guard let node = document.node(id: chain.outputID),
              case .output(let config) = node.config else {
            return nil
        }
        return config.deviceUID
    }
}
