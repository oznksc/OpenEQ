import Foundation

/// Maps a persistent Core Audio device UID to a preferred EQ preset.
struct DeviceEQProfile: Codable, Equatable, Identifiable {
    var id: String { deviceUID }
    var deviceUID: String
    var deviceName: String
    var presetID: UUID?
    var presetName: String?
    var updatedAt: Date

    init(
        deviceUID: String,
        deviceName: String,
        presetID: UUID? = nil,
        presetName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.deviceUID = deviceUID
        self.deviceName = deviceName
        self.presetID = presetID
        self.presetName = presetName
        self.updatedAt = updatedAt
    }
}

final class DeviceProfileStore {
    private let fileManager = FileManager.default
    private let logger = AppLogger(category: "DeviceProfiles")
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder = JSONDecoder()

    private var fileURL: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = appSupport.appendingPathComponent("OpenEQ", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("device-profiles.json")
    }

    func loadProfiles() -> [DeviceEQProfile] {
        guard let fileURL, fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode([DeviceEQProfile].self, from: data)
        } catch {
            logger.error("Failed to load device profiles: \(error.localizedDescription)")
            return []
        }
    }

    func saveProfiles(_ profiles: [DeviceEQProfile]) {
        guard let fileURL else {
            logger.error("Cannot resolve device profiles path.")
            return
        }

        do {
            let data = try encoder.encode(profiles)
            try data.write(to: fileURL, options: .atomic)
            logger.info("Saved \(profiles.count) device profiles.")
        } catch {
            logger.error("Failed to save device profiles: \(error.localizedDescription)")
        }
    }

    func profile(forDeviceUID uid: String, in profiles: [DeviceEQProfile]) -> DeviceEQProfile? {
        profiles.first { $0.deviceUID == uid }
    }

    func upsert(
        deviceUID: String,
        deviceName: String,
        presetID: UUID?,
        presetName: String?,
        into profiles: inout [DeviceEQProfile]
    ) {
        let profile = DeviceEQProfile(
            deviceUID: deviceUID,
            deviceName: deviceName,
            presetID: presetID,
            presetName: presetName,
            updatedAt: Date()
        )
        if let index = profiles.firstIndex(where: { $0.deviceUID == deviceUID }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        saveProfiles(profiles)
    }

    func remove(deviceUID: String, from profiles: inout [DeviceEQProfile]) {
        profiles.removeAll { $0.deviceUID == deviceUID }
        saveProfiles(profiles)
    }
}
