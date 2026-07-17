import Foundation

/// Best-effort mirror of Claude Code permission *allow* rules.
///
/// Why this exists: PreToolUse hooks fire before Claude Code evaluates
/// permission rules, so without this mirror the notch would interrupt for
/// commands the user has already allow-listed (e.g. `Bash(git *)`). When a
/// call matches a mirrored allow rule, Holocron replies `passthrough`
/// immediately and Claude Code's own engine auto-approves it.
///
/// Fidelity notes (documented drift risk):
/// - Only `permissions.allow` is mirrored. `deny`/`ask` rules need no mirror:
///   they are still enforced by Claude Code even when a hook says "allow",
///   and a passthrough on an unmatched call just shows the normal prompt.
/// - Supported patterns: `Tool`, `Tool(exact)`, `Bash(prefix:*)`,
///   glob specifiers (`*`/`?`) for path/url-style tools.
/// - Unknown/unparsable rules are ignored (fail open to the terminal prompt,
///   never to auto-approval).
struct PermissionRuleMirror: Sendable {
    struct Rule: Sendable {
        let tool: String
        let specifier: String?   // nil = whole tool allowed
    }

    private(set) var rules: [Rule] = []

    init(allowPatterns: [String]) {
        rules = allowPatterns.compactMap(Self.parse)
    }

    /// Loads and merges allow rules the way Claude Code does (user scope +
    /// project scope + project-local scope; arrays merge across scopes).
    static func load(home: URL, projectCwd: String?) -> PermissionRuleMirror {
        var patterns: [String] = []
        var candidates = [home.appendingPathComponent(".claude/settings.json")]
        if let projectCwd {
            let projectRoot = URL(fileURLWithPath: projectCwd)
            candidates.append(projectRoot.appendingPathComponent(".claude/settings.json"))
            candidates.append(projectRoot.appendingPathComponent(".claude/settings.local.json"))
        }
        for file in candidates {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let permissions = json["permissions"] as? [String: Any],
                  let allow = permissions["allow"] as? [String] else { continue }
            patterns.append(contentsOf: allow)
        }
        return PermissionRuleMirror(allowPatterns: patterns)
    }

    static func parse(_ pattern: String) -> Rule? {
        let trimmed = pattern.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard let open = trimmed.firstIndex(of: "(") else {
            return Rule(tool: trimmed, specifier: nil)
        }
        guard trimmed.hasSuffix(")") else { return nil }
        let tool = String(trimmed[trimmed.startIndex..<open])
        let specifier = String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
        guard !tool.isEmpty else { return nil }
        return Rule(tool: tool, specifier: specifier.isEmpty ? nil : specifier)
    }

    func allows(toolName: String, toolInput: JSONValue) -> Bool {
        for rule in rules where rule.tool == toolName {
            guard let specifier = rule.specifier else { return true }
            if matches(specifier: specifier, toolName: toolName, toolInput: toolInput) {
                return true
            }
        }
        return false
    }

    private func matches(specifier: String, toolName: String, toolInput: JSONValue) -> Bool {
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
            return Self.globMatch(pattern: specifier, subject: subject)
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
