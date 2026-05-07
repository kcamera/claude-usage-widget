import Foundation

struct CalibrationSample: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let timestamp: Date
    let window: WindowKind
    let serverPercent: Double
    let weightedTokenSnapshot: Double
    let perModelTokenSnapshot: [String: Double]
    var note: String?
    var isFirstInEpoch: Bool
    var resetsAt: Date?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        window: WindowKind,
        serverPercent: Double,
        weightedTokenSnapshot: Double,
        perModelTokenSnapshot: [String: Double],
        note: String? = nil,
        isFirstInEpoch: Bool = false,
        resetsAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.window = window
        self.serverPercent = serverPercent
        self.weightedTokenSnapshot = weightedTokenSnapshot
        self.perModelTokenSnapshot = perModelTokenSnapshot
        self.note = note
        self.isFirstInEpoch = isFirstInEpoch
        self.resetsAt = resetsAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, window, serverPercent, weightedTokenSnapshot, perModelTokenSnapshot, note, isFirstInEpoch, resetsAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        window = try c.decode(WindowKind.self, forKey: .window)
        serverPercent = try c.decode(Double.self, forKey: .serverPercent)
        weightedTokenSnapshot = try c.decode(Double.self, forKey: .weightedTokenSnapshot)
        perModelTokenSnapshot = try c.decode([String: Double].self, forKey: .perModelTokenSnapshot)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        isFirstInEpoch = try c.decodeIfPresent(Bool.self, forKey: .isFirstInEpoch) ?? false
        resetsAt = try c.decodeIfPresent(Date.self, forKey: .resetsAt)
    }
}
