import Foundation

/// Converts weighted-token usage into a soft-% against the (uncalibrated) Pro plan caps.
///
/// **Algorithm: anchor + learned marginal rate.**
/// - The most recent valid same-window sample is the *anchor*: at the moment the user typed
///   their server%, the displayed % equals exactly that.
/// - Between calibrations, % grows at a *marginal* rate learned from same-window adjacent-sample
///   pairs that share an epoch (no user-flagged reset between them).
/// - When a sample is flagged `isFirstInEpoch`, it carries the epoch's authoritative `resetsAt`
///   timestamp. The anchor is invalidated once `now >= resetsAt` and we fall back to the seed.
/// - With no usable anchor, we use a pricing-prior seed scale per window so day-one users see
///   plausible numbers.
///
/// The earlier "absolute through-origin" fit was wrong: it forced `chat_offset = 0` and the
/// global fit never passed through the most recent calibration point — typing 65% could result
/// in a displayed 70%. Anchoring on the most recent sample restores the user-contract that
/// calibration *is* ground truth at its moment.
nonisolated struct PercentEstimator: Sendable {
    enum Mode: String, Codable, Sendable, CaseIterable {
        case scalar
        case perModel
    }

    /// Pricing-prior seed scales: 100% ≈ X weighted-Opus-equivalent tokens.
    /// These are deliberately conservative starting points — they are wrong; calibration fixes them.
    static let defaultScalarSeed: [WindowKind: Double] = [
        .fiveHour: 100.0 / 200_000.0,
        .sevenDay: 100.0 / 2_500_000.0,
    ]

    let mode: Mode
    let samples: [CalibrationSample]

    /// Compute (softPercent, estimatorState) given a current weighted-token total + per-model breakdown.
    func estimate(
        window: WindowKind,
        weightedTokens: Double,
        perModelWeighted: [String: Double]
    ) -> (Double, EstimatorState) {
        let now = Date()
        let windowSamples = samples
            .filter { $0.window == window }
            .sorted { $0.timestamp < $1.timestamp }

        guard let anchor = activeAnchor(in: windowSamples, now: now) else {
            let seed = Self.defaultScalarSeed[window] ?? 0
            return (max(0, seed * weightedTokens), .estimated)
        }

        let epoch = currentEpoch(in: windowSamples, anchor: anchor)

        switch mode {
        case .scalar:
            return scalarEstimate(
                window: window,
                weightedTokens: weightedTokens,
                anchor: anchor,
                epoch: epoch
            )
        case .perModel:
            return perModelEstimate(
                window: window,
                weightedTokens: weightedTokens,
                perModelWeighted: perModelWeighted,
                anchor: anchor,
                epoch: epoch
            )
        }
    }

    /// The active epoch's user-entered `resetsAt`, if known and still in the future.
    /// Used by the panel to display an authoritative reset countdown rather than the
    /// rolling-window age-out estimate.
    func epochResetsAt(window: WindowKind, now: Date = Date()) -> Date? {
        let windowSamples = samples
            .filter { $0.window == window }
            .sorted { $0.timestamp < $1.timestamp }
        guard let anchor = activeAnchor(in: windowSamples, now: now) else { return nil }
        let epoch = currentEpoch(in: windowSamples, anchor: anchor)
        guard let resetsAt = epoch.first?.resetsAt, resetsAt > now else { return nil }
        return resetsAt
    }

    // MARK: - Anchor & epoch selection

    /// Return the most recent sample whose epoch hasn't expired (`resetsAt` in the future or absent).
    /// If the most recent sample's epoch has reset, treat as no anchor.
    private func activeAnchor(in samples: [CalibrationSample], now: Date) -> CalibrationSample? {
        guard let latest = samples.last else { return nil }
        let epoch = currentEpoch(in: samples, anchor: latest)
        if let resetsAt = epoch.first?.resetsAt, now >= resetsAt {
            return nil
        }
        return latest
    }

    /// Return the contiguous run of samples ending at `anchor` that share an epoch.
    /// An epoch starts at the most recent sample with `isFirstInEpoch == true` at or before the anchor;
    /// if none exists, the whole prefix forms one open epoch (no known reset boundary).
    private func currentEpoch(in samples: [CalibrationSample], anchor: CalibrationSample) -> [CalibrationSample] {
        guard let anchorIdx = samples.firstIndex(where: { $0.id == anchor.id }) else { return [] }
        var startIdx = 0
        for i in stride(from: anchorIdx, through: 0, by: -1) where samples[i].isFirstInEpoch {
            startIdx = i
            break
        }
        return Array(samples[startIdx...anchorIdx])
    }

    // MARK: - Scalar estimate

    private func scalarEstimate(
        window: WindowKind,
        weightedTokens: Double,
        anchor: CalibrationSample,
        epoch: [CalibrationSample]
    ) -> (Double, EstimatorState) {
        let pairs = adjacentPairs(in: epoch)
        let totalSamples = samples.filter { $0.window == window }.count

        if pairs.isEmpty {
            let seed = Self.defaultScalarSeed[window] ?? 0
            let display = anchor.serverPercent + seed * (weightedTokens - anchor.weightedTokenSnapshot)
            return (max(0, display), .calibratedAnchor(samples: totalSamples))
        }

        let scale = fitScalarMarginal(pairs: pairs)
        let display = anchor.serverPercent + scale * (weightedTokens - anchor.weightedTokenSnapshot)
        return (max(0, display), .calibratedScalar(samples: totalSamples))
    }

    /// Least-squares slope through origin on (Δtokens, Δpct) for adjacent same-epoch pairs.
    /// Clamped to ≥ 0 — a negative marginal rate is unphysical (using Code shouldn't *decrease*
    /// the displayed %); treat negative fits as "no signal" and fall back to seed.
    private func fitScalarMarginal(pairs: [(prev: CalibrationSample, curr: CalibrationSample)]) -> Double {
        var sumXY = 0.0
        var sumX2 = 0.0
        for p in pairs {
            let dx = p.curr.weightedTokenSnapshot - p.prev.weightedTokenSnapshot
            let dy = p.curr.serverPercent - p.prev.serverPercent
            sumXY += dx * dy
            sumX2 += dx * dx
        }
        guard sumX2 > 0 else { return 0 }
        return max(0, sumXY / sumX2)
    }

    // MARK: - Per-model estimate

    private func perModelEstimate(
        window: WindowKind,
        weightedTokens: Double,
        perModelWeighted: [String: Double],
        anchor: CalibrationSample,
        epoch: [CalibrationSample]
    ) -> (Double, EstimatorState) {
        let totalSamples = samples.filter { $0.window == window }.count
        let pairs = adjacentPairs(in: epoch)
        let modelsInPairs = Set(pairs.flatMap { Array($0.curr.perModelTokenSnapshot.keys) + Array($0.prev.perModelTokenSnapshot.keys) })

        // Need at least one valid pair, and at least one model represented in pairs.
        if pairs.isEmpty || modelsInPairs.isEmpty {
            let seed = Self.defaultScalarSeed[window] ?? 0
            let display = anchor.serverPercent + seed * (weightedTokens - anchor.weightedTokenSnapshot)
            return (max(0, display), .calibratedAnchor(samples: totalSamples))
        }

        let coefficients = fitPerModelMarginal(pairs: pairs, models: Array(modelsInPairs))

        // Display: anchor% + Σ_model coef_model · (current_tokens_model − anchor.tokens_model).
        // Models present in the live snapshot but absent from the fit fall back to the pricing-prior
        // seed × delta — keeps per-model mode stable when only a subset of models has signal.
        let seed = Self.defaultScalarSeed[window] ?? 0
        var delta = 0.0
        let anchorTokens = anchor.perModelTokenSnapshot
        let allModels = Set(perModelWeighted.keys).union(anchorTokens.keys)
        for model in allModels {
            let curr = perModelWeighted[model] ?? 0
            let prev = anchorTokens[model] ?? 0
            let dx = curr - prev
            let coef = coefficients[model] ?? seed
            delta += coef * dx
        }
        let display = anchor.serverPercent + delta
        return (max(0, display), .calibratedPerModel(samples: totalSamples))
    }

    /// Ridge regression over per-model deltas: Δ% = Σ c_m · Δtokens_m, no intercept.
    /// Clamps each coefficient to ≥ 0; missing models are absent from the result and the
    /// caller falls back to the pricing-prior seed for them.
    private func fitPerModelMarginal(
        pairs: [(prev: CalibrationSample, curr: CalibrationSample)],
        models: [String]
    ) -> [String: Double] {
        let n = pairs.count
        let k = models.count
        guard n > 0, k > 0 else { return [:] }

        var X = [[Double]](repeating: [Double](repeating: 0, count: k), count: n)
        var y = [Double](repeating: 0, count: n)
        for (i, p) in pairs.enumerated() {
            y[i] = p.curr.serverPercent - p.prev.serverPercent
            for (j, m) in models.enumerated() {
                let prev = p.prev.perModelTokenSnapshot[m] ?? 0
                let curr = p.curr.perModelTokenSnapshot[m] ?? 0
                X[i][j] = curr - prev
            }
        }

        var XtX = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
        var Xty = [Double](repeating: 0, count: k)
        for j1 in 0..<k {
            for j2 in 0..<k {
                var s = 0.0
                for i in 0..<n { s += X[i][j1] * X[i][j2] }
                XtX[j1][j2] = s
            }
            var s = 0.0
            for i in 0..<n { s += X[i][j1] * y[i] }
            Xty[j1] = s
        }

        let lambda = 1e-6
        for i in 0..<k { XtX[i][i] += lambda }

        guard let beta = solve(matrix: XtX, vector: Xty) else { return [:] }

        var result: [String: Double] = [:]
        for (j, m) in models.enumerated() {
            result[m] = max(0, beta[j])
        }
        return result
    }

    // MARK: - Helpers

    /// Form (prev, curr) pairs over consecutive samples in an epoch. Since an epoch is constructed
    /// to end at the anchor and start at the most recent `isFirstInEpoch == true` sample (or the
    /// beginning of history), every adjacent pair within it is a valid same-epoch pair.
    private func adjacentPairs(in epoch: [CalibrationSample]) -> [(prev: CalibrationSample, curr: CalibrationSample)] {
        guard epoch.count >= 2 else { return [] }
        var out: [(CalibrationSample, CalibrationSample)] = []
        for i in 1..<epoch.count {
            out.append((epoch[i - 1], epoch[i]))
        }
        return out
    }

    private func solve(matrix A: [[Double]], vector b: [Double]) -> [Double]? {
        var a = A
        var rhs = b
        let n = a.count
        for i in 0..<n {
            var maxRow = i
            for r in (i + 1)..<n where abs(a[r][i]) > abs(a[maxRow][i]) {
                maxRow = r
            }
            if maxRow != i {
                a.swapAt(i, maxRow)
                rhs.swapAt(i, maxRow)
            }
            guard abs(a[i][i]) > 1e-12 else { return nil }
            for r in (i + 1)..<n {
                let factor = a[r][i] / a[i][i]
                for c in i..<n { a[r][c] -= factor * a[i][c] }
                rhs[r] -= factor * rhs[i]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var s = rhs[i]
            for c in (i + 1)..<n { s -= a[i][c] * x[c] }
            x[i] = s / a[i][i]
        }
        return x
    }
}
