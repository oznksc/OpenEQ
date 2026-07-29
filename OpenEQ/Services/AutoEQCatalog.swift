import Foundation

/// Curated headphone correction catalog (AutoEQ-style 10-band gains).
/// Full 4000+ database is available via import from AutoEQ exports / autoeq.app.
final class AutoEQCatalog {
    private let logger = AppLogger(category: "AutoEQCatalog")

    func loadBundledProfiles() -> [HeadphoneProfile] {
        if let url = Bundle.main.url(forResource: "autoeq_catalog", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([HeadphoneProfile].self, from: data) {
            logger.info("Loaded \(decoded.count) bundled headphone profiles.")
            return decoded.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }

        logger.warning("Bundled AutoEQ catalog missing — using built-in fallback list.")
        return Self.fallbackProfiles.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func search(_ query: String, in profiles: [HeadphoneProfile]) -> [HeadphoneProfile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return profiles }
        return profiles.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || $0.brand.localizedCaseInsensitiveContains(trimmed)
                || $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.source.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Built-in subset so the feature works even if the JSON resource is missing.
    static let fallbackProfiles: [HeadphoneProfile] = [
        // gains: 32 64 125 250 500 1k 2k 4k 8k 16k
        HeadphoneProfile(name: "HD 600", brand: "Sennheiser", source: "AutoEQ-style", target: "Harman OE", gains: [2.5, 2.0, 1.0, 0.5, 0.0, -0.5, 1.5, 3.0, 2.0, 1.0], preamp: -3.5),
        HeadphoneProfile(name: "HD 650", brand: "Sennheiser", source: "AutoEQ-style", target: "Harman OE", gains: [2.0, 1.5, 0.8, 0.3, 0.0, -0.3, 1.2, 2.5, 1.8, 0.8], preamp: -3.0),
        HeadphoneProfile(name: "HD 800 S", brand: "Sennheiser", source: "AutoEQ-style", target: "Harman OE", gains: [3.0, 2.0, 0.5, -1.0, -0.5, 0.0, 1.0, -1.5, -2.0, -1.0], preamp: -3.5),
        HeadphoneProfile(name: "DT 1990 Pro", brand: "beyerdynamic", source: "AutoEQ-style", target: "Harman OE", gains: [1.5, 1.0, 0.5, 0.0, -0.5, -1.0, -2.5, -4.0, -3.0, -1.5], preamp: -2.0),
        HeadphoneProfile(name: "DT 770 Pro 80", brand: "beyerdynamic", source: "AutoEQ-style", target: "Harman OE", gains: [-1.0, 0.0, 1.5, 1.0, 0.0, -0.5, -1.5, -3.5, -2.5, -1.0], preamp: -2.0),
        HeadphoneProfile(name: "ATH-M50x", brand: "Audio-Technica", source: "AutoEQ-style", target: "Harman OE", gains: [-2.0, -1.0, 0.5, 1.0, 0.5, 0.0, -1.0, -2.0, -1.0, 0.5], preamp: -1.5),
        HeadphoneProfile(name: "WH-1000XM5", brand: "Sony", source: "AutoEQ-style", target: "Harman OE", gains: [-4.0, -2.5, -1.0, 0.5, 1.0, 0.5, 0.0, -0.5, 0.5, 1.0], preamp: -1.5),
        HeadphoneProfile(name: "WH-1000XM4", brand: "Sony", source: "AutoEQ-style", target: "Harman OE", gains: [-3.5, -2.0, -0.5, 0.5, 1.0, 0.5, -0.5, -1.0, 0.0, 0.5], preamp: -1.5),
        HeadphoneProfile(name: "AirPods Pro 2", brand: "Apple", source: "AutoEQ-style", target: "Harman IE", gains: [-1.5, -0.5, 0.5, 1.0, 0.5, 0.0, -0.5, 0.5, 1.0, 0.5], preamp: -1.5),
        HeadphoneProfile(name: "AirPods Max", brand: "Apple", source: "AutoEQ-style", target: "Harman OE", gains: [-2.0, -1.0, 0.0, 0.5, 0.5, 0.0, -0.5, -1.0, 0.5, 1.0], preamp: -1.5),
        HeadphoneProfile(name: "Momentum 4", brand: "Sennheiser", source: "AutoEQ-style", target: "Harman OE", gains: [-3.0, -1.5, 0.0, 0.5, 0.5, 0.0, -0.5, -1.0, 0.0, 0.5], preamp: -1.5),
        HeadphoneProfile(name: "Edition XS", brand: "HIFIMAN", source: "AutoEQ-style", target: "Harman OE", gains: [3.5, 2.5, 1.0, 0.0, -0.5, 0.0, 1.0, 0.5, -0.5, -1.0], preamp: -4.0),
        HeadphoneProfile(name: "Sundara", brand: "HIFIMAN", source: "AutoEQ-style", target: "Harman OE", gains: [3.0, 2.0, 1.0, 0.0, -0.5, 0.0, 1.5, 1.0, 0.0, -0.5], preamp: -3.5),
        HeadphoneProfile(name: "Ananda", brand: "HIFIMAN", source: "AutoEQ-style", target: "Harman OE", gains: [2.5, 1.5, 0.5, 0.0, -0.5, 0.0, 1.0, 0.5, -0.5, -1.0], preamp: -3.0),
        HeadphoneProfile(name: "Clear MG", brand: "Focal", source: "AutoEQ-style", target: "Harman OE", gains: [1.5, 1.0, 0.5, 0.0, 0.0, -0.5, 0.5, 1.5, 0.5, -0.5], preamp: -2.0),
        HeadphoneProfile(name: "Celestee", brand: "Focal", source: "AutoEQ-style", target: "Harman OE", gains: [-1.0, 0.0, 1.0, 0.5, 0.0, -0.5, -1.0, -2.0, -1.0, 0.0], preamp: -1.5),
        HeadphoneProfile(name: "K712 Pro", brand: "AKG", source: "AutoEQ-style", target: "Harman OE", gains: [2.0, 1.5, 0.5, 0.0, 0.0, -0.5, 1.0, 2.0, 1.0, 0.0], preamp: -2.5),
        HeadphoneProfile(name: "K371", brand: "AKG", source: "AutoEQ-style", target: "Harman OE", gains: [-0.5, 0.0, 0.5, 0.5, 0.0, 0.0, 0.5, 0.0, -0.5, -0.5], preamp: -1.0),
        HeadphoneProfile(name: "SRH840A", brand: "Shure", source: "AutoEQ-style", target: "Harman OE", gains: [-1.5, -0.5, 0.5, 1.0, 0.5, 0.0, -1.0, -2.0, -1.0, 0.0], preamp: -1.5),
        HeadphoneProfile(name: "LCD-X", brand: "Audeze", source: "AutoEQ-style", target: "Harman OE", gains: [1.0, 0.5, 0.0, -0.5, -0.5, 0.0, 1.5, 2.5, 1.0, 0.0], preamp: -3.0),
        HeadphoneProfile(name: "Elex", brand: "Meze", source: "AutoEQ-style", target: "Harman OE", gains: [1.5, 1.0, 0.5, 0.0, 0.0, -0.5, 0.5, 1.0, 0.5, 0.0], preamp: -2.0),
        HeadphoneProfile(name: "Drop + THX Panda", brand: "Drop", source: "AutoEQ-style", target: "Harman OE", gains: [-2.0, -1.0, 0.0, 0.5, 0.5, 0.0, -0.5, -1.5, -0.5, 0.5], preamp: -1.5),
        HeadphoneProfile(name: "HE400se", brand: "HIFIMAN", source: "AutoEQ-style", target: "Harman OE", gains: [3.0, 2.0, 1.0, 0.0, -0.5, 0.0, 1.0, 0.5, -0.5, -0.5], preamp: -3.5),
        HeadphoneProfile(name: "EQ50", brand: "OpenEQ Demo", source: "Built-in", target: "Flat+Bass", gains: [4, 3, 2, 1, 0, 0, 0, 1, 2, 1], preamp: -4.5, notes: "Demo profile"),
        HeadphoneProfile(name: "IE 200", brand: "Sennheiser", source: "AutoEQ-style", target: "Harman IE", gains: [-1.0, 0.0, 1.0, 0.5, 0.0, -0.5, 0.5, 1.0, 0.5, 0.0], preamp: -1.5),
        HeadphoneProfile(name: "Blessing 3", brand: "Moondrop", source: "AutoEQ-style", target: "Harman IE", gains: [0.0, 0.5, 0.5, 0.0, 0.0, 0.0, 0.5, 0.0, -0.5, -0.5], preamp: -1.0),
        HeadphoneProfile(name: "Aria", brand: "Moondrop", source: "AutoEQ-style", target: "Harman IE", gains: [-0.5, 0.0, 0.5, 0.5, 0.0, 0.0, 0.5, 0.0, -0.5, 0.0], preamp: -1.0),
        HeadphoneProfile(name: "Zero:Red", brand: "7Hz", source: "AutoEQ-style", target: "Harman IE", gains: [-1.5, -0.5, 0.5, 0.5, 0.0, 0.0, 0.5, 1.0, 0.5, 0.0], preamp: -1.5),
        HeadphoneProfile(name: "Chu II", brand: "Moondrop", source: "AutoEQ-style", target: "Harman IE", gains: [-1.0, 0.0, 0.5, 0.5, 0.0, 0.0, 0.5, 0.5, 0.0, -0.5], preamp: -1.0),
        HeadphoneProfile(name: "Truthear Hexa", brand: "Truthear", source: "AutoEQ-style", target: "Harman IE", gains: [-0.5, 0.0, 0.5, 0.0, 0.0, 0.0, 0.5, 0.5, 0.0, -0.5], preamp: -1.0)
    ]
}
