# Changelog

All notable changes to Holocron. Release notes are extracted from the
matching `## [x.y.z]` section by the release workflow.

## [Unreleased]

## [0.2.0]

### Added
- Living pill: breathing green dot while agents run, fast red pulse with a
  halo when a card awaits you; the menu bar icon shows the pending count.
- Launch at login (Settings → Shortcuts & alerts).
- Jump works across hosts: iTerm2 (exact tab/split), Terminal.app (tab by
  tty), PhpStorm & other JetBrains IDEs (focus the project window), and
  the official Claude desktop app (activate). Orca sessions route to
  wherever Orca runs. Hooks now capture TERMINAL_EMULATOR and
  __CFBundleIdentifier to identify the host.

### Changed
- The installed hook helper is refreshed automatically at app launch, so
  hook-side improvements apply without a manual Reinstall.

## [0.1.7]

### Fixed
- First-hover expansion stutter: the window now grows before the spring
  starts (next runloop tick), so every expansion plays inside a stable
  window — the smooth path that previously only quick re-hovers hit.
- Ghost hover zone while collapsing: only the pill rectangle is a hover
  target, so brushing the area the panel just vacated no longer reopens
  it (mouseMoved tracking added so sliding onto the pill still works).

## [0.1.6]

### Fixed
- The expanding panel no longer detaches and floats below the screen top:
  NSHostingView's default sizing constraints were fighting the window
  frame (sizingOptions = []).
- Hover-to-expand actually fires: the tracking-area owner methods were
  exported with Swift-mangled selectors (mouseEnteredWith:) that AppKit
  never sends; explicit @objc(mouseEntered:) names fix delivery.

## [0.1.5]

### Fixed
- Hover-to-expand now uses an AppKit tracking area (SwiftUI onHover missed
  most entries in the borderless panel) — opens reliably, no entry delay.
- Dynamic-Island-style transition: pill and board stay mounted at fixed
  sizes; only the clip shape animates. No more content re-layout churn.
- Settings no longer open a separate window (the repeated crash source):
  they render as a page inside the notch panel, with a close button.
- A stale hung instance is terminated at launch (it used to swallow all
  hover/clicks with an invisible stacked panel).

## [0.1.4]

### Fixed
- Expand/collapse oscillation: hover now only opens the panel; closing is
  decided by a pointer-position watcher immune to the spurious exit events
  emitted while the window resizes.
- Settings window hardened: owned by an NSWindowController, created via
  NSHostingController outside the notch panel's event dispatch.

### Changed
- Repo hygiene: the Sparkle tools distribution is no longer committed
  (CI downloads it); `sparkle/` is ignored.

## [0.1.3]

### Fixed
- Updater: ship a real Sparkle EdDSA public key (same key pair as r2-git2)
  and never start Sparkle without one — kills the "updater failed to start"
  dialog. Update controls hide when unconfigured.

### Changed
- Release pipeline aligned with r2-git2: version derived from the tag,
  `sign_update` EdDSA signature, hand-written appcast with CHANGELOG notes.

## [0.1.2]

### Fixed
- Smooth expand/collapse: only the SwiftUI content animates; the window is
  resized instantly (no more down-then-up glitch).
- Settings open from the notch gear (owned NSWindow).
- Jump to iTerm2 without hooks: locate the claude process by session cwd
  (ps + lsof) and match its tty.

### Added
- Menu bar icon can be hidden (Settings → General).

## [0.1.1]

### Fixed
- Pin the panel flush to the top of the screen (constrainFrameRect).
- Compact pill layout: wings around the notch, centered cluster elsewhere.

## [0.1.0]

First testable build: transcript-driven session monitor in the notch,
Claude Code hooks (permissions, questions, plan review), iTerm2 jump,
8-bit alert sounds, token burn gauge, Sparkle scaffolding.
