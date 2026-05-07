import SwiftUI
import Combine

struct PanelView: View {
    @Environment(UsageStore.self) private var usageStore
    @Environment(Preferences.self) private var preferences
    @Environment(CalibrationStore.self) private var calibrationStore

    @State private var showCalibrationSheet = false
    @State private var calibrationWindow: WindowKind = .fiveHour
    @State private var showPreferences = false
    @State private var now: Date = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 12) {
            header

            VStack(spacing: 12) {
                WindowSection(summary: usageStore.fiveHour, now: now) {
                    calibrationWindow = .fiveHour
                    showCalibrationSheet = true
                }
                WindowSection(summary: usageStore.sevenDay, now: now) {
                    calibrationWindow = .sevenDay
                    showCalibrationSheet = true
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 12)
        .background(Theme.panelBackground)
        .onReceive(timer) { now = $0 }
        .sheet(isPresented: $showCalibrationSheet) {
            CalibrationSheet(window: calibrationWindow)
                .environment(usageStore)
                .environment(calibrationStore)
        }
        .sheet(isPresented: $showPreferences) {
            PreferencesView()
                .environment(preferences)
                .environment(usageStore)
                .environment(calibrationStore)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ClaudeMark(size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text("Claude Usage")
                    .font(.system(size: 14, weight: .semibold))
                Text(updatedDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { usageStore.refreshFromDisk() } label: {
                Image(systemName: usageStore.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            .keyboardShortcut("r")

            Toggle(isOn: alwaysOnTopBinding) {
                Image(systemName: preferences.alwaysOnTop ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .help(preferences.alwaysOnTop ? "Always on top" : "Pin to keep on top")

            Button { showPreferences = true } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Preferences")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var alwaysOnTopBinding: Binding<Bool> {
        Binding(
            get: { preferences.alwaysOnTop },
            set: { newValue in
                preferences.alwaysOnTop = newValue
                NotificationCenter.default.post(name: .claudeUsageAlwaysOnTopChanged, object: nil)
            }
        )
    }

    private var updatedDescription: String {
        guard usageStore.lastUpdated > .distantPast else { return "Loading…" }
        let secondsAgo = Int(now.timeIntervalSince(usageStore.lastUpdated))
        if secondsAgo < 2 { return "Updated just now" }
        if secondsAgo < 60 { return "Updated \(secondsAgo)s ago" }
        return "Updated \(secondsAgo / 60)m ago"
    }
}

extension Notification.Name {
    static let claudeUsageAlwaysOnTopChanged = Notification.Name("claudeUsageAlwaysOnTopChanged")
}
