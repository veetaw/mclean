"use strict";

/**
 * MClean Pro Remote — vanilla JS, no build step, no dependencies.
 *
 * Talks to the RemoteControlServer HTTP API documented in
 * RemoteWebApp/README.md. This file is the only JS in the app; keep it
 * dependency-free on purpose (see that README for why).
 */

// ---------------------------------------------------------------------
// Session storage (device token + which server it's for)
// ---------------------------------------------------------------------

const STORAGE_KEYS = {
  apiBase: "mcleanpro.apiBase",
  deviceToken: "mcleanpro.deviceToken",
  deviceName: "mcleanpro.deviceName",
};

function getApiBase() {
  return localStorage.getItem(STORAGE_KEYS.apiBase);
}

function getDeviceToken() {
  return localStorage.getItem(STORAGE_KEYS.deviceToken);
}

function setSession(apiBase, deviceToken, deviceName) {
  localStorage.setItem(STORAGE_KEYS.apiBase, apiBase);
  localStorage.setItem(STORAGE_KEYS.deviceToken, deviceToken);
  if (deviceName) localStorage.setItem(STORAGE_KEYS.deviceName, deviceName);
}

function clearSession() {
  localStorage.removeItem(STORAGE_KEYS.apiBase);
  localStorage.removeItem(STORAGE_KEYS.deviceToken);
  localStorage.removeItem(STORAGE_KEYS.deviceName);
}

function joinURL(base, path) {
  return base.replace(/\/+$/, "") + path;
}

// ---------------------------------------------------------------------
// API client
// ---------------------------------------------------------------------

class UnauthorizedError extends Error {
  constructor() {
    super("unauthorized");
  }
}

/**
 * Fetches `path` against the paired server, attaching the device's bearer
 * token. On a 401 (missing/invalid/revoked token — see README "Auth"),
 * clears the local session and routes back to the pairing screen, matching
 * the server's contract: every non-pairing request must carry a valid
 * per-device token or is rejected outright.
 */
async function apiFetch(path, options = {}) {
  const base = getApiBase();
  const token = getDeviceToken();
  const headers = Object.assign({}, options.headers || {});
  if (token) headers["Authorization"] = `Bearer ${token}`;
  if (options.body && !headers["Content-Type"]) {
    headers["Content-Type"] = "application/json";
  }

  const response = await fetch(joinURL(base, path), { ...options, headers });
  if (response.status === 401) {
    clearSession();
    showPairingView(
      "Your session expired or this device was unpaired on the Mac. Please pair again."
    );
    throw new UnauthorizedError();
  }
  return response;
}

async function apiFetchJSON(path, options = {}) {
  const response = await apiFetch(path, options);
  const json = await response.json().catch(() => null);
  if (!response.ok) {
    const message =
      (json && json.error && json.error.message) || `Request failed (${response.status}).`;
    const error = new Error(message);
    error.status = response.status;
    error.body = json;
    throw error;
  }
  return json;
}

// ---------------------------------------------------------------------
// App state
// ---------------------------------------------------------------------

const state = {
  status: null,
  findings: [],
  /** Map<findingID (string), ApprovalRequest> — most recent request per finding. */
  approvalsByFinding: new Map(),
};

function latestApprovalByFinding(approvalRequests) {
  const map = new Map();
  // The server already returns these sorted most-recent-first.
  for (const request of approvalRequests) {
    if (!map.has(request.findingID)) {
      map.set(request.findingID, request);
    }
  }
  return map;
}

// ---------------------------------------------------------------------
// Formatting helpers
// ---------------------------------------------------------------------

function formatBytes(bytes) {
  if (bytes === null || bytes === undefined) return "—";
  const units = ["B", "KB", "MB", "GB", "TB", "PB"];
  let value = Math.abs(bytes);
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  const rounded = value < 10 && unitIndex > 0 ? value.toFixed(1) : Math.round(value);
  return `${bytes < 0 ? "-" : ""}${rounded} ${units[unitIndex]}`;
}

function formatRelativeTime(isoString) {
  if (!isoString) return "never";
  const date = new Date(isoString);
  if (Number.isNaN(date.getTime())) return "—";
  const diffMinutes = Math.round((Date.now() - date.getTime()) / 60000);
  if (diffMinutes < 1) return "just now";
  if (diffMinutes < 60) return `${diffMinutes} min ago`;
  const diffHours = Math.round(diffMinutes / 60);
  if (diffHours < 24) return `${diffHours} h ago`;
  const diffDays = Math.round(diffHours / 24);
  return `${diffDays} d ago`;
}

// Matches the three-tier vocabulary in SAFETY_RULES.md. `SafetyVerdict` is
// encoded by Swift's default `Codable` synthesis as a single-key object
// keyed by case name, e.g. {"needsConfirmation": {"reason": "..."}} — see
// README "Wire-format notes".
function verdictTier(verdict) {
  if (verdict && "forbidden" in verdict) return "forbidden";
  if (verdict && "safeAuto" in verdict) return "safeAuto";
  return "needsConfirmation";
}

