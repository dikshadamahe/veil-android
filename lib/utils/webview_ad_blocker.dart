import 'dart:collection';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Lightweight WebView ad / click-out protection for embed players.
///
/// Android WebView cannot run uBlock Origin. This approximates the bits that
/// matter for sports / XPass embeds:
/// - block known ad / betting network requests ([contentBlockers])
/// - refuse `window.open` / `target=_blank` popups ([onCreateWindow] → false)
/// - keep the main frame on the original embed host ([shouldAllowNavigation])
/// - neuter `window.open` early via [antiPopupUserScripts]
class WebViewAdBlocker {
  WebViewAdBlocker._();

  /// Host/path substrings that serve ads, trackers, or betting click-outs.
  ///
  /// Matched against the full lower-cased URL (not just the host).
  static const List<String> blockedUrlFragments = <String>[
    // Betting / affiliate overlays common on sports embeds
    'parimatch',
    'pari-match',
    '1xbet',
    '1xbetting',
    'melbet',
    'mostbet',
    'linebet',
    'bet365',
    'stake.com',
    'stake.bet',
    'bc.game',
    'roobet',
    'cloudbet',
    'ggbet',
    'vbet',
    'favbet',
    'marathonbet',
    'betway',
    'bwin.',
    // Ad networks / popunder infra
    'doubleclick.net',
    'googlesyndication',
    'googleadservices',
    'adservice.google',
    'pagead2.googlesyndication',
    'adsystem',
    'adnxs.com',
    'adsrvr.org',
    'adform.net',
    'advertising.com',
    'propellerads',
    'propellerclick',
    'popads',
    'popcash',
    'adsterra',
    'clickadu',
    'hilltopads',
    'exoclick',
    'juicyads',
    'trafficjunky',
    'tsyndicate',
    'mgid.com',
    'outbrain.com',
    'taboola.com',
    'revcontent',
    'ad-delivery',
    'popunder',
    'pop-under',
    'onclickads',
    'onclickmega',
  ];

  static const String _hideAdsCss = '''
a[href*="parimatch" i],
a[href*="1xbet" i],
a[href*="melbet" i],
a[href*="mostbet" i],
a[href*="bet365" i],
iframe[src*="parimatch" i],
iframe[src*="1xbet" i],
iframe[src*="doubleclick" i],
iframe[src*="googlesyndication" i],
[id*="ad-container" i],
[id*="adsbox" i],
[class*="ad-banner" i],
[class*="adsbox" i] {
  display: none !important;
  pointer-events: none !important;
  visibility: hidden !important;
  width: 0 !important;
  height: 0 !important;
}
''';

  /// Document-start script: kill popups and strip `target=_blank` on ad links.
  static const String antiPopupJs = r'''
(function () {
  if (window.__pstreamAntiPopup) { return; }
  window.__pstreamAntiPopup = true;

  try {
    window.open = function () { return null; };
  } catch (e) {}

  document.addEventListener('click', function (e) {
    try {
      var el = e.target;
      while (el && el.tagName !== 'A') { el = el.parentElement; }
      if (!el || !el.href) { return; }
      var href = String(el.href).toLowerCase();
      var bad = [
        'parimatch', '1xbet', 'melbet', 'mostbet', 'bet365', 'stake.',
        'doubleclick', 'googlesyndication', 'popunder', 'clickadu'
      ];
      for (var i = 0; i < bad.length; i++) {
        if (href.indexOf(bad[i]) !== -1) {
          e.preventDefault();
          e.stopPropagation();
          return false;
        }
      }
      if (el.target === '_blank') {
        el.removeAttribute('target');
      }
    } catch (err) {}
  }, true);
})();
''';

  static String get _hideAdsJs {
    final String cssLiteral = _hideAdsCss
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', r'\n');
    return '''
(function () {
  if (window.__pstreamHideAdsCss) { return; }
  window.__pstreamHideAdsCss = true;
  var style = document.createElement('style');
  style.type = 'text/css';
  style.appendChild(document.createTextNode('$cssLiteral'));
  (document.head || document.documentElement).appendChild(style);
})();
''';
  }

