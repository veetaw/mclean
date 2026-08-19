import Foundation
import Swifter

/// Shared JSON encode/decode configuration for the whole HTTP surface, kept
/// in one place so every endpoint agrees on the wire format documented in
/// `RemoteWebApp/README.md` (ISO 8601 dates, sorted keys for stable output).
enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Builds a `Content-Type: application/json` `HttpResponse` from any
/// `Encodable` value. Uses `.raw` (not Swifter's `.ok(.json(...))`, which
/// round-trips through `JSONSerialization` and Foundation's default date
/// encoding) so every response consistently uses `JSONCoding.encoder`.
func jsonResponse<T: Encodable>(_ value: T, status: Int = 200, reason: String = "OK") -> HttpResponse {
    guard let data = try? JSONCoding.encoder.encode(value) else {
        return .internalServerError
    }
    return .raw(status, reason, ["Content-Type": "application/json; charset=utf-8"]) { writer in
        try writer.write(data)
    }
}

struct APIErrorBody: Encodable {
    struct Detail: Encodable {
        let code: String
        let message: String
    }
    let error: Detail
}

func errorResponse(_ status: Int, _ reason: String, code: String, message: String) -> HttpResponse {
    jsonResponse(APIErrorBody(error: .init(code: code, message: message)), status: status, reason: reason)
}

func decodeBody<T: Decodable>(_ type: T.Type, from request: HttpRequest) -> T? {
    try? JSONCoding.decoder.decode(T.self, from: Data(request.body))
}
