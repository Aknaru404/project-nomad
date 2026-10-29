import SwiftUI
import WebKit

/// CyberChef is a self-contained web app; the build bundles its release and serves it over `nomad://`.
struct CyberChefView: View {
    @State private var webView = WKWebView.withAppScheme()
    private let isBundled = Bundle.main.url(forResource: "CyberChef", withExtension: "html", subdirectory: "CyberChef") != nil

    var body: some View {
        NavigationStack {
            Group {
                if isBundled {
                    WebView(webView: webView)
                        .onAppear {
                            if webView.url == nil {
                                webView.load(URLRequest(url: AppSchemeHandler.url("cyberchef/CyberChef.html")))
                            }
                        }
                } else {
                    ContentUnavailableView("CyberChef is not in this build", systemImage: "wrench.and.screwdriver",
                                           description: Text("Run ios/scripts/fetch-assets.sh before building."))
                }
            }
            .navigationTitle("Data Tools")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
