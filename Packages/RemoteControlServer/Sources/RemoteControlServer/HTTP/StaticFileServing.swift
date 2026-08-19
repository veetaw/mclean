import Foundation
import Swifter

/// Serves the static `RemoteWebApp` bundle (index.html, src/*) over the
/// same origin as the JSON API, so the mobile browser only ever has to talk
/// to one host:port (no CORS setup needed).
///
/// `RemoteControlServer` registers one concrete route per file discovered
/// under `root` at server-start time (see `registerStaticFiles(root:)`)
/// rather than relying on a wildcard route, since Swifter's router treats a
/// literal `**` path segment as a *middle* wildcard (matching a gap between
/// two fixed segments), not a trailing catch-all — it would never actually
/// dispatch to a handler registered at `/**` for e.g. `/src/app.js`. Since
/// `RemoteWebApp` is a small, known static asset set, enumerating it once
/// is simpler and more predictable than fighting that.
enum StaticFileServing {
    static func handler(root: URL) -> (HttpRequest) -> HttpResponse {
        let rootPath = root.standardizedFileURL.path
        return { request in
            var relativePath = request.path
            if relativePath.isEmpty || relativePath == "/" {
                relativePath = "/index.html"
            }
            guard let decoded = relativePath.removingPercentEncoding else {
                return .badRequest(nil)
            }
            let candidate = root.appendingPathComponent(decoded).standardizedFileURL
            // Defense in depth: refuse anything that escapes the static
            // root (e.g. "/../../etc/passwd") even though in practice only
            // routes we ourselves enumerated under `root` are ever
            // registered to reach this closure.
            guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
                return .forbidden
            }
            guard let data = FileManager.default.contents(atPath: candidate.path) else {
                return .notFound
            }
            return .raw(200, "OK", ["Content-Type": contentType(for: candidate.pathExtension)]) { writer in
                try writer.write(data)
            }
        }
    }

    private static func contentType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "application/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "ico": return "image/x-icon"
        case "webmanifest": return "application/manifest+json"
        default: return "application/octet-stream"
        }
    }
}
