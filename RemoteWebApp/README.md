# RemoteWebApp

Static web app (HTML/CSS/JS, no build step, no dependencies) served in-LAN
by `Packages/RemoteControlServer` for mobile remote control, per PROMPT
MASTER §5.6.

```
RemoteWebApp/
  index.html      Pairing screen + main (status/findings) screen, both in one page
  src/app.js      All app logic — vanilla JS, no frameworks/bundler
  src/style.css   Responsive, mobile-first styling (light/dark aware)
```

This file is the API contract between `RemoteWebApp` and
`Packages/RemoteControlServer`. `MainAppUI` (not yet scaffolded) should
treat this as the reference for what to host and how to talk to it — the
two are implemented together specifically so they don't drift.

## How it's served

`RemoteControlServer` can serve this directory's files directly, same
origin as the JSON API (pass `staticFileRoot:` at init). That's the
intended deployment: the mobile browser only ever talks to one
`host:port`, so no CORS setup is needed. `index.html` is served at `/`;
`src/app.js` and `src/style.css` at their matching paths.

## LAN-only, by design

Every request — API or static asset — is checked against the real TCP
peer address (never a client-supplied `Host`/`Origin` header) and rejected
with `403` if it's not on a private/loopback/link-local network segment.
See `RemoteControlServer.swift`'s module doc comment and `LANGuard.swift`
for exactly which ranges. There is no code path to reach this server from
outside the LAN.

## Pairing flow

1. On the Mac, the user starts pairing (`RemoteControlServer.beginPairing()`
   — an in-process Swift call, not HTTP). That returns a `PairingInvitation`
   holding a short-lived, single-use pairing token and (via
   `PairingInvitation.pairingURL(host:port:)`) a full URL like
   `http://192.168.1.23:8080/pair?token=<pairingToken>`.
2. The Mac shows that URL as a QR code (rendering the QR image itself is a
   `MainAppUI` concern, not this package's or this web app's) and/or the
   raw token as text.
3. **This build has no camera QR scanner** — `index.html`'s pairing form is
   a plain text field for the token. If the user instead opens the URL
   directly (e.g. by tapping a QR-code notification), `app.js` reads
   `?token=...` from `location.search` and prefills the field. Follow-up:
   wire a `getUserMedia` + QR-decoder to fill this automatically.
4. Submitting the form does `POST /api/v1/pair` with that token. On
   success the server returns a **different**, long-lived `deviceToken`,
   which `app.js` stores in `localStorage` and sends as
   `Authorization: Bearer <deviceToken>` on every subsequent request. The
   one-time pairing token itself is discarded by the server the instant
   it's redeemed (or when it expires — 5 minutes by default) and is never
   reused, so a photographed QR code is worthless within minutes.

## Auth

Every endpoint except `GET /api/v1/health` and `POST /api/v1/pair`
requires:

```
Authorization: Bearer <deviceToken>
```

Missing or invalid/revoked token → `401` with an `APIErrorBody` (see
below), and `app.js` responds to any `401` by clearing the stored session
and returning to the pairing screen.

## Wire-format notes

- All request/response bodies are JSON, `Content-Type: application/json`.
- Dates are ISO 8601 strings (`JSONEncoder.dateEncodingStrategy = .iso8601`).
- Optional fields with no value are **omitted from the JSON object**
  entirely (Swift's synthesized `Codable` uses `encodeIfPresent`) — they
  are never emitted as `null`. Treat a missing key the same as `null`.
- `SafetyVerdict` (defined in `SafetyRules`, not this package) encodes as a
  single-key object named after the case, e.g.
  `{"needsConfirmation": {"reason": "..."}}`,
  `{"safeAuto": {"ruleID": "..."}}`, or
  `{"forbidden": {"ruleID": "...", "reason": "..."}}`. This is the
  three-tier vocabulary from `SAFETY_RULES.md` — `app.js`'s `verdictTier()`
  reads whichever one key is present.
- A `ScanFinding`'s identifier is **`item.id`**, not a top-level `id` field
  (`ScanFinding.id` is a computed Swift property, so it isn't part of the
  encoded JSON). Use `finding.item.id` when building
  `/api/v1/findings/{id}/approval-requests` URLs.
- `ApprovalRequest.resolvedBy` (when present) is
  `{"type": "desktop"}` or `{"type": "device", "deviceID": "<uuid>"}`.

## Endpoints

### `GET /api/v1/health` — no auth

```json
200 { "status": "ok", "apiVersion": 1 }
```

### `POST /api/v1/pair` — no auth

Request:

```json
{ "pairingToken": "<token from the QR code>", "deviceName": "Vito's iPhone" }
```

`deviceName` is optional; the server falls back to `"Paired device"`.

```json
201 {
  "deviceID": "<uuid>",
  "deviceToken": "<long-lived bearer token — store this>",
  "deviceName": "Vito's iPhone",
  "pairedAt": "2026-08-18T12:00:00Z",
  "apiVersion": 1
}
```

`401` (`invalid_pairing_token`) if the token is unknown, expired, or
already redeemed.

### `POST /api/v1/pair/revoke` — auth required

Revokes the **calling device's own** token (self-unpair; a device can never
revoke another device's token over HTTP — that's an in-process-only,
desktop-initiated action, see `RemoteControlServer.revokeDevice(_:)`).

