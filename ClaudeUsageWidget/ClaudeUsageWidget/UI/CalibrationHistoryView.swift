import SwiftUI

struct CalibrationHistoryView: View {
    @Environment(CalibrationStore.self) private var calibrationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Calibration samples")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !calibrationStore.samples.isEmpty {
                    Button("Clear all", role: .destructive) {
                        calibrationStore.clear()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
            }
            if calibrationStore.samples.isEmpty {
                Text("No samples yet. Use Calibrate on the panel to add one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Table(calibrationStore.samples) {
                    TableColumn("When") { sample in
                        Text(sample.timestamp.formatted(date: .abbreviated, time: .shortened))
                    }
                    TableColumn("Window") { sample in
                        Text(sample.window.label)
                    }
                    TableColumn("Server %") { sample in
                        Text(String(format: "%.1f%%", sample.serverPercent))
                    }
                    TableColumn("Local wt tokens") { sample in
                        Text(sample.weightedTokenSnapshot.formattedTokens())
                    }
                    TableColumn("") { sample in
                        Button {
                            calibrationStore.remove(id: sample.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .width(28)
                }
                .frame(minHeight: 200)
            }
        }
    }
}
