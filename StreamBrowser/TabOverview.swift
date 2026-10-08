import SwiftUI

/// Tab-Übersicht im Opera-Stil: Kacheln mit Vorschaubild der Seite.
/// Antippen zum Wechseln, ✕ zum Schließen, + für neuen Tab.
struct TabOverview: View {
    @ObservedObject var tabs: TabManager
    @Environment(\.dismiss) private var dismiss

    static let accent = Color(red: 0.98, green: 0.22, blue: 0.40)
    private static let background = Color(red: 0.09, green: 0.09, blue: 0.16)
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(tabs.tabs) { tab in
                            TabCard(tab: tab, isSelected: tab.id == tabs.selected?.id) {
                                withAnimation { tabs.close(tab) }
                            }
                            .id(tab.id)
                            .onTapGesture {
                                tabs.select(tab)
                                dismiss()
                            }
                        }
                    }
                    .padding(14)
                }
                .onAppear { proxy.scrollTo(tabs.selectedID, anchor: .center) }
            }
            bottomBar
        }
        .background(Self.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(.white.opacity(0.12)))
            }
            .accessibilityLabel("Schließen")
            Spacer()
            Text("\(tabs.tabs.count) \(tabs.tabs.count == 1 ? "Tab" : "Tabs")")
                .font(.headline)
            Spacer()
            Color.clear.frame(width: 48, height: 48)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        Button {
            tabs.newTab()
            dismiss()
        } label: {
            Image(systemName: "plus")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Self.accent))
        }
        .accessibilityLabel("Neuer Tab")
        .padding(.vertical, 12)
    }
}

private struct TabCard: View {
    @ObservedObject var tab: BrowserModel
    let isSelected: Bool
    let onClose: () -> Void

    private var host: String? { tab.webView.url?.host }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                favicon
                Text(tab.title.isEmpty ? (host ?? "Neuer Tab") : tab.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black.opacity(0.6))
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(.black.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tab schließen")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)

            preview
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding([.horizontal, .bottom], 5)
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 19)
                    .stroke(TabOverview.accent, lineWidth: 3)
                    .padding(-4)
            }
        }
        .padding(isSelected ? 4 : 0)
        .contentShape(Rectangle())
    }

    /// Vorschaubild, oben bündig zugeschnitten (wie bei Opera).
    private var preview: some View {
        Color(white: 0.92)
            .aspectRatio(0.78, contentMode: .fit)
            .overlay(alignment: .top) {
                if let snapshot = tab.snapshot {
                    Image(uiImage: snapshot)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "globe")
                        .font(.largeTitle)
                        .foregroundStyle(.gray)
                        .frame(maxHeight: .infinity)
                }
            }
            .clipped()
    }

    private var favicon: some View {
        AsyncImage(url: host.flatMap { URL(string: "https://\($0)/favicon.ico") }) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "globe").foregroundStyle(.gray)
        }
        .frame(width: 18, height: 18)
    }
}