```json
200 { "revoked": true }
```

### `GET /api/v1/status` — auth required

```json
200 {
  "apiVersion": 1,
  "serverTime": "2026-08-18T12:00:00Z",
  "disk": { "freeBytes": 123456789, "totalBytes": 987654321 },
  "lastScanStartedAt": "2026-08-18T11:55:00Z",
  "lastScanFinishedAt": "2026-08-18T11:56:30Z",
  "findingsCount": 42,
  "totalReclaimableBytes": 4567890123,
  "quarantineActiveCount": 3
}
```

`lastScanStartedAt`/`lastScanFinishedAt` are absent if no scan has run yet.

### `GET /api/v1/findings` — auth required

```json
200 {
  "generatedAt": "2026-08-18T12:00:00Z",
  "findings": [
    {
      "item": {
        "id": "<uuid>",
        "path": "/Users/vito/Library/Caches/pip",
        "sizeBytes": 104857600,
        "sourceDetectorID": "dev.python.pip-cache",
        "category": "Python — pip cache",
        "lastUsed": null,
        "reason": "Not accessed in 90+ days"
      },
      "verdict": { "needsConfirmation": { "reason": "..." } }
    }
  ]
}
```

### `POST /api/v1/findings/{findingID}/approval-requests` — auth required

`findingID` is a finding's `item.id` from the list above. Empty body.
Creating a request never quarantines anything by itself — see "Approval
lifecycle" below.

```json
201 {
  "id": "<uuid>",
  "findingID": "<uuid>",
  "requestedByDeviceID": "<uuid>",
  "requestedAt": "2026-08-18T12:00:00Z",
  "status": "pending"
}
```

If a `pending` request already exists for that finding, the existing one
is returned with `200` instead of creating a duplicate. `404` if the
finding isn't in the current snapshot; `409` (`forbidden_item`) if its
verdict is `forbidden` — those can never be quarantined, full stop.

### `GET /api/v1/approval-requests` — auth required

Optional `?status=pending|rejected|fulfilled|failed` filter.

```json
200 { "approvalRequests": [ /* ApprovalRequest, newest first */ ] }
```

### `GET /api/v1/approval-requests/{id}` — auth required

```json
200 { "id": "...", "findingID": "...", "status": "fulfilled", "quarantineReceiptID": "...", "resolvedAt": "...", "resolvedBy": { "type": "desktop" } }
```

### `POST /api/v1/approval-requests/{id}/fulfill` — auth required

```json
{ "decision": "approve" }
```

or `{ "decision": "reject" }`.

- **`reject`** always succeeds over HTTP (`200`, `status: "rejected"`) —
  dismissing a suggestion never touches the filesystem, so there's nothing
  to gate.
- **`approve`** only succeeds over HTTP if the Mac has turned on
  `RemoteControlSettings.allowMobileApprovalFulfillment` (default **off**,
  and not wired to any UI yet). Otherwise: `403`
  (`mobile_fulfillment_disabled`) and the request is left `pending` for a
  human to resolve from the Mac app
  (`RemoteControlServer.fulfillApprovalRequest`, called in-process — never
  over HTTP). When it *does* succeed, the server calls into
  `QuarantineManaging.quarantine(_:retention:)` — the **only** place this
  whole package ever performs a destructive action — and returns the
  updated request with `status: "fulfilled"` and a `quarantineReceiptID`,
  or `status: "failed"` with `failureReason` set if quarantining itself
  threw (e.g. the item vanished from disk between listing and fulfilling).

`404` if the id is unknown; `409` (`already_resolved`) if it isn't
`pending` anymore.

### Errors

Every non-2xx JSON response has this shape:

```json
{ "error": { "code": "invalid_token", "message": "Token is invalid, revoked, or unknown." } }
```

## What the UI does with all this

`app.js` maps the two-step create-then-fulfill API onto two buttons per
finding:

- **"Request removal"** → `POST .../approval-requests` then immediately
  `POST .../fulfill` with `"decision": "approve"`. If mobile fulfillment is
  disabled server-side, the `403` is treated as an expected outcome, not an
  error — the card shows "Requested — waiting for approval on your Mac."
- **"Dismiss"** → the same create step, then `fulfill` with
  `"decision": "reject"` (always succeeds).

Forbidden items show a "Protected system item" badge with no actions at
all — the UI doesn't even attempt to request approval for those, since the
server would refuse with `409` anyway.

## Deferred / follow-ups

- **Camera QR scanning**: not implemented. The pairing screen is a plain
  text field. See the note in `index.html`/`app.js`.
- **SQLite-backed pairing persistence**: `RemoteControlServer`'s default
  `PairingStore` is in-memory only (state resets on relaunch). PROMPT
  MASTER §3 calls for a SQLite/GRDB-backed store; `PairingStore` is defined
  as a narrow protocol specifically so that can be swapped in later without
  touching this web app or the HTTP layer.
- **Local TLS**: this API is plain HTTP (LAN-scoped, token-authenticated —
  see `ARCHITECTURE.md`'s "Trade-offs" section). A future mkcert-style
  local TLS option is out of scope for this iteration.
