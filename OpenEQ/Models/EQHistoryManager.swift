import Foundation

/// Snapshot entry stored in history and A/B/C comparative slots.
struct EQSnapshot: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let timestamp: Date
    let mode: EQMode
    let bands: [EQBand]
    let preamp: Float
    let selectedHeadphoneProfileID: UUID?

    init(
        id: UUID = UUID(),
        name: String = "Snapshot",
        timestamp: Date = Date(),
        mode: EQMode,
        bands: [EQBand],
        preamp: Float,
        selectedHeadphoneProfileID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.mode = mode
        self.bands = bands
        self.preamp = preamp
        self.selectedHeadphoneProfileID = selectedHeadphoneProfileID
    }
}

/// Identifies fast-access snapshot memory banks.
enum EQSnapshotSlot: String, CaseIterable, Identifiable {
    case a = "A"
    case b = "B"
    case c = "C"

    var id: String { rawValue }
    var title: String { "Slot \(rawValue)" }
}

/// Manages Undo / Redo history stack and A/B/C snapshot memory slots.
final class EQHistoryManager {
    private let maxHistoryDepth: Int = 40
    private var undoStack: [EQSnapshot] = []
    private var redoStack: [EQSnapshot] = []
    private var slots: [EQSnapshotSlot: EQSnapshot] = [:]

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func push(
        current: EQSnapshot
    ) {
        undoStack.append(current)
        if undoStack.count > maxHistoryDepth {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo(current: EQSnapshot) -> EQSnapshot? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    func redo(current: EQSnapshot) -> EQSnapshot? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    func saveSlot(_ slot: EQSnapshotSlot, snapshot: EQSnapshot) {
        slots[slot] = snapshot
    }

    func getSlot(_ slot: EQSnapshotSlot) -> EQSnapshot? {
        slots[slot]
    }

    func clearSlots() {
        slots.removeAll()
    }

    func clearHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
