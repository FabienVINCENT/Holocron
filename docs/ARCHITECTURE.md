# Holocron — Architecture

Holocron is **transcript-driven**: the source of truth is the JSONL
transcripts Claude Code writes for every session. Hooks add exactness
(permissions, questions, lifecycle, terminal identity) on top.

```
   ~/.claude/projects/**/*.jsonl                Claude Code hooks
              │  FSEvents                              │ stdin JSON
              ▼                                        ▼
      TranscriptWatcher                        holocron-hook (CLI)
              │ changed files                          │ Unix socket (NDJSON)
              ▼                                        ▼
   TranscriptTail → TranscriptParser            HookServer (BSD socket)
              │ TranscriptLine[]                       │ HookEnvelope
              ▼                                        ▼
        SessionReducer  ──────────────►  SessionStore ◄── InteractionCenter
              (per file)      AgentSession[]   │  ▲            │ PendingInteraction[]
                                               ▼  │            ▼
                                        SwiftUI notch UI (NSPanel non-activating)
                                               │
                          TerminalJump (iTerm2 AppleScript) · SoundEngine · Sparkle
```

## Modules

| Module | Files | Role |
|---|---|---|
| Core/Models | `TranscriptLine`, `AgentSession`, `JSONValue`, `PendingInteraction`, `TerminalAttachment` | Codable models; tolerant decoding (transcript format is not a public contract) |
| Core/Transcript | `TranscriptParser`, `TranscriptTail`, `SessionReducer`, `TranscriptWatcher` | Streaming JSONL → per-session state; FSEvents watching; O(new bytes) reads |
| Core/Hooks | `HookProtocol`, `PermissionRuleMirror` | IPC wire format (shared with the CLI); best-effort mirror of `permissions.allow` |
| Core/Usage | `UsageAggregator` | Rolling 5h token window (burn gauge — see honesty note in README) |
| HookCLI | `main.swift` | The `holocron-hook` binary Claude Code invokes; fail-open by design |
| Services | `HookServer`, `HookInstaller`, `SoundEngine`, `HotKeyManager`, `NotificationService`, `Updater`, `TerminalJump/*`, `DesktopProbe/*` | Side-effecting layers |
| Store | `AppSettings`, `SessionStore`, `InteractionCenter`, `AppState` | Observable state; composition root |
| UI | `NotchPanelController`, `NotchRootView`, `CompactPillView`, `ExpandedPanelView`, `SessionRowView`, `InteractionCardView`, `MarkdownBlockView`, `UsageFooterView`, `SettingsView`, `Theme` | SwiftUI in a borderless non-activating `NSPanel` |

## Key decisions

**Sessions come from transcripts, not from hooks.** Transcripts exist for
every session (Claude Code direct, Orca-driven, resumed…), even when Holocron
starts late or hooks aren't installed. Hooks are an enhancement layer:
without them you still get the monitor; with them you get permission cards,
exact lifecycle, and terminal identity.

**Status inference.** Per session: pending hook card → waiting-permission/
question (exact). Otherwise from the transcript: unresolved `tool_use` →
running; last line is a user prompt → running (thinking); completed assistant
turn (`stop_reason`) → waiting-for-input; stale → idle; `SessionEnd` → done.

**PreToolUse interception is fail-open.** The hook binary exits 0 with no
output whenever the app is missing, the socket is dead, or the user doesn't
answer in time — Claude Code then shows its normal terminal prompt. A deny
can only ever come from an explicit human click/hotkey.

**Why PermissionRuleMirror exists.** PreToolUse hooks fire *before* Claude
Code evaluates permission rules. Without a mirror of the user's allow rules,
every `git status` would raise a notch card even though Claude Code would
auto-approve it. Matching a mirrored allow rule → immediate `passthrough`.
The mirror is best-effort (drift risk documented in the source); mismatches
degrade to the normal terminal prompt, never to silent approval. `deny`/`ask`
rules need no mirror: Claude Code still enforces them even after a hook
"allow".

**AskUserQuestion answering.** Hooks have no official "answer the question"
API. Holocron denies the tool call with a structured reason carrying the
selected option ("The user answered via Holocron — proceed with…"), which
Claude receives as feedback and acts on. Documented trade-off, toggleable
(Settings → Permissions); when disabled, questions surface as jump-to-terminal
cards.

**Terminal matching (jump).** The hook inherits the environment of the shell
that launched `claude`, so every envelope carries `ITERM_SESSION_ID`
(`w0t2p0:GUID` — the GUID equals the AppleScript `id` of the iTerm2 session)
plus the controlling `tty`. Jump = AppleScript scan of windows/tabs/sessions
matching GUID first, tty second. No fuzzy cwd matching: a wrong-tab jump is
worse than an error. Other terminals implement `TerminalIntegration`.

**Non-activating panel.** `NSPanel(.nonactivatingPanel)` with
`canBecomeKey = false`, level above the status bar, on all Spaces. Buttons
work via mouse without stealing keyboard focus from the terminal. Because the
panel never becomes key, decision shortcuts (⌘Y/⌘N/⌘1…4) are Carbon global
hotkeys registered **only while a card is pending** — a deliberate,
short-lived system-wide capture, toggleable in Settings.

**Orca support.** Orca drives real Claude Code sessions, so transcripts appear
automatically. Detection: `ORCA_*` environment markers seen by the hook
(badge in the UI); extra transcript roots configurable in Settings in case
Orca ever relocates session storage.

**Memory/CPU budget.** No polling anywhere: FSEvents (transcripts), blocking
socket accepts (hooks), timers only at 30s for time-derived statuses.
Transcript reads are incremental from the stored offset; initial backfill of
huge files is capped (last 4 MB) and flagged `isPartialParse`.
