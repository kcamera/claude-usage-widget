import SwiftUI

struct MenuBarLabel: View {
    let fiveHourPercent: Double
    let sevenDayPercent: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: ClaudeMarkImage.menuBar)
            Text(formatPair())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
    }

    private func formatPair() -> String {
        "\(round(fiveHourPercent))% · \(round(sevenDayPercent))%"
    }

    private func round(_ p: Double) -> Int {
        Int(p.rounded())
    }
}
