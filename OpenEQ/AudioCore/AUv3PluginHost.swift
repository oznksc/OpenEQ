import AVFoundation
import AudioToolbox
import Foundation

/// Discovers and instantiates effect Audio Units for the local playback chain.
@MainActor
final class AUv3PluginHost {
    private(set) var availablePlugins: [AUPluginDescriptor] = []
    private(set) var loadedUnit: AVAudioUnit?
    private(set) var loadedDescriptor: AUPluginDescriptor?
    private(set) var lastError: String?

    private let logger = AppLogger(category: "AUv3Host")

    func refreshAvailablePlugins() {
        let manager = AVAudioUnitComponentManager.shared()
        // Effects only — instruments are out of scope for an EQ host slot.
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let components = manager.components(matching: description)
        availablePlugins = components
            .filter { component in
                // Prefer non-Apple stock units for the "plugin" list, but keep Apple
                // dynamics/reverb options that users may still want.
                let name = component.name
                return !name.isEmpty
            }
            .map { component in
                AUPluginDescriptor(
                    name: component.name,
                    manufacturer: component.manufacturerName,
                    typeName: component.typeName,
                    audioComponentDescription: component.audioComponentDescription
                )
            }
            .sorted { lhs, rhs in
                lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }

        logger.info("Discovered \(availablePlugins.count) Audio Unit effects.")
    }

    func loadPlugin(
        _ descriptor: AUPluginDescriptor,
        completion: @escaping (Result<AVAudioUnit, Error>) -> Void
    ) {
        lastError = nil
        AVAudioUnit.instantiate(
            with: descriptor.audioComponentDescription,
            options: []
        ) { [weak self] unit, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.lastError = error.localizedDescription
                    self.logger.error("Failed to load AU: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                guard let unit else {
                    let err = AUv3HostError.instantiationFailed
                    self.lastError = err.localizedDescription
                    completion(.failure(err))
                    return
                }
                self.loadedUnit = unit
                self.loadedDescriptor = descriptor
                self.logger.info("Loaded AU plugin: \(descriptor.displayName)")
                completion(.success(unit))
            }
        }
    }

    func unloadPlugin() {
        loadedUnit = nil
        loadedDescriptor = nil
        lastError = nil
    }
}

enum AUv3HostError: LocalizedError {
    case instantiationFailed

    var errorDescription: String? {
        switch self {
        case .instantiationFailed:
            return "The Audio Unit could not be instantiated."
        }
    }
}
