import SwiftUI

/// Liste aller offenen Tabs: antippen zum Wechseln, wischen oder ✕ zum Schließen, + für neuen Tab.
struct TabOverview: View {
    @ObservedObject var tabs: TabManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(tabs.tabs) { tab in
                    TabRow(tab: tab, isSelected: tab.id == tabs.selected?.id) {
                        tabs.close(tab)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        tabs.select(tab)
                        dismiss()
                    }
                }
                .onDelete { offsets in
                    offsets.map { tabs.tabs[$0] }.forEach(tabs.close)
                }
            }
            .navigationTitle("Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        tabs.newTab()
                        dismiss()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neuer Tab")
                }
            }
        }
    }
}

private struct TabRow: View {
    @ObservedObject var tab: BrowserModel
    let isSelected: Bool
    let onClose: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title.isEmpty ? (tab.webView.url?.host ?? "Neuer Tab") : tab.title)
                    .lineLimit(1)
                    .fontWeight(isSelected ? .semibold : .regular)
                Text(tab.webView.url?.host ?? tab.addressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Tab schließen")
        }
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
    }
}
