import Combine
import Foundation
import WebKit

/// Verwaltet die Tabs und die Blocker-Einstellungen, die für alle Tabs gelten.
@MainActor
final class TabManager: ObservableObject {
    @Published private(set) var tabs: [BrowserModel] = []
    @Published var selectedID: UUID? {
        didSet { saveTabs() }
    }

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
            // Tabs erst, wenn die Regeln bereitstehen, damit schon die erste Seite gefiltert wird.
            restoreTabs()
            // Zum Testen: Launch-Argument "-startURL <url>" öffnet die Adresse in einem neuen Tab.
            if let startURL = UserDefaults.standard.string(forKey: "startURL") {
                newTab(url: startURL)
            } else if tabs.isEmpty {
                newTab()
            }
            await adBlock.updateIfNeeded()
        }
    }

    // MARK: - Tabs speichern

    private struct SavedTab: Codable {
        let id: UUID
        let url: String
        let title: String
    }

    private struct SavedSession: Codable {
        let tabs: [SavedTab]
        let selectedID: UUID?
    }

    private static let sessionKey = "openTabs"
    private var isRestoring = false

    /// Speichert offene Tabs (Adresse, Titel) und den aktiven Tab.
    func saveTabs() {
        guard !isRestoring, !tabs.isEmpty else { return }
        let session = SavedSession(
            tabs: tabs.map { SavedTab(id: $0.id, url: $0.currentURL, title: $0.title) },
            selectedID: selectedID
        )
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        }
    }

    /// Stellt die Tabs vom letzten Mal wieder her. Geladen wird nur der angezeigte Tab.
    private func restoreTabs() {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionKey),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data) else { return }
        isRestoring = true
        defer { isRestoring = false }
        for saved in session.tabs where !saved.url.isEmpty {
            addTab(makeTab(id: saved.id, url: saved.url, title: saved.title, loadNow: false))
        }
        selectedID = tabs.contains { $0.id == session.selectedID } ? session.selectedID : tabs.last?.id
    }

    /// Der aktuell angezeigte Tab (nil nur ganz am Anfang, bis die Regeln geladen sind).
    var selected: BrowserModel? {
        tabs.first { $0.id == selectedID } ?? tabs.first
    }

    @discardableResult
    func newTab(url: String = BrowserModel.homeURL) -> BrowserModel {
        let tab = makeTab(id: UUID(), url: url, title: "", loadNow: true)
        addTab(tab)
        selectedID = tab.id
        return tab
    }

    private func makeTab(id: UUID, url: String, title: String, loadNow: Bool) -> BrowserModel {
        BrowserModel(
            id: id,
            url: url,
            title: title,
            loadNow: loadNow,
            blockerEnabled: blockerEnabled,
            adblockEnabled: adblockEnabled,
            contentRules: adblockEnabled ? adBlock.ruleList : nil
        )
    }

    private func addTab(_ tab: BrowserModel) {
        tab.onBlocked = { [weak self] url in self?.registerBlocked(url) }
        tab.onAdSkipped = { [weak self] in self?.skippedAdCount += 1 }
        tab.onStateChange = { [weak self] in self?.saveTabs() }
        tabs.append(tab)
    }

    func select(_ tab: BrowserModel) {
        selectedID = tab.id
    }

    func close(_ tab: BrowserModel) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs.remove(at: index)
        tab.deleteSnapshot()
        if tabs.isEmpty {
            newTab()
        } else if selectedID == tab.id {
            selectedID = tabs[min(index, tabs.count - 1)].id
        } else {
            saveTabs()
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
