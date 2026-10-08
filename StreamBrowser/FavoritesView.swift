import SwiftUI

/// Liste der Favoriten: antippen öffnet im aktuellen Tab, gedrückt halten für mehr Optionen.
struct FavoritesView: View {
    @ObservedObject var favorites: Favorites
    let onOpen: (Favorite, _ inNewTab: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var renaming: Favorite?
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if favorites.items.isEmpty {
                    ContentUnavailableView(
                        "Noch keine Favoriten",
                        systemImage: "star",
                        description: Text("Tippe auf ☆ neben der Adressleiste, um eine Seite zu speichern.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Favoriten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                if !favorites.items.isEmpty {
                    ToolbarItem(placement: .primaryAction) { EditButton() }
                }
            }
            .alert("Umbenennen", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newTitle)
                Button("Abbrechen", role: .cancel) {}
                Button("Sichern") {
                    if let renaming { favorites.rename(renaming, to: newTitle) }
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(favorites.items) { favorite in
                Button {
                    onOpen(favorite, false)
                    dismiss()
                } label: {
                    FavoriteRow(favorite: favorite)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        onOpen(favorite, true)
                        dismiss()
                    } label: {
                        Label("In neuem Tab öffnen", systemImage: "plus.square.on.square")
                    }
                    Button {
                        newTitle = favorite.title
                        renaming = favorite
                    } label: {
                        Label("Umbenennen", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        if let index = favorites.items.firstIndex(of: favorite) {
                            favorites.remove(atOffsets: [index])
                        }
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
            }
            .onDelete(perform: favorites.remove)
            .onMove(perform: favorites.move)
        }
    }
}

private struct FavoriteRow: View {
    let favorite: Favorite

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: "https://\(favorite.host)/favicon.ico")) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(favorite.title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(favorite.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
