import Foundation

struct Favorite: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var url: String

    var host: String { URL(string: url)?.host ?? url }
}

/// Gespeicherte Favoriten (bleiben über App-Neustarts erhalten).
@MainActor
final class Favorites: ObservableObject {
    @Published private(set) var items: [Favorite] = [] {
        didSet { save() }
    }

    private static let key = "favorites"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([Favorite].self, from: data) {
            items = saved
        }
    }

    func contains(_ url: String) -> Bool {
        items.contains { $0.url == url }
    }

    /// Fügt die Seite hinzu oder entfernt sie, falls sie schon gespeichert ist.
    func toggle(url: String, title: String) {
        guard !url.isEmpty else { return }
        if let index = items.firstIndex(where: { $0.url == url }) {
            items.remove(at: index)
        } else {
            items.append(Favorite(title: title.isEmpty ? (URL(string: url)?.host ?? url) : title, url: url))
        }
    }

    func remove(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func rename(_ favorite: Favorite, to title: String) {
        guard let index = items.firstIndex(of: favorite), !title.isEmpty else { return }
        items[index].title = title
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
