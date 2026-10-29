import SwiftUI
import WebKit

struct MapsView: View {
    var body: some View {
        FileLibraryView(
            title: "Maps",
            folder: Storage.maps,
            fileExtension: "pmtiles",
            contentType: Storage.pmtilesType,
            emptyMessage: "Import a .pmtiles region map, for example one downloaded by a NOMAD server or extracted from maps.protomaps.com, or copy it in the Files app to On My iPad > NOMAD > Maps.",
            openAllLabel: "View All Maps"
        ) { files in
            MapViewerView(files: files)
        }
    }
}

/// MapLibre in a web view, drawing the user's .pmtiles files with the same base style as the NOMAD server.
struct MapViewerView: View {
    let files: [URL]
    @State private var webView = WKWebView.withAppScheme()

    var body: some View {
        WebView(webView: webView)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(files.count == 1 ? files[0].deletingPathExtension().lastPathComponent : "All Maps")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard webView.url == nil else { return }
                var components = URLComponents(url: AppSchemeHandler.url("web/map.html"), resolvingAgainstBaseURL: false)!
                components.queryItems = files.map { URLQueryItem(name: "file", value: $0.lastPathComponent) }
                webView.load(URLRequest(url: components.url!))
            }
    }
}
