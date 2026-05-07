import SwiftUI
import AppKit

/// Claude logomark approximation — an 8-pointed rounded asterisk.
/// SwiftUI view (looks nicer than a single-Path Shape — each ray is its own Capsule).
struct ClaudeMark: View {
    var color: Color = Theme.claudeOrange
    var size: CGFloat = 18

    var body: some View {
        let rayLength = size * 0.9
        let rayThickness = size * 0.18
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: rayThickness, height: rayLength)
                    .offset(y: -size * 0.06)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Pre-rendered NSImage of the Claude mark, suitable for `MenuBarExtra` labels
/// where complex SwiftUI views don't rasterize reliably. Marked as a template
/// so the system tints it for menu bar light/dark/focus states.
@MainActor
enum ClaudeMarkImage {
    static let menuBar: NSImage = {
        let view = ClaudeMark(color: .black, size: 18)
            .padding(2)
            .frame(width: 22, height: 22)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 22, height: 22))
        image.isTemplate = true
        return image
    }()
}
