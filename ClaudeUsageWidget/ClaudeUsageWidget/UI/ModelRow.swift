import SwiftUI

struct ModelRow: View {
    let summary: ModelSummary
    let windowWeightedTotal: Double

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(Theme.color(for: summary.family))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.modelId)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text("in \(summary.inputTokens.formattedTokens())")
                        .help("Input tokens — your prompt content sent to the model.")
                    Text("out \(summary.outputTokens.formattedTokens())")
                        .help("Output tokens — what the model generated.")
                    Text("c-r \(summary.cacheReadTokens.formattedTokens())")
                        .help("Cache reads — prompt-cache hits, billed at ~10% of input cost.")
                    Text("c-w \(summary.cacheCreationTokens.formattedTokens())")
                        .help("Cache writes — newly cached input, billed at a slight markup over input.")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(summary.weightedTokens.formattedTokens()) wt")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .help("Weighted tokens — raw tokens multiplied by per-model and per-type cost factors.")
                if windowWeightedTotal > 0 {
                    let share = (summary.weightedTokens / windowWeightedTotal * 100).rounded()
                    Text("\(Int(share))% of weighted total")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .help("This model's share of all weighted tokens in this window.")
                }
            }

            // Mini bar: this model's share
            if windowWeightedTotal > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Theme.color(for: summary.family))
                            .frame(width: geo.size.width * (summary.weightedTokens / windowWeightedTotal))
                    }
                }
                .frame(width: 56, height: 6)
            }
        }
        .padding(.vertical, 4)
    }
}
