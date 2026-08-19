# Release process

There are two very different things this document could mean by
"release," and this project is only set up for one of them today.

## Local development build (what `Scripts/release.sh` produces today)

Running `Scripts/release.sh <patch|minor|major>` builds `MCleanPro-DeveloperID`
in Release configuration and packages it into a `.dmg` under `dist/`
(gitignored). This is a real, working `.app` — it runs fine on **the Mac
that built it**.

Every build today is signed with Xcode's automatic personal-team signing
(or is unsigned/ad-hoc), never a paid Developer ID Application
certificate — because none exists, and **none is needed for this**.
`release.sh` checks the actual `codesign` output for real and names the
`.dmg` honestly: `MCleanPro-DeveloperID-vX.Y.Z-unsigned-local-build-only.dmg`.
It will never silently drop that suffix unless the build was actually
signed with a real Developer ID Application certificate.

**This is sufficient if you only ever run the app on this Mac.** That's
it — no further action needed.

## Signed, notarized release (what's needed to share the app or run it on another Mac)

macOS's Gatekeeper refuses to run an app on a *different* Mac (or one
downloaded from the internet, quarantine-flagged) unless it's signed with
a certificate Apple trusts and notarized. Getting there requires, in
order:

1. **A paid Apple Developer Program membership** (currently $99/year) —
   this is the one genuinely blocking step; everything else follows from
   having it. Not required for personal use on your own Mac (see above).
2. **A Developer ID Application certificate**, generated from that
   membership via Xcode or the Apple Developer portal, installed in your
   keychain (for local signing) or exported as a `.p12` (for CI signing).
3. **Code signing** the built `.app` with that certificate — a
   configuration change in `App/project.yml` (currently
   `CODE_SIGN_IDENTITY: "-"`, `CODE_SIGNING_REQUIRED: NO` — deliberately,
   see `ARCHITECTURE.md`) plus the real team ID.
4. **Notarization** — submitting the signed, packaged build to Apple's
   `notarytool` (needs an app-specific password or API key tied to your
   Apple ID) and stapling the resulting ticket to the `.dmg`, so
   Gatekeeper can verify it offline.
5. **(Optional, only if you want CI to do this automatically)** Pushing
   this repository to a GitHub remote and configuring the certificate,
   its password, the team ID, and the notarization credentials as
   repository secrets — see `.github/workflows/release.yml`'s
   `[NON-FUNCTIONAL]`-marked section, which references exactly these five
   secrets by name (`DEVELOPER_ID_CERTIFICATE_P12_BASE64`,
   `DEVELOPER_ID_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`,
   `NOTARIZATION_APPLE_ID`, `NOTARIZATION_APP_SPECIFIC_PASSWORD`) and
   contains no real or placeholder-that-looks-real credential material —
   only the reference syntax.

**None of this exists in the repo yet**, and there's no work item pending
on it — it's simply not needed until/unless you decide to distribute the
app beyond this Mac. When that day comes, this document is the checklist;
`Scripts/release.sh` and `.github/workflows/release.yml` are both already
shaped to slot the real signing/notarization steps in without a redesign.

## What never happens automatically, on either path

- No script or workflow in this repo ever runs `git push`.
- No script or workflow ever creates a GitHub Release, uploads a build to
  any external service, or publishes anything anywhere.
- No script or workflow ever creates a git commit or tag on your behalf —
  `release.sh` prints the exact `git add`/`commit`/`tag` commands and lets
  you run them once you've reviewed `CHANGELOG.md` and the built `.dmg`.

Publishing a release — however it's signed — is always a deliberate,
manual, human action.

## Versioning

Semantic versioning via git tags (`vX.Y.Z`). No tag exists yet in this
repo; `release.sh` treats `v0.1.0` as the starting baseline until you
create the first real tag yourself:

```sh
git tag v0.1.0
```

See `Scripts/README.md` for the full `ci.sh`/`release.sh` behavior and
the Conventional Commits convention this project follows going forward.
