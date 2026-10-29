import Combine
import SwiftUI
import UIKit
import WebKit
import ZimKit

extension ZimEntry: Identifiable {
    public var id: UInt32 { index }
}

@MainActor
final class ZimReaderModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var results: [ZimEntry] = []
    @Published var errorMessage: String?

    let webView: WKWebView
    let title: String
    private let archive: ZimArchive?
    private var searchTask: Task<Void, Never>?

    init(fileURL: URL) {
        let configuration = WKWebViewConfiguration()
        var archive: ZimArchive?
        var openError: String?
        do {
            let opened = try ZimArchive(url: fileURL)
            configuration.setURLSchemeHandler(ZimSchemeHandler(archive: opened), forURLScheme: ZimSchemeHandler.scheme)
            archive = opened
        } catch {
            openError = error.localizedDescription
        }
        self.archive = archive
        self.title = archive?.title ?? fileURL.deletingPathExtension().lastPathComponent
        _errorMessage = Published(initialValue: openError)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        super.init()

        webView.navigationDelegate = self
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
        goHome()
    }

    func goHome() {
        guard let archive else { return }
        do {
            guard let main = try archive.mainEntry() else {
                errorMessage = "This ZIM file has no main page. Use search to open an article."
                return
            }
            open(main)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ entry: ZimEntry) {
        webView.load(URLRequest(url: ZimSchemeHandler.url(for: entry)))
    }

    func search(_ query: String) {
        searchTask?.cancel()
        guard let archive, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            // The first search loads the title index, which can take a moment on large archives.
            let found = await Task.detached(priority: .userInitiated) {
                (try? archive.searchTitles(query)) ?? []
            }.value
            if !Task.isCancelled { results = found }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Links out of the archive go to Safari, which shows its own offline page if there is no connection.
        if let url = action.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }
}

struct ZimReaderView: View {
    @StateObject private var model: ZimReaderModel
    @State private var query = ""

    init(fileURL: URL) {
        _model = StateObject(wrappedValue: ZimReaderModel(fileURL: fileURL))
    }

    var body: some View {
        Group {
            if let message = model.errorMessage {
                ContentUnavailableView("Cannot open this file", systemImage: "exclamationmark.triangle", description: Text(message))
            } else {
                WebView(webView: model.webView)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search titles")
        .searchSuggestions {
            ForEach(model.results) { entry in
                Button {
                    model.open(entry)
                    query = ""
                    model.results = []
                } label: {
                    Label(entry.title, systemImage: entry.isRedirect ? "arrow.turn.down.right" : "doc.text")
                }
            }
        }
        .onChange(of: query) { _, newValue in model.search(newValue) }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.webView.goBack() } label: { Label("Back", systemImage: "chevron.backward") }
                    .disabled(!model.canGoBack)
                Button { model.webView.goForward() } label: { Label("Forward", systemImage: "chevron.forward") }
                    .disabled(!model.canGoForward)
                Button { model.goHome() } label: { Label("Main page", systemImage: "house") }
            }
        }
    }
}
