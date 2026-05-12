import Foundation

/// Buckets a set of usage events into rolling 5-hour and 7-day windows
/// with per-exact-model breakdowns and weighted-token totals.
nonisolated struct WindowAggregator: Sendable {
    let weights: ModelWeights

    func summarize(
        events: [UsageEvent],
        now: Date,
        window: WindowKind,
        epochResetsAt: Date?,
        scaleProvider: (Double, [String: Double]) -> (Double, EstimatorState)
    ) -> WindowSummary {
        // When the user has told us when the server's window resets, the true window is
        // [resetsAt - duration, resetsAt]. Otherwise fall back to rolling [now - duration, now].
        let windowStart: Date
        if let resetsAt = epochResetsAt, resetsAt > now {
            windowStart = resetsAt.addingTimeInterval(-window.duration)
        } else {
            windowStart = now.addingTimeInterval(-window.duration)
        }
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

        // Prefer the user-entered reset time; fall back to "oldest event in window will age out"
        // (a rolling-window estimate that's only meaningful for the 5h window, and only when no
        // calibration has supplied an authoritative reset).
        let resetAt: Date?
        if let epochResetsAt {
            resetAt = epochResetsAt
        } else {
            let oldestInWindow = events
                .filter { $0.timestamp >= windowStart && $0.timestamp <= now }
                .map(\.timestamp)
                .min()
            resetAt = oldestInWindow.map { $0.addingTimeInterval(window.duration) }
        }

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
