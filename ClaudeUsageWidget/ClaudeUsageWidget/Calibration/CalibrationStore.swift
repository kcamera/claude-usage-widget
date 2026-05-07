import Foundation

@MainActor
@Observable
final class CalibrationStore {
    private(set) var samples: [CalibrationSample] = []
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("ClaudeUsageWidget", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("calibrations.json")
        load()
    }

    func add(_ sample: CalibrationSample) {
        samples.append(sample)
        samples.sort { $0.timestamp < $1.timestamp }
        save()
    }

    func remove(id: UUID) {
        samples.removeAll { $0.id == id }
        save()
    }

    func clear() {
        samples.removeAll()
        save()
    }

    var fiveHourSamples: [CalibrationSample] { samples.filter { $0.window == .fiveHour } }
    var sevenDaySamples: [CalibrationSample] { samples.filter { $0.window == .sevenDay } }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([CalibrationSample].self, from: data) {
            samples = loaded.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(samples) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
