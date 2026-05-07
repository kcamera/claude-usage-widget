import Foundation

/// Buckets a set of usage events into rolling 5-hour and 7-day windows
/// with per-exact-model breakdowns and weighted-token totals.
nonisolated struct WindowAggregator: Sendable {
    let weights: ModelWeights

    func summarize(
        events: [UsageEvent],
        now: Date,
        window: WindowKind,
        scaleProvider: (Double, [String: Double]) -> (Double, EstimatorState)
    ) -> WindowSummary {
        let windowStart = now.addingTimeInterval(-window.duration)
        let inWindow = events.lazy.filter { $0.timestamp >= windowStart && $0.timestamp <= now }

        var perModel: [String: ModelSummary] = [:]
        var totalWeighted = 0.0

        for e in inWindow {
            var summary = perModel[e.model] ?? ModelSummary(modelId: e.model, family: e.modelFamily)
            summary.inputTokens += e.inputTokens
            summary.outputTokens += e.outputTokens
            summary.cacheCreationTokens += e.cacheCreationTokens
            summary.cacheReadTokens += e.cacheReadTokens

            let weighted = weights.weightedTokens(
                modelId: e.model,
                input: e.inputTokens,
                output: e.outputTokens,
                cacheCreation: e.cacheCreationTokens,
                cacheRead: e.cacheReadTokens
            )
            summary.weightedTokens += weighted
            totalWeighted += weighted
            perModel[e.model] = summary
        }

        // Reset = when the oldest event in the window will fall out
        let oldestInWindow = events
            .filter { $0.timestamp >= windowStart && $0.timestamp <= now }
            .map(\.timestamp)
            .min()
        let resetAt = oldestInWindow.map { $0.addingTimeInterval(window.duration) }

        let perModelTokens = perModel.mapValues { $0.weightedTokens }
        let (softPercent, state) = scaleProvider(totalWeighted, perModelTokens)

        return WindowSummary(
            window: window,
            perModel: perModel,
            windowStart: windowStart,
            windowEnd: now,
            resetAt: resetAt,
            weightedTokens: totalWeighted,
            softPercent: softPercent,
            estimatorState: state
        )
    }
}
