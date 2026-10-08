import SwiftUI

struct ContentView: View {
    @StateObject private var tabs = TabManager()
    @State private var showTabs = false

    var body: some View {
        Group {
            if let tab = tabs.selected {
                // .id: beim Tab-Wechsel wird die Ansicht samt WebView neu aufgebaut.
                BrowserView(browser: tab, tabs: tabs, showTabs: $showTabs)
                    .id(tab.id)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showTabs) {
            TabOverview(tabs: tabs)
        }
    }
}

/// Ansicht eines einzelnen Tabs: Adressleiste, Seite, Werkzeugleiste.
struct BrowserView: View {
    @ObservedObject var browser: BrowserModel
    @ObservedObject var tabs: TabManager
    @ObservedObject private var adBlock: AdBlockManager
    @Binding var showTabs: Bool
    @FocusState private var addressFocused: Bool

    init(browser: BrowserModel, tabs: TabManager, showTabs: Binding<Bool>) {
        self.browser = browser
        self.tabs = tabs
        self.adBlock = tabs.adBlock
        self._showTabs = showTabs
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
            tabsButton
            Spacer()
            adblockToggle
            Spacer()
            blockerToggle
        }
        .font(.title3)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Öffnet die Tab-Übersicht; zeigt die Anzahl offener Tabs.
    private var tabsButton: some View {
        Button {
            showTabs = true
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
        }
        .contextMenu {
            Text("\(adBlock.ruleCount.formatted()) Filterregeln")
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
