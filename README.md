# Holocron

A native macOS **notch app** ("Dynamic Island"-style) to monitor and drive
your **Claude Code** agent sessions — including sessions orchestrated by
**Orca** — without leaving your flow.

> A holocron stores the knowledge of the masters. This one watches your
> agents.

- **See every session at a glance**: project, branch, status (running /
  waiting / idle / done), last message, current tool, files & commands.
- **Approve/deny permissions from the notch** (⌘Y / ⌘N) via Claude Code
  hooks — with your existing allow-rules respected.
- **Answer `AskUserQuestion`** with ⌘1…⌘4, review plans (Markdown) before
  approving.
- **Jump to the session's host**: exact iTerm2 tab/split, Terminal.app tab,
  PhpStorm/JetBrains project window, or the Claude desktop app — Orca
  sessions route to wherever Orca runs.
- **8-bit synthesized alerts** (permission, question, done, error) —
  per-event toggles.
- **Token burn gauge** over the rolling 5-hour window.
- 100% local & native: Swift/SwiftUI/AppKit, no Electron, no account, no
  telemetry. Target: macOS 15 (Sequoia)+, Apple Silicon.

## How it works

Holocron is **transcript-driven**: it watches
`~/.claude/projects/**/*.jsonl` (the JSONL transcripts Claude Code writes
for every session) with FSEvents and parses them incrementally. That covers
Claude Code *and* Orca-driven sessions automatically — Orca launches real
Claude Code sessions underneath. Extra transcript directories can be added
in Settings if Orca ever stores sessions elsewhere.

On top, Holocron installs **Claude Code hooks** (optional but recommended)
for the interactive parts:

| Hook | Purpose |
|---|---|
| `PreToolUse` (matcher: `Bash\|Edit\|Write\|MultiEdit\|NotebookEdit\|ExitPlanMode\|AskUserQuestion`) | Blocks synchronously, shows the card in the notch, returns `permissionDecision: allow/deny` |
| `PostToolUse` | Clears stale cards |
| `Notification` | Degraded mode: “the terminal is prompting” alert + jump |
| `Stop` / `SessionStart` / `SessionEnd` | Turn/lifecycle status, sounds, terminal identity capture |

The hook helper is **fail-open by design**: if Holocron isn't running or you
don't answer in time, it exits silently and Claude Code's normal terminal
prompt takes over. A deny can only come from an explicit click/hotkey.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design,
including the permission-rule mirror, the AskUserQuestion answer mechanism
(deny-with-reason — hooks have no official answer API), and the iTerm2
matching strategy (`ITERM_SESSION_ID` GUID, then tty).

## Build

Requirements: Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
make generate   # xcodegen generate → Holocron.xcodeproj
make build      # Release build via xcodebuild
make test       # unit tests
make run        # build & open the app
make dmg        # package dist/Holocron-<version>.dmg
```

Targets: `Holocron` (the app), `holocron-hook` (CLI helper embedded in
`Contents/Helpers/`), `HolocronTests`.

## First run

1. Launch the app — the notch pill appears on the built-in display (a
   floating top-center bar on Macs/displays without a notch). `⌃⌥H`
   toggles the expanded panel; hovering the pill expands it too.
2. Accept the **hooks install** prompt (or Settings → Permissions →
   Install). This edits `~/.claude/settings.json` — existing content is
   preserved and a timestamped backup is written next to it. Uninstall from
   the same place restores a hook-free config.
3. The first “Jump to terminal” asks for the **Automation** permission
   (Apple Events → iTerm2). If you decline, jumping is disabled until you
   re-enable it in System Settings → Privacy & Security → Automation.
4. Optionally allow **notifications** for alerts when the notch isn't
   visible.

New Claude Code / Orca sessions appear automatically; sessions already
running appear at their next transcript write. Terminal identity (for jump)
is captured from the first hook event of each session.

## Permissions summary

| macOS permission | Why | Required? |
|---|---|---|
| Automation (Apple Events → iTerm2) | Jump to the session's tab | Only for jump |
| Notifications | Alerts when the notch is hidden | Optional |
| ~~Accessibility~~ | Not needed — global hotkeys use Carbon `RegisterEventHotKey` | — |

## Usage / quota — honest limitation

Anthropic rate limits (5-hour window, weekly caps) are enforced
**server-side** and Claude Code does not persist "remaining quota" anywhere
on disk. Holocron therefore shows what *can* be computed locally: token
consumption aggregated from transcripts over the rolling 5-hour window (a
**burn gauge**, clearly labeled — not a remaining-quota gauge). If Claude
Code ever exposes quota locally, `UsageAggregator` is where it plugs in.

## Claude desktop app (official)

Investigated, not implemented: the desktop app exposes no transcripts, no
hooks, and no automation API; its local stores are binary Chromium caches
and conversations live server-side. Full report:
[docs/CLAUDE-DESKTOP-FEASIBILITY.md](docs/CLAUDE-DESKTOP-FEASIBILITY.md).
A read-only probe ships in Settings → Advanced (plus
`scripts/investigate-claude-desktop.sh`) to re-check surfaces after desktop
app updates. Note: Claude Code sessions *launched from* the desktop app
write normal transcripts and are already monitored.

## Updates & releases

Auto-updates via **Sparkle 2** with EdDSA signatures, feed hosted on GitHub
Releases (`appcast.xml`). CI (`.github/workflows/`):

- `ci.yml` — build + tests on every PR/push to `main`.
- `release.yml` — on `v*` tags: build → DMG → EdDSA sign → appcast → GitHub
  Release. Requires the `SPARKLE_PRIVATE_KEY` secret.

Setup, key generation, and the release procedure:
[docs/RELEASE.md](docs/RELEASE.md).

⚠️ **Gatekeeper**: builds are not notarized yet (no Apple Developer ID).
First launch: right-click → Open. Notarization is a documented TODO.

## Privacy

Everything stays on your machine. Holocron reads local transcripts, listens
on a user-only Unix socket, and never makes network calls except Sparkle
update checks against GitHub Releases.

## License

[MIT](LICENSE)
