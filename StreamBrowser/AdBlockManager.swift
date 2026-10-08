import ContentBlockerConverter
import Foundation
import WebKit

/// Lädt echte Filterlisten (EasyList), wandelt sie mit AdGuards ContentBlockerConverter
/// in Safari-Regeln um und kompiliert sie zu einer `WKContentRuleList`.
///
/// Die kompilierte Liste speichert `WKContentRuleListStore` dauerhaft auf dem Gerät –
/// beim nächsten Start wird sie nur nachgeschlagen, nicht neu kompiliert.
/// Neu geladen und kompiliert wird nur, wenn der Stand älter als `updateInterval` ist.
@MainActor
final class AdBlockManager: ObservableObject {
    /// Fertige Regelliste zum Anhängen an `WKUserContentController` (nil, solange noch nichts da ist).
    @Published private(set) var ruleList: WKContentRuleList?
    @Published private(set) var ruleCount: Int
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var isUpdating = false

    /// Filterlisten im Adblock-Plus-Format. Weitere Listen einfach ergänzen.
    static let filterListURLs = [
        URL(string: "https://easylist.to/easylist/easylist.txt")!,
    ]
    static let updateInterval: TimeInterval = 3 * 24 * 60 * 60

    private static let identifier = "easylist"
    private static let lastUpdateKey = "adblockLastUpdate"
    private static let ruleCountKey = "adblockRuleCount"

    private let store = WKContentRuleListStore.default()!

    init() {
        lastUpdate = UserDefaults.standard.object(forKey: Self.lastUpdateKey) as? Date
        ruleCount = UserDefaults.standard.integer(forKey: Self.ruleCountKey)
    }

    /// Beim App-Start aufrufen: holt die schon kompilierte Liste aus dem Speicher (Millisekunden).
    func loadCached() async {
        if let cached = try? await store.contentRuleList(forIdentifier: Self.identifier) {
            ruleList = cached
        } else {
            // Erster Start: sofort die mitgelieferte Domainliste nutzen, bis EasyList geladen ist.
            await compile(rules: Self.bundledRules(), saveDate: false)
        }
    }

    /// Lädt EasyList neu, wenn der Stand älter als `updateInterval` ist.
    func updateIfNeeded() async {
        let isStale = lastUpdate.map { Date().timeIntervalSince($0) > Self.updateInterval } ?? true
        if isStale { await update() }
    }

    /// Lädt die Filterlisten neu, konvertiert und kompiliert sie.
    func update() async {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        var rules = Self.bundledRules()
        for url in Self.filterListURLs {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                rules += String(decoding: data, as: UTF8.self).components(separatedBy: .newlines)
            } catch {
                print("Filterliste \(url) nicht geladen: \(error)")
                return
            }
        }
        await compile(rules: rules, saveDate: true)
    }

    private func compile(rules: [String], saveDate: Bool) async {
        // Konvertieren dauert bei EasyList einige Sekunden → nicht auf dem Main-Thread.
        let result = await Task.detached(priority: .utility) {
            ContentBlockerConverter().convertArray(rules: rules, safariVersion: Self.safariVersion)
        }.value

        do {
            // Kompilieren mit festem Identifier speichert die Liste automatisch im Store.
            let list = try await store.compileContentRuleList(
                forIdentifier: Self.identifier,
                encodedContentRuleList: result.safariRulesJSON
            )
            ruleList = list
            ruleCount = result.safariRulesCount
            UserDefaults.standard.set(ruleCount, forKey: Self.ruleCountKey)
            if saveDate {
                lastUpdate = Date()
                UserDefaults.standard.set(lastUpdate, forKey: Self.lastUpdateKey)
            }
        } catch {
            print("Regeln konnten nicht kompiliert werden: \(error)")
        }
    }

    /// Eigene Werbe-Domains (adblock_domains.json) als Adblock-Regeln, z. B. "||popads.net^".
    private static func bundledRules() -> [String] {
        guard let file = Bundle.main.url(forResource: "adblock_domains", withExtension: "json"),
              let data = try? Data(contentsOf: file),
              let domains = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return domains.map { "||\($0)^" }
    }

    /// Safari-Version entspricht der iOS-Version (bestimmt z. B. das Regel-Limit von 150.000).
    private nonisolated static var safariVersion: SafariVersion {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return SafariVersion(Double(os.majorVersion) + Double(os.minorVersion) / 10)
    }
}
