# Notes for ARCHITECTURE.md — PrivilegedHelperXPC mock

Temporary notes file. Someone should fold the following into `ARCHITECTURE.md`
and then delete this file. Not committed as part of `ARCHITECTURE.md` itself
per the task that produced it — see git history / PR description for context.

## What was added

- `Packages/PrivilegedHelperXPC/Sources/PrivilegedHelperXPC/MockPrivilegedHelper.swift`:
  - `PrivilegedHelperClientProtocol` — a new, Swift-native `async`/`await`
    protocol that mirrors `PrivilegedHelperProtocol` 1:1 (same four
    operations), but with plain return values instead of `@objc` reply
    closures. This is the abstraction app-side call sites should depend on.
  - `MockPrivilegedHelper` — an `actor` implementing
    `PrivilegedHelperClientProtocol` entirely in memory. No `SMAppService`
    call, no `NSXPCConnection`, no elevated file operation anywhere in it.
  - `PrivilegedHelperOperationResult` / `PrivilegedHelperMaintenanceResult` —
    small `Sendable` value types standing in for the reply-closure payloads.
- `Packages/PrivilegedHelperXPC/Tests/PrivilegedHelperXPCTests/MockPrivilegedHelperTests.swift`:
  unit tests for the mock (quarantine/restore round trip, restore of an
  unknown or already-consumed receipt ID, forbidden-prefix quarantine
  attempts, recognized vs. unrecognized maintenance task IDs, a basic
  concurrency sanity check). Replaces the prior placeholder test file.
- `PrivilegedHelper/README.md` updated to describe this state instead of
  "Not yet scaffolded".

## Why this shape (architectural reasoning to record)

`PrivilegedHelperProtocol` is `@objc` with reply closures because that's what
`NSXPCConnection` needs on the wire, and `@objc` protocol conformance is
realistically restricted to `NSObject`-derived classes. That's the right
shape for the real IPC boundary, but a poor fit for Swift 6 strict-
concurrency app-side code. `PrivilegedHelperClientProtocol` was introduced as
the app-facing seam instead: call sites should depend on
`PrivilegedHelperClientProtocol`, never directly on `PrivilegedHelperProtocol`
or a concrete implementation. `MockPrivilegedHelper` conforms to it today;
a future real client would wrap an `NSXPCConnection`'s remote object proxy
(typed `PrivilegedHelperProtocol`) and adapt its reply closures into
`async`/`await`, conforming to the same `PrivilegedHelperClientProtocol` —
letting the mock be swapped for the real thing with zero call-site changes,
only a change at the dependency-injection root.

## Scope and limits of the mock (important to flag prominently)

- `MockPrivilegedHelper` is an **in-memory simulation only**. Quarantining a
  path never moves, copies, or otherwise touches the file on disk — it only
  records the path in a dictionary keyed by the caller-supplied `requestID`
  (which this mock treats as doubling as the "receipt ID", since
  `PrivilegedHelperProtocol.quarantinePath`'s reply doesn't hand back a
  separate identifier).
- Its forbidden-path check (`MockPrivilegedHelper.forbiddenPathPrefixes`) is
  a small, hardcoded list chosen only to mirror the *spirit* of
  `SafetyRules.Denylist.forbiddenPathPrefixes` well enough that the mock
  never plausibly claims it would quarantine something like `/System`. It is
  **not** a re-implementation of `SafetyRules.Denylist` and must not be
  treated as authoritative. `PrivilegedHelperXPC` deliberately does not
  depend on the `SafetyRules` package.
- Its maintenance-task recognition is a fixed, made-up set of three IDs with
  canned output — not tied to any real script or command.
- State lives only in the `MockPrivilegedHelper` instance's memory for the
  current process's lifetime; nothing persists across launches.

## What still needs to be built for real (not done here)

- **No `SMAppService` registration exists anywhere in this codebase.** No
  daemon is installed, started, or looked up. Confirmed via
  `grep -r SMAppService` across `Packages/PrivilegedHelperXPC` and
  `PrivilegedHelper/` at the time this was written — zero matches.
- **No executable target exists under `PrivilegedHelper/`.** That directory
  currently holds only `README.md`. The real helper executable
  (`main.swift`, an `NSXPCListener`/`NSXPCListenerDelegate` pair exporting an
  object conforming to `PrivilegedHelperProtocol` over
  `PrivilegedHelperConstants.machServiceName`) still needs to be written,
  signed (Developer ID only — never shipped in the App Store build), and
  registered via `SMAppService.daemon(plistName:)` from the main app.
- **No real `PrivilegedHelperClientProtocol` conformer backed by XPC
  exists.** It needs to wrap `NSXPCConnection`'s remote object proxy and
  bridge its reply closures to `async`/`await`.
- **The helper's own independent denylist re-check is not implemented**
  because the helper itself doesn't exist yet. `PrivilegedHelperProtocol`'s
  doc comment is explicit that the helper must never trust the app's
  classification alone; this remains true and unaddressed until the real
  helper is built.
