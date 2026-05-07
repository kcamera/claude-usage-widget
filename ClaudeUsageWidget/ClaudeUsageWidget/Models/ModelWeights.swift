import Foundation

struct ModelWeights: Codable, Sendable, Hashable {
    var perModel: [String: Double]
    var familyDefaults: [ModelFamily: Double]
    var cacheReadDiscount: Double
    var cacheCreationMarkup: Double
    var inputDiscount: Double

    static let `default` = ModelWeights(
        perModel: [
            "claude-opus-4-7": 1.00,
            "claude-opus-4-6": 1.00,
            "claude-opus-4-5": 1.00,
            "claude-sonnet-4-7": 0.20,
            "claude-sonnet-4-6": 0.20,
            "claude-sonnet-4-5": 0.20,
            "claude-haiku-4-5": 0.04,
            "claude-haiku-4-6": 0.04,
        ],
        familyDefaults: [
            .opus: 1.00,
            .sonnet: 0.20,
            .haiku: 0.04,
            .other: 1.00,
        ],
        cacheReadDiscount: 0.10,
        cacheCreationMarkup: 1.25,
        inputDiscount: 0.20
    )

    func weight(for modelId: String) -> Double {
        if let w = perModel[modelId] { return w }
        let fam = ModelFamily.derive(from: modelId)
        return familyDefaults[fam] ?? 1.0
    }

    func weightedTokens(
        modelId: String,
        input: Int,
        output: Int,
        cacheCreation: Int,
        cacheRead: Int
    ) -> Double {
        let w = weight(for: modelId)
        let weightedInput = Double(input) * inputDiscount
        let weightedCacheCreate = Double(cacheCreation) * cacheCreationMarkup * inputDiscount
        let weightedCacheRead = Double(cacheRead) * cacheReadDiscount * inputDiscount
        let weightedOutput = Double(output)
        return w * (weightedInput + weightedCacheCreate + weightedCacheRead + weightedOutput)
    }
}
