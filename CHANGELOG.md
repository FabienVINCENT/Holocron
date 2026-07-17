# Changelog

All notable changes to Holocron. Release notes are extracted from the
matching `## [x.y.z]` section by the release workflow.

## [Unreleased]

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
