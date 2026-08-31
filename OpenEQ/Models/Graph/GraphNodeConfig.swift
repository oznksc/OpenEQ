import Foundation

enum GraphNodeConfig: Codable, Equatable {
    case appSource(AppSourceConfig)
    case systemSource(SystemSourceConfig)
    case inputSource(InputSourceConfig)
    case fileSource(FileSourceConfig)
    case equalizer(EqualizerConfig)
    case dynamics(DynamicsConfig)
    case output(OutputConfig)
    case monitor(MonitorConfig)

    struct AppSourceConfig: Codable, Equatable {
        var bundleID: String?
        var processObjectID: UInt32?
        var displayName: String
        var pid: Int32?

        static let empty = AppSourceConfig(
            bundleID: nil,
            processObjectID: nil,
            displayName: "Select App",
            pid: nil
        )
    }

    struct SystemSourceConfig: Codable, Equatable {
        var excludeSelf: Bool

        static let `default` = SystemSourceConfig(excludeSelf: true)
    }

    struct InputSourceConfig: Codable, Equatable {
        var deviceUID: String?
        var deviceName: String

        static let empty = InputSourceConfig(deviceUID: nil, deviceName: "Default Input")
    }

    struct FileSourceConfig: Codable, Equatable {
        var fileName: String?

        static let empty = FileSourceConfig(fileName: nil)
    }

    struct EqualizerConfig: Codable, Equatable {
        var isEnabled: Bool
        var mode: EQMode
        var bands: [EQBand]
        var preamp: Float
        var presetName: String

        static func flat() -> EqualizerConfig {
            let preset = EQPreset.flatPreset()
            return EqualizerConfig(
                isEnabled: true,
                mode: preset.mode,
                bands: preset.bands,
                preamp: preset.preamp,
                presetName: preset.name
            )
        }

        var asPreset: EQPreset {
            EQPreset(name: presetName, mode: mode, bands: bands, preamp: preamp)
        }
    }

    struct DynamicsConfig: Codable, Equatable {
        var settings: DynamicsSettings

        static let `default` = DynamicsConfig(settings: .default)
    }

    struct OutputConfig: Codable, Equatable {
        var deviceUID: String?
        var deviceName: String

        static let systemDefault = OutputConfig(deviceUID: nil, deviceName: "System Default")
    }

    struct MonitorConfig: Codable, Equatable {
        var showSpectrum: Bool

        static let `default` = MonitorConfig(showSpectrum: true)
    }

    static func `default`(for kind: GraphNodeKind) -> GraphNodeConfig {
        switch kind {
        case .appSource: return .appSource(.empty)
        case .systemSource: return .systemSource(.default)
        case .inputSource: return .inputSource(.empty)
        case .fileSource: return .fileSource(.empty)
        case .equalizer: return .equalizer(.flat())
        case .dynamics: return .dynamics(.default)
        case .output: return .output(.systemDefault)
        case .monitor: return .monitor(.default)
        }
    }

    var subtitle: String {
        switch self {
        case .appSource(let c):
            return c.displayName
        case .systemSource:
            return "All apps"
        case .inputSource(let c):
            return c.deviceName
        case .fileSource(let c):
            return c.fileName ?? "No file"
        case .equalizer(let c):
            return c.isEnabled ? c.presetName : "Bypassed"
        case .dynamics(let c):
            return c.settings.isCompressorEnabled ? "Compressor on" : "Off"
        case .output(let c):
            return c.deviceName
        case .monitor:
            return "Spectrum"
        }
    }
}
