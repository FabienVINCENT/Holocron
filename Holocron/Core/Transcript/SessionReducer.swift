import Foundation

/// Folds transcript lines into an `AgentSession`. One reducer per transcript
/// file; pure logic, fully unit-testable.
struct SessionReducer {
    private(set) var session: AgentSession
    private var pendingToolUses: [String: ToolActivity] = [:]

    static let maxRecentItems = 12
    static let maxPreviewLength = 600

    init(sessionId: String, transcriptURL: URL) {
        self.session = AgentSession(id: sessionId, transcriptURL: transcriptURL)
    }

    mutating func apply(_ lines: [TranscriptLine]) {
        for line in lines { apply(line) }
        session.runningTools = Array(pendingToolUses.values)
            .sorted { ($0.startedAt ?? .distantPast) < ($1.startedAt ?? .distantPast) }
    }

    private mutating func apply(_ line: TranscriptLine) {
        // Sidechains are subagent traffic inside the same session: they count
        // as activity but must not overwrite the main thread's last message.
        let isSidechain = line.isSidechain ?? false

        if session.cwd == nil { session.cwd = line.cwd }
        if session.gitBranch == nil || line.gitBranch != nil {
            session.gitBranch = line.gitBranch ?? session.gitBranch
        }
        if let timestamp = line.timestamp {
            if session.startedAt == nil { session.startedAt = timestamp }
            if timestamp > (session.lastActivityAt ?? .distantPast) {
                session.lastActivityAt = timestamp
            }
        }
        if let entrypoint = line.entrypoint, session.agentKind == .unknown {
            // Best-effort origin detection. Orca drives Claude Code through
            // its normal CLI entrypoint, so `entrypoint` alone cannot prove
            // Orca; SessionStore refines this using process context from
            // hooks. Anything non-CLI is still surfaced as-is.
            session.agentKind = entrypoint.lowercased().contains("orca") ? .orca : .claudeCode
        }

        switch line.type {
        case "assistant":
            applyAssistant(line, isSidechain: isSidechain)
        case "user":
            applyUser(line, isSidechain: isSidechain)
        case "system":
            break
        case "summary":
            if let summary = line.summary, session.lastAssistantText == nil {
                session.lastAssistantText = Self.preview(summary)
            }
        case "queue-operation", "last-prompt":
            if let content = line.content, !isSidechain {
                session.lastUserPrompt = Self.preview(content)
            }
        default:
            break
        }
        if !isSidechain { session.lastLineType = line.type }
    }

    private mutating func applyAssistant(_ line: TranscriptLine, isSidechain: Bool) {
        guard let message = line.message else { return }
        if let usage = message.usage { session.usage.add(usage) }
        if session.model == nil { session.model = message.model }
        if !isSidechain, let stop = message.stopReason {
            session.lastStopReason = stop
        } else if !isSidechain {
            session.lastStopReason = nil
        }

        for block in message.content?.blocks ?? [] {
            switch block {
            case .text(let text):
                if !isSidechain, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    session.lastAssistantText = Self.preview(text)
                }
            case .toolUse(let id, let name, let input):
                let activity = ToolActivity(
                    toolUseId: id,
                    name: name,
                    detail: Self.toolDetail(name: name, input: input),
                    startedAt: line.timestamp
                )
                pendingToolUses[id] = activity
                recordArtifacts(name: name, input: input)
            case .thinking, .toolResult, .unknown:
                break
            }
        }
    }

    private mutating func applyUser(_ line: TranscriptLine, isSidechain: Bool) {
        guard let message = line.message else { return }
        var sawToolResult = false
        for block in message.content?.blocks ?? [] {
            switch block {
            case .toolResult(let toolUseId, _):
                sawToolResult = true
                if let toolUseId { pendingToolUses.removeValue(forKey: toolUseId) }
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !isSidechain, !sawToolResult, !trimmed.isEmpty,
                   !trimmed.hasPrefix("<") {  // skip system-reminder / meta turns
                    session.lastUserPrompt = Self.preview(trimmed)
                }
            default:
                break
            }
        }
    }

    private mutating func recordArtifacts(name: String, input: JSONValue) {
        switch name {
        case "Bash":
            if let command = input["command"]?.stringValue {
                appendCapped(&session.recentCommands, Self.preview(command, limit: 120))
            }
        case "Edit", "Write", "Read", "NotebookEdit", "MultiEdit":
            if let path = input["file_path"]?.stringValue {
                appendCapped(&session.recentFiles, path)
            }
        default:
            break
        }
    }

    private func appendCapped(_ list: inout [String], _ item: String) {
        if let existing = list.firstIndex(of: item) { list.remove(at: existing) }
        list.append(item)
        if list.count > Self.maxRecentItems { list.removeFirst(list.count - Self.maxRecentItems) }
    }

    static func toolDetail(name: String, input: JSONValue) -> String {
        let raw: String
        switch name {
        case "Bash": raw = input["command"]?.stringValue ?? ""
        case "Edit", "Write", "Read", "NotebookEdit", "MultiEdit":
            raw = input["file_path"]?.stringValue ?? ""
        case "Grep": raw = input["pattern"]?.stringValue ?? ""
        case "Glob": raw = input["pattern"]?.stringValue ?? ""
        case "WebFetch": raw = input["url"]?.stringValue ?? ""
        case "Agent", "Task": raw = input["description"]?.stringValue ?? ""
        case "AskUserQuestion": raw = ""
        default: raw = input.objectValue == nil ? "" : input.compactDescription
        }
        return preview(raw, limit: 160)
    }

    static func preview(_ text: String, limit: Int = SessionReducer.maxPreviewLength) -> String {
        let flattened = text.replacingOccurrences(of: "\r", with: "")
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit)) + "…"
    }
}
