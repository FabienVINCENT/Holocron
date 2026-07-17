import Foundation

/// One line of a Claude Code transcript (`~/.claude/projects/<dir>/<uuid>.jsonl`).
///
/// The format is an implementation detail of Claude Code and is not officially
/// documented, so every field is optional and unknown line types are kept
/// (with `type` preserved) instead of failing. Validated against real
/// transcripts produced by Claude Code 2.x:
///
/// - `type`: "user" | "assistant" | "system" | "summary" | "attachment"
///   | "queue-operation" | "last-prompt" | "progress" | …
/// - assistant lines carry `message` (Anthropic API message shape: `content`
///   blocks of type text / thinking / tool_use, plus `usage`, `model`,
///   `stop_reason`).
/// - user lines carry either a plain prompt (string content) or
///   `tool_result` blocks.
struct TranscriptLine: Decodable, Sendable {
    let type: String
    let uuid: String?
    let parentUuid: String?
    let sessionId: String?
    let timestamp: Date?
    let cwd: String?
    let gitBranch: String?
    let version: String?
    let isSidechain: Bool?
    let entrypoint: String?
    let message: TranscriptMessage?
    /// "summary" lines: human-readable summary of a (compacted) session.
    let summary: String?
    /// "system" lines: subtype such as "turn_duration", "compact_boundary"…
    let subtype: String?
    /// "queue-operation" lines: the queued prompt text.
    let content: String?

    enum CodingKeys: String, CodingKey {
        case type, uuid, parentUuid, sessionId, timestamp, cwd, gitBranch
        case version, isSidechain, entrypoint, message, summary, subtype, content
    }
}

struct TranscriptMessage: Decodable, Sendable {
    let role: String?
    let model: String?
    let stopReason: String?
    let usage: TokenUsage?
    let content: MessageContent?

    enum CodingKeys: String, CodingKey {
        case role, model, usage, content
        case stopReason = "stop_reason"
    }
}

/// `message.content` is either a plain string (user prompts) or an array of
/// typed blocks (assistant output, tool results).
enum MessageContent: Decodable, Sendable {
    case text(String)
    case blocks([ContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else {
            self = .blocks(try container.decode([ContentBlock].self))
        }
    }

    var blocks: [ContentBlock] {
        switch self {
        case .text(let text): return [.text(text)]
        case .blocks(let blocks): return blocks
        }
    }
}

enum ContentBlock: Decodable, Sendable {
    case text(String)
    case thinking
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String?, isError: Bool)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? "unknown"
        switch type {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "thinking", "redacted_thinking":
            self = .thinking
        case "tool_use":
            self = .toolUse(
                id: try container.decodeIfPresent(String.self, forKey: .id) ?? "",
                name: try container.decodeIfPresent(String.self, forKey: .name) ?? "?",
                input: try container.decodeIfPresent(JSONValue.self, forKey: .input) ?? .null
            )
        case "tool_result":
            self = .toolResult(
                toolUseId: try container.decodeIfPresent(String.self, forKey: .toolUseId),
                isError: try container.decodeIfPresent(Bool.self, forKey: .isError) ?? false
            )
        default:
            self = .unknown(type: type)
        }
    }
}

struct TokenUsage: Decodable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}

enum TranscriptJSON {
    /// Decoder configured for transcript timestamps
    /// (ISO 8601, with or without fractional seconds).
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = isoFractional.date(from: raw) ?? isoPlain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized timestamp: \(raw)"
            )
        }
        return decoder
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
