import Foundation

nonisolated struct LogParser: Sendable {
    static let claudeProjectsDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/projects", isDirectory: true)
    }()

    static func discoverSessionFiles() -> [URL] {
        let fm = FileManager.default
        let root = claudeProjectsDir
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for projectDir in projectDirs {
            let isDir = (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            guard let sessionFiles = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for file in sessionFiles where file.pathExtension == "jsonl" {
                files.append(file)
            }
        }
        return files
    }

    /// Parse all events from a Data slice (one JSON object per line).
    /// Events that aren't usage-bearing assistant events are silently skipped.
    static func parseLines(_ data: Data, projectPath: String) -> [UsageEvent] {
        var events: [UsageEvent] = []
        events.reserveCapacity(64)

        // Iterate by newline without allocating substrings up-front.
        var start = data.startIndex
        let end = data.endIndex
        while start < end {
            // Find next newline
            var i = start
            while i < end && data[i] != 0x0A { // '\n'
                i = data.index(after: i)
            }
            if start < i {
                let lineRange = start..<i
                let lineData = data[lineRange]
                if let event = parseLine(lineData, projectPath: projectPath) {
                    events.append(event)
                }
            }
            // Advance past the newline (if any)
            if i < end {
                start = data.index(after: i)
            } else {
                start = end
            }
        }
        return events
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseLine(_ data: Data, projectPath: String) -> UsageEvent? {
        guard !data.isEmpty else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        guard let type = json["type"] as? String, type == "assistant" else { return nil }
        guard let message = json["message"] as? [String: Any] else { return nil }
        guard let usage = message["usage"] as? [String: Any] else { return nil }
        guard let timestampStr = json["timestamp"] as? String else { return nil }
        let timestamp = isoFormatter.date(from: timestampStr)
            ?? isoFormatterNoFrac.date(from: timestampStr)
        guard let ts = timestamp else { return nil }

        let model = (message["model"] as? String) ?? "unknown"
        let inputTokens = (usage["input_tokens"] as? Int) ?? 0
        let outputTokens = (usage["output_tokens"] as? Int) ?? 0
        let cacheCreation = (usage["cache_creation_input_tokens"] as? Int) ?? 0
        let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

        // Skip events with zero usage (rare — keep noise out)
        if inputTokens == 0 && outputTokens == 0 && cacheCreation == 0 && cacheRead == 0 {
            return nil
        }

        let sessionId = (json["sessionId"] as? String) ?? ""
        let uuid = (json["uuid"] as? String) ?? ""

        return UsageEvent(
            timestamp: ts,
            model: model,
            modelFamily: ModelFamily.derive(from: model),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheCreationTokens: cacheCreation,
            cacheReadTokens: cacheRead,
            sessionId: sessionId,
            projectPath: projectPath,
            uuid: uuid
        )
    }
}
