//
//  PresetStore.swift
//  OpenEQ
//
//  Created by Antigravity on 26.06.2026.
//

import Foundation

final class PresetStore {
    private let fileManager = FileManager.default
    private let logger = AppLogger(subsystem: "com.openeq.app", category: "PresetStore")

    private var presetsFileURL: URL? {
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appDirectoryURL = appSupportURL.appendingPathComponent("OpenEQ")
        
        // Ensure directory exists
        if !fileManager.fileExists(atPath: appDirectoryURL.path) {
            do {
                try fileManager.createDirectory(at: appDirectoryURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                logger.error("Failed to create Application Support directory: \(error.localizedDescription)")
                return nil
            }
        }
        
        return appDirectoryURL.appendingPathComponent("presets.json")
    }

    /// Loads the saved custom user presets from local storage.
    func loadUserPresets() -> [EQPreset] {
        guard let fileURL = presetsFileURL else {
            return []
        }
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.info("No custom user presets file exists yet.")
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let presets = try decoder.decode([EQPreset].self, from: data)
            logger.info("Successfully loaded \(presets.count) custom user presets.")
            return presets
        } catch {
            logger.error("Failed to read user presets from file: \(error.localizedDescription)")
            return []
        }
    }

    /// Saves the current list of custom user presets to local storage.
    func saveUserPresets(_ presets: [EQPreset]) {
        guard let fileURL = presetsFileURL else {
            logger.error("Cannot resolve target path to save user presets.")
            return
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(presets)
            try data.write(to: fileURL, options: .atomic)
            logger.info("Successfully saved \(presets.count) custom user presets to disk.")
        } catch {
            logger.error("Failed to write custom user presets: \(error.localizedDescription)")
        }
    }

    /// Exports a specific preset to a chosen local file URL as a JSON document.
    func exportPreset(_ preset: EQPreset, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(preset)
        try data.write(to: url, options: .atomic)
        logger.info("Exported preset '\(preset.name)' successfully.")
    }

    /// Imports a preset configuration from a chosen JSON file.
    func importPreset(from url: URL) throws -> EQPreset {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        
        // Decodes and validates the preset format
        let preset = try decoder.decode(EQPreset.self, from: data)
        
        // Generate a new unique ID and reset dates to import time to avoid conflicts
        let importedPreset = EQPreset(
            id: UUID(),
            name: preset.name,
            bands: preset.bands,
            preamp: preset.preamp,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        logger.info("Imported preset '\(importedPreset.name)' successfully.")
        return importedPreset
    }
}
