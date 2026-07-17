# Releasing Holocron

## One-time setup

1. **Generate Sparkle EdDSA keys** (on your Mac):

   ```sh
   curl -fsSL -o sparkle.tar.xz \
     "https://github.com/sparkle-project/Sparkle/releases/download/2.6.4/Sparkle-2.6.4.tar.xz"
   mkdir sparkle-tools && tar -xf sparkle.tar.xz -C sparkle-tools
   ./sparkle-tools/bin/generate_keys
   ```

   - The **public key** printed by `generate_keys` goes into
     `Holocron/Resources/Info.plist` → `SUPublicEDKey`
     (replace `REPLACE_WITH_SPARKLE_ED25519_PUBLIC_KEY`).
   - Export the **private key** and store it as the repository secret
     `SPARKLE_PRIVATE_KEY` (GitHub → Settings → Secrets → Actions):

     ```sh
     ./sparkle-tools/bin/generate_keys -x sparkle_private_key.pem
     # paste the file content into the SPARKLE_PRIVATE_KEY secret, then
     shred -u sparkle_private_key.pem   # never commit it
     ```

2. Commit the Info.plist change.

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

Keep `VERSION` and `MARKETING_VERSION` (project.yml) in sync — the DMG file
name comes from MARKETING_VERSION, the tag from VERSION.

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
