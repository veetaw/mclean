import Foundation

/// Typed errors thrown by `RealVirusTotalClient`, so callers can distinguish
/// "not configured" / "consent missing" / "genuinely not found" (which isn't
/// an error at all -- see `VirusTotalClient.lookupHash`) from an actual
/// request failure, instead of catching a generic `Error`.
public enum VirusTotalClientError: Error, Sendable, Equatable, CustomStringConvertible {
    /// No usable API key is configured. Thrown immediately, before any
    /// network call is attempted.
    case notConfigured

    /// `uploadFile` was called with `consentGiven: false`. Thrown
    /// immediately, before any network call -- not even a HEAD request --
    /// is attempted.
    case consentRequired

    /// The supplied string isn't a well-formed SHA-256 hex digest.
    case invalidHash(String)

    /// The file at the given path could not be read for upload.
    case fileReadFailed(String)

    /// The server response wasn't a valid HTTP response at all.
    case invalidResponse

    /// The response body could not be decoded into the expected shape.
    case decodingFailed(String)

    /// A non-2xx, non-404 HTTP status was returned. 404 is handled
    /// separately by `lookupHash` (mapped to `nil`, not an error) since VT
    /// uses it to mean "no record for this hash", not "request failed".
    case requestFailed(statusCode: Int, message: String?)

    public var description: String {
        switch self {
        case .notConfigured:
            return "VirusTotal is not configured — no API key has been set."
        case .consentRequired:
            return "Uploading a file to VirusTotal requires explicit per-file user consent (consentGiven: true)."
        case .invalidHash(let hash):
            return "\"\(hash)\" is not a valid SHA-256 hash."
        case .fileReadFailed(let reason):
            return "Could not read the file to upload: \(reason)"
        case .invalidResponse:
            return "VirusTotal returned a response that wasn't a valid HTTP response."
        case .decodingFailed(let reason):
            return "Could not parse VirusTotal's response: \(reason)"
        case .requestFailed(let statusCode, let message):
            if let message {
                return "VirusTotal request failed (HTTP \(statusCode)): \(message)"
            }
            return "VirusTotal request failed (HTTP \(statusCode))."
        }
    }
}
