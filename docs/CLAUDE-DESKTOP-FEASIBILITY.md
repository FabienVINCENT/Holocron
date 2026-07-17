# Claude desktop app — feasibility report (investigation module)

**Status: investigated, NOT implemented beyond a read-only probe. v1 makes no
architectural bet on the desktop app.**

The official Claude desktop app is an Electron application. Unlike Claude
Code, it exposes **no plain-text transcripts, no hooks, and no public
automation API**. This report enumerates every local surface we identified,
what it would give us, and what it would cost. The in-app probe
(Settings → Advanced → “Probe Claude desktop app surfaces”) and
`scripts/investigate-claude-desktop.sh` re-check these surfaces on a real
machine — run them after desktop app updates, since none of this is a
contract.

## Surfaces

### 1. `~/Library/Application Support/Claude/` (Electron user-data dir)

| Item | Readable? | Useful? |
|---|---|---|
| `claude_desktop_config.json` | ✅ plain JSON | MCP server config only — no session state |
| `Local Storage/leveldb/` | ⚠️ binary LevelDB | UI prefs/keys; conversations are **not** stored here in clear form |
| `IndexedDB/` | ⚠️ binary, Chromium blob format | Cache fragments at best; schema undocumented and version-unstable |
| `Session Storage/`, `Cookies` | ⚠️ | Auth/session tokens — deliberately out of scope (secrets, ToS risk) |

Reading LevelDB/IndexedDB of a **running** Chromium app is unreliable by
construction (LOCK files, compaction, write-ahead logs) and the schema is an
implementation detail that changes with releases. Conversations live
server-side; there is no local “conversation store” to tail. **Verdict:
not viable as a state source.**

### 2. `~/Library/Logs/Claude/`

`mcp.log` / `mcp-server-*.log` contain MCP server lifecycle messages —
startup, errors — but no conversation content. Cheap to tail, and could
power a tiny “desktop app MCP server X is failing” indicator. **Verdict:
viable but low value; deferred.**

### 3. Accessibility API (AX)

Electron apps expose a meaningful AX tree only after the client sets the
undocumented `AXManualAccessibility` attribute on the app, and the tree then
mirrors the DOM. It is possible to detect coarse states (a “Claude is
responding” spinner, a permission dialog for MCP tools) by walking that tree.

Costs: requires the Accessibility permission (heavier than Automation),
polling (CPU), and selectors break on every UI redesign — this is
screen-scraping. **Verdict: the only viable interaction surface, but
fragile; acceptable only as an optional, clearly-labeled “best effort”
module. Not in v1.**

### 4. Local sockets / ports

The desktop app talks to MCP servers over **stdio pipes of child
processes**, not connectable sockets. No documented local HTTP/IPC port for
third parties. `scripts/investigate-claude-desktop.sh` includes an `lsof`
sweep to re-verify on a live machine. **Verdict: nothing to attach to.**

### 5. Claude Code sessions launched from the desktop app ✅

When the desktop app (or anything else) runs **Claude Code** sessions, they
write standard transcripts to `~/.claude/projects/` — which Holocron already
monitors. This is the one integration that works today, for free.

## Recommendation

- v1 stays 100% transcript-driven (Claude Code + Orca).
- The probe module ships (read-only, disabled unless run manually) so these
  findings can be re-verified over time.
- If desktop monitoring becomes a must-have, the AX route is the only
  candidate: prototype behind a feature flag, budget for breakage on every
  desktop app release, and require explicit user opt-in for the
  Accessibility permission.
