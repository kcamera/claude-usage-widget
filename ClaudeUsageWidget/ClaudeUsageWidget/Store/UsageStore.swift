import Foundation
import SwiftUI

@MainActor
@Observable
final class UsageStore {
    private(set) var fiveHour: WindowSummary
    private(set) var sevenDay: WindowSummary
    private(set) var lastUpdated: Date = .distantPast
    private(set) var isLoading: Bool = false

    let preferences: Preferences
    let calibrationStore: CalibrationStore

    private var allEvents: [UsageEvent] = []
    private let reader: IncrementalReader
    private var watcher: FSWatcher?
    private var pollTimer: PollTimer?

    init(preferences: Preferences, calibrationStore: CalibrationStore) {
        self.preferences = preferences
        self.calibrationStore = calibrationStore

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("ClaudeUsageWidget", isDirectory: true)
        self.reader = IncrementalReader(stateURL: dir.appendingPathComponent("offsets.json"))

        let now = Date()
        let emptyFive = WindowSummary(
            window: .fiveHour, perModel: [:], windowStart: now.addingTimeInterval(-WindowKind.fiveHour.duration),
            windowEnd: now, resetAt: nil, weightedTokens: 0, softPercent: 0, estimatorState: .estimated
        )
        let emptySeven = WindowSummary(
            window: .sevenDay, perModel: [:], windowStart: now.addingTimeInterval(-WindowKind.sevenDay.duration),
            windowEnd: now, resetAt: nil, weightedTokens: 0, softPercent: 0, estimatorState: .estimated
        )
        self.fiveHour = emptyFive
        self.sevenDay = emptySeven
    }

    func startWatching() {
        let path = LogParser.claudeProjectsDir.path
        try? FileManager.default.createDirectory(at: LogParser.claudeProjectsDir, withIntermediateDirectories: true)

        let watcher = FSWatcher(path: path) { [weak self] in
            Task { @MainActor in self?.refreshFromDisk() }
        }
        watcher.start()
        self.watcher = watcher

        let timer = PollTimer(interval: preferences.pollInterval) { [weak self] in
            self?.refreshFromDisk()
        }
        timer.start()
        self.pollTimer = timer

        // Initial cold load
        refreshFromDisk(coldStart: true)
    }

    func updatePollInterval(_ newInterval: TimeInterval) {
        preferences.pollInterval = newInterval
        pollTimer?.setInterval(newInterval)
    }

    func refreshFromDisk(coldStart: Bool = false) {
        guard !isLoading else { return }
        isLoading = true
        let weights = preferences.currentModelWeights()
        let mode = preferences.estimatorMode
        let samples = calibrationStore.samples
        let reader = self.reader
        let existingEvents = self.allEvents
        let isCold = coldStart || existingEvents.isEmpty

        Task.detached(priority: .userInitiated) {
            let events = await Self.loadEvents(
                reader: reader,
                existingEvents: existingEvents,
                forceFullRescan: isCold
            )
            let aggregator = WindowAggregator(weights: weights)
            let now = Date()
            let estimator = PercentEstimator(mode: mode, samples: samples)
            let fiveResetsAt = estimator.epochResetsAt(window: .fiveHour, now: now)
            let sevenResetsAt = estimator.epochResetsAt(window: .sevenDay, now: now)
            let five = aggregator.summarize(events: events, now: now, window: .fiveHour, epochResetsAt: fiveResetsAt) { totalW, perModelW in
                estimator.estimate(window: .fiveHour, weightedTokens: totalW, perModelWeighted: perModelW)
            }
            let seven = aggregator.summarize(events: events, now: now, window: .sevenDay, epochResetsAt: sevenResetsAt) { totalW, perModelW in
                estimator.estimate(window: .sevenDay, weightedTokens: totalW, perModelWeighted: perModelW)
            }
            await MainActor.run {
                self.allEvents = events
                self.fiveHour = five
                self.sevenDay = seven
                self.lastUpdated = now
                self.isLoading = false
            }
        }
    }

    nonisolated private static func loadEvents(
        reader: IncrementalReader,
        existingEvents: [UsageEvent],
        forceFullRescan: Bool
    ) async -> [UsageEvent] {
        if forceFullRescan { reader.reset() }

        let files = LogParser.discoverSessionFiles()

        // Drop events older than 7 days right away — they don't matter for either window
        let cutoff = Date().addingTimeInterval(-WindowKind.sevenDay.duration - 60 * 60)
        var keyed: [String: UsageEvent] = [:]
        keyed.reserveCapacity(existingEvents.count)
        for e in existingEvents where e.timestamp >= cutoff {
            keyed[Self.eventKey(e)] = e
        }

        for file in files {
            guard let data = reader.readNew(from: file), !data.isEmpty else { continue }
            let projectPath = file.deletingLastPathComponent().lastPathComponent
            let parsed = LogParser.parseLines(data, projectPath: projectPath)
            for e in parsed where e.timestamp >= cutoff {
                keyed[Self.eventKey(e)] = e
            }
        }

        return keyed.values.sorted { $0.timestamp < $1.timestamp }
    }

    nonisolated private static func eventKey(_ e: UsageEvent) -> String {
        if !e.uuid.isEmpty { return e.uuid }
        return "\(e.sessionId)|\(e.timestamp.timeIntervalSince1970)|\(e.model)"
    }

    func snapshotForCalibration(window: WindowKind) -> (weightedTotal: Double, perModel: [String: Double]) {
        let summary = (window == .fiveHour) ? fiveHour : sevenDay
        var perModel: [String: Double] = [:]
        for (id, m) in summary.perModel { perModel[id] = m.weightedTokens }
        return (summary.weightedTokens, perModel)
    }
}
