import SwiftUI

enum Theme {
    /// Official Claude brand orange ("Crail")
    static let claudeOrange = Color(red: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x57 / 255.0)

    static let opusColor = claudeOrange
    static let sonnetColor = Color(red: 0x6B / 255.0, green: 0x9B / 255.0, blue: 0xD8 / 255.0)
    static let haikuColor = Color(red: 0x8E / 255.0, green: 0xC9 / 255.0, blue: 0xA3 / 255.0)
    static let otherColor = Color.gray

    static func color(for family: ModelFamily) -> Color {
        switch family {
        case .opus: opusColor
        case .sonnet: sonnetColor
        case .haiku: haikuColor
        case .other: otherColor
        }
    }

    static let panelBackground = Color(NSColor.windowBackgroundColor)
    static let cardBackground = Color(NSColor.controlBackgroundColor)
}

extension Double {
    func clampedSoftPercent() -> Double {
        max(0, min(self, 999))
    }

    func formattedTokens() -> String {
        let v = self
        if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fk", v / 1_000) }
        return String(format: "%.0f", v)
    }
}

extension Int {
    func formattedTokens() -> String { Double(self).formattedTokens() }
}

extension TimeInterval {
    func formattedShortDuration() -> String {
        if self <= 0 { return "now" }
        let total = Int(self)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
