import Foundation

/// Converts weighted-token usage into a soft-% against the (uncalibrated) Pro plan caps,
/// improving with calibration samples over time.
///
/// Two modes:
/// - **Scalar** (default): one `scale` per window; soft-% = scale × weightedTokens.
///   Default scale comes from a community-estimate seed (so day-one users see plausible numbers).
///   With ≥2 samples in the same rolling window, fits scale via least-squares on (% delta vs weighted-token delta) pairs.
/// - **Per-model** (advanced): linear coefficients per exact model id, fitted from sample deltas.
///   Used only when toggled on AND enough samples exist.
nonisolated struct PercentEstimator: Sendable {
    enum Mode: String, Codable, Sendable, CaseIterable {
        case scalar
        case perModel
    }

    /// Default seed scales: 100% ≈ X weighted-Opus-equivalent tokens.
    /// These are deliberately conservative starting points — they are wrong; calibration fixes them.
    static let defaultScalarSeed: [WindowKind: Double] = [
        .fiveHour: 100.0 / 200_000.0,    // ~200k weighted tokens ≈ 100% of 5h window
        .sevenDay: 100.0 / 2_500_000.0,  // ~2.5M weighted tokens ≈ 100% of 7d window
    ]

    let mode: Mode
    let samples: [CalibrationSample]

    /// Compute (softPercent, estimatorState) given a current weighted-token total + per-model breakdown.
    func estimate(
        window: WindowKind,
        weightedTokens: Double,
        perModelWeighted: [String: Double]
    ) -> (Double, EstimatorState) {
        let windowSamples = samples.filter { $0.window == window }

        switch mode {
        case .scalar:
            let usable = windowSamples.filter { $0.weightedTokenSnapshot > 0 && $0.serverPercent > 0 }
            if !usable.isEmpty {
                let scale = fitScalar(samples: usable)
                return (scale * weightedTokens, .calibratedScalar(samples: windowSamples.count))
            }
            let seed = Self.defaultScalarSeed[window] ?? 0
            return (seed * weightedTokens, .estimated)

        case .perModel:
            let usable = windowSamples.filter { !$0.perModelTokenSnapshot.isEmpty && $0.serverPercent > 0 }
            let distinctModels = Set(usable.flatMap { $0.perModelTokenSnapshot.keys })
            if usable.count >= distinctModels.count, !distinctModels.isEmpty {
                let coefficients = fitPerModel(samples: usable, models: Array(distinctModels))
                var pct = 0.0
                for (model, tokens) in perModelWeighted {
                    let c = coefficients[model] ?? 0
                    pct += c * tokens
                }
                return (pct, .calibratedPerModel(samples: windowSamples.count))
            }
            // Fall back to scalar fit
            let scalarUsable = windowSamples.filter { $0.weightedTokenSnapshot > 0 && $0.serverPercent > 0 }
            if !scalarUsable.isEmpty {
                let scale = fitScalar(samples: scalarUsable)
                return (scale * weightedTokens, .calibratedScalar(samples: windowSamples.count))
            }
            let seed = Self.defaultScalarSeed[window] ?? 0
            return (seed * weightedTokens, .estimated)
        }
    }

    // MARK: - Scalar fit (line through origin: % = scale × weightedTokens)

    /// Least-squares slope through origin using each sample's absolute (snapshot, %) values.
    /// Window resets across samples don't matter: each sample independently votes for `scale`,
    /// and a sample at lower tokens with proportionally lower % still lies on the same line.
    private func fitScalar(samples: [CalibrationSample]) -> Double {
        var sumXY = 0.0
        var sumX2 = 0.0
        for s in samples {
            let x = s.weightedTokenSnapshot
            let y = s.serverPercent
            sumXY += x * y
            sumX2 += x * x
        }
        guard sumX2 > 0 else { return 0 }
        return max(0, sumXY / sumX2)
    }

    // MARK: - Per-model fit (% = Σ c_m × perModelTokens_m, no intercept)

    /// Ridge-regression fit on absolute samples: % = Σ c_m × perModelTokens_m
    private func fitPerModel(samples: [CalibrationSample], models: [String]) -> [String: Double] {
        let n = samples.count
        let k = models.count
        guard n > 0, k > 0 else { return [:] }

        var X = [[Double]](repeating: [Double](repeating: 0, count: k), count: n)
        var y = [Double](repeating: 0, count: n)
        for (i, s) in samples.enumerated() {
            y[i] = s.serverPercent
            for (j, m) in models.enumerated() {
                X[i][j] = s.perModelTokenSnapshot[m] ?? 0
            }
        }

        // Compute X^T X (k × k) and X^T y (k)
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

        // Add ridge regularization
        let lambda = 1e-6
        for i in 0..<k { XtX[i][i] += lambda }

        // Solve via Gaussian elimination (k is small — ≤ ~10 in practice)
        guard let beta = solve(matrix: XtX, vector: Xty) else { return [:] }

        var result: [String: Double] = [:]
        for (j, m) in models.enumerated() {
            result[m] = max(0, beta[j])
        }
        return result
    }

    private func solve(matrix A: [[Double]], vector b: [Double]) -> [Double]? {
        var a = A
        var rhs = b
        let n = a.count
        for i in 0..<n {
            // Pivot
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
