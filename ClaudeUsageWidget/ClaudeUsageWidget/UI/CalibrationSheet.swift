import SwiftUI

struct CalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UsageStore.self) private var usageStore
    @Environment(CalibrationStore.self) private var calibrationStore

    let window: WindowKind

    @State private var serverPercent: String = ""
    @State private var note: String = ""
    @State private var error: String?

    @State private var isFirstInEpoch: Bool = false

    // 5-hour relative entry
    @State private var resetsInHours: String = ""
    @State private var resetsInMinutes: String = ""

    // 7-day absolute entry (default: a week from now)
    @State private var sevenDayResetsAt: Date = Date().addingTimeInterval(7 * 24 * 60 * 60)

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

            Toggle(isOn: $isFirstInEpoch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("First sample in a new window")
                        .font(.system(size: 12))
                    Text("Check this if claude.ai just reset to a fresh window. The widget will use the reset time below as the boundary.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)

            if isFirstInEpoch {
                resetEntry
                    .padding(.leading, 22)
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
        .frame(width: 420)
    }

    @ViewBuilder
    private var resetEntry: some View {
        switch window {
        case .fiveHour:
            HStack(spacing: 6) {
                Text("Resets in")
                    .font(.system(size: 12))
                TextField("h", text: $resetsInHours)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Text("hours").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("m", text: $resetsInMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Text("minutes").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
            }
        case .sevenDay:
            HStack(spacing: 6) {
                Text("Resets at")
                    .font(.system(size: 12))
                DatePicker(
                    "",
                    selection: $sevenDayResetsAt,
                    in: Date()...Date().addingTimeInterval(7 * 24 * 60 * 60),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                Spacer()
            }
        }
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

        var resetsAt: Date? = nil
        if isFirstInEpoch {
            switch window {
            case .fiveHour:
                let h = Int(resetsInHours.trimmingCharacters(in: .whitespaces)) ?? 0
                let m = Int(resetsInMinutes.trimmingCharacters(in: .whitespaces)) ?? 0
                let total = h * 3600 + m * 60
                guard total > 0 else {
                    error = "Enter the time remaining until reset"
                    return
                }
                guard total <= 5 * 3600 else {
                    error = "5-hour window resets in 5 hours or less"
                    return
                }
                resetsAt = Date().addingTimeInterval(TimeInterval(total))
            case .sevenDay:
                guard sevenDayResetsAt > Date() else {
                    error = "Reset time must be in the future"
                    return
                }
                resetsAt = sevenDayResetsAt
            }
        }

        let snapshot = usageStore.snapshotForCalibration(window: window)
        let sample = CalibrationSample(
            window: window,
            serverPercent: pct,
            weightedTokenSnapshot: snapshot.weightedTotal,
            perModelTokenSnapshot: snapshot.perModel,
            note: note.isEmpty ? nil : note,
            isFirstInEpoch: isFirstInEpoch,
            resetsAt: resetsAt
        )
        calibrationStore.add(sample)
        usageStore.refreshFromDisk()
        dismiss()
    }
}
