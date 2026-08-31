import Foundation
import CoreGraphics

enum GraphNodeKind: String, Codable, CaseIterable, Identifiable {
    case appSource
    case systemSource
    case inputSource
    case fileSource
    case equalizer
    case dynamics
    case output
    case monitor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appSource: return "App"
        case .systemSource: return "System Audio"
        case .inputSource: return "Microphone"
        case .fileSource: return "File"
        case .equalizer: return "Equalizer"
        case .dynamics: return "Dynamics"
        case .output: return "Output"
        case .monitor: return "Monitor"
        }
    }

    var systemImage: String {
        switch self {
        case .appSource: return "app.badge"
        case .systemSource: return "waveform"
        case .inputSource: return "mic.fill"
        case .fileSource: return "doc.fill"
        case .equalizer: return "slider.vertical.3"
        case .dynamics: return "waveform.path.ecg"
        case .output: return "hifispeaker.fill"
        case .monitor: return "chart.bar.fill"
        }
    }

    var isSource: Bool {
        switch self {
        case .appSource, .systemSource, .inputSource, .fileSource: return true
        default: return false
        }
    }

    var isProcessor: Bool {
        switch self {
        case .equalizer, .dynamics: return true
        default: return false
        }
    }

    var isSink: Bool {
        switch self {
        case .output, .monitor: return true
        default: return false
        }
    }

    var defaultSize: CGSize {
        switch self {
        case .equalizer: return CGSize(width: 188, height: 112)
        case .appSource, .systemSource, .inputSource, .fileSource:
            return CGSize(width: 168, height: 76)
        case .dynamics:
            return CGSize(width: 156, height: 72)
        case .output, .monitor:
            return CGSize(width: 156, height: 72)
        }
    }

    var inputPortNames: [String] {
        switch self {
        case .appSource, .systemSource, .inputSource, .fileSource:
            return []
        case .equalizer, .dynamics, .output, .monitor:
            return ["in"]
        }
    }

    var outputPortNames: [String] {
        switch self {
        case .output:
            return []
        case .monitor:
            return []
        case .appSource, .systemSource, .inputSource, .fileSource, .equalizer, .dynamics:
            return ["out"]
        }
    }
}

struct CodablePoint: Codable, Equatable, Hashable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

struct GraphNode: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: GraphNodeKind
    var title: String
    var position: CodablePoint
    var config: GraphNodeConfig

    init(
        id: UUID = UUID(),
        kind: GraphNodeKind,
        title: String? = nil,
        position: CGPoint,
        config: GraphNodeConfig? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title ?? kind.title
        self.position = CodablePoint(position)
        self.config = config ?? .default(for: kind)
    }

    var cgPosition: CGPoint {
        get { position.cgPoint }
        set { position = CodablePoint(newValue) }
    }

    var size: CGSize { kind.defaultSize }

    func portID(name: String) -> GraphPortID {
        GraphPortID(nodeID: id, name: name)
    }
}

struct GraphPortID: Hashable, Codable, Equatable {
    var nodeID: UUID
    var name: String
}

struct GraphEdge: Identifiable, Codable, Equatable {
    var id: UUID
    var from: GraphPortID
    var to: GraphPortID

    init(id: UUID = UUID(), from: GraphPortID, to: GraphPortID) {
        self.id = id
        self.from = from
        self.to = to
    }
}
