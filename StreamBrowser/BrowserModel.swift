import Combine
import Foundation
import UIKit
import WebKit

/// Ein Browser-Tab mit eigener WKWebView. Blocker-Einstellungen setzt der `TabManager`.
final class BrowserModel: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView

    @Published var addressText = ""
    /// Solange der Nutzer tippt, wird die Adressleiste nicht von der Seite überschrieben.
    var isEditingAddress = false
    @Published private(set) var title = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0

    /// Vorschaubild der Seite für die Tab-Übersicht.
    @Published private(set) var snapshot: UIImage?

    /// Blockiert neue Tabs/Fenster und automatische Weiterleitungen auf fremde Seiten.
    private(set) var blockerEnabled: Bool
    /// Werbeblocker an: Filterregeln + Video-Werbeblocker-Skript.
    private(set) var adblockEnabled: Bool
    /// Wird bei jedem blockierten Pop-up / jeder blockierten Weiterleitung aufgerufen.
    var onBlocked: ((URL?) -> Void)?
    /// Wird aufgerufen, wenn das Skript Videowerbung entfernt oder übersprungen hat.
    var onAdSkipped: (() -> Void)?

    private static let popupMessage = "popupBlocked"
    private static let adSkippedMessage = "adSkipped"

    /// Video-Werbeblocker (video_adblock.js), einmal aus dem Bundle geladen.
    private static let videoAdblockScript: WKUserScript? = {
        guard let url = Bundle.main.url(forResource: "video_adblock", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Dokumentbeginn: YouTube-Daten müssen bereinigt sein, bevor der Player startet.
        // Alle Frames: Videoplayer stecken auf Streaming-Seiten meist in iframes.
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }()
    static let homeURL = "https://yandex.com"

    /// true, solange eine vom Nutzer gestartete Navigation läuft (Eingabe, Zurück, Neu laden).
    /// Weiterleitungen in dieser Phase (z. B. google.com → www.google.com) sind erlaubt.
    private var userInitiatedLoad = false

    private var contentRules: WKContentRuleList?
    private var cancellables = Set<AnyCancellable>()

    init(url: String, blockerEnabled: Bool, adblockEnabled: Bool, contentRules: WKContentRuleList?) {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"

        // Ohne Erlaubnis darf JavaScript keine Fenster öffnen.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        self.blockerEnabled = blockerEnabled
        self.adblockEnabled = adblockEnabled
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        installUserScripts()
        setContentRules(contentRules)
        observeWebView()
        load(url)
    }

    private func observeWebView() {
        webView.publisher(for: \.canGoBack).assign(to: &$canGoBack)
        webView.publisher(for: \.canGoForward).assign(to: &$canGoForward)
        webView.publisher(for: \.isLoading).assign(to: &$isLoading)
        webView.publisher(for: \.estimatedProgress).assign(to: &$progress)
        webView.publisher(for: \.title).map { $0 ?? "" }.assign(to: &$title)
        webView.publisher(for: \.url)
            .compactMap { $0?.absoluteString }
            .sink { [weak self] url in
                guard let self, !self.isEditingAddress else { return }
                self.addressText = url
            }
            .store(in: &cancellables)
    }

    // MARK: - Navigation

    /// Lädt eine URL oder startet eine Yandex-Suche, wenn die Eingabe keine Adresse ist.
    func load(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let url: URL?
        if text.contains("://") {
            url = URL(string: text)
        } else if text.contains("."), !text.contains(" ") {
            url = URL(string: "https://" + text)
        } else {
            var components = URLComponents(string: "https://yandex.com/search/")
            components?.queryItems = [URLQueryItem(name: "text", value: text)]
            url = components?.url
        }
        if let url { load(url) }
    }

    func load(_ url: URL) {
        userInitiatedLoad = true
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        userInitiatedLoad = true
        webView.goBack()
    }

    func goForward() {
        userInitiatedLoad = true
        webView.goForward()
    }

    func reload() {
        userInitiatedLoad = true
        webView.reload()
    }

    func reloadOrStop() {
        if isLoading { webView.stopLoading() } else { reload() }
    }

    private func loadUserInitiated(_ request: URLRequest) {
        userInitiatedLoad = true
        webView.load(request)
    }

    // MARK: - Blocker

    func setBlockerEnabled(_ enabled: Bool) {
        blockerEnabled = enabled
        installUserScripts()
    }

    func setAdblockEnabled(_ enabled: Bool) {
        adblockEnabled = enabled
        installUserScripts()
    }

    /// Macht ein Vorschaubild der sichtbaren Seite für die Tab-Übersicht.
    @MainActor
    func captureSnapshot() async {
        guard webView.window != nil, webView.bounds.width > 0 else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 400
        if let image = try? await webView.takeSnapshot(configuration: config) {
            snapshot = image
        }
    }

    /// Hängt die Werbeblocker-Regeln an (oder entfernt sie mit nil).
    func setContentRules(_ rules: WKContentRuleList?) {
        let controller = webView.configuration.userContentController
        if let contentRules { controller.remove(contentRules) }
        contentRules = rules
        if let rules { controller.add(rules) }
    }

    private func registerBlocked(_ url: URL?) {
        onBlocked?(url)
    }

    /// Ersetzt `window.open` durch eine Attrappe. Werbeskripte bekommen ein „Fenster“ zurück
    /// und versuchen deshalb nicht, stattdessen den aktuellen Tab umzuleiten.
    private func installUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.removeScriptMessageHandler(forName: Self.popupMessage)
        controller.removeScriptMessageHandler(forName: Self.adSkippedMessage)

        if adblockEnabled, let videoAdblockScript = Self.videoAdblockScript {
            controller.add(WeakScriptHandler(self), name: Self.adSkippedMessage)
            controller.addUserScript(videoAdblockScript)
        }
        guard blockerEnabled else { return }

        controller.add(WeakScriptHandler(self), name: Self.popupMessage)
        let source = """
        (function() {
          var noop = function() {};
          var fake = { closed: false, opener: null, close: noop, focus: noop, blur: noop,
                       postMessage: noop, location: { href: '', replace: noop, assign: noop },
                       document: { write: noop, writeln: noop, open: noop, close: noop } };
          window.open = function(url) {
            try { window.webkit.messageHandlers.\(Self.popupMessage).postMessage(String(url || '')); } catch (e) {}
            return fake;
          };
        })();
        """
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
    }

    /// Grobe Annäherung an die Hauptdomain (letzte zwei Labels), z. B. "video.example.com" → "example.com".
    private static func siteKey(_ url: URL?) -> String? {
        guard let host = url?.host?.lowercased() else { return nil }
        return host.split(separator: ".").suffix(2).joined(separator: ".")
    }
}

