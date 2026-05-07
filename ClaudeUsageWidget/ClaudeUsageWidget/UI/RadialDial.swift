import SwiftUI

/// Stacked-arc radial dial. Each segment is drawn end-to-end around the ring.
struct RadialDial: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    let totalPercent: Double      // 0...100+, may exceed 100
    let label: String
    let lineWidth: CGFloat
    let size: CGFloat

    init(segments: [Segment], totalPercent: Double, label: String, size: CGFloat = 96, lineWidth: CGFloat = 12) {
        self.segments = segments
        self.totalPercent = totalPercent
        self.label = label
        self.size = size
        self.lineWidth = lineWidth
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)

            // Stacked segments. Total filled = min(totalPercent, 100) / 100
            let cap = min(totalPercent, 100) / 100
            let totalValue = segments.reduce(0) { $0 + $1.value }
            if totalValue > 0 && cap > 0 {
                let scale = cap / totalValue
                var runningStart = 0.0
                ForEach(segments) { seg in
                    let length = seg.value * scale
                    let from = runningStart
                    let to = runningStart + length
                    Circle()
                        .trim(from: from, to: min(to, 1.0))
                        .stroke(seg.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.4), value: totalPercent)
                    let _ = (runningStart = to)
                }
            }

            // Overflow indicator if >100
            if totalPercent > 100 {
                Circle()
                    .stroke(Color.red.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .padding(-(lineWidth / 2 + 3))
            }

            VStack(spacing: 0) {
                Text(formatPercent(totalPercent))
                    .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: size * 0.12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func formatPercent(_ p: Double) -> String {
        if p < 1 && p > 0 { return String(format: "%.1f%%", p) }
        return "\(Int(p.rounded()))%"
    }
}
