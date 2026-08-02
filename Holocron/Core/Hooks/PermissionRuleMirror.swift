import Foundation

/// Best-effort mirror of Claude Code permission rules.
///
/// Why this exists: PreToolUse hooks fire before Claude Code evaluates
/// permission rules, so without this mirror the notch would interrupt for
/// commands the user has already allow-listed (e.g. `Bash(git *)`). When a
/// call matches a mirrored allow rule — and no deny/ask rule — Holocron
/// replies `passthrough` immediately and Claude Code's own engine
/// auto-approves it.
///
/// Claude Code precedence is deny > ask > allow: an allow match alone is
/// NOT enough to predict "no prompt", so deny/ask lists are mirrored too
/// and veto the passthrough.
///
/// Fidelity notes (documented drift risk):
/// - Supported patterns: `Tool`, `Tool(exact)`, `Bash(prefix:*)`,
///   glob specifiers (`*`/`?`) for path/url-style tools.
/// - Unknown/unparsable rules are ignored (fail open to the terminal prompt,
///   never to auto-approval).
struct PermissionRuleMirror: Sendable {
    struct Rule: Sendable {
        let tool: String
        let specifier: String?   // nil = whole tool
        let raw: String
    }

    enum Verdict: Equatable, Sendable {
        /// An allow rule matches and nothing vetoes it: Claude Code will
        /// auto-approve, no card needed.
        case autoAllowed(rule: String)
        /// No conclusive allow: Claude Code will prompt (or deny) — show
        /// the card.
        case wouldPrompt
    }

    private(set) var allowRules: [Rule] = []
    private(set) var vetoRules: [Rule] = []   // deny + ask

    init(allowPatterns: [String], denyPatterns: [String] = [], askPatterns: [String] = []) {
        allowRules = allowPatterns.compactMap(Self.parse)
        vetoRules = (denyPatterns + askPatterns).compactMap(Self.parse)
    }

    /// Loads and merges rules the way Claude Code does (user scope +
    /// project scope + project-local scope; arrays merge across scopes).
    static func load(home: URL, projectCwd: String?) -> PermissionRuleMirror {
        var allow: [String] = []
        var deny: [String] = []
        var ask: [String] = []
        var candidates = [home.appendingPathComponent(".claude/settings.json")]
        if let projectCwd {
            let projectRoot = URL(fileURLWithPath: projectCwd)
            candidates.append(projectRoot.appendingPathComponent(".claude/settings.json"))
            candidates.append(projectRoot.appendingPathComponent(".claude/settings.local.json"))
        }
        for file in candidates {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let permissions = json["permissions"] as? [String: Any] else { continue }
            allow.append(contentsOf: permissions["allow"] as? [String] ?? [])
            deny.append(contentsOf: permissions["deny"] as? [String] ?? [])
            ask.append(contentsOf: permissions["ask"] as? [String] ?? [])
        }
        return PermissionRuleMirror(allowPatterns: allow, denyPatterns: deny, askPatterns: ask)
    }

    func verdict(toolName: String, toolInput: JSONValue) -> Verdict {
        // deny/ask veto first — mirrors Claude Code's precedence.
        if firstMatch(in: vetoRules, toolName: toolName, toolInput: toolInput) != nil {
            return .wouldPrompt
        }
        if let rule = firstMatch(in: allowRules, toolName: toolName, toolInput: toolInput) {
            return .autoAllowed(rule: rule.raw)
        }
        return .wouldPrompt
    }

    /// Legacy convenience (tests).
    func allows(toolName: String, toolInput: JSONValue) -> Bool {
        if case .autoAllowed = verdict(toolName: toolName, toolInput: toolInput) { return true }
        return false
    }

    private func firstMatch(in rules: [Rule], toolName: String, toolInput: JSONValue) -> Rule? {
        rules.first { rule in
            guard rule.tool == toolName else { return false }
            guard let specifier = rule.specifier else { return true }
            return Self.matches(specifier: specifier, toolName: toolName, toolInput: toolInput)
        }
    }

    static func parse(_ pattern: String) -> Rule? {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let open = trimmed.firstIndex(of: "(") else {
            return Rule(tool: trimmed, specifier: nil, raw: trimmed)
        }
        guard trimmed.hasSuffix(")") else { return nil }
        let tool = String(trimmed[trimmed.startIndex..<open])
        let specifier = String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
        guard !tool.isEmpty else { return nil }
        return Rule(tool: tool, specifier: specifier.isEmpty ? nil : specifier, raw: trimmed)
    }

    static func matches(specifier: String, toolName: String, toolInput: JSONValue) -> Bool {
        let subject: String
        switch toolName {
        case "Bash":
            subject = toolInput["command"]?.stringValue ?? ""
        case "Edit", "Write", "Read", "NotebookEdit", "MultiEdit":
            subject = toolInput["file_path"]?.stringValue ?? ""
        case "WebFetch", "WebSearch":
            // "WebFetch(domain:example.com)" compares against the URL host.
            if specifier.hasPrefix("domain:") {
                let domain = String(specifier.dropFirst("domain:".count))
                let host = toolInput["url"]?.stringValue
                    .flatMap(URL.init(string:))?.host ?? ""
                return host == domain || host.hasSuffix("." + domain)
            }
            subject = toolInput["url"]?.stringValue ?? ""
        default:
            subject = toolInput.compactDescription
        }

        // Claude Code Bash rules use ":*" for prefix matching.
        if specifier.hasSuffix(":*") {
            let prefix = String(specifier.dropLast(2))
            return subject == prefix || subject.hasPrefix(prefix + " ") || subject.hasPrefix(prefix)
        }
        if specifier.contains("*") || specifier.contains("?") {
            return globMatch(pattern: specifier, subject: subject)
        }
        return subject == specifier
    }

    /// Minimal fnmatch-style glob: `*` any run, `?` single char.
    static func globMatch(pattern: String, subject: String) -> Bool {
        let patternChars = Array(pattern)
        let subjectChars = Array(subject)
        var memo: [String: Bool] = [:]

        func match(_ pi: Int, _ si: Int) -> Bool {
            let key = "\(pi):\(si)"
            if let cached = memo[key] { return cached }
            let result: Bool
            if pi == patternChars.count {
                result = si == subjectChars.count
            } else if patternChars[pi] == "*" {
                result = match(pi + 1, si) || (si < subjectChars.count && match(pi, si + 1))
            } else if si < subjectChars.count,
                      patternChars[pi] == "?" || patternChars[pi] == subjectChars[si] {
                result = match(pi + 1, si + 1)
            } else {
                result = false
            }
            memo[key] = result
            return result
        }
        return match(0, 0)
    }
}
