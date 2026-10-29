import Foundation
import ZimKit

/// `zim://book/<namespace>/<path>` serves entries from one open archive. Keeping the namespace as the
/// first path segment means the relative links inside ZIM pages ("Other_page", "../I/image.png") resolve as-is.
final class ZimSchemeHandler: BackgroundSchemeHandler {
    static let scheme = "zim"

    let archive: ZimArchive

    init(archive: ZimArchive) {
        self.archive = archive
        super.init()
    }

    static func url(for entry: ZimEntry) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "book"
        components.path = "/" + entry.fullPath
        return components.url!
    }

    override func response(for request: URLRequest) throws -> SchemeResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        let path = url.path.dropFirst()
        guard let namespace = path.first, path.dropFirst().first == "/" else { return .notFound(url) }
        guard let entry = try archive.entry(namespace: namespace, path: String(path.dropFirst(2))) else {
            return .notFound(url)
        }

        // Send page navigations to the redirect target's own URL so its relative links resolve from there.
        if entry.isRedirect, request.mainDocumentURL == url {
            let target = Self.url(for: try archive.resolveRedirects(entry)).absoluteString
            let html = "<!doctype html><meta http-equiv=\"refresh\" content=\"0;url=\(target)\">"
            return .make(url, mimeType: "text/html", body: Data(html.utf8))
        }

        let content = try archive.content(of: entry)
        return .make(url, mimeType: content.mimeType, body: content.data)
    }
}
