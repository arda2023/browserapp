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

## Videowerbung (Teil des Werbeblockers)
`video_adblock.js` läuft als `WKUserScript` zu Dokumentbeginn in allen Frames:
1. **YouTube:** entfernt `adPlacements`, `playerAds`, `adSlots` aus den Player-Daten (`ytInitialPlayerResponse`,
   `JSON.parse`, `fetch().json()`), bevor der Player sie sieht → Pre-Roll wird gar nicht erst geladen.
2. **CSS:** versteckt Werbe-Overlays, Banner und während einer Werbung das Bild und die gelbe Fortschrittsleiste.
3. **Fallback auf allen Seiten** (YouTube, JW Player, Video.js/IMA, Fluid Player, Plyr, VAST …): Skip-Buttons werden sofort
   geklickt; nicht überspringbare Werbung wird stumm geschaltet, auf 16-fache Geschwindigkeit gesetzt und ans Ende gespult.
   Danach werden Ton und Geschwindigkeit des echten Videos wiederhergestellt.

Der Zähler am Hand-Button zeigt, wie viele Videowerbungen entfernt wurden.

## Tabs
Tab-Button unten (zeigt die Anzahl) → Übersicht im Opera-Stil mit Vorschaubild jeder Seite:
antippen zum Wechseln, ✕ zum Schließen, + für neuen Tab.
Offene Tabs (Adresse, Titel, Vorschaubild, aktiver Tab) werden gespeichert und beim nächsten Start wiederhergestellt.
Wiederhergestellte Tabs laden erst, wenn man sie öffnet.

## Favoriten
☆ neben der Adressleiste speichert die aktuelle Seite (★ = gespeichert, nochmal tippen entfernt sie).
Das Buch-Symbol unten öffnet die Liste: antippen öffnet die Seite, gedrückt halten → „In neuem Tab öffnen“,
„Umbenennen“, „Löschen“; „Bearbeiten“ zum Sortieren.
Webseiten selbst können weiterhin keine Tabs öffnen. Neu laden sitzt rechts neben der Adressleiste.

Startseite und Suchmaschine: Yandex.

## Auf dem iPhone installieren
1. `StreamBrowser.xcodeproj` in Xcode öffnen.
2. Target *StreamBrowser* → *Signing & Capabilities* → dein Team (Apple-ID) wählen.
   Falls die Bundle-ID schon vergeben ist, `com.arda2023.StreamBrowser` ändern.
3. iPhone per Kabel verbinden, als Ziel auswählen und ▶︎ drücken.
4. Auf dem iPhone: *Einstellungen → Allgemein → VPN & Geräteverwaltung* → Entwickler vertrauen.

Mit kostenloser Apple-ID läuft die App 7 Tage, danach einfach erneut aus Xcode installieren.
