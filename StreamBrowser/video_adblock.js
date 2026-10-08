// StreamBrowser – Video-Werbeblocker (iOS: WKUserScript, Android: UserScript).
// Läuft zu Dokumentbeginn in allen Frames.
//
// Stufe 1 (YouTube): Werbedaten aus den Player-Daten entfernen, bevor der Player sie sieht
//                     → die Werbung wird gar nicht erst geladen.
// Stufe 2 (überall):  Werbe-Oberflächen per CSS verstecken.
// Stufe 3 (überall):  Läuft trotzdem Werbung: Skip-Button sofort klicken, sonst Werbevideo
//                     stumm schalten, unsichtbar machen und ans Ende spulen.
(function () {
  'use strict';
  if (window.__sbVideoAdblock) return;
  window.__sbVideoAdblock = true;

  var host = location.hostname;
  var isYouTube = /(^|\.)(youtube\.com|youtube-nocookie\.com)$/.test(host);

  // Eine Werbung löst oft mehrere Treffer aus (Daten, Video, Button) → als eine zählen.
  var lastReport = 0;
  function report(kind) {
    var now = Date.now();
    if (now - lastReport < 2000) return;
    lastReport = now;
    try { window.webkit.messageHandlers.adSkipped.postMessage(kind); return; } catch (e) {}
    try { window.flutter_inappwebview.callHandler('adSkipped', kind); } catch (e) {}
  }

  // ---------------------------------------------------------------------------
  // Stufe 1: YouTube-Player-Daten bereinigen
  // ---------------------------------------------------------------------------
  if (isYouTube) {
    var AD_KEYS = ['adPlacements', 'adSlots', 'playerAds', 'adBreakHeartbeatParams'];

    var prune = function (data) {
      if (!data || typeof data !== 'object') return data;
      var removed = false;
      var targets = [data, data.playerResponse];
      for (var i = 0; i < targets.length; i++) {
        var t = targets[i];
        if (!t || typeof t !== 'object') continue;
        for (var k = 0; k < AD_KEYS.length; k++) {
          if (AD_KEYS[k] in t) {
            delete t[AD_KEYS[k]];
            removed = true;
          }
        }
      }
      if (removed) report('youtube-data');
      return data;
    };

    // Antworten von /youtubei/v1/player (Seitenwechsel ohne Neuladen)
    var nativeParse = JSON.parse;
    var patchedParse = function () { return prune(nativeParse.apply(this, arguments)); };
    patchedParse.toString = function () { return nativeParse.toString(); };
    JSON.parse = patchedParse;

    var nativeJson = Response.prototype.json;
    Response.prototype.json = function () { return nativeJson.apply(this, arguments).then(prune); };

    // Erster Seitenaufruf: Daten stecken in window.ytInitialPlayerResponse
    ['ytInitialPlayerResponse', 'playerResponse'].forEach(function (name) {
      var value;
      try {
        Object.defineProperty(window, name, {
          configurable: true,
          get: function () { return value; },
          set: function (v) { value = prune(v); }
        });
      } catch (e) {}
    });
  }

  // ---------------------------------------------------------------------------
  // Stufe 2: Werbe-Oberflächen verstecken
  // ---------------------------------------------------------------------------
  var css = [
    // YouTube: Overlays, Banner, Werbung im Feed (Desktop + Mobil)
    '.video-ads, .ytp-ad-module, .ytp-ad-overlay-container, .ytp-ad-image-overlay,',
    '.ytp-ad-player-overlay, .ytp-ad-player-overlay-layout, .ytp-ad-text, .ytp-ad-preview-container,',
    '#player-ads, #masthead-ad, ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer,',
    'ytd-promoted-sparkles-web-renderer, ytd-display-ad-renderer, ytd-banner-promo-renderer,',
    'ytd-player-legacy-desktop-watch-ads-renderer, ytd-companion-slot-renderer,',
    'ytm-promoted-sparkles-web-renderer, ytm-companion-ad-renderer, ytm-promoted-video-renderer,',
    'ad-slot-renderer, ytm-ad-slot-renderer, .ytwAdBadgeHost,',
    // Generische Werbe-Overlays in Playern
    '.vast-blocker, .ima-ad-container .ad-overlay',
    '{ display: none !important; }',
    // Während Werbung läuft: Bild und gelbe Werbe-Fortschrittsleiste unsichtbar
    '.ad-showing video, .ad-interrupting video, .jw-flag-ads video, .vjs-ad-playing video,',
    '.ad-showing .ytp-progress-bar-container, .ad-showing .ytp-chrome-bottom',
    '{ opacity: 0 !important; }'
  ].join('\n');

  function addStyle() {
    var root = document.head || document.documentElement;
    if (!root) return false;
    var style = document.createElement('style');
    style.textContent = css;
    root.appendChild(style);
    return true;
  }
  if (!addStyle()) document.addEventListener('DOMContentLoaded', addStyle, { once: true });

  // ---------------------------------------------------------------------------
  // Stufe 3: Laufende Werbung überspringen
  // ---------------------------------------------------------------------------

  // Container, die anzeigen, dass im Player gerade Werbung läuft
  var AD_CONTAINERS = [
    '.ad-showing', '.ad-interrupting',                 // YouTube
    '.jw-flag-ads', '.jw-flag-ads-vpaid',              // JW Player
    '.vjs-ad-playing', '.vjs-ad-loading',              // Video.js (contrib-ads / IMA)
    '.ima-ad-container', '[id^="ima-ad"]',             // Google IMA SDK
    '.fluid_ad_playing', '.fp-ad', '.plyr--ad',        // Fluid Player, Flowplayer, Plyr
    '.vast-container', '.vast-player', '.preroll-container', '#preroll'
  ].join(',');

  // Bekannte Skip-Buttons
  var SKIP_BUTTONS = [
    '.ytp-ad-skip-button', '.ytp-ad-skip-button-modern', '.ytp-skip-ad-button',
    '.ytp-ad-skip-button-slot button', '.videoAdUiSkipButton', '.ytp-ad-overlay-close-button',
    '.jw-skip.jw-skippable', '.vjs-ad-skip', '.vast-skip-button', '.skip_button_active',
    '.fluid_ad_skip', '.fp-ad-skip', '.ima-skip-button', '[class*="skip-ad"]', '[class*="skipAd"]',
    '[id*="skip-ad"]', '[id*="skipAd"]'
  ].join(',');

  // Text von Skip-Buttons ohne Countdown, z. B. „Skip Ad“, „Werbung überspringen“
  var SKIP_TEXT = /^\s*(skip|skip ad|skip ads|skip advertisement|überspringen|werbung überspringen|anzeige überspringen|anzeigen überspringen|passer|passer la publicité|saltar|saltar anuncio|salta|salta annuncio|пропустить|reklamı geç|geç)\s*[›»>▶︎▸]*\s*$/i;

  function isVisible(el) {
    var r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  }

  // Bereits geklickte Buttons nur einmal zählen
  var clickedOnce = typeof WeakSet === 'function' ? new WeakSet() : null;
  function press(el) {
    el.click();
    if (clickedOnce && clickedOnce.has(el)) return false;
    if (clickedOnce) clickedOnce.add(el);
    return true;
  }

  function clickSkipButtons() {
    var clicked = false;
    var buttons = document.querySelectorAll(SKIP_BUTTONS);
    for (var i = 0; i < buttons.length; i++) {
      var b = buttons[i];
      if (b.disabled || b.getAttribute('aria-disabled') === 'true') continue;
      if (/\d/.test(b.textContent || '') && !isYouTube) continue; // Countdown läuft noch
      if (press(b)) clicked = true;
    }

    // Text-Suche nur innerhalb von Playern, damit keine normalen Links getroffen werden
    var videos = document.querySelectorAll('video');
    for (var v = 0; v < videos.length; v++) {
      var player = videos[v].parentElement;
      for (var up = 0; up < 3 && player && player.parentElement; up++) player = player.parentElement;
      if (!player) continue;
      var candidates = player.querySelectorAll('button, a, div[role="button"], span[role="button"], div[class*="skip"], div[class*="Skip"]');
      for (var c = 0; c < candidates.length; c++) {
        var el = candidates[c];
        var text = el.textContent || '';
        if (text.length > 40 || !SKIP_TEXT.test(text) || !isVisible(el)) continue;
        if (press(el)) clicked = true;
      }
    }
    if (clicked) report('skip-button');
    return clicked;
  }

  function isAdVideo(video) {
    return !!(video.closest && video.closest(AD_CONTAINERS));
  }

  function fastForward(video) {
    if (!video.dataset.sbAd) {
      // Ursprünglichen Zustand merken – YouTube nutzt dasselbe <video> danach fürs eigentliche Video
      video.dataset.sbAd = '1';
      video.dataset.sbMuted = video.muted ? '1' : '0';
      video.dataset.sbRate = String(video.playbackRate || 1);
      report('video');
    }
    video.muted = true;
    try { video.playbackRate = 16; } catch (e) {}
    if (isFinite(video.duration) && video.duration > 0 && video.currentTime < video.duration - 0.3) {
      try { video.currentTime = video.duration - 0.1; } catch (e) {}
    }
  }

  function restore(video) {
    if (!video.dataset.sbAd) return;
    video.muted = video.dataset.sbMuted === '1';
    try { video.playbackRate = parseFloat(video.dataset.sbRate) || 1; } catch (e) {}
    delete video.dataset.sbAd;
    delete video.dataset.sbMuted;
    delete video.dataset.sbRate;
  }

  function check() {
    clickSkipButtons();
    var videos = document.querySelectorAll('video');
    for (var i = 0; i < videos.length; i++) {
      if (isAdVideo(videos[i])) fastForward(videos[i]); else restore(videos[i]);
    }
  }

  // Auf DOM-Änderungen reagieren (gebündelt), plus Sicherheitsnetz per Intervall
  var scheduled = false;
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(function () { scheduled = false; check(); }, 50);
  }

  function start() {
    new MutationObserver(schedule).observe(document.documentElement, {
      childList: true, subtree: true, attributes: true, attributeFilter: ['class']
    });
    // Medien-Events blubbern nicht, lassen sich aber in der Capture-Phase abfangen
    ['play', 'playing', 'loadedmetadata', 'durationchange'].forEach(function (type) {
      document.addEventListener(type, schedule, true);
    });
    setInterval(check, 500);
    check();
  }

  if (document.documentElement) start();
  else document.addEventListener('DOMContentLoaded', start, { once: true });
})();
