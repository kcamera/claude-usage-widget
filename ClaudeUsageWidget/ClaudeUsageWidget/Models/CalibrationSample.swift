import Foundation

struct CalibrationSample: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let window: WindowKind
    let serverPercent: Double
    let weightedTokenSnapshot: Double
    let perModelTokenSnapshot: [String: Double]
    var note: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        window: WindowKind,
        serverPercent: Double,
        weightedTokenSnapshot: Double,
        perModelTokenSnapshot: [String: Double],
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.window = window
        self.serverPercent = serverPercent
        self.weightedTokenSnapshot = weightedTokenSnapshot
        self.perModelTokenSnapshot = perModelTokenSnapshot
        self.note = note
    }
}
