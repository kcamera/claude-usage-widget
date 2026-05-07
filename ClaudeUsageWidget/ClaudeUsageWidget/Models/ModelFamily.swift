import Foundation

enum ModelFamily: String, Codable, Hashable, Sendable, CaseIterable {
    case opus
    case sonnet
    case haiku
    case other

    static func derive(from modelId: String) -> ModelFamily {
        let lowered = modelId.lowercased()
        if lowered.contains("opus") { return .opus }
        if lowered.contains("sonnet") { return .sonnet }
        if lowered.contains("haiku") { return .haiku }
        return .other
    }

    var displayName: String {
        switch self {
        case .opus: "Opus"
        case .sonnet: "Sonnet"
        case .haiku: "Haiku"
        case .other: "Other"
        }
    }
}
