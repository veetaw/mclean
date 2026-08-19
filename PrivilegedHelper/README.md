# PrivilegedHelper

Executable target for the `SMAppService` privileged helper, implementing
`PrivilegedHelperXPC.PrivilegedHelperProtocol` (see
`Packages/PrivilegedHelperXPC`).

## Current state

**No real privileged helper exists yet.** This directory has no executable
target implementation, and nothing in this build registers, installs, or
talks to an `SMAppService`-managed daemon. No elevated privileges are
exercised anywhere in this build.

What exists today is a **mock**, `PrivilegedHelperXPC.MockPrivilegedHelper`
(`Packages/PrivilegedHelperXPC/Sources/PrivilegedHelperXPC/MockPrivilegedHelper.swift`),
which simulates the helper's behavior in memory — in the same process as its
caller, no XPC connection, no real elevated file operations. It exists so
app-side and UI code can be developed and tested against the helper's
interface shape before a real, signed, `SMAppService`-registered daemon is
built. It conforms to `PrivilegedHelperClientProtocol`, a Swift-native
`async`/`await` abstraction defined alongside it — see that file's doc
comments for why app-side call sites should depend on that protocol rather
than on `PrivilegedHelperProtocol` or `MockPrivilegedHelper` directly, so a
real XPC-backed implementation can later replace the mock without call-site
changes.

Real implementation work still to be done here, once the Developer ID app
target exists to register it:

- An executable target in this directory (`main.swift` + a
  `NSXPCListener`/`NSXPCListenerDelegate` setup) that actually exports an
  object conforming to `PrivilegedHelperXPC.PrivilegedHelperProtocol` over
  `PrivilegedHelperXPC.PrivilegedHelperConstants.machServiceName`.
- Registration of that executable as a daemon via
  `SMAppService.daemon(plistName:)` from the main app (Developer ID build
  only — the App Store build must never call this).
- A real, XPC-backed conformer to `PrivilegedHelperClientProtocol` on the app
  side, wrapping `NSXPCConnection`'s remote object proxy and adapting its
  reply closures into `async`/`await`.
- The helper's own independent re-check of `SafetyRules.Denylist` before
  ever touching disk (see the doc comments on
  `PrivilegedHelperProtocol.quarantinePath` and on
  `SafetyRules.FileSystemQuarantineManager` for why this must not be skipped
  or merely inherited from the app's own classification).

See `Packages/PrivilegedHelperXPC/NOTES_FOR_ARCHITECTURE_DOC.md` for what
should be folded into `ARCHITECTURE.md` once this is reviewed.

Only used by the Developer ID build; the App Store build never installs or
references this helper.
