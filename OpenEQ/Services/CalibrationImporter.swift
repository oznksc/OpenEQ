import Foundation

/// Parses AutoEQ / Equalizer APO / REW style calibration text into OpenEQ presets.
enum CalibrationImporter {
    enum ImportError: LocalizedError {
        case emptyFile
        case unrecognizedFormat
        case noFiltersFound

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "The calibration file is empty."
            case .unrecognizedFormat:
                return "Unrecognized calibration format. Use AutoEQ GraphicEQ/ParametricEQ or REW Equalizer APO export."
            case .noFiltersFound:
                return "No EQ filters were found in the file."
            }
        }
    }

    struct ImportResult: Equatable {
        let preset: EQPreset
        let formatName: String
        let sourceName: String
    }

    static func importFile(at url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.emptyFile
        }
        return try importText(text, sourceName: url.deletingPathExtension().lastPathComponent)
    }

    static func importText(_ text: String, sourceName: String) throws -> ImportResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyFile }

        if let graphic = parseGraphicEQ(trimmed, sourceName: sourceName) {
            return graphic
        }
        if let parametric = parseParametricFilters(trimmed, sourceName: sourceName) {
            return parametric
        }
        if let rewCSV = parseREWFrequencyCSV(trimmed, sourceName: sourceName) {
            return rewCSV
        }
        throw ImportError.unrecognizedFormat
    }

    // MARK: - GraphicEQ (AutoEQ / Equalizer APO)

    /// `GraphicEQ: 20 -0.2; 25 0.1; ... 20000 1.5`
    private static func parseGraphicEQ(_ text: String, sourceName: String) -> ImportResult? {
        guard let range = text.range(of: "GraphicEQ:", options: .caseInsensitive) else {
            return nil
        }
        let payload = text[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs = payload.split(separator: ";")
        var points: [(Float, Float)] = []
        for pair in pairs {
            let parts = pair.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
                .compactMap { Float($0.replacingOccurrences(of: ",", with: ".")) }
            guard parts.count >= 2 else { continue }
            points.append((parts[0], parts[1]))
        }
        guard points.count >= 4 else { return nil }

        let preamp = parsePreamp(text) ?? suggestedPreamp(for: points.map(\.1))
        let gains = resample(points: points, to: EQBand.tenBandFrequencies)
        let bands = zip(EQBand.tenBandFrequencies, gains).map { frequency, gain in
            EQBand(frequency: frequency, gain: gain)
        }
        let preset = EQPreset(
            name: sourceName,
            mode: .graphic,
            bands: bands,
            preamp: preamp
        )
        return ImportResult(preset: preset, formatName: "GraphicEQ", sourceName: sourceName)
    }

    // MARK: - Parametric (AutoEQ / REW / Equalizer APO)

    /// Examples:
    /// `Filter 1: ON PK Fc 100 Hz Gain -3.0 dB Q 1.41`
    /// `Filter  1: ON  PK       Fc   100.0 Hz  Gain  -3.0 dB  Q  5.000`
    /// `Preamp: -6.2 dB`
    private static func parseParametricFilters(_ text: String, sourceName: String) -> ImportResult? {
        let lines = text.components(separatedBy: .newlines)
        var bands: [EQBand] = []
        let filterPattern = try? NSRegularExpression(
            pattern: #"(?i)filter\s*\d+\s*:\s*(?:on|off)?\s*(pk|peaking|lsc|low.?shelf|hsc|high.?shelf|ls|hs|modal|none)?\s*fc\s*([0-9.]+)\s*hz\s*gain\s*([-+]?[0-9.]+)\s*dB\s*q\s*([0-9.]+)"#,
            options: []
        )
        guard let filterPattern else { return nil }

        for line in lines {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = filterPattern.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges >= 5 else {
                continue
            }

            let typeRaw = ns.substring(with: match.range(at: 1)).lowercased()
            guard let frequency = Float(ns.substring(with: match.range(at: 2))),
                  let gain = Float(ns.substring(with: match.range(at: 3))),
                  let q = Float(ns.substring(with: match.range(at: 4))) else {
                continue
            }
            if typeRaw.contains("none") { continue }

            let filterType: EQFilterType
            if typeRaw.contains("lsc") || typeRaw.contains("low") || typeRaw == "ls" {
                filterType = .lowShelf
            } else if typeRaw.contains("hsc") || typeRaw.contains("high") || typeRaw == "hs" {
                filterType = .highShelf
            } else {
                filterType = .parametric
            }

            bands.append(
                EQBand(
                    frequency: frequency,
                    gain: gain,
                    q: q,
                    filterType: filterType,
                    isEnabled: !line.lowercased().contains("off")
                )
            )
        }

        guard !bands.isEmpty else { return nil }

        // Cap to a reasonable parametric set; keep strongest by |gain| if too many.
        let limited: [EQBand]
        if bands.count > 10 {
            limited = Array(
                bands.sorted { abs($0.gain) > abs($1.gain) }.prefix(10)
            ).sorted { $0.frequency < $1.frequency }
        } else {
            limited = bands
        }

        let preamp = parsePreamp(text) ?? suggestedPreamp(for: limited.map(\.gain))
        let preset = EQPreset(
            name: sourceName,
            mode: .parametric,
            bands: limited,
            preamp: preamp
        )
        return ImportResult(preset: preset, formatName: "Parametric EQ", sourceName: sourceName)
    }

    // MARK: - REW frequency response CSV (Freq, SPL)

    private static func parseREWFrequencyCSV(_ text: String, sourceName: String) -> ImportResult? {
        let lines = text.components(separatedBy: .newlines)
        var points: [(Float, Float)] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("*") || trimmed.hasPrefix("#") || trimmed.lowercased().hasPrefix("freq") {
                continue
            }
            let parts = trimmed.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\t" || $0 == " " })
                .map(String.init)
                .compactMap { Float($0.replacingOccurrences(of: ",", with: ".")) }
            // REW exports often: Freq, SPL, Phase
            guard parts.count >= 2, parts[0] >= 10, parts[0] <= 30_000 else { continue }
            points.append((parts[0], parts[1]))
        }
        guard points.count >= 16 else { return nil }

        // Convert absolute SPL curve into a relative EQ by subtracting mean in 200–2kHz.
        let mid = points.filter { $0.0 >= 200 && $0.0 <= 2000 }
        let reference: Float
        if mid.isEmpty {
            reference = points.map(\.1).reduce(0, +) / Float(points.count)
        } else {
            reference = mid.map(\.1).reduce(0, +) / Float(mid.count)
        }
        let relative = points.map { ($0.0, reference - $0.1) } // invert: boost where measurement is low
        let gains = resample(points: relative, to: EQBand.tenBandFrequencies)
        let preamp = suggestedPreamp(for: gains)
        let bands = zip(EQBand.tenBandFrequencies, gains).map { frequency, gain in
            EQBand(frequency: frequency, gain: max(-12, min(12, gain)))
        }
        let preset = EQPreset(
            name: sourceName,
            mode: .graphic,
            bands: bands,
            preamp: preamp
        )
        return ImportResult(preset: preset, formatName: "REW / FR CSV", sourceName: sourceName)
    }

    // MARK: - Helpers

    private static func parsePreamp(_ text: String) -> Float? {
        let pattern = try? NSRegularExpression(
            pattern: #"(?i)preamp\s*:\s*([-+]?[0-9]*\.?[0-9]+)\s*dB"#,
            options: []
        )
        guard let pattern else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = pattern.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return Float(ns.substring(with: match.range(at: 1)))
    }

    private static func suggestedPreamp(for gains: [Float]) -> Float {
        guard let peak = gains.max() else { return 0 }
        // Negative preamp to avoid clipping when applying boosts.
        let suggested = -max(0, peak)
        return max(-12, min(0, suggested))
    }

    /// Log-frequency nearest-neighbor resample into OpenEQ band centers.
    private static func resample(points: [(Float, Float)], to centers: [Float]) -> [Float] {
        guard !points.isEmpty else {
            return Array(repeating: 0, count: centers.count)
        }
        let sorted = points.sorted { $0.0 < $1.0 }
        return centers.map { center in
            // Linear interpolate in log-frequency domain between neighbors.
            if center <= sorted.first!.0 { return sorted.first!.1 }
            if center >= sorted.last!.0 { return sorted.last!.1 }
            for index in 0..<(sorted.count - 1) {
                let left = sorted[index]
                let right = sorted[index + 1]
                if center >= left.0 && center <= right.0 {
                    let logC = log(center)
                    let logL = log(left.0)
                    let logR = log(right.0)
                    let t = (logC - logL) / max(logR - logL, 0.0001)
                    return left.1 + (right.1 - left.1) * t
                }
            }
            return 0
        }
    }
}
