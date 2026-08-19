import Foundation

/// A TCC ("Transparency, Consent, and Control") service identifier —
/// macOS's own internal name for a privacy-gated capability, e.g.
/// `"kTCCServiceCamera"`. Modeled as a raw-string wrapper rather than an
/// exhaustive enum because Apple's own list of service identifiers is
/// undocumented and has grown across releases; treating it as an open set
/// (with well-known constants for the common cases) is more honest than
/// pretending this package has a complete, stable enumeration.
public struct TCCServiceIdentifier: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension TCCServiceIdentifier {
    public static let camera = TCCServiceIdentifier(rawValue: "kTCCServiceCamera")
    public static let microphone = TCCServiceIdentifier(rawValue: "kTCCServiceMicrophone")
    public static let accessibility = TCCServiceIdentifier(rawValue: "kTCCServiceAccessibility")
    public static let fullDiskAccess = TCCServiceIdentifier(rawValue: "kTCCServiceSystemPolicyAllFiles")
    public static let screenCapture = TCCServiceIdentifier(rawValue: "kTCCServiceScreenCapture")
    public static let calendars = TCCServiceIdentifier(rawValue: "kTCCServiceCalendar")
    public static let contacts = TCCServiceIdentifier(rawValue: "kTCCServiceAddressBook")
    public static let photos = TCCServiceIdentifier(rawValue: "kTCCServicePhotos")
    public static let reminders = TCCServiceIdentifier(rawValue: "kTCCServiceReminders")
    public static let automation = TCCServiceIdentifier(rawValue: "kTCCServiceAppleEvents")
    public static let inputMonitoring = TCCServiceIdentifier(rawValue: "kTCCServiceListenEvent")
    public static let locationServices = TCCServiceIdentifier(rawValue: "kTCCServiceLocation")
    public static let bluetooth = TCCServiceIdentifier(rawValue: "kTCCServiceBluetoothAlways")
    public static let developerTools = TCCServiceIdentifier(rawValue: "kTCCServiceDeveloperTool")
}

/// Which `TCC.db` `access` table column layout a row was decoded from.
/// macOS 10.14 and earlier used a boolean `allowed` column; Catalina (10.15)
/// introduced the richer `auth_value` column (0=denied, 2=allowed,
/// 3=limited, 4=unspecified/prompt-pending, ...). Kept internal — callers
/// only ever see the normalized `TCCAuthorizationValue`.
enum TCCSchemaHint: Sendable {
    case modern
    case legacy
}

/// One row read from `TCC.db`: "does `clientIdentifier` have `service`
/// access, and as of when."
public struct TCCGrant: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    /// Bundle identifier (apps) or absolute path (command-line tools) of
    /// the client the grant applies to, exactly as TCC recorded it.
    public let clientIdentifier: String
    public let service: TCCServiceIdentifier
    public let authorizationValue: TCCAuthorizationValue
    /// `last_modified` from the database, if present — a Unix timestamp of
    /// when this grant was last changed, not a "last used" signal.
    public let lastModified: Date?

    public init(
        id: UUID = UUID(),
        clientIdentifier: String,
        service: TCCServiceIdentifier,
        authorizationValue: TCCAuthorizationValue,
        lastModified: Date?
    ) {
        self.id = id
        self.clientIdentifier = clientIdentifier
        self.service = service
        self.authorizationValue = authorizationValue
        self.lastModified = lastModified
    }
}

/// Normalized reading of a TCC grant's authorization state, regardless of
/// which on-disk schema (`allowed` vs. `auth_value`) it was read from.
public enum TCCAuthorizationValue: Sendable, Hashable, Codable {
    case denied
    case allowed
    /// "Limited" grants (e.g. Limited Photos access), only meaningful under
    /// the modern (`auth_value`) schema.
    case limited
    /// Recorded but not yet decided by the user (modern `auth_value == 4`).
    case promptPending
    /// A raw value this type doesn't recognize — preserved rather than
    /// dropped, so the UI can still show "something", just unlabeled.
    case other(Int)

    init(rawValue: Int?, schema: TCCSchemaHint) {
        guard let rawValue else {
            self = .other(-1)
            return
        }
        switch schema {
        case .modern:
            switch rawValue {
            case 0: self = .denied
            case 2: self = .allowed
            case 3: self = .limited
            case 4: self = .promptPending
            default: self = .other(rawValue)
            }
        case .legacy:
            switch rawValue {
            case 0: self = .denied
            case 1: self = .allowed
            default: self = .other(rawValue)
            }
        }
    }
}

/// Outcome of a best-effort `TCC.db` read. Deliberately not a plain
/// `[TCCGrant]` (which would make "no grants" and "couldn't read the
/// database at all" indistinguishable) — see `TCCUnavailableReason` for why
/// a read fails.
public enum TCCReadResult: Sendable, Equatable {
    case grants([TCCGrant])
    case unavailable(reason: TCCUnavailableReason)
}

public enum TCCUnavailableReason: String, Sendable, Codable {
    /// The database file doesn't exist at the expected path.
    case databaseNotFound
    /// `sqlite3` isn't present/executable on this machine.
    case queryToolUnavailable
    /// Most common case in practice: this process lacks Full Disk Access,
    /// so SQLite can open the file handle but every read fails.
    case fullDiskAccessRequired
    /// The query ran but didn't decode into either known schema — most
    /// likely a macOS release with a `TCC.db` layout this reader doesn't
    /// recognize yet.
    case unrecognizedSchema
}
