import Foundation
import SwiftUI

@MainActor
@Observable
final class Preferences {
    var pollInterval: TimeInterval {
        didSet { UserDefaults.standard.set(pollInterval, forKey: Keys.pollInterval) }
    }
    var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }
    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            LaunchAtLogin.set(launchAtLogin)
        }
    }
    var estimatorMode: PercentEstimator.Mode {
        didSet { UserDefaults.standard.set(estimatorMode.rawValue, forKey: Keys.estimatorMode) }
    }
    var modelWeightsJSON: String {
        didSet { UserDefaults.standard.set(modelWeightsJSON, forKey: Keys.modelWeightsJSON) }
    }

    enum Keys {
        static let pollInterval = "pref.pollInterval"
        static let alwaysOnTop = "pref.alwaysOnTop"
        static let launchAtLogin = "pref.launchAtLogin"
        static let estimatorMode = "pref.estimatorMode"
        static let modelWeightsJSON = "pref.modelWeightsJSON"
    }

    init() {
        let d = UserDefaults.standard
        self.pollInterval = d.object(forKey: Keys.pollInterval) as? TimeInterval ?? 30
        self.alwaysOnTop = d.bool(forKey: Keys.alwaysOnTop)
        self.launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        if let raw = d.string(forKey: Keys.estimatorMode),
           let m = PercentEstimator.Mode(rawValue: raw) {
            self.estimatorMode = m
        } else {
            self.estimatorMode = .scalar
        }
        self.modelWeightsJSON = d.string(forKey: Keys.modelWeightsJSON) ?? ""
    }

    func currentModelWeights() -> ModelWeights {
        guard !modelWeightsJSON.isEmpty,
              let data = modelWeightsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(ModelWeights.self, from: data) else {
            return .default
        }
        return decoded
    }

    func resetModelWeights() {
        modelWeightsJSON = ""
    }
}
