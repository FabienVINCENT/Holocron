import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    static let defaultInterceptMatcher =
        "Bash|Edit|Write|MultiEdit|NotebookEdit|ExitPlanMode|AskUserQuestion"

    /// Extra transcript roots (e.g. if Orca writes sessions somewhere else
    /// than ~/.claude/projects). Absolute paths, one per entry.
    var additionalTranscriptDirs: [String] {
        didSet { defaults.set(additionalTranscriptDirs, forKey: "additionalTranscriptDirs") }
    }

    /// Route permission prompts to the notch (PreToolUse interception).
    var interceptPermissions: Bool {
        didSet { defaults.set(interceptPermissions, forKey: "interceptPermissions") }
    }

    /// Which tools are intercepted (Claude Code hook matcher syntax).
    var interceptMatcher: String {
        didSet { defaults.set(interceptMatcher, forKey: "interceptMatcher") }
    }

    /// Answer AskUserQuestion from the notch. Relies on deny-with-reason
    /// feedback (no official "answer" API in hooks) — see README.
    var answerQuestionsFromNotch: Bool {
        didSet { defaults.set(answerQuestionsFromNotch, forKey: "answerQuestionsFromNotch") }
    }

    /// Seconds before an unanswered card resolves itself.
    var decisionTimeoutSeconds: Int {
        didSet { defaults.set(decisionTimeoutSeconds, forKey: "decisionTimeoutSeconds") }
    }

    /// What an unanswered card does on timeout: hand back to the terminal
    /// prompt (`passthrough`, safe default) or `deny`.
    var timeoutAction: HookReply.Action {
        didSet { defaults.set(timeoutAction.rawValue, forKey: "timeoutAction") }
    }

    /// Minutes without transcript activity before a session shows as idle.
    var idleAfterMinutes: Int {
        didSet { defaults.set(idleAfterMinutes, forKey: "idleAfterMinutes") }
    }

    /// Hours after which quiet sessions disappear from the list.
    var retentionHours: Int {
        didSet { defaults.set(retentionHours, forKey: "retentionHours") }
    }

    // Sounds (8-bit synth), individually toggleable.
    var soundMasterVolume: Double {
        didSet { defaults.set(soundMasterVolume, forKey: "soundMasterVolume") }
    }
    var soundOnPermission: Bool {
        didSet { defaults.set(soundOnPermission, forKey: "soundOnPermission") }
    }
    var soundOnQuestion: Bool {
        didSet { defaults.set(soundOnQuestion, forKey: "soundOnQuestion") }
    }
    var soundOnDone: Bool {
        didSet { defaults.set(soundOnDone, forKey: "soundOnDone") }
    }
    var soundOnError: Bool {
        didSet { defaults.set(soundOnError, forKey: "soundOnError") }
    }

    /// While a card is pending, ⌘Y/⌘N (and ⌘1…⌘4 for questions) are captured
    /// system-wide via Carbon hotkeys. Off by default would be safer, but the
    /// capture window only exists while a card is on screen.
    var decisionHotkeysEnabled: Bool {
        didSet { defaults.set(decisionHotkeysEnabled, forKey: "decisionHotkeysEnabled") }
    }

    /// Global panel toggle hotkey (⌃⌥H).
    var panelHotkeyEnabled: Bool {
        didSet { defaults.set(panelHotkeyEnabled, forKey: "panelHotkeyEnabled") }
    }

    /// Post a macOS notification when a card appears while the panel is
    /// hidden or the screen has no notch visible.
    var systemNotifications: Bool {
        didSet { defaults.set(systemNotifications, forKey: "systemNotifications") }
    }

    /// The status bar icon is a fallback entry point; notch purists can
    /// hide it (Settings stay reachable via the gear in the panel).
    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        additionalTranscriptDirs = defaults.stringArray(forKey: "additionalTranscriptDirs") ?? []
        interceptPermissions = defaults.object(forKey: "interceptPermissions") as? Bool ?? true
        interceptMatcher = defaults.string(forKey: "interceptMatcher") ?? Self.defaultInterceptMatcher
        answerQuestionsFromNotch = defaults.object(forKey: "answerQuestionsFromNotch") as? Bool ?? true
        decisionTimeoutSeconds = defaults.object(forKey: "decisionTimeoutSeconds") as? Int ?? 120
        timeoutAction = HookReply.Action(
            rawValue: defaults.string(forKey: "timeoutAction") ?? "passthrough") ?? .passthrough
        idleAfterMinutes = defaults.object(forKey: "idleAfterMinutes") as? Int ?? 30
        retentionHours = defaults.object(forKey: "retentionHours") as? Int ?? 12
        soundMasterVolume = defaults.object(forKey: "soundMasterVolume") as? Double ?? 0.5
        soundOnPermission = defaults.object(forKey: "soundOnPermission") as? Bool ?? true
        soundOnQuestion = defaults.object(forKey: "soundOnQuestion") as? Bool ?? true
        soundOnDone = defaults.object(forKey: "soundOnDone") as? Bool ?? true
        soundOnError = defaults.object(forKey: "soundOnError") as? Bool ?? true
        decisionHotkeysEnabled = defaults.object(forKey: "decisionHotkeysEnabled") as? Bool ?? true
        panelHotkeyEnabled = defaults.object(forKey: "panelHotkeyEnabled") as? Bool ?? true
        systemNotifications = defaults.object(forKey: "systemNotifications") as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
    }

    var transcriptRoots: [URL] {
        var roots = [TranscriptWatcher.defaultRoot]
        for path in additionalTranscriptDirs where !path.isEmpty {
            roots.append(URL(fileURLWithPath: (path as NSString).expandingTildeInPath,
                             isDirectory: true))
        }
        return roots
    }
}
