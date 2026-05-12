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
    /// Recognizes:
    ///   - `type:"assistant"` lines with a `message.usage` block (the bulk of usage)
    ///   - `type:"system" subtype:"compact_boundary"` lines, which carry
    ///     `compactMetadata.preTokens` (context the compaction read) and
    ///     `postTokens` (summary it produced). Synthesized into a UsageEvent
    ///     attributed to the most recent assistant model seen in this stream
    ///     so compaction cost flows through the same weighted-tokens pipeline.
    /// Other line types are silently skipped.
    static func parseLines(_ data: Data, projectPath: String) -> [UsageEvent] {
        var events: [UsageEvent] = []
        events.reserveCapacity(64)

        // Last assistant model seen in this stream, used to attribute
        // compaction cost. Falls back to "unknown" (treated as Opus by the
        // pricing prior) when a chunk begins with a compaction boundary
        // before any assistant event has been parsed.
        var lastAssistantModel: String = "unknown"

        var start = data.startIndex
        let end = data.endIndex
        while start < end {
            var i = start
            while i < end && data[i] != 0x0A { // '\n'
                i = data.index(after: i)
            }
            if start < i {
                let lineData = data[start..<i]
                if let event = parseLine(lineData, projectPath: projectPath, lastAssistantModel: lastAssistantModel) {
                    // Updating from a synthesized compaction event is a no-op
                    // (it copies lastAssistantModel into its own model field),
                    // so we can update unconditionally.
                    lastAssistantModel = event.model
                    events.append(event)
                }
            }
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

    static func parseLine(_ data: Data, projectPath: String, lastAssistantModel: String = "unknown") -> UsageEvent? {
        guard !data.isEmpty else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        guard let type = json["type"] as? String else { return nil }

        switch type {
        case "assistant":
            return parseAssistantUsage(json: json, projectPath: projectPath)
        case "system":
            if (json["subtype"] as? String) == "compact_boundary" {
                return parseCompactBoundary(json: json, projectPath: projectPath, lastAssistantModel: lastAssistantModel)
            }
            return nil
        default:
            return nil
        }
    }

    private static func parseAssistantUsage(json: [String: Any], projectPath: String) -> UsageEvent? {
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

    /// Synthesize a UsageEvent from a `compact_boundary` system event.
    ///
    /// Compaction is server-side work that produces no `assistant` event in
    /// the JSONL — its cost would otherwise be invisible. The boundary
    /// event carries `compactMetadata.preTokens` (the context the
    /// compaction call read) and `postTokens` (the summary it produced),
    /// which we map to `cacheReadTokens` and `outputTokens` respectively.
    /// Pre-compaction context is virtually always cached at this point in
    /// a session, so cache_read is the correct bucket on the input side.
    /// We attribute the cost to the most recent assistant model in the
    /// stream because the user can't choose a model for compaction itself.
    private static func parseCompactBoundary(json: [String: Any], projectPath: String, lastAssistantModel: String) -> UsageEvent? {
        guard let timestampStr = json["timestamp"] as? String else { return nil }
        let timestamp = isoFormatter.date(from: timestampStr)
            ?? isoFormatterNoFrac.date(from: timestampStr)
        guard let ts = timestamp else { return nil }
        guard let meta = json["compactMetadata"] as? [String: Any] else { return nil }
        let preTokens = (meta["preTokens"] as? Int) ?? 0
        let postTokens = (meta["postTokens"] as? Int) ?? 0
        if preTokens == 0 && postTokens == 0 { return nil }

        let sessionId = (json["sessionId"] as? String) ?? ""
        let uuid = (json["uuid"] as? String) ?? ""

        return UsageEvent(
            timestamp: ts,
            model: lastAssistantModel,
            modelFamily: ModelFamily.derive(from: lastAssistantModel),
            inputTokens: 0,
            outputTokens: postTokens,
            cacheCreationTokens: 0,
            cacheReadTokens: preTokens,
            sessionId: sessionId,
            projectPath: projectPath,
            uuid: uuid
        )
    }
}