// MARK: - WKNavigationDelegate

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url

        // Link mit target="_blank" o. ä.: würde einen neuen Tab öffnen.
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            if blockerEnabled {
                registerBlocked(url)
            } else {
                loadUserInitiated(navigationAction.request)
            }
            return
        }

        // Automatische Umleitung des Haupt-Tabs auf eine fremde Seite (typische Werbe-Weiterleitung).
        if blockerEnabled,
           navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.navigationType == .other,
           !userInitiatedLoad,
           let current = Self.siteKey(webView.url),
           let target = Self.siteKey(url),
           current != target {
            decisionHandler(.cancel)
            registerBlocked(url)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        userInitiatedLoad = false
        Task { await captureSnapshot() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        userInitiatedLoad = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        userInitiatedLoad = false
    }
}

// MARK: - WKUIDelegate

extension BrowserModel: WKUIDelegate {
    /// Wird aufgerufen, wenn die Seite ein neues Fenster/einen neuen Tab will. Es gibt nie einen neuen Tab.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if blockerEnabled {
            registerBlocked(navigationAction.request.url)
        } else {
            loadUserInitiated(navigationAction.request)
        }
        return nil
    }
}

// MARK: - WKScriptMessageHandler

extension BrowserModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == Self.adSkippedMessage {
            onAdSkipped?()
            return
        }
        guard message.name == Self.popupMessage else { return }
        registerBlocked(URL(string: message.body as? String ?? "", relativeTo: webView.url)?.absoluteURL)
    }
}

/// Verhindert einen Retain-Cycle zwischen WKUserContentController und BrowserModel.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
