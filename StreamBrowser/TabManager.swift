import Combine
import Foundation
import WebKit

/// Verwaltet die Tabs und die Blocker-Einstellungen, die für alle Tabs gelten.
@MainActor
final class TabManager: ObservableObject {
    @Published private(set) var tabs: [BrowserModel] = []
    @Published var selectedID: UUID?

    /// Blockiert neue Tabs/Fenster und automatische Weiterleitungen auf fremde Seiten.
    @Published var blockerEnabled: Bool {
        didSet {
            UserDefaults.standard.set(blockerEnabled, forKey: Self.blockerKey)
            tabs.forEach { $0.setBlockerEnabled(blockerEnabled) }
            selected?.reload()
        }
    }

    /// Werbeblocker (EasyList über `AdBlockManager`).
    @Published var adblockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(adblockEnabled, forKey: Self.adblockKey)
            applyContentRules()
            tabs.forEach { $0.setAdblockEnabled(adblockEnabled) }
            selected?.reload()
        }
    }

    @Published private(set) var blockedCount = 0
    /// Anzahl entfernter/übersprungener Videowerbungen.
    @Published private(set) var skippedAdCount = 0
    /// Zuletzt blockierte Adresse – kann über das Banner trotzdem geöffnet werden.
    @Published var lastBlockedURL: URL?

    let adBlock = AdBlockManager()

    private static let blockerKey = "blockerEnabled"
    private static let adblockKey = "adblockEnabled"
    private var cancellables = Set<AnyCancellable>()

    init() {
        blockerEnabled = UserDefaults.standard.object(forKey: Self.blockerKey) as? Bool ?? true
        adblockEnabled = UserDefaults.standard.object(forKey: Self.adblockKey) as? Bool ?? true

        // Sobald eine (neue) Regelliste fertig ist, an alle Tabs hängen.
        adBlock.$ruleList
            .dropFirst()
            .sink { [weak self] _ in
                // $ruleList feuert vor dem Setzen → erst danach anwenden.
                DispatchQueue.main.async { self?.applyContentRules() }
            }
            .store(in: &cancellables)

        Task {
            await adBlock.loadCached()
            // Erster Tab erst, wenn die Regeln bereitstehen, damit schon die erste Seite gefiltert wird.
            if tabs.isEmpty {
                // Startseite; zum Testen überschreibbar per Launch-Argument "-startURL <url>".
                newTab(url: UserDefaults.standard.string(forKey: "startURL") ?? BrowserModel.homeURL)
            }
            await adBlock.updateIfNeeded()
        }
    }

    /// Der aktuell angezeigte Tab (nil nur ganz am Anfang, bis die Regeln geladen sind).
    var selected: BrowserModel? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    @discardableResult
    func newTab(url: String = BrowserModel.homeURL) -> BrowserModel {
        let tab = BrowserModel(
            url: url,
            blockerEnabled: blockerEnabled,
            adblockEnabled: adblockEnabled,
            contentRules: adblockEnabled ? adBlock.ruleList : nil
        )
        tab.onBlocked = { [weak self] url in self?.registerBlocked(url) }
        tab.onAdSkipped = { [weak self] in self?.skippedAdCount += 1 }
        tabs.append(tab)
        selectedID = tab.id
        return tab
    }

    func select(_ tab: BrowserModel) {
        selectedID = tab.id
    }

    func close(_ tab: BrowserModel) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab()
        } else if selectedID == tab.id {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
    }

    /// Öffnet die zuletzt blockierte Adresse im aktuellen Tab.
    func openLastBlocked() {
        guard let url = lastBlockedURL else { return }
        lastBlockedURL = nil
        selected?.load(url)
    }

    private func registerBlocked(_ url: URL?) {
        blockedCount += 1
        if let url, url.scheme?.hasPrefix("http") == true { lastBlockedURL = url }
    }

    private func applyContentRules() {
        let rules = adblockEnabled ? adBlock.ruleList : nil
        tabs.forEach { $0.setContentRules(rules) }
    }
}
