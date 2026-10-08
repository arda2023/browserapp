import SwiftUI

struct ContentView: View {
    @StateObject private var browser = BrowserModel()
    @FocusState private var addressFocused: Bool

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
            Button(action: browser.reloadOrStop) {
                Image(systemName: browser.isLoading ? "xmark" : "arrow.clockwise")
            }
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

    /// Hand-Button: Werbeblocker an/aus.
    private var adblockToggle: some View {
        Button {
            browser.adblockEnabled.toggle()
        } label: {
            Image(systemName: browser.adblockEnabled ? "hand.raised.fill" : "hand.raised.slash")
                .foregroundStyle(browser.adblockEnabled ? .orange : .secondary)
        }
        .accessibilityLabel(browser.adblockEnabled ? "Werbeblocker an" : "Werbeblocker aus")
    }

    /// Schild-Button: Pop-up-Blocker an/aus, mit Zähler der blockierten Tabs.
    private var blockerToggle: some View {
        Button {
            browser.blockerEnabled.toggle()
        } label: {
            Image(systemName: browser.blockerEnabled ? "checkmark.shield.fill" : "shield.slash")
                .foregroundStyle(browser.blockerEnabled ? .green : .secondary)
                .overlay(alignment: .topTrailing) {
                    if browser.blockerEnabled && browser.blockedCount > 0 {
                        Text("\(browser.blockedCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(.red))
                            .offset(x: 10, y: -8)
                    }
                }
        }
        .accessibilityLabel(browser.blockerEnabled ? "Pop-up-Blocker an" : "Pop-up-Blocker aus")
    }

    @ViewBuilder
    private var blockedBanner: some View {
        if let url = browser.lastBlockedURL {
            HStack {
                VStack(alignment: .leading) {
                    Text("Pop-up blockiert").font(.subheadline.bold())
                    Text(url.host ?? url.absoluteString)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Öffnen", action: browser.openLastBlocked)
                Button {
                    browser.lastBlockedURL = nil
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
                if browser.lastBlockedURL == url { browser.lastBlockedURL = nil }
            }
        }
    }
}

#Preview {
    ContentView()
}
