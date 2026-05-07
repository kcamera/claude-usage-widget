import SwiftUI

struct WindowSection: View {
    let summary: WindowSummary
    let now: Date
    let onCalibrate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(alignment: .top, spacing: 16) {
                dial
                summaryColumn
            }
            Divider().opacity(0.4)
            VStack(spacing: 0) {
                ForEach(summary.sortedModels, id: \.modelId) { m in
                    ModelRow(summary: m, windowWeightedTotal: summary.weightedTokens)
                }
                if summary.perModel.isEmpty {
                    Text("No usage in this window yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(summary.window.longLabel)
                .font(.system(size: 13, weight: .semibold))
            badge(summary.estimatorState.badgeText)

            Spacer()

            Button(action: onCalibrate) {
                Label("Calibrate", systemImage: "scope")
                    .font(.system(size: 11, weight: .medium))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.claudeOrange)
            .help("Enter your current % from claude.ai/settings/usage to calibrate this widget.")
        }
    }

    private var dial: some View {
        let segs = familySegments()
        return RadialDial(
            segments: segs,
            totalPercent: summary.softPercent.clampedSoftPercent(),
            label: summary.window.label,
            size: 110,
            lineWidth: 13
        )
    }

    private func familySegments() -> [RadialDial.Segment] {
        let perFamily = summary.perFamilyWeighted
        let total = perFamily.values.reduce(0, +)
        guard total > 0 else { return [] }
        let order: [ModelFamily] = [.opus, .sonnet, .haiku, .other]
        return order.compactMap { fam in
            let v = perFamily[fam] ?? 0
            guard v > 0 else { return nil }
            return RadialDial.Segment(id: fam.rawValue, value: v, color: Theme.color(for: fam))
        }
    }

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            row(title: "Weighted tokens", value: summary.weightedTokens.formattedTokens())
            if let resetAt = summary.resetAt {
                let remaining = resetAt.timeIntervalSince(now)
                row(title: "Resets in", value: remaining.formattedShortDuration())
            } else {
                row(title: "Resets in", value: "—")
            }
            HStack(alignment: .top, spacing: 6) {
                ForEach([ModelFamily.opus, .sonnet, .haiku], id: \.self) { fam in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.color(for: fam)).frame(width: 6, height: 6)
                        Text(fam.displayName).font(.system(size: 10))
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.claudeOrange.opacity(0.18))
            .foregroundStyle(Theme.claudeOrange)
            .clipShape(Capsule())
    }
}
