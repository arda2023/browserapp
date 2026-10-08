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
            toolbar
        }
    }

    private var addressBar: some View {
        TextField("Suchen oder Adresse eingeben", text: $browser.addressText)
            .textFieldStyle(.roundedBorder)
            .keyboardType(.webSearch)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($addressFocused)
            .onSubmit { browser.load(browser.addressText) }
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
        }
        .font(.title3)
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

#Preview {
    ContentView()
}
