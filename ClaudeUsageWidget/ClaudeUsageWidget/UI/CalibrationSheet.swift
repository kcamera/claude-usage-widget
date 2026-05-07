import SwiftUI

struct CalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UsageStore.self) private var usageStore
    @Environment(CalibrationStore.self) private var calibrationStore

    let window: WindowKind

    @State private var serverPercent: String = ""
    @State private var note: String = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calibrate \(window.longLabel)")
                    .font(.system(size: 14, weight: .semibold))
                Text("Open claude.ai/settings/usage in your browser, then enter the current % the page shows for the \(window.longLabel.lowercased()). The widget will adjust over time.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Server %")
                TextField("e.g. 17", text: $serverPercent)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("%").foregroundStyle(.secondary)
                Spacer()
            }

            TextField("Note (optional)", text: $note)
                .textFieldStyle(.roundedBorder)

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func save() {
        guard let pct = Double(serverPercent.trimmingCharacters(in: .whitespaces)) else {
            error = "Enter a number for Server %"
            return
        }
        guard pct >= 0, pct <= 200 else {
            error = "Server % should be between 0 and 200"
            return
        }
        let snapshot = usageStore.snapshotForCalibration(window: window)
        let sample = CalibrationSample(
            window: window,
            serverPercent: pct,
            weightedTokenSnapshot: snapshot.weightedTotal,
            perModelTokenSnapshot: snapshot.perModel,
            note: note.isEmpty ? nil : note
        )
        calibrationStore.add(sample)
        usageStore.refreshFromDisk()
        dismiss()
    }
}
