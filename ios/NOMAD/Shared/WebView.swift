import SwiftUI
import WebKit

/// Hosts a WKWebView owned by a view model, so toolbar buttons can drive navigation.
struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

extension WKWebView {
    /// A web view whose `nomad://` requests are answered from the app bundle and Documents folder.
    static func withAppScheme() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(AppSchemeHandler(), forURLScheme: AppSchemeHandler.scheme)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
        return webView
    }
}
