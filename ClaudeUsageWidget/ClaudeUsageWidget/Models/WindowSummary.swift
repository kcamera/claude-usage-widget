import Foundation

enum WindowKind: String, Codable, Hashable, Sendable, CaseIterable {
    case fiveHour
    case sevenDay

    var duration: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 60 * 60
        case .sevenDay: return 7 * 24 * 60 * 60
        }
    }

    var label: String {
        switch self {
        case .fiveHour: "5h"
        case .sevenDay: "7d"
        }
    }

    var longLabel: String {
        switch self {
        case .fiveHour: "5-hour window"
        case .sevenDay: "7-day window"
        }
    }
}

enum EstimatorState: Hashable, Sendable {
    case estimated
    case calibratedScalar(samples: Int)
    case calibratedPerModel(samples: Int)

    var badgeText: String {
        switch self {
        case .estimated: "Estimated"
        case .calibratedScalar(let n): "Calibrated (\(n))"
        case .calibratedPerModel(let n): "Calibrated · per-model (\(n))"
        }
    }

    var sampleCount: Int {
        switch self {
        case .estimated: 0
        case .calibratedScalar(let n), .calibratedPerModel(let n): n
        }
    }
}

struct ModelSummary: Hashable, Sendable {
    let modelId: String
    let family: ModelFamily
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0
    var weightedTokens: Double = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }
}

struct WindowSummary: Hashable, Sendable {
    let window: WindowKind
    let perModel: [String: ModelSummary]
    let windowStart: Date
    let windowEnd: Date
    let resetAt: Date?
    let weightedTokens: Double
    let softPercent: Double
    let estimatorState: EstimatorState

    var perFamilyWeighted: [ModelFamily: Double] {
        var out: [ModelFamily: Double] = [:]
        for (_, m) in perModel {
            out[m.family, default: 0] += m.weightedTokens
        }
        return out
    }

    var sortedModels: [ModelSummary] {
        perModel.values.sorted { lhs, rhs in
            if lhs.weightedTokens != rhs.weightedTokens {
                return lhs.weightedTokens > rhs.weightedTokens
            }
            return lhs.modelId < rhs.modelId
        }
    }
}
