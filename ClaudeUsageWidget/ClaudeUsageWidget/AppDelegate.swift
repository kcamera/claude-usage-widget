import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences: Preferences
    let calibrationStore: CalibrationStore
    let usageStore: UsageStore
    let panelController: FloatingPanelController

    private var observer: NSObjectProtocol?

    override init() {
        let prefs = Preferences()
        let cal = CalibrationStore()
        let usage = UsageStore(preferences: prefs, calibrationStore: cal)
        self.preferences = prefs
        self.calibrationStore = cal
        self.usageStore = usage
        self.panelController = FloatingPanelController(
            usageStore: usage,
            preferences: prefs,
            calibrationStore: cal
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        usageStore.startWatching()
        panelController.show()
        observer = NotificationCenter.default.addObserver(
            forName: .claudeUsageAlwaysOnTopChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panelController.applyAlwaysOnTop() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Re-show panel when user clicks the Dock or app icon (no Dock here, but harmless).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController.show()
        return true
    }
}
