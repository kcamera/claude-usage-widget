import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject {
    private var panel: DraggablePanel?
    private let usageStore: UsageStore
    private let preferences: Preferences
    private let calibrationStore: CalibrationStore

    /// Initial panel width. Height is driven by SwiftUI content via NSHostingController self-sizing.
    private let panelWidth: CGFloat = 520

    init(usageStore: UsageStore, preferences: Preferences, calibrationStore: CalibrationStore) {
        self.usageStore = usageStore
        self.preferences = preferences
        self.calibrationStore = calibrationStore
        super.init()
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        if let panel {
            applyAlwaysOnTop()
            panel.orderFrontRegardless()
            return
        }

        let content = PanelView()
            .environment(usageStore)
            .environment(preferences)
            .environment(calibrationStore)
            .frame(width: panelWidth)

        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]

        let panel = DraggablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 200),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.acceptsMouseMovedEvents = true
        panel.contentViewController = hosting

        // Round the corners of the content
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 14
            contentView.layer?.masksToBounds = true
        }

        // Force first layout, then explicitly resize the panel to the content's fitting size
        // (NSHostingController self-sizing happens asynchronously, which broke our positioning).
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize
        if fitting.height > 0 && fitting.width > 0 {
            panel.setContentSize(fitting)
        }

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let frame = panel.frame
            let origin = NSPoint(
                x: visible.maxX - frame.width - 24,
                y: visible.maxY - frame.height - 24
            )
            panel.setFrameOrigin(origin)
        }

        self.panel = panel
        applyAlwaysOnTop()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func applyAlwaysOnTop() {
        guard let panel else { return }
        panel.level = preferences.alwaysOnTop ? .floating : .normal
        if preferences.alwaysOnTop {
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        } else {
            panel.collectionBehavior = [.fullScreenAuxiliary]
        }
    }
}

final class DraggablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