function verdictDetail(verdict) {
  const tier = verdictTier(verdict);
  const payload = verdict && verdict[tier];
  return (payload && (payload.reason || payload.ruleID)) || null;
}

function tierBadgeClass(tier) {
  if (tier === "forbidden") return "badge-forbidden";
  if (tier === "safeAuto") return "badge-safe-auto";
  return "badge-needs-confirmation";
}

function tierLabel(tier) {
  if (tier === "forbidden") return "Forbidden";
  if (tier === "safeAuto") return "Safe (auto)";
  return "Needs review";
}

function approvalStatusLabel(approval) {
  switch (approval.status) {
    case "pending":
      return "Requested — waiting for approval on your Mac.";
    case "fulfilled":
      return "Moved to quarantine.";
    case "rejected":
      return "Dismissed.";
    case "failed":
      return `Could not remove it: ${approval.failureReason || "unknown error"}.`;
    default:
      return approval.status;
  }
}

// ---------------------------------------------------------------------
// View switching
// ---------------------------------------------------------------------

const pairingView = document.getElementById("pairing-view");
const mainView = document.getElementById("main-view");
const pairingError = document.getElementById("pairing-error");
const findingsError = document.getElementById("findings-error");
const connectionPill = document.getElementById("connection-pill");

function showPairingView(message) {
  pairingView.hidden = false;
  mainView.hidden = true;
  connectionPill.hidden = true;
  if (message) {
    showError(pairingError, message);
  }
}

function showMainView() {
  pairingView.hidden = true;
  mainView.hidden = false;
}

function showError(element, message) {
  element.textContent = message;
  element.hidden = false;
}

function hideError(element) {
  element.hidden = true;
  element.textContent = "";
}

function setConnectionPill(isOnline) {
  connectionPill.hidden = false;
  connectionPill.textContent = isOnline ? "Connected" : "Offline";
  connectionPill.classList.toggle("offline", !isOnline);
}

// ---------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------

function renderStatus() {
  const status = state.status;
  if (!status) return;
  document.getElementById("stat-free").textContent = formatBytes(status.disk.freeBytes);
  document.getElementById("stat-reclaimable").textContent = formatBytes(status.totalReclaimableBytes);
  document.getElementById("stat-quarantine").textContent = String(status.quarantineActiveCount);
  document.getElementById("stat-last-scan").textContent =
    "Last scan: " + formatRelativeTime(status.lastScanFinishedAt);
}

function metaSpan(text) {
  const span = document.createElement("span");
  span.textContent = text;
  return span;
}

function renderFindingCard(finding, approval) {
  const card = document.createElement("li");
  card.className = "finding-card";

  const top = document.createElement("div");
  top.className = "finding-top";
  const pathEl = document.createElement("div");
  pathEl.className = "finding-path";
  pathEl.textContent = finding.item.path;
  const tier = verdictTier(finding.verdict);
  const badge = document.createElement("span");
  badge.className = `badge ${tierBadgeClass(tier)}`;
  badge.textContent = tierLabel(tier);
  top.append(pathEl, badge);
  card.append(top);

  const meta = document.createElement("div");
  meta.className = "finding-meta";
  meta.append(metaSpan(finding.item.category), metaSpan(formatBytes(finding.item.sizeBytes)));
  card.append(meta);

  const reasonText = verdictDetail(finding.verdict) || finding.item.reason;
  if (reasonText) {
    const reasonEl = document.createElement("p");
    reasonEl.className = "finding-reason";
    reasonEl.textContent = reasonText;
    card.append(reasonEl);
  }

  if (tier === "forbidden") {
    const status = document.createElement("div");
    status.className = "finding-status";
    status.textContent = "Protected system item — MClean Pro can never remove this.";
    card.append(status);
    return card;
  }

  if (approval && approval.status !== "rejected") {
    const status = document.createElement("div");
    status.className = `finding-status status-${approval.status}`;
    status.textContent = approvalStatusLabel(approval);
    card.append(status);
    return card;
  }

  const actions = document.createElement("div");
  actions.className = "finding-actions";

  const approveButton = document.createElement("button");
  approveButton.type = "button";
  approveButton.className = "btn-approve";
  approveButton.textContent = "Request removal";
  approveButton.addEventListener("click", () => handleDecision(finding, "approve", card));

  const rejectButton = document.createElement("button");
  rejectButton.type = "button";
  rejectButton.className = "btn-reject";
  rejectButton.textContent = "Dismiss";
  rejectButton.addEventListener("click", () => handleDecision(finding, "reject", card));

  actions.append(approveButton, rejectButton);
  card.append(actions);
  return card;
}

function renderFindings() {
  const list = document.getElementById("findings-list");
  const empty = document.getElementById("findings-empty");
  list.innerHTML = "";
  if (!state.findings || state.findings.length === 0) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;
  for (const finding of state.findings) {
    const approval = state.approvalsByFinding.get(finding.item.id);
    list.append(renderFindingCard(finding, approval));
  }
}

// ---------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------

