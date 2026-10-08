import Combine
import Foundation
import WebKit

final class BrowserModel: NSObject, ObservableObject {
    let webView: WKWebView

    @Published var addressText = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0

    private var cancellables = Set<AnyCancellable>()

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebView()
        load("https://www.google.com")
    }

    private func observeWebView() {
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
        webView.publisher(for: \.isLoading).assign(to: &$isLoading)
        webView.publisher(for: \.estimatedProgress).assign(to: &$progress)
        webView.publisher(for: \.url)
            .compactMap { $0?.absoluteString }
            .sink { [weak self] in self?.addressText = $0 }
            .store(in: &cancellables)
    }

    // MARK: - Navigation

    /// Lädt eine URL oder startet eine Google-Suche, wenn die Eingabe keine Adresse ist.
    func load(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let url: URL?
        if text.contains("://") {
            url = URL(string: text)
        } else if text.contains("."), !text.contains(" ") {
            url = URL(string: "https://" + text)
        } else {
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: text)]
            url = components?.url
        }
        if let url { webView.load(URLRequest(url: url)) }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reloadOrStop() {
        if isLoading { webView.stopLoading() } else { webView.reload() }
    }
}

extension BrowserModel: WKNavigationDelegate {}

extension BrowserModel: WKUIDelegate {}
