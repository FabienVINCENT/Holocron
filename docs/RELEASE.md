# Releasing Holocron

The pipeline mirrors r2-git2's (same key pair, same appcast mechanics).

## One-time setup

Holocron's `Info.plist` already embeds the **same Sparkle public key as
r2-git2**. So the only step is:

- Copy the `SPARKLE_PRIVATE_KEY` secret from the r2-git2 repository to this
  one (GitHub → Holocron → Settings → Secrets and variables → Actions →
  New repository secret, paste the same value).

To rotate to a fresh key pair instead: run Sparkle's `generate_keys`
(tools tarball, same `SPARKLE_VERSION` as release.yml), put the public key
in `Holocron/Resources/Info.plist` → `SUPublicEDKey`, export the private
key with `generate_keys -x` into the secret.

## Cutting a release

Three equivalent triggers:

```sh
# A. Tag push (classic)
# bump MARKETING_VERSION (and CURRENT_PROJECT_VERSION) in project.yml
git commit -am "release: 0.2.0"
git tag v0.2.0
git push origin main v0.2.0

# B. VERSION file bump (works where tag pushes are blocked, e.g. remote
#    Claude Code sessions): edit VERSION, commit, push. auto-release.yml
#    builds and creates the tag v<VERSION> itself at that commit.

# C. Manual: Actions → Release → Run workflow, with the tag as input.
```

The released app's version comes from the tag (`MARKETING_VERSION` is
overridden at build time; the value in project.yml is only a dev-build
fallback). Release notes come from the matching `## [x.y.z]` section of
CHANGELOG.md (falls back to `## [Unreleased]`).

The `release.yml` workflow then: builds Release → packages
`Holocron-<version>.dmg` (`scripts/make-dmg.sh`, hdiutil) → signs it and
generates `appcast.xml` with Sparkle's `generate_appcast` (EdDSA) → creates
the GitHub Release with both files attached.

`SUFeedURL` points at
`https://github.com/FabienVINCENT/Holocron/releases/latest/download/appcast.xml`,
so shipped apps always see the newest release.

## Gatekeeper note (no notarization yet)

Builds are ad-hoc signed — **no Apple Developer ID, no notarization**. On
first launch macOS will warn that the app is from an unidentified developer:
right-click → Open (or System Settings → Privacy & Security → “Open Anyway”).

**TODO:** once a Developer ID is available — sign with Developer ID
Application, enable Hardened Runtime, notarize (`xcrun notarytool submit`),
staple, and keep Sparkle's EdDSA signing on top.