/**
 * "Request removal" / "Dismiss" both map onto the same two-step API:
 * create an approval request, then immediately resolve it with the chosen
 * decision. A reject always succeeds over HTTP. An approve only succeeds
 * immediately if the Mac has turned on
 * `RemoteControlSettings.allowMobileApprovalFulfillment`; otherwise the
 * server returns 403 and the request is left `pending` for a human to
 * resolve from the Mac app — this function still shows that as a normal
 * outcome, not an error.
 */
async function handleDecision(finding, decision, cardElement) {
  const buttons = cardElement.querySelectorAll("button");
  buttons.forEach((button) => (button.disabled = true));
  hideError(findingsError);

  try {
    const approval = await apiFetchJSON(`/api/v1/findings/${finding.item.id}/approval-requests`, {
      method: "POST",
    });

    let resolved = approval;
    try {
      resolved = await apiFetchJSON(`/api/v1/approval-requests/${approval.id}/fulfill`, {
        method: "POST",
        body: JSON.stringify({ decision }),
      });
    } catch (fulfillError) {
      if (fulfillError.status === 403) {
        // Expected when mobile-initiated approval is disabled on the Mac —
        // the request stays pending for the desktop app to resolve.
        resolved = approval;
      } else {
        throw fulfillError;
      }
    }

    state.approvalsByFinding.set(finding.item.id, resolved);
    renderFindings();
  } catch (error) {
    if (error instanceof UnauthorizedError) return;
    showError(findingsError, error.message || "That action failed. Try again.");
    buttons.forEach((button) => (button.disabled = false));
  }
}

async function loadAll() {
  const [status, findingsResponse, approvalsResponse] = await Promise.all([
    apiFetchJSON("/api/v1/status"),
    apiFetchJSON("/api/v1/findings"),
    apiFetchJSON("/api/v1/approval-requests"),
  ]);
  state.status = status;
  state.findings = findingsResponse.findings;
  state.approvalsByFinding = latestApprovalByFinding(approvalsResponse.approvalRequests);
  renderStatus();
  renderFindings();
  setConnectionPill(true);
}

// ---------------------------------------------------------------------
// Pairing form
// ---------------------------------------------------------------------

const pairingForm = document.getElementById("pairing-form");
const pairingTokenInput = document.getElementById("pairing-token");
const deviceNameInput = document.getElementById("device-name");
const apiBaseInput = document.getElementById("api-base");

function prefillFromPairingLink() {
  // The Mac's QR code encodes a URL like http://<lan-ip>:<port>/pair?token=...
  // (see PairingInvitation.pairingURL in RemoteControlServer). Since this
  // page IS being served by that same host:port, `location.origin` is
  // already the right API base — only the token needs prefilling.
  const params = new URLSearchParams(location.search);
  const token = params.get("token");
  if (token) {
    pairingTokenInput.value = token;
  }
}

pairingForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  hideError(pairingError);

  const pairingToken = pairingTokenInput.value.trim();
  const deviceName = deviceNameInput.value.trim();
  const apiBase = apiBaseInput.value.trim() || location.origin;
  const submitButton = pairingForm.querySelector('button[type="submit"]');
  submitButton.disabled = true;

  try {
    const response = await fetch(joinURL(apiBase, "/api/v1/pair"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        pairingToken,
        deviceName: deviceName || undefined,
      }),
    });
    const json = await response.json().catch(() => null);
    if (!response.ok) {
      const message =
        (json && json.error && json.error.message) || `Pairing failed (${response.status}).`;
      showError(pairingError, message);
      return;
    }

    setSession(apiBase, json.deviceToken, json.deviceName);
    await loadAll();
    showMainView();
  } catch (error) {
    showError(
      pairingError,
      "Could not reach that address. Check the server address and that you're on the same Wi-Fi network as your Mac."
    );
  } finally {
    submitButton.disabled = false;
  }
});

// ---------------------------------------------------------------------
// Main view controls
// ---------------------------------------------------------------------

document.getElementById("refresh-button").addEventListener("click", async () => {
  const button = document.getElementById("refresh-button");
  button.disabled = true;
  hideError(findingsError);
  try {
    await loadAll();
  } catch (error) {
    if (!(error instanceof UnauthorizedError)) {
      showError(findingsError, "Could not refresh. Check your connection to the Mac.");
      setConnectionPill(false);
    }
  } finally {
    button.disabled = false;
  }
});

document.getElementById("unpair-button").addEventListener("click", async () => {
  try {
    await apiFetch("/api/v1/pair/revoke", { method: "POST" });
  } catch (error) {
    // Best-effort: still drop the local session even if the network call
    // failed, so the user is never stuck "paired" to an unreachable Mac.
  }
  clearSession();
  showPairingView();
});

// ---------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------

async function init() {
  prefillFromPairingLink();

  if (!getApiBase() || !getDeviceToken()) {
    showPairingView();
    return;
  }

  try {
    await loadAll();
    showMainView();
  } catch (error) {
    if (!(error instanceof UnauthorizedError)) {
      showPairingView(
        "Could not reach your Mac. Check that you're on the same Wi-Fi network, then pair again."
      );
    }
  }
}

init();
