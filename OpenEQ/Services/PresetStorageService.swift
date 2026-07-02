//
//  PresetStorageService.swift
//  OpenEQ
//
//  Created by Ozan
//

import Foundation

final class PresetStorageService {
    private let userDefaultsKey = "openeq.custom.presets"
    private let logger = AppLogger(subsystem: "Services", category: "PresetStorage")

    func loadCustomPresets() -> [EQPreset] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            logger.info("No custom presets found in storage.")
            return []
        }

        do {
            let decoder = JSONDecoder()
            let presets = try decoder.decode([EQPreset].self, from: data)
            logger.info("Successfully loaded \(presets.count) custom presets.")
            return presets
        } catch {
            logger.error("Failed to decode custom presets: \(error.localizedDescription)")
            return []
        }
    }

    func saveCustomPresets(_ presets: [EQPreset]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(presets)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
            logger.info("Successfully saved \(presets.count) custom presets.")
        } catch {
            logger.error("Failed to encode custom presets: \(error.localizedDescription)")
        }
    }
}