  /// Document-start script that strips `sandbox` from player iframes and keeps
  /// it stripped. Many streamed embeds ship their `<iframe sandbox="...">`
  /// with `allow-scripts` withheld, which blocks the actual player from
  /// running. This mirrors the old GeckoView `veil_embed_guard` WebExtension so
  /// embeds play under a plain Android WebView. Uses `var`/index loops to stay
  /// safe on the widest range of WebView JS engines.
  static const String sandboxStripJs = r'''
(function () {
  if (window.__veilSandboxStrip) { return; }
  window.__veilSandboxStrip = true;

  function strip(frame) {
    try {
      if (!frame || frame.tagName !== 'IFRAME' ||
          !frame.hasAttribute('sandbox')) { return; }
      frame.removeAttribute('sandbox');
      var src = frame.getAttribute('src');
      if (src) { frame.setAttribute('src', src); }
    } catch (e) {}
  }

  var nativeSetAttribute = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function (name, value) {
    if (this && this.tagName === 'IFRAME' &&
        String(name).toLowerCase() === 'sandbox') { return; }
    return nativeSetAttribute.call(this, name, value);
  };

  function sweep(root) {
    try {
      var frames = (root || document).querySelectorAll('iframe[sandbox]');
      for (var i = 0; i < frames.length; i++) { strip(frames[i]); }
    } catch (e) {}
  }

  var observer = new MutationObserver(function (mutations) {
    for (var m = 0; m < mutations.length; m++) {
      var mutation = mutations[m];
      if (mutation.type === 'attributes' &&
          mutation.attributeName === 'sandbox') {
        strip(mutation.target);
        continue;
      }
      for (var n = 0; n < mutation.addedNodes.length; n++) {
        var node = mutation.addedNodes[n];
        if (node && node.nodeType === 1) {
          if (node.tagName === 'IFRAME') { strip(node); }
          if (node.querySelectorAll) { sweep(node); }
        }
      }
    }
  });

  function start() {
    sweep(document);
    observer.observe(document.documentElement || document, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['sandbox']
    });
  }

  if (document.documentElement) { start(); }
  else { document.addEventListener('readystatechange', start, { once: true }); }
})();
''';

  static UserScript get _antiPopupUserScript => UserScript(
        source: antiPopupJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      );

  static UserScript get _hideAdsUserScript => UserScript(
        source: _hideAdsJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      );

  static UserScript get _sandboxStripUserScript => UserScript(
        source: sandboxStripJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      );

  /// Anti-popup + ad-hiding scripts (used by the XPass embed player).
  static final UnmodifiableListView<UserScript> antiPopupUserScripts =
      UnmodifiableListView<UserScript>(<UserScript>[
    _antiPopupUserScript,
    _hideAdsUserScript,
  ]);

  /// Full guard for third-party sports embeds: anti-popup + ad-hiding **plus**
  /// iframe-sandbox stripping so the embedded player is allowed to run.
  static final UnmodifiableListView<UserScript> embedUserScripts =
      UnmodifiableListView<UserScript>(<UserScript>[
    _antiPopupUserScript,
    _hideAdsUserScript,
    _sandboxStripUserScript,
  ]);

  /// Content blockers for [InAppWebViewSettings.contentBlockers].
  static List<ContentBlocker> get contentBlockers {
    return blockedUrlFragments
        .map(
          (String fragment) => ContentBlocker(
            trigger: ContentBlockerTrigger(
              urlFilter: _toUrlFilter(fragment),
            ),
            action: ContentBlockerAction(
              type: ContentBlockerActionType.BLOCK,
            ),
          ),
        )
        .toList(growable: false);
  }

  /// Settings that make popup interception reliable on Android WebView.
  static InAppWebViewSettings embedSettings({
    String? userAgent,
    bool transparentBackground = true,
  }) {
    return InAppWebViewSettings(
      userAgent: userAgent,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      iframeAllowFullscreen: true,
      javaScriptEnabled: true,
      // Must be true so `onCreateWindow` fires; we still refuse every window.
      javaScriptCanOpenWindowsAutomatically: true,
      supportMultipleWindows: true,
      // Required on Android for [shouldOverrideUrlLoading] to run.
      useShouldOverrideUrlLoading: true,
      supportZoom: false,
      transparentBackground: transparentBackground,
      contentBlockers: contentBlockers,
    );
  }

  /// Returns true when [url] matches a known ad / betting fragment.
  static bool isBlockedUrl(Uri? url) {
    if (url == null) {
      return false;
    }
    final String haystack = url.toString().toLowerCase();
    for (final String fragment in blockedUrlFragments) {
      if (haystack.contains(fragment.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  /// Allow the initial embed load and same-host navigations; block ad hosts
  /// and main-frame click-outs to unrelated sites.
  static NavigationActionPolicy shouldAllowNavigation({
    required NavigationAction action,
    required Uri embedOrigin,
  }) {
    final Uri? requestUrl = action.request.url?.uriValue;
    if (requestUrl == null) {
      return NavigationActionPolicy.ALLOW;
    }

    if (isBlockedUrl(requestUrl)) {
      return NavigationActionPolicy.CANCEL;
    }

    // Subframe / iframe loads: only cancel known ad URLs (handled above).
    if (!action.isForMainFrame) {
      return NavigationActionPolicy.ALLOW;
    }

    // Main frame: stay on the embed host (allow http↔https and path changes).
    final String requestHost = requestUrl.host.toLowerCase();
    final String embedHost = embedOrigin.host.toLowerCase();
    if (requestHost.isEmpty || embedHost.isEmpty) {
      return NavigationActionPolicy.ALLOW;
    }
    if (requestHost == embedHost ||
        requestHost.endsWith('.$embedHost') ||
        embedHost.endsWith('.$requestHost')) {
      return NavigationActionPolicy.ALLOW;
    }

    // Typical ad click-out: leave embed.st → parimatch / random landing page.
    return NavigationActionPolicy.CANCEL;
  }

  /// Always refuse popup / new-tab windows from embed pages.
  static Future<bool> refuseCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction action,
  ) async {
    return false;
  }

  static String _toUrlFilter(String fragment) {
    final String escaped = RegExp.escape(fragment);
    return '.*$escaped.*';
  }
}
