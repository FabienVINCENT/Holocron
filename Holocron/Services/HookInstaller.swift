import Foundation

/// Installs / uninstalls Holocron's hooks in Claude Code's user settings
/// (`~/.claude/settings.json`), preserving everything else in the file.
///
/// Strategy:
/// - the hook binary shipped in `Holocron.app/Contents/Helpers/` is copied to
///   `~/Library/Application Support/Holocron/bin/holocron-hook` so the wiring
///   survives the app being moved or updated;
/// - every entry Holocron writes calls that binary, and uninstall simply
///   removes entries whose command references it;
/// - a timestamped backup of settings.json is written before each change.
struct HookInstaller {
    enum InstallError: LocalizedError {
        case bundledHookMissing
        case settingsUnreadable(String)

        var errorDescription: String? {
            switch self {
            case .bundledHookMissing:
                return "The holocron-hook helper is missing from the app bundle."
            case .settingsUnreadable(let path):
                return "\(path) exists but is not valid JSON — fix or remove it, then retry."
            }
        }
    }

    let home: URL
    let appSupport: URL
    let bundledHookURL: URL?

    static let hookMarker = "holocron-hook"

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         appSupport: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
         bundledHookURL: URL? = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/holocron-hook")) {
        self.home = home
        self.appSupport = appSupport
        self.bundledHookURL = bundledHookURL
    }

    var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    var installedHookURL: URL {
        appSupport.appendingPathComponent("Holocron/bin/holocron-hook")
    }

    var isInstalled: Bool {
        guard let settings = try? readSettings() else { return false }
        return Self.containsHolocronEntries(settings)
    }

    // MARK: - Install

    /// The PreToolUse matcher: which tools get intercepted in the notch.
    /// Everything else never even spawns the hook process.
    func install(interceptMatcher: String) throws {
        try copyHookBinary()
        var settings = try readSettings() ?? [:]
        try backupSettingsIfPresent()

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        let bin = installedHookURL.path

        func entry(_ subcommand: String, matcher: String?, timeout: Int) -> [String: Any] {
            var value: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": "\"\(bin)\" \(subcommand)",
                    "timeout": timeout,
                ]]
            ]
            if let matcher { value["matcher"] = matcher }
            return value
        }

        let plan: [(event: String, entry: [String: Any])] = [
            // Blocking interception: waits for the notch decision (fails open).
            ("PreToolUse", entry("pretooluse", matcher: interceptMatcher, timeout: 600)),
            // Clears cards if the tool ran anyway (auto-allowed elsewhere).
            ("PostToolUse", entry("posttooluse", matcher: interceptMatcher, timeout: 10)),
            // Degraded-mode alerts (terminal is prompting) + status.
            ("Notification", entry("notification", matcher: nil, timeout: 10)),
            // Turn finished → status + sound.
            ("Stop", entry("stop", matcher: nil, timeout: 10)),
            // Session lifecycle + terminal identity capture (ITERM_SESSION_ID).
            ("SessionStart", entry("sessionstart", matcher: nil, timeout: 10)),
            ("SessionEnd", entry("sessionend", matcher: nil, timeout: 10)),
        ]

        for (event, newEntry) in plan {
            var entries = (hooks[event] as? [[String: Any]] ?? [])
                .filter { !Self.isHolocronEntry($0) }
            entries.append(newEntry)
            hooks[event] = entries
        }
        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    func uninstall() throws {
        guard var settings = try readSettings() else { return }
        guard var hooks = settings["hooks"] as? [String: Any] else { return }
        try backupSettingsIfPresent()

        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.filter { !Self.isHolocronEntry($0) }
            if kept.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = kept
            }
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        try writeSettings(settings)
    }

    /// Re-copies the bundled hook binary (called at every launch: cheap, and
    /// keeps the installed helper in sync with the app version).
    func copyHookBinary() throws {
        guard let bundledHookURL,
              FileManager.default.fileExists(atPath: bundledHookURL.path) else {
            throw InstallError.bundledHookMissing
        }
        let destination = installedHookURL
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: bundledHookURL, to: destination)
        chmod(destination.path, 0o755)
    }

    // MARK: - settings.json plumbing

    static func isHolocronEntry(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { ($0["command"] as? String)?.contains(hookMarker) == true }
    }

    static func containsHolocronEntries(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]])?.contains(where: isHolocronEntry) == true
        }
    }

    private func readSettings() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.settingsUnreadable(settingsURL.path)
        }
        return json
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    private func backupSettingsIfPresent() throws {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = settingsURL.deletingLastPathComponent()
            .appendingPathComponent("settings.json.holocron-backup-\(formatter.string(from: Date()))")
        try? FileManager.default.copyItem(at: settingsURL, to: backup)
        pruneBackups(keeping: 5)
    }

    private func pruneBackups(keeping: Int) {
        let directory = settingsURL.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        let backups = files
            .filter { $0.lastPathComponent.hasPrefix("settings.json.holocron-backup-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in backups.dropFirst(keeping) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
