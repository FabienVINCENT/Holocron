import Foundation

/// IPC contract between the `holocron-hook` CLI (spawned by Claude Code for
/// each hook event) and the Holocron app (Unix domain socket server).
///
/// Wire format: one JSON object per line (newline-delimited), UTF-8.
/// The hook sends a single `HookEnvelope`, then — for blocking events only
/// (PreToolUse) — waits for a single `HookReply` line.
enum HookWire {
    static let protocolVersion = 1

    /// Socket path. Kept short: sockaddr_un paths are limited to ~104 bytes.
    static func socketURL(appSupport: URL? = nil) -> URL {
        let base = appSupport ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Holocron", isDirectory: true)
            .appendingPathComponent("hook.sock", isDirectory: false)
    }
}

/// Hook events forwarded to the app. Raw values are the CLI subcommands and
/// match Claude Code hook event names (lowercased).
enum HookEvent: String, Codable, Sendable {
    case preToolUse = "pretooluse"
    case postToolUse = "posttooluse"
    case notification = "notification"
    case stop = "stop"
    case sessionStart = "sessionstart"
    case sessionEnd = "sessionend"

    /// Blocking events: the hook waits for the app's decision before letting
    /// Claude Code continue. Everything else is fire-and-forget.
    var expectsReply: Bool { self == .preToolUse }
}

struct HookEnvelope: Codable, Sendable {
    let v: Int
    let event: HookEvent
    let context: HookProcessContext
    /// Verbatim stdin JSON from Claude Code (schema owned by Claude Code).
    let payload: JSONValue
}

/// Snapshot of the hook process environment. Because the hook inherits the
/// Claude Code process environment — which inherits the terminal's — this is
/// how sessions get tied to their exact iTerm2 tab (ITERM_SESSION_ID) and how
/// Orca-driven sessions are recognized.
struct HookProcessContext: Codable, Sendable {
    let pid: Int32
    let ppid: Int32
    let tty: String?
    let itermSessionId: String?
    let termSessionId: String?
    let termProgram: String?
    let isOrca: Bool

    static func capture() -> HookProcessContext {
        let env = ProcessInfo.processInfo.environment
        var ttyName: String?
        if let cName = ttyname(STDIN_FILENO) ?? ttyname(STDERR_FILENO) {
            ttyName = String(cString: cName)
        }
        let orcaMarkers = ["ORCA_SESSION_ID", "ORCA_AGENT_ID", "ORCA_RUN_ID", "ORCA"]
        return HookProcessContext(
            pid: ProcessInfo.processInfo.processIdentifier,
            ppid: getppid(),
            tty: ttyName,
            itermSessionId: env["ITERM_SESSION_ID"],
            termSessionId: env["TERM_SESSION_ID"],
            termProgram: env["TERM_PROGRAM"],
            isOrca: orcaMarkers.contains { env[$0] != nil }
        )
    }
}

struct HookReply: Codable, Sendable {
    enum Action: String, Codable, Sendable {
        /// Emit permissionDecision=allow (skips the terminal prompt).
        case allow
        /// Emit permissionDecision=deny with a reason.
        case deny
        /// Emit nothing: Claude Code's normal permission flow decides.
        case passthrough
        /// AskUserQuestion only: deny the tool call while carrying the
        /// selected answer in the reason, which Claude receives as feedback.
        case answer
    }

    let action: Action
    let reason: String?

    static let passthrough = HookReply(action: .passthrough, reason: nil)

    /// The JSON the hook must print on stdout for Claude Code, or nil to
    /// print nothing (passthrough).
    func stdoutJSON() -> String? {
        let decision: String
        let reasonText: String
        switch action {
        case .passthrough:
            return nil
        case .allow:
            decision = "allow"
            reasonText = reason ?? "Approved from Holocron"
        case .deny:
            decision = "deny"
            reasonText = reason ?? "Denied from Holocron"
        case .answer:
            decision = "deny"
            reasonText = reason ?? "Answered from Holocron"
        }
        let output: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": decision,
                "permissionDecisionReason": reasonText,
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: output),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}

/// Typed accessors over the PreToolUse stdin payload
/// (https://code.claude.com/docs/en/hooks — fields: session_id,
/// transcript_path, cwd, permission_mode, tool_name, tool_input).
struct PreToolUseInfo: Sendable {
    let sessionId: String?
    let transcriptPath: String?
    let cwd: String?
    let permissionMode: String?
    let toolName: String
    let toolInput: JSONValue

    init(payload: JSONValue) {
        sessionId = payload["session_id"]?.stringValue
        transcriptPath = payload["transcript_path"]?.stringValue
        cwd = payload["cwd"]?.stringValue
        permissionMode = payload["permission_mode"]?.stringValue
        toolName = payload["tool_name"]?.stringValue ?? "?"
        toolInput = payload["tool_input"] ?? .null
    }
}

/// Parsed AskUserQuestion tool input. Schema is not formally documented;
/// tolerant parsing with graceful degradation to raw JSON display.
struct AskUserQuestionInput: Sendable {
    struct Option: Sendable {
        let label: String
        let description: String?
    }
    struct Question: Sendable {
        let text: String
        let header: String?
        let multiSelect: Bool
        let options: [Option]
    }

    let questions: [Question]

    init?(toolInput: JSONValue) {
        guard let rawQuestions = toolInput["questions"]?.arrayValue, !rawQuestions.isEmpty else {
            return nil
        }
        questions = rawQuestions.compactMap { raw in
            guard let text = raw["question"]?.stringValue else { return nil }
            let options = (raw["options"]?.arrayValue ?? []).compactMap { rawOption -> Option? in
                if let label = rawOption["label"]?.stringValue {
                    return Option(label: label, description: rawOption["description"]?.stringValue)
                }
                if let label = rawOption.stringValue {
                    return Option(label: label, description: nil)
                }
                return nil
            }
            return Question(
                text: text,
                header: raw["header"]?.stringValue,
                multiSelect: raw["multiSelect"]?.boolValue ?? false,
                options: options
            )
        }
        if questions.isEmpty { return nil }
    }
}
