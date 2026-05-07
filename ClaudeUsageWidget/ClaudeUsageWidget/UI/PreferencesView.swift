import SwiftUI

struct PreferencesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralPreferencesTab()
                    .padding(20)
                    .tabItem { Label("General", systemImage: "gearshape") }
                CalibrationPreferencesTab()
                    .padding(20)
                    .tabItem { Label("Calibration", systemImage: "scope") }
                AdvancedPreferencesTab()
                    .padding(20)
                    .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 580, height: 560)
    }
}

private struct GeneralPreferencesTab: View {
    @Environment(Preferences.self) private var preferences
    @Environment(UsageStore.self) private var usageStore

    var body: some View {
        @Bindable var prefs = preferences
        Form {
            Section("Refresh") {
                Slider(value: $prefs.pollInterval, in: 5...300, step: 5) {
                    Text("Poll interval")
                } minimumValueLabel: {
                    Text("5s").font(.caption)
                } maximumValueLabel: {
                    Text("5m").font(.caption)
                }
                Text("\(Int(preferences.pollInterval))s — file system events trigger updates instantly; this is the safety-net poll.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Window") {
                Toggle("Always on top", isOn: $prefs.alwaysOnTop)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $prefs.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferences.pollInterval) { _, newValue in
            usageStore.updatePollInterval(newValue)
        }
    }
}

private struct CalibrationPreferencesTab: View {
    @Environment(Preferences.self) private var preferences
    @Environment(UsageStore.self) private var usageStore
    @Environment(CalibrationStore.self) private var calibrationStore

    var body: some View {
        @Bindable var prefs = preferences
        VStack(alignment: .leading, spacing: 16) {
            Picker("Estimator mode", selection: $prefs.estimatorMode) {
                Text("Scalar (recommended)").tag(PercentEstimator.Mode.scalar)
                Text("Per-model (advanced)").tag(PercentEstimator.Mode.perModel)
            }
            .pickerStyle(.segmented)
            Text(estimatorExplainer)
                .font(.caption)
                .foregroundStyle(.secondary)

            CalibrationHistoryView()
                .environment(calibrationStore)
        }
        .onChange(of: preferences.estimatorMode) { _, _ in usageStore.refreshFromDisk() }
    }

    private var estimatorExplainer: String {
        switch preferences.estimatorMode {
        case .scalar:
            return "Fits one scalar that maps weighted tokens to %. Robust with as few as 2 samples per window."
        case .perModel:
            return "Fits a per-model coefficient (Opus, Sonnet, Haiku, …) — learns each model's true cost. Needs more samples covering varied model mixes."
        }
    }
}

private struct AdvancedPreferencesTab: View {
    @Environment(Preferences.self) private var preferences
    @Environment(UsageStore.self) private var usageStore

    var body: some View {
        @Bindable var prefs = preferences
        VStack(alignment: .leading, spacing: 12) {
            Text("Model weights (JSON)")
                .font(.system(size: 13, weight: .semibold))
            Text("Override the pricing prior used to weight tokens before estimation. Leave blank to use defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $prefs.modelWeightsJSON)
                .font(.system(size: 11, design: .monospaced))
                .frame(minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))

            HStack {
                Button("Load defaults") {
                    if let data = try? JSONEncoder().encode(ModelWeights.default),
                       let s = String(data: data, encoding: .utf8) {
                        preferences.modelWeightsJSON = s
                    }
                }
                Button("Reset") { preferences.resetModelWeights() }
                Spacer()
                Button("Refresh now") { usageStore.refreshFromDisk() }
                    .keyboardShortcut("r")
            }
        }
    }
}
