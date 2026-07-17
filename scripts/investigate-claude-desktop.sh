#!/usr/bin/env bash
# Read-only survey of the Claude desktop app's local surfaces.
# Companion to docs/CLAUDE-DESKTOP-FEASIBILITY.md — run it on your Mac after
# desktop app updates to see whether any new surface appeared.
set -uo pipefail

section() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }

section "Support directory (~/Library/Application Support/Claude)"
SUPPORT="$HOME/Library/Application Support/Claude"
if [ -d "$SUPPORT" ]; then
  ls -la "$SUPPORT" | head -30
  for d in "Local Storage/leveldb" "IndexedDB" "Session Storage"; do
    if [ -d "$SUPPORT/$d" ]; then
      printf '%-28s %s entries, %s\n' "$d:" \
        "$(find "$SUPPORT/$d" -maxdepth 1 | wc -l | tr -d ' ')" \
        "$(du -sh "$SUPPORT/$d" 2>/dev/null | cut -f1)"
    fi
  done
  [ -f "$SUPPORT/claude_desktop_config.json" ] \
    && echo "claude_desktop_config.json present (MCP config, plain JSON)"
else
  echo "not found — desktop app not installed?"
fi

section "Logs (~/Library/Logs/Claude)"
LOGS="$HOME/Library/Logs/Claude"
[ -d "$LOGS" ] && ls -la "$LOGS" | head -20 || echo "not found"

section "Running Claude desktop processes"
pgrep -fl "Claude" | grep -v "$$" | head -10 || echo "none running"

section "Listening sockets/ports owned by Claude processes"
PIDS=$(pgrep -f "Claude.app" | tr '\n' ',' | sed 's/,$//')
if [ -n "${PIDS}" ]; then
  lsof -a -p "$PIDS" -i -P 2>/dev/null | head -20 || echo "none"
  echo "-- unix sockets --"
  lsof -a -p "$PIDS" -U 2>/dev/null | head -20 || echo "none"
else
  echo "app not running"
fi

section "Claude Code CLI state (~/.claude) — already covered by Holocron"
[ -d "$HOME/.claude/projects" ] \
  && echo "projects dir: $(find "$HOME/.claude/projects" -name '*.jsonl' | wc -l | tr -d ' ') transcript files" \
  || echo "no ~/.claude/projects"

printf '\nDone. Interpretation guide: docs/CLAUDE-DESKTOP-FEASIBILITY.md\n'
