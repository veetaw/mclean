import Foundation

/// A mobile client's decision about one approval request.
public enum ApprovalDecision: String, Sendable, Codable {
    case approve
    case reject
}

public enum ApprovalStatus: String, Sendable, Codable {
    case pending
    case rejected
    /// The quarantine action was performed successfully.
    case fulfilled
    /// Approved, but resolving it failed (finding disappeared from the
    /// current snapshot, turned out to be `forbidden` on re-check, or the
    /// underlying `QuarantineManaging` call threw). See `failureReason`.
    case failed
}

/// Who resolved an approval request. Kept distinct from a bare device ID so
/// desktop-initiated resolutions (which never go through HTTP/auth at all —
/// see `RemoteControlServer.fulfillApprovalRequest`) are distinguishable
/// from a paired mobile device's own action.
public enum ApprovalActor: Sendable, Equatable {
    case desktop
    case device(UUID)
}

extension ApprovalActor: Codable {
    // A hand-written conformance instead of the synthesized one: the
    // default synthesis for an enum case with an *unlabeled* associated
    // value (`device(UUID)`) encodes as `{"device":{"_0":"<uuid>"}}`, which
    // is an awkward, synthesis-detail-dependent shape to hang a public API
    // contract on. This gives a stable `{"type":"desktop"}` /
    // `{"type":"device","deviceID":"<uuid>"}` shape instead — see
    // `RemoteWebApp/README.md`.
    private enum CodingKeys: String, CodingKey {
        case type
        case deviceID
    }

    private enum Kind: String, Codable {
        case desktop
        case device
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .desktop:
            self = .desktop
        case .device:
            self = .device(try container.decode(UUID.self, forKey: .deviceID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .desktop:
            try container.encode(Kind.desktop, forKey: .type)
        case .device(let id):
            try container.encode(Kind.device, forKey: .type)
            try container.encode(id, forKey: .deviceID)
        }
    }
}

/// A mobile client's request to quarantine one finding.
///
/// Creating this request (`POST /api/v1/findings/{id}/approval-requests`)
/// never performs the quarantine itself — it only records intent. The only
/// code paths that ever call into `QuarantineManaging` are
/// `RemoteControlServer.fulfillApprovalRequest` (desktop, in-process, always
/// available) and the HTTP `POST /approval-requests/{id}/fulfill` endpoint
/// (mobile, gated by `RemoteControlSettings.allowMobileApprovalFulfillment`,
/// default off). This mirrors the same confirmation semantics as the rest
/// of the app — this package never quarantines anything unilaterally.
public struct ApprovalRequest: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let findingID: UUID
    public let requestedByDeviceID: UUID
    public let requestedAt: Date
    public var status: ApprovalStatus
    public var resolvedAt: Date?
    public var resolvedBy: ApprovalActor?
    public var quarantineReceiptID: UUID?
    public var failureReason: String?

    public init(
        id: UUID = UUID(),
        findingID: UUID,
        requestedByDeviceID: UUID,
        requestedAt: Date = Date(),
        status: ApprovalStatus = .pending,
        resolvedAt: Date? = nil,
        resolvedBy: ApprovalActor? = nil,
        quarantineReceiptID: UUID? = nil,
        failureReason: String? = nil
    ) {
        self.id = id
        self.findingID = findingID
        self.requestedByDeviceID = requestedByDeviceID
        self.requestedAt = requestedAt
        self.status = status
        self.resolvedAt = resolvedAt
        self.resolvedBy = resolvedBy
        self.quarantineReceiptID = quarantineReceiptID
        self.failureReason = failureReason
    }
}

/// In-memory store of `ApprovalRequest`s for the lifetime of one
/// `RemoteControlServer`. Deliberately not part of the injectable
/// `PairingStore` boundary (unlike paired-device tokens, these are
/// session/scan-scoped, not identity — see `PairingStore` for the
/// persistence note on tokens).
actor ApprovalRequestStore {
    private var requestsByID: [UUID: ApprovalRequest] = [:]

    func create(findingID: UUID, requestedByDeviceID: UUID) -> ApprovalRequest {
        let request = ApprovalRequest(findingID: findingID, requestedByDeviceID: requestedByDeviceID)
        requestsByID[request.id] = request
        return request
    }

    func existingPending(forFindingID findingID: UUID) -> ApprovalRequest? {
        requestsByID.values.first { $0.findingID == findingID && $0.status == .pending }
    }

    func get(_ id: UUID) -> ApprovalRequest? {
        requestsByID[id]
    }

    func all(status: ApprovalStatus?) -> [ApprovalRequest] {
        let values = Array(requestsByID.values)
        let filtered = status.map { wanted in values.filter { $0.status == wanted } } ?? values
        return filtered.sorted { $0.requestedAt > $1.requestedAt }
    }

    func update(_ request: ApprovalRequest) {
        requestsByID[request.id] = request
    }
}
