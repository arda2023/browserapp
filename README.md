# StreamBrowser

Minimaler iOS-Browser (Swift / SwiftUI / WKWebView) zum Video-Streamen.

## Kernfunktion: Pop-up-/Tab-Blocker
Viele Streaming-Seiten öffnen beim Klick auf „Play“ Werbe-Tabs oder leiten den
aktuellen Tab auf Werbung um. Mit dem Schild-Button (an/aus) wird das verhindert:

- Neue Fenster/Tabs (`window.open`, `target="_blank"`) werden komplett verworfen – du bleibst im aktuellen Tab.
- Automatische Weiterleitungen des Haupt-Tabs auf fremde Domains (ohne dass du einen Link antippst) werden blockiert.
- Ist der Blocker aus, werden neue Tabs stattdessen im aktuellen Tab geöffnet (es gibt nur einen Tab).

Ein Zähler zeigt, wie viele Pop-ups blockiert wurden.
