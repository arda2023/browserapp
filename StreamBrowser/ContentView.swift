import SwiftUI

struct ContentView: View {
    @StateObject private var tabs = TabManager()
    @StateObject private var favorites = Favorites()
    @State private var showTabs = false
    @State private var showFavorites = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let tab = tabs.selected {
                // .id: beim Tab-Wechsel wird die Ansicht samt WebView neu aufgebaut.
                BrowserView(browser: tab, tabs: tabs, favorites: favorites,
                            showTabs: $showTabs, showFavorites: $showFavorites)
                    .id(tab.id)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fullScreenCover(isPresented: $showTabs) {
            TabOverview(tabs: tabs)
        }
        .sheet(isPresented: $showFavorites) {
            FavoritesView(favorites: favorites) { favorite, inNewTab in
                if inNewTab {
                    tabs.newTab(url: favorite.url)
                } else {
                    tabs.selected?.load(favorite.url)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { tabs.saveTabs() }
        }
    }
}

/// Ansicht eines einzelnen Tabs: Adressleiste, Seite, Werkzeugleiste.
struct BrowserView: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var tabs: TabManager
    @ObservedObject var favorites: Favorites
    @ObservedObject private var adBlock: AdBlockManager
    @Binding var showTabs: Bool
    @Binding var showFavorites: Bool
    @FocusState private var addressFocused: Bool

    init(browser: BrowserModel, tabs: TabManager, favorites: Favorites,
         showTabs: Binding<Bool>, showFavorites: Binding<Bool>) {
        self.browser = browser
        self.tabs = tabs
        self.favorites = favorites
        self.adBlock = tabs.adBlock
        self._showTabs = showTabs
        self._showFavorites = showFavorites
    }

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            if browser.isLoading {
                ProgressView(value: browser.progress)
                    .progressViewStyle(.linear)
            }
            WebView(webView: browser.webView)
                .overlay(alignment: .bottom) { blockedBanner }
            toolbar
        }
        // Wiederhergestellte Tabs laden erst, wenn sie angezeigt werden.
        .onAppear { browser.activate() }
    }

    private var addressBar: some View {
        HStack(spacing: 12) {
            TextField("Mit Yandex suchen oder Adresse eingeben", text: $browser.addressText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit { browser.load(browser.addressText) }
                .onChange(of: addressFocused) { _, focused in
                    browser.isEditingAddress = focused
                    if focused {
                        // Gesamten Text markieren, damit man direkt eine neue Adresse tippen kann.
                        DispatchQueue.main.async {
                            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                        }
                    } else if let url = browser.webView.url {
                        browser.addressText = url.absoluteString
                    }
                }
            favoriteButton
            Button(action: browser.reloadOrStop) {
                Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
            }
            .accessibilityLabel(browser.isLoading ? "Stopp" : "Neu laden")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var toolbar: some View {
        HStack {
            Button(action: browser.goBack) { Image(systemName: "chevron.left") }
                .disabled(!browser.canGoBack)
            Spacer()
            Button(action: browser.goForward) { Image(systemName: "chevron.right") }
                .disabled(!browser.canGoForward)
            Spacer()
            Button {
                showFavorites = true
            } label: {
                Image(systemName: "book")
            }
            .accessibilityLabel("Favoriten")
            Spacer()
            tabsButton
            Spacer()
            adblockToggle
            Spacer()
            blockerToggle
        }
        .font(.title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Stern: aktuelle Seite als Favorit speichern oder entfernen.
    private var favoriteButton: some View {
        let isFavorite = favorites.contains(browser.currentURL)
        return Button {
            favorites.toggle(url: browser.currentURL, title: browser.title)
        } label: {
            Image(systemName: isFavorite ? "star.fill" : "star")
                .foregroundStyle(isFavorite ? .yellow : .accentColor)
        }
        .accessibilityLabel(isFavorite ? "Aus Favoriten entfernen" : "Zu Favoriten hinzufügen")
    }

    /// Öffnet die Tab-Übersicht; zeigt die Anzahl offener Tabs.
    private var tabsButton: some View {
        Button {
            // Erst aktuelles Vorschaubild aufnehmen, dann Übersicht zeigen.
            Task {
                await browser.captureSnapshot()
                showTabs = true
            }
        } label: {
            Image(systemName: "square")
                .overlay {
                    Text("\(tabs.tabs.count)")
                        .font(.caption.bold())
                }
        }
        .accessibilityLabel("Tabs, \(tabs.tabs.count) offen")
    }

    /// Hand-Button: Werbeblocker an/aus. Gedrückt halten zeigt den EasyList-Stand.
    private var adblockToggle: some View {
        Button {
            tabs.adblockEnabled.toggle()
        } label: {
            Image(systemName: tabs.adblockEnabled ? "hand.raised.fill" : "hand.raised.slash")
                .foregroundStyle(tabs.adblockEnabled ? .orange : .secondary)
                .overlay(alignment: .topTrailing) {
                    if tabs.adblockEnabled && tabs.skippedAdCount > 0 {
                        Text("\(tabs.skippedAdCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(.orange))
                            .offset(x: 10, y: -8)
                    }
                }
        }
        .contextMenu {
            Text("\(adBlock.ruleCount.formatted()) Filterregeln")
            Text("\(tabs.skippedAdCount) Videowerbungen entfernt")
            if let date = adBlock.lastUpdate {
                Text("EasyList-Stand: \(date.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("EasyList noch nicht geladen")
            }
            Button {
                Task { await adBlock.update() }
            } label: {
                Label(adBlock.isUpdating ? "Wird aktualisiert …" : "Filterlisten aktualisieren",
                      systemImage: "arrow.down.circle")
            }
            .disabled(adBlock.isUpdating)
        }
        .accessibilityLabel(tabs.adblockEnabled ? "Werbeblocker an" : "Werbeblocker aus")
    }

    /// Schild-Button: Pop-up-Blocker an/aus, mit Zähler der blockierten Tabs.
    private var blockerToggle: some View {
        Button {
            tabs.blockerEnabled.toggle()
        } label: {
            Image(systemName: tabs.blockerEnabled ? "checkmark.shield.fill" : "shield.slash")
                .foregroundStyle(tabs.blockerEnabled ? .green : .secondary)
                .overlay(alignment: .topTrailing) {
                    if tabs.blockerEnabled && tabs.blockedCount > 0 {
                        Text("\(tabs.blockedCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(.red))
                            .offset(x: 10, y: -8)
                    }
                }
        }
        .accessibilityLabel(tabs.blockerEnabled ? "Pop-up-Blocker an" : "Pop-up-Blocker aus")
    }

    @ViewBuilder
    private var blockedBanner: some View {
        if let url = tabs.lastBlockedURL {
            HStack {
                VStack(alignment: .leading) {
                    Text("Pop-up blockiert").font(.subheadline.bold())
                    Text(url.host ?? url.absoluteString)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Öffnen", action: tabs.openLastBlocked)
                Button {
                    tabs.lastBlockedURL = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Schließen")
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding()
            .task(id: url) {
                try? await Task.sleep(for: .seconds(4))
                if tabs.lastBlockedURL == url { tabs.lastBlockedURL = nil }
            }
        }
    }
}

#Preview {
    ContentView()
}
