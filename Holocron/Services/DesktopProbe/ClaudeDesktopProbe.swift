import Foundation

/// Claude **desktop app** investigation module — exploration only.
///
/// The desktop app exposes no transcripts, no hooks, and no public
/// automation API, so Holocron makes NO architectural bet on it (see
/// docs/CLAUDE-DESKTOP-FEASIBILITY.md for the full report). This probe only
/// enumerates which local surfaces exist on this machine so the feasibility
/// findings can be re-checked after app updates. Disabled unless explicitly
/// run from Settings → Advanced.
struct ClaudeDesktopProbe {
    struct Finding: Identifiable, Sendable {
        let id = UUID()
        let surface: String
        let path: String
        let exists: Bool
        let detail: String
    }

    /// Non-destructive, read-only checks. Runs in <10ms.
    static func run(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Finding] {
        let fileManager = FileManager.default

        func check(_ surface: String, _ relativePath: String, detail: String) -> Finding {
            let url = home.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            var info = detail
            if exists, isDirectory.boolValue,
               let children = try? fileManager.contentsOfDirectory(atPath: url.path) {
                info += " — \(children.count) entries"
            }
            return Finding(surface: surface, path: url.path, exists: exists, detail: info)
        }

        return [
            check("App support (Electron)",
                  "Library/Application Support/Claude",
                  detail: "Electron user-data dir: Local Storage (LevelDB), IndexedDB, Session Storage, Cookies"),
            check("Local Storage (LevelDB)",
                  "Library/Application Support/Claude/Local Storage/leveldb",
                  detail: "Binary LevelDB; keys/settings, no readable conversation store"),
            check("IndexedDB",
                  "Library/Application Support/Claude/IndexedDB",
                  detail: "Per-origin blobs; conversations are server-side, cache only"),
            check("Logs",
                  "Library/Logs/Claude",
                  detail: "App + MCP server logs (mcp*.log); startup/errors, no chat content"),
            check("Claude Code CLI state (shared)",
                  ".claude",
                  detail: "The CLI state the desktop app may reuse when running Claude Code sessions"),
            check("Desktop-launched Claude Code transcripts",
                  ".claude/projects",
                  detail: "If the desktop app spawns Claude Code sessions, they land here and Holocron already sees them"),
        ]
    }
}
