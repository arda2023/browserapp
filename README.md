# StreamBrowser

Minimaler iOS-Browser (Swift / SwiftUI / WKWebView) zum Video-Streamen.

## Kernfunktion: Pop-up-/Tab-Blocker
Viele Streaming-Seiten öffnen beim Klick auf „Play“ Werbe-Tabs oder leiten den
aktuellen Tab auf Werbung um. Mit dem Schild-Button (an/aus) wird das verhindert:

- Neue Fenster/Tabs (`window.open`, `target="_blank"`) werden komplett verworfen – du bleibst im aktuellen Tab.
- Automatische Weiterleitungen des Haupt-Tabs auf fremde Domains (ohne dass du einen Link antippst) werden blockiert.
- Ist der Blocker aus, werden neue Tabs stattdessen im aktuellen Tab geöffnet (es gibt nur einen Tab).

Ein Zähler zeigt, wie viele Pop-ups blockiert wurden.

## Werbeblocker (Hand-Button)
Echte Filterlisten wie bei Brave/Opera:

- `AdBlockManager` lädt **EasyList**, wandelt sie mit AdGuards
  [ContentBlockerConverter](https://github.com/AdguardTeam/SafariConverterLib) (Swift Package, ab 4.3.0)
  in Safari-Regeln um und kompiliert sie zu einer `WKContentRuleList`.
- Die kompilierte Liste wird über `WKContentRuleListStore` dauerhaft gespeichert – beim Start nur nachgeschlagen,
  nicht neu kompiliert. Aktualisiert wird alle 3 Tage (oder per langem Druck auf den Hand-Button).
- Beim allerersten Start (oder offline) gilt sofort die mitgelieferte Liste `adblock_domains.json`.
- Blockiert Werbe-Server **und** blendet Werbe-Elemente per CSS aus.

## Tabs
Tab-Button unten (zeigt die Anzahl) → Übersicht: antippen zum Wechseln, ✕ oder Wischen zum Schließen, + für neuen Tab.
Webseiten selbst können weiterhin keine Tabs öffnen. Neu laden sitzt rechts neben der Adressleiste.

Startseite und Suchmaschine: Yandex.

## Auf dem iPhone installieren
1. `StreamBrowser.xcodeproj` in Xcode öffnen.
2. Target *StreamBrowser* → *Signing & Capabilities* → dein Team (Apple-ID) wählen.
   Falls die Bundle-ID schon vergeben ist, `com.arda2023.StreamBrowser` ändern.
3. iPhone per Kabel verbinden, als Ziel auswählen und ▶︎ drücken.
4. Auf dem iPhone: *Einstellungen → Allgemein → VPN & Geräteverwaltung* → Entwickler vertrauen.

Mit kostenloser Apple-ID läuft die App 7 Tage, danach einfach erneut aus Xcode installieren.
