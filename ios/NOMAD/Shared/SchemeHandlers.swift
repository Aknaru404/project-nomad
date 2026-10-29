import Foundation
import UniformTypeIdentifiers
import WebKit

struct SchemeResponse {
    let response: HTTPURLResponse
    let body: Data

    static func make(_ url: URL, status: Int = 200, mimeType: String, body: Data, headers: [String: String] = [:]) -> SchemeResponse {
        var contentType = mimeType
        if mimeType.hasPrefix("text/") && !mimeType.contains("charset") { contentType += "; charset=utf-8" }
        var all = headers
        all["Content-Type"] = contentType
        all["Content-Length"] = String(body.count)
        all["Access-Control-Allow-Origin"] = "*"
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: all)!
        return SchemeResponse(response: response, body: body)
    }

    static func notFound(_ url: URL) -> SchemeResponse {
        make(url, status: 404, mimeType: "text/plain", body: Data("Not found".utf8))
    }
}

/// Serves custom-scheme requests off the main thread and drops responses for tasks WebKit has already stopped.
class BackgroundSchemeHandler: NSObject, WKURLSchemeHandler {
    private var activeTasks = Set<ObjectIdentifier>()
    private let queue = DispatchQueue(label: "us.projectnomad.scheme", qos: .userInitiated, attributes: .concurrent)

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task as AnyObject)
        activeTasks.insert(id)
        let request = task.request
        queue.async {
            let result = Result { try self.response(for: request) }
            DispatchQueue.main.async {
                guard self.activeTasks.remove(id) != nil else { return }
                switch result {
                case .success(let reply):
                    task.didReceive(reply.response)
                    task.didReceive(reply.body)
                    task.didFinish()
                case .failure(let error):
                    task.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(task as AnyObject))
    }

    func response(for request: URLRequest) throws -> SchemeResponse {
        preconditionFailure("Subclasses implement response(for:)")
    }
}

/// `nomad://app/...` serves the bundled web assets and the user's map files, with HTTP Range support for PMTiles.
///
/// - `/web/...`       bundled viewer pages (Resources/Web)
/// - `/mapassets/...` NOMAD map style, sprites and fonts (Resources/MapAssets)
/// - `/cyberchef/...` bundled CyberChef (Resources/CyberChef)
/// - `/maps/<file>`   .pmtiles files in Documents/Maps
final class AppSchemeHandler: BackgroundSchemeHandler {
    static let scheme = "nomad"

    private let roots: [String: URL] = {
        var roots = ["maps": Storage.maps]
        for (prefix, folder) in [("web", "Web"), ("mapassets", "MapAssets"), ("cyberchef", "CyberChef")] {
            if let url = Bundle.main.url(forResource: folder, withExtension: nil) { roots[prefix] = url }
        }
        return roots
    }()

    static func url(_ path: String) -> URL {
        URL(string: "\(scheme)://app/\(path)")!
    }

    override func response(for request: URLRequest) throws -> SchemeResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let parts = url.path.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let root = roots[parts[0]] else { return .notFound(url) }

        // Resolve inside the root only; reject any path that climbs out of it.
        let file = root.appendingPathComponent(parts[1]).standardizedFileURL
        guard file.path.hasPrefix(root.standardizedFileURL.path + "/"),
              let handle = try? FileHandle(forReadingFrom: file) else { return .notFound(url) }
        defer { try? handle.close() }

        let size = try handle.seekToEnd()
        let mimeType = Self.mimeType(for: file)
        if let range = Self.byteRange(request.value(forHTTPHeaderField: "Range"), size: size) {
            try handle.seek(toOffset: range.lowerBound)
            let body = try handle.read(upToCount: Int(range.upperBound - range.lowerBound + 1)) ?? Data()
            return .make(url, status: 206, mimeType: mimeType, body: body, headers: [
                "Content-Range": "bytes \(range.lowerBound)-\(range.lowerBound + UInt64(body.count) - 1)/\(size)",
                "Accept-Ranges": "bytes",
            ])
        }
        try handle.seek(toOffset: 0)
        return .make(url, mimeType: mimeType, body: try handle.readToEnd() ?? Data(), headers: ["Accept-Ranges": "bytes"])
    }

    /// Parses `bytes=a-b`, `bytes=a-` and `bytes=-n`. Returns nil for a missing or unsatisfiable header.
    static func byteRange(_ header: String?, size: UInt64) -> ClosedRange<UInt64>? {
        guard size > 0, let header, header.hasPrefix("bytes=") else { return nil }
        let spec = header.dropFirst(6).split(separator: ",").first.map(String.init) ?? ""
        let bounds = spec.split(separator: "-", omittingEmptySubsequences: false).map { UInt64($0.trimmingCharacters(in: .whitespaces)) }
        guard bounds.count == 2 else { return nil }
        switch (bounds[0], bounds[1]) {
        case let (start?, end?) where start <= end && start < size:
            return start...min(end, size - 1)
        case let (start?, nil) where start < size:
            return start...(size - 1)
        case let (nil, suffix?) where suffix > 0:
            return (size - min(suffix, size))...(size - 1)
        default:
            return nil
        }
    }

    static func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "pbf": return "application/x-protobuf"
        case "pmtiles": return "application/octet-stream"
        case "js", "mjs": return "text/javascript"
        case "wasm": return "application/wasm"
        default: return UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}
