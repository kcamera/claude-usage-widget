import Foundation

/// Tracks per-file byte offsets so we can avoid re-parsing whole .jsonl files on every refresh.
/// Persisted to disk so cold-start after a restart doesn't re-parse the entire history.
nonisolated final class IncrementalReader: Sendable {
    private struct Persisted: Codable {
        var offsets: [String: UInt64]
    }

    private let stateURL: URL
    private let lock = NSLock()
    nonisolated(unsafe) private var offsets: [String: UInt64] = [:]

    init(stateURL: URL) {
        self.stateURL = stateURL
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        guard let p = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        lock.lock()
        offsets = p.offsets
        lock.unlock()
    }

    private func persist() {
        lock.lock()
        let p = Persisted(offsets: offsets)
        lock.unlock()
        guard let data = try? JSONEncoder().encode(p) else { return }
        try? FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: stateURL, options: .atomic)
    }

    /// Read new bytes appended to `file` since last call. Returns the data slice and updates offset.
    /// If the file shrank (rotated/truncated), restarts from 0.
    func readNew(from file: URL) -> Data? {
        let path = file.path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else {
            return nil
        }

        lock.lock()
        let lastOffset = offsets[path] ?? 0
        lock.unlock()

        let startAt: UInt64
        if size < lastOffset {
            startAt = 0
        } else if size == lastOffset {
            return Data()
        } else {
            startAt = lastOffset
        }

        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: startAt)
        } catch { return nil }
        let data = (try? handle.readToEnd()) ?? Data()

        lock.lock()
        offsets[path] = size
        lock.unlock()
        persist()
        return data
    }

    /// Forget all offsets, so the next pass re-reads everything from scratch.
    func reset() {
        lock.lock()
        offsets.removeAll()
        lock.unlock()
        persist()
    }
}
