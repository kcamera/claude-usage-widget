import Foundation

struct UsageEvent: Hashable, Sendable {
    let timestamp: Date
    let model: String
    let modelFamily: ModelFamily
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let sessionId: String
    let projectPath: String
    let uuid: String
}
