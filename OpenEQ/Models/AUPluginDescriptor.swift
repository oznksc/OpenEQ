import AudioToolbox
import Foundation

/// Lightweight description of a discoverable Audio Unit effect.
struct AUPluginDescriptor: Identifiable, Hashable {
    let id: String
    let name: String
    let manufacturer: String
    let typeName: String
    let audioComponentDescription: AudioComponentDescription

    init(
        name: String,
        manufacturer: String,
        typeName: String,
        audioComponentDescription: AudioComponentDescription
    ) {
        self.name = name
        self.manufacturer = manufacturer
        self.typeName = typeName
        self.audioComponentDescription = audioComponentDescription
        let type = audioComponentDescription.componentType.fourCharString
        let subtype = audioComponentDescription.componentSubType.fourCharString
        let mfr = audioComponentDescription.componentManufacturer.fourCharString
        self.id = "\(type).\(subtype).\(mfr).\(name)"
    }

    var displayName: String {
        if manufacturer.isEmpty {
            return name
        }
        return "\(name) — \(manufacturer)"
    }

    static func == (lhs: AUPluginDescriptor, rhs: AUPluginDescriptor) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension FourCharCode {
    var fourCharString: String {
        let bytes: [UInt8] = [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "????"
    }
}
