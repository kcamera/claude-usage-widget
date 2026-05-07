import SwiftUI
import AppKit

@main
struct ClaudeUsageWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                togglePanel: { appDelegate.panelController.toggle() },
                refresh: { appDelegate.usageStore.refreshFromDisk() }
            )
            .environment(appDelegate.usageStore)
            .environment(appDelegate.preferences)
            .environment(appDelegate.calibrationStore)
        } label: {
            MenuBarLabel(
                fiveHourPercent: appDelegate.usageStore.fiveHour.softPercent,
                sevenDayPercent: appDelegate.usageStore.sevenDay.softPercent
            )
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    let togglePanel: () -> Void
    let refresh: () -> Void
    @Environment(UsageStore.self) private var usageStore

    var body: some View {
        Button(percentLine()) {}
            .disabled(true)
        Divider()
        Button("Show / hide panel") { togglePanel() }
            .keyboardShortcut("p")
        Button("Refresh now") { refresh() }
            .keyboardShortcut("r")
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func percentLine() -> String {
        let f = Int(usageStore.fiveHour.softPercent.rounded())
        let s = Int(usageStore.sevenDay.softPercent.rounded())
        return "5h: \(f)%  ·  7d: \(s)%"
    }
}
