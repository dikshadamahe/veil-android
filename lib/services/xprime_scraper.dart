import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';

class XprimeScraper {
  const XprimeScraper();

  static const List<String> providers = <String>[
    'finger',
    'primebox',
    'king',
    'facile',
    'lighter',
    'fed',
    'eek',
  ];

  static const List<ScrapeSourceDefinition> sourceDefinitions =
      <ScrapeSourceDefinition>[
    ScrapeSourceDefinition(
      id: 'xprime:auto',
      name: 'Auto (XPrime)',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
    ScrapeSourceDefinition(
      id: 'xprime:finger',
      name: 'Finger (XPrime)',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
    ScrapeSourceDefinition(
      id: 'xprime:primebox',
      name: 'PrimeBox (XPrime)',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
    ScrapeSourceDefinition(
      id: 'xprime:king',
      name: 'King (XPrime)',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
    ScrapeSourceDefinition(
      id: 'xprime:facile',
      name: 'Facile (XPrime)',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
    ScrapeSourceDefinition(
      id: 'xprime:lighter',
      name: 'Lighter (XPrime)',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
    ScrapeSourceDefinition(
      id: 'xprime:fed',
      name: 'Fed (XPrime)',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
    ScrapeSourceDefinition(
      id: 'xprime:eek',
      name: 'Eek (XPrime)',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
  ];

  static const String autoSourceId = 'xprime:auto';

  static void _log(String message) {
    debugPrint('[XPrime] $message');
  }

  Future<StreamResult?> scrape({
    required BuildContext context,
    required String tmdbId,
    required String title,
    required int year,
    int? season,
    int? episode,
    String? provider,
  }) async {
    _log(
      'scrape start tmdbId=$tmdbId provider=${provider ?? 'auto'} '
      'season=${season ?? '-'} episode=${episode ?? '-'}',
    );
    final Completer<StreamResult?> completer = Completer<StreamResult?>();
    final String normalizedRequestedProvider =
        provider?.trim().toLowerCase() ?? '';
    final Set<String> seenPayloadKeys = <String>{};
    String lastObservedProvider =
        normalizedRequestedProvider.isNotEmpty
        ? normalizedRequestedProvider
        : 'finger';
    InAppWebViewController? webViewController;
    String? currentPageUrl;
    OverlayEntry? overlayEntry;
    bool closed = false;
    bool requestedProviderTriggered = false;

    Future<Map<String, String>> buildSessionHeaders(String playbackUrl) async {
      final Map<String, String> headers = <String, String>{
        'User-Agent': _xprimeUserAgent,
      };

      final String? referer = currentPageUrl;
      if (referer != null && referer.trim().isNotEmpty) {
        headers['Referer'] = referer;
        final Uri? refererUri = Uri.tryParse(referer);
        if (refererUri != null && refererUri.hasScheme && refererUri.host.isNotEmpty) {
          headers['Origin'] = refererUri.origin;
        }
      }

      final List<String> cookieSources = <String>{
        playbackUrl,
        if (currentPageUrl != null) currentPageUrl!,
        'https://xprime.stream/',
        'https://mznxiwqjdiq00239q.space/',
      }.toList(growable: false);

      final Map<String, String> cookieJar = <String, String>{};
      final CookieManager cookieManager = CookieManager.instance();
      for (final String source in cookieSources) {
        try {
          final List<dynamic> cookies = await cookieManager.getCookies(
            url: WebUri(source),
            webViewController: webViewController,
          );
          for (final dynamic cookie in cookies) {
            final String name = '${cookie.name ?? ''}'.trim();
            if (name.isEmpty) {
              continue;
            }
            cookieJar[name] = '${cookie.value ?? ''}';
          }
        } catch (_) {
          // Ignore cookie read failures per-host.
        }
      }

      if (cookieJar.isNotEmpty) {
        headers['Cookie'] = cookieJar.entries
            .map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}')
            .join('; ');
      }

      _log(
        'session headers built referer=${headers['Referer'] ?? '-'} '
        'cookieCount=${cookieJar.length}',
      );
      return headers;
    }

    Future<StreamResult> attachSessionHeaders(StreamResult result) async {
      final String? playbackUrl = result.stream.playbackUrl?.trim();
      if (playbackUrl == null || playbackUrl.isEmpty) {
        return result;
      }
      final Map<String, String> sessionHeaders = await buildSessionHeaders(
        playbackUrl,
      );
      if (sessionHeaders.isEmpty) {
        return result;
      }
      final Map<String, String> headers = <String, String>{
        ...result.stream.headers,
        ...sessionHeaders,
      };
      return StreamResult(
        sourceId: result.sourceId,
        sourceName: result.sourceName,
        embedId: result.embedId,
        embedName: result.embedName,
        stream: StreamPlayback(
          id: result.stream.id,
          type: result.stream.type,
          playlist: result.stream.playlist,
          proxiedPlaylist: result.stream.proxiedPlaylist,
          playbackUrl: result.stream.playbackUrl,
          playbackType: result.stream.playbackType,
          selectedQuality: result.stream.selectedQuality,
          qualities: result.stream.qualities,
          headers: headers,
          preferredHeaders: headers,
          captions: result.stream.captions,
          flags: result.stream.flags,
        ),
      );
    }

    Future<StreamResult> buildWorkerResultWithSession({
      required String provider,
      required String playbackUrl,
    }) async {
      final StreamResult base = _buildWorkerPlaybackResult(
        provider: provider,
        playbackUrl: playbackUrl,
      );
      return attachSessionHeaders(base);
    }

    Future<void> finish(StreamResult? result) async {
      if (closed) {
        return;
      }
      _log(
        'finish result=${result == null ? 'null' : result.sourceId} '
        'playback=${result?.stream.playbackUrl ?? '-'}',
      );
      closed = true;
      try {
        overlayEntry?.remove();
        overlayEntry = null;
      } catch (_) {
        // Best effort cleanup.
      }
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    Future<void> handlePayload(Map<String, dynamic> payload) async {
      final String providerName = '${payload['provider'] ?? ''}'.trim();
      if (providerName.isNotEmpty) {
        lastObservedProvider = providerName.toLowerCase();
      }
      final dynamic rawData = payload['data'];
      final String keys = rawData is Map
          ? rawData.keys.map((dynamic e) => '$e').join(',')
          : 'non-map';
      _log('payload provider=$providerName dataKeys=$keys');
      final StreamResult? builtResult = _buildStreamResult(
        requestedProvider: provider,
        payload: payload,
      );
      if (builtResult == null) {
        _log('payload discarded provider=$providerName');
        return;
      }
      final StreamResult result = await attachSessionHeaders(builtResult);
      final String key =
          '${result.sourceId}|${result.stream.playbackUrl}|${result.stream.selectedQuality}';
      if (!seenPayloadKeys.add(key)) {
        _log('duplicate payload ignored key=$key');
        return;
      }
      _log('payload accepted key=$key');
      unawaited(finish(result));
    }

    Future<void> maybeTriggerRequestedProvider(String? rawUrl) async {
      if (closed || requestedProviderTriggered || normalizedRequestedProvider.isEmpty) {
        return;
      }
      final String? currentProvider = _providerFromBackendUrl(rawUrl);
      if (currentProvider == null || currentProvider == normalizedRequestedProvider) {
        return;
      }
      lastObservedProvider = currentProvider;
      _log(
        'observed backend provider=$currentProvider while waiting for '
        '$normalizedRequestedProvider url=$rawUrl',
      );
      final String? explicitUrl =
          _replaceProviderInBackendUrl(rawUrl!, normalizedRequestedProvider);
      if (explicitUrl == null || explicitUrl == rawUrl) {
        _log('could not build explicit provider url from $rawUrl');
        return;
      }
      requestedProviderTriggered = true;
      _log('trigger explicit provider request url=$explicitUrl');
      try {
        await webViewController?.evaluateJavascript(
          source: _explicitProviderFetchScript(explicitUrl),
        );
      } catch (_) {
        _log('explicit provider request injection failed');
        requestedProviderTriggered = false;
      }
    }

    final OverlayState overlay = Overlay.of(context, rootOverlay: true);

    overlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return Positioned(
          right: 0,
          bottom: 0,
          width: 1,
          height: 1,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.01,
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(_watchUrl(tmdbId, season, episode)),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  javaScriptCanOpenWindowsAutomatically: true,
                  cacheEnabled: true,
                  clearCache: false,
                  domStorageEnabled: true,
                  thirdPartyCookiesEnabled: true,
                  transparentBackground: true,
                  disableContextMenu: true,
                  mediaPlaybackRequiresUserGesture: false,
                  useShouldInterceptAjaxRequest: true,
                  useShouldInterceptFetchRequest: true,
                  useShouldInterceptRequest: true,
                  useOnLoadResource: true,
                  userAgent: _xprimeUserAgent,
                ),
                initialUserScripts: UnmodifiableListView<UserScript>(
                  <UserScript>[
                    UserScript(
                      source: _xprimeHookScript,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ],
                ),
                onWebViewCreated: (InAppWebViewController controller) {
                  webViewController = controller;
                  _log('webview created');
                  controller.addJavaScriptHandler(
                    handlerName: _handlerName,
                    callback: (dynamic args) {
                      final List<dynamic> values = args is List
                          ? args
                          : const <dynamic>[];
                      if (values.isEmpty) {
                        return null;
                      }
                      final dynamic payload = values.first;
                      if (payload is! Map) {
                        _log('js handler received non-map payload');
                        return null;
                      }
                      unawaited(handlePayload(Map<String, dynamic>.from(payload)));
                      return null;
                    },
                  );
                },
                shouldInterceptAjaxRequest: (
                  InAppWebViewController controller,
                  AjaxRequest ajaxRequest,
                ) async {
                  final String? url = ajaxRequest.url?.toString();
                  final String? provider = _providerFromBackendUrl(url);
                  if (provider != null) {
                    lastObservedProvider = provider;
                  }
                  if (_isInterestingXprimeUrl(url)) {
                    _log('ajax request url=$url');
                  }
                  unawaited(
                    maybeTriggerRequestedProvider(url),
                  );
                  return ajaxRequest;
                },
                onAjaxReadyStateChange: (
                  InAppWebViewController controller,
                  AjaxRequest ajaxRequest,
                ) async {
                  if (ajaxRequest.readyState == AjaxRequestReadyState.DONE) {
                    final String? finalUrl =
                        ajaxRequest.responseURL?.toString() ??
                            ajaxRequest.url?.toString();
                    if (_isInterestingXprimeUrl(finalUrl)) {
                      _log(
                        'ajax done status=${ajaxRequest.status} url=$finalUrl '
                        'bodyLen=${ajaxRequest.responseText?.length ?? 0}',
                      );
                    }
                    final Map<String, dynamic>? payload =
                        _payloadFromNetworkResponse(
                      url: finalUrl,
                      status: ajaxRequest.status,
                      headers: ajaxRequest.responseHeaders,
                      bodyText: ajaxRequest.responseText,
                    );
                    if (payload != null) {
                      unawaited(handlePayload(payload));
                    }
                  }
                  return AjaxRequestAction.PROCEED;
                },
                shouldInterceptFetchRequest: (
                  InAppWebViewController controller,
                  FetchRequest fetchRequest,
                ) async {
                  final String? url = fetchRequest.url?.toString();
                  final String? provider = _providerFromBackendUrl(url);
                  if (provider != null) {
                    lastObservedProvider = provider;
                  }
                  if (_isInterestingXprimeUrl(url)) {
                    _log('fetch request url=$url');
                  }
                  unawaited(
                    maybeTriggerRequestedProvider(url),
                  );
                  return fetchRequest;
                },
                shouldInterceptRequest: (
                  InAppWebViewController controller,
                  WebResourceRequest request,
                ) async {
                  final String url = request.url.toString();
                  final String? provider = _providerFromBackendUrl(url);
                  if (provider != null) {
                    lastObservedProvider = provider;
                  }
                  if (_isFinalPlaybackWorkerUrl(url)) {
                    _log('worker playback captured provider=$lastObservedProvider');
                    unawaited(
                      buildWorkerResultWithSession(
                          provider: lastObservedProvider,
                          playbackUrl: url,
                        ).then(finish),
                    );
                  }
                  if (_isInterestingXprimeUrl(url)) {
                    _log('resource request url=$url');
                  }
                  unawaited(
                    maybeTriggerRequestedProvider(url),
                  );
                  return null;
                },
                onLoadStart: (
                  InAppWebViewController controller,
                  WebUri? url,
                ) {
                  currentPageUrl = url?.toString();
                  _log('load start url=${url?.toString() ?? '-'}');
                },
                onLoadStop: (
                  InAppWebViewController controller,
                  WebUri? url,
                ) {
                  currentPageUrl = url?.toString() ?? currentPageUrl;
                  _log('load stop url=${url?.toString() ?? '-'}');
                },
                onLoadResource: (
                  InAppWebViewController controller,
                  LoadedResource resource,
                ) {
                  final String url = resource.url.toString();
                  final String? provider = _providerFromBackendUrl(url);
                  if (provider != null) {
                    lastObservedProvider = provider;
                  }
                  if (_isFinalPlaybackWorkerUrl(url)) {
                    _log(
                      'worker playback resource captured provider=$lastObservedProvider',
                    );
                    unawaited(
                      buildWorkerResultWithSession(
                          provider: lastObservedProvider,
                          playbackUrl: url,
                        ).then(finish),
                    );
                  }
                  if (_isInterestingXprimeUrl(url)) {
                    _log('load resource url=$url');
                  }
                },
                onConsoleMessage: (
                  InAppWebViewController controller,
                  ConsoleMessage consoleMessage,
                ) {
                  final String msg = consoleMessage.message;
                  if (msg.contains('xprime') ||
                      msg.contains('turnstile') ||
                      msg.contains('backend.xprime.tv') ||
                      msg.contains('mznxiwqjdiq00239q.space') ||
                      msg.contains('db.xprime.stream')) {
                    _log('console ${consoleMessage.messageLevel}: $msg');
                  }
                },
                onReceivedError: (
                  InAppWebViewController controller,
                  WebResourceRequest request,
                  WebResourceError error,
                ) {
                  final String url = request.url.toString();
                  if (_isFinalPlaybackWorkerUrl(url)) {
                    _log(
                      'worker playback error-path captured provider=$lastObservedProvider',
                    );
                    unawaited(
                      buildWorkerResultWithSession(
                          provider: lastObservedProvider,
                          playbackUrl: url,
                        ).then(finish),
                    );
                    return;
                  }
                  _log(
                    'received error code=${error.type} '
                    'url=$url mainFrame=${request.isForMainFrame}',
                  );
                  if (request.isForMainFrame == true) {
                    unawaited(finish(null));
                  }
                },
                onReceivedHttpError: (
                  InAppWebViewController controller,
                  WebResourceRequest request,
                  WebResourceResponse errorResponse,
                ) {
                  _log(
                    'received http error status=${errorResponse.statusCode} '
                    'url=${request.url} mainFrame=${request.isForMainFrame}',
                  );
                  if (request.isForMainFrame == true) {
                    unawaited(finish(null));
                  }
                },
              ),
            ),
          ),
        );
      },
    );

    try {
      overlay.insert(overlayEntry!);
      _log('overlay inserted watchUrl=${_watchUrl(tmdbId, season, episode)}');
      return await completer.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          _log('timeout after 45s');
          unawaited(finish(null));
          return null;
        },
      );
    } finally {
      await finish(null);
    }
  }

  static String sourceIdForProvider(String? provider) {
    final String normalized = provider?.trim().toLowerCase() ?? '';
    return normalized.isEmpty ? autoSourceId : 'xprime:$normalized';
  }

  static String labelForProvider(String? provider) {
    switch (provider?.trim().toLowerCase()) {
      case 'finger':
        return 'Finger (XPrime)';
      case 'primebox':
        return 'PrimeBox (XPrime)';
      case 'king':
        return 'King (XPrime)';
      case 'facile':
        return 'Facile (XPrime)';
      case 'lighter':
        return 'Lighter (XPrime)';
      case 'fed':
        return 'Fed (XPrime)';
      case 'eek':
        return 'Eek (XPrime)';
      default:
        return 'Auto (XPrime)';
    }
  }

  static const String _handlerName = 'veilXprimeResult';
  static const String _xprimeUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static String _watchUrl(String tmdbId, int? season, int? episode) {
    if (season != null && episode != null) {
      return 'https://xprime.stream/watch/$tmdbId/$season/$episode';
    }
    return 'https://xprime.stream/watch/$tmdbId';
  }

  static bool _isInterestingXprimeUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) {
      return false;
    }
    final Uri? uri = Uri.tryParse(rawUrl);
    final String host = (uri?.host ?? '').toLowerCase();
    return host == 'backend.xprime.tv' ||
        host == 'db.xprime.stream' ||
        host == 'mznxiwqjdiq00239q.space' ||
        host == 'oca.lihala-n-tmurt.workers.dev' ||
        host.endsWith('.xprime.stream') ||
        host.endsWith('.website') ||
        host == 'xprime.stream';
  }

  static bool _isFinalPlaybackWorkerUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) {
      return false;
    }
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return false;
    }
    return uri.host.toLowerCase() == 'oca.lihala-n-tmurt.workers.dev' &&
        uri.queryParameters.containsKey('v');
  }

  static String get _xprimeHookScript {
    final String providersJson = jsonEncode(providers);
    return '''
(function() {
  if (window.__veilXprimeInstalled) {
    return;
  }
  window.__veilXprimeInstalled = true;
  const providers = new Set($providersJson);

  function silenceMediaElement(element) {
    try {
      element.muted = true;
      element.volume = 0;
      element.autoplay = false;
      element.setAttribute('muted', 'muted');
      element.playsInline = true;
      element.setAttribute('playsinline', 'playsinline');
    } catch (_) {}
  }

  function silenceAllMedia() {
    try {
      document.querySelectorAll('video, audio').forEach(silenceMediaElement);
    } catch (_) {}
  }

  silenceAllMedia();
  try {
    const observer = new MutationObserver(function() {
      silenceAllMedia();
    });
    observer.observe(document.documentElement || document, {
      childList: true,
      subtree: true
    });
  } catch (_) {}

  try {
    const originalPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function() {
      silenceMediaElement(this);
      return originalPlay.apply(this, arguments);
    };
  } catch (_) {}

  function inferProvider(value) {
    const text = String(value || '').toLowerCase().trim();
    if (!text) {
      return 'finger';
    }
    for (const provider of providers) {
      if (text === provider || text.startsWith(provider + ' ') || text.startsWith(provider + '>')) {
        return provider;
      }
    }
    return 'finger';
  }

  function normalize(url) {
    try {
      const parsed = new URL(url, window.location.href);
      if (parsed.hostname !== 'backend.xprime.tv' &&
          parsed.hostname !== 'mznxiwqjdiq00239q.space') {
        return null;
      }
      const parts = parsed.pathname.split('/').filter(Boolean);
      const provider = parts.length > 0 ? String(parts[0]).toLowerCase() : '';
      if (!providers.has(provider)) {
        return null;
      }
      return { provider, url: parsed.toString() };
    } catch (_) {
      return null;
    }
  }

  function sendPayload(payload) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('$_handlerName', payload);
      }
    } catch (_) {}
  }

  function parseHeaders(rawHeaders) {
    const headers = {};
    if (!rawHeaders) {
      return headers;
    }
    rawHeaders.trim().split(/[\\r\\n]+/).forEach(function(line) {
      const index = line.indexOf(':');
      if (index <= 0) {
        return;
      }
      const key = line.substring(0, index).trim().toLowerCase();
      const value = line.substring(index + 1).trim();
      headers[key] = value;
    });
    return headers;
  }

  function maybeReport(url, status, bodyText, headers) {
    const match = normalize(url);
    if (!match || !bodyText) {
      return;
    }
    let data = null;
    try {
      data = JSON.parse(bodyText);
    } catch (_) {
      return;
    }
    sendPayload({
      provider: match.provider,
      requestUrl: match.url,
      status: status || 0,
      headers: headers || {},
      data: data
    });
  }

  function maybeReportStreamReady(detail) {
    if (!detail || typeof detail !== 'object') {
      return;
    }
    const url = detail.url || detail.playbackUrl || detail.stream || detail.playlist;
    if (!url) {
      return;
    }
    sendPayload({
      provider: inferProvider(detail.serverName),
      requestUrl: detail.url || '',
      status: 200,
      headers: {},
      data: {
        url: detail.url,
        type: detail.type,
        subtitles: Array.isArray(detail.subtitles) ? detail.subtitles : [],
        qualityOptions: detail.qualityOptions || {},
        availableQualities: detail.availableQualities || [],
        availableServers: detail.availableServers || [],
        serverName: detail.serverName || ''
      }
    });
  }

  const originalFetch = window.fetch;
  if (typeof originalFetch === 'function') {
    window.fetch = async function(input, init) {
      const response = await originalFetch.apply(this, arguments);
      try {
        const responseUrl = response && response.url ? response.url : (input && input.url ? input.url : input);
        if (normalize(responseUrl)) {
          const clone = response.clone();
          const headers = {};
          try {
            clone.headers.forEach(function(value, key) {
              headers[key] = value;
            });
          } catch (_) {}
          clone.text().then(function(bodyText) {
            maybeReport(responseUrl, response.status, bodyText, headers);
          }).catch(function() {});
        }
      } catch (_) {}
      return response;
    };
  }

  const originalOpen = XMLHttpRequest.prototype.open;
  const originalSend = XMLHttpRequest.prototype.send;

  XMLHttpRequest.prototype.open = function(method, url) {
    this.__veilXprimeUrl = url;
    return originalOpen.apply(this, arguments);
  };

  XMLHttpRequest.prototype.send = function(body) {
    this.addEventListener('readystatechange', function() {
      if (this.readyState !== 4) {
        return;
      }
      const url = this.responseURL || this.__veilXprimeUrl;
      if (!normalize(url)) {
        return;
      }
      const responseText = typeof this.responseText === 'string' ? this.responseText : '';
      maybeReport(url, this.status, responseText, parseHeaders(this.getAllResponseHeaders()));
    });
    return originalSend.apply(this, arguments);
  };

  const originalDispatchEvent = EventTarget.prototype.dispatchEvent;
  EventTarget.prototype.dispatchEvent = function(event) {
    try {
      if (event && event.type === 'streamready') {
        maybeReportStreamReady(event.detail);
      }
    } catch (_) {}
    return originalDispatchEvent.apply(this, arguments);
  };

  window.addEventListener('streamready', function(event) {
    try {
      maybeReportStreamReady(event.detail);
    } catch (_) {}
  }, true);
})();
''';
  }

  static String _explicitProviderFetchScript(String url) {
    final String encodedUrl = jsonEncode(url);
    return '''
(function() {
  const url = $encodedUrl;
  try {
    if (window.fetch) {
      window.fetch(url, {
        credentials: 'omit',
        mode: 'cors',
        cache: 'force-cache',
        headers: {
          'accept': 'application/json, text/plain, */*'
        }
      }).catch(function() {});
    }
  } catch (_) {}

  try {
    const xhr = new XMLHttpRequest();
    xhr.open('GET', url, true);
    xhr.withCredentials = false;
    xhr.send();
  } catch (_) {}
})();
''';
  }

  static Map<String, dynamic>? _payloadFromNetworkResponse({
    required String? url,
    required int? status,
    required Map<String, dynamic>? headers,
    required String? bodyText,
  }) {
    final String? provider = _providerFromBackendUrl(url);
    if (provider == null) {
      return null;
    }
    final String raw = bodyText?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    return <String, dynamic>{
      'provider': provider,
      'requestUrl': url,
      'status': status ?? 0,
      'headers': headers ?? const <String, dynamic>{},
      'data': Map<String, dynamic>.from(decoded),
    };
  }

  static String? _providerFromBackendUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return null;
    }
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return null;
    }
    final String host = uri.host.toLowerCase();
    if (host != 'backend.xprime.tv' &&
        host != 'mznxiwqjdiq00239q.space') {
      return null;
    }
    if (uri.pathSegments.isEmpty) {
      return null;
    }
    final String provider = uri.pathSegments.first.trim().toLowerCase();
    return providers.contains(provider) ? provider : null;
  }

  static String? _replaceProviderInBackendUrl(String rawUrl, String provider) {
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.pathSegments.isEmpty) {
      return null;
    }
    final List<String> segments = List<String>.from(uri.pathSegments);
    segments[0] = provider;
    return uri.replace(pathSegments: segments).toString();
  }

  static StreamResult? _buildStreamResult({
    required String? requestedProvider,
    required Map<String, dynamic> payload,
  }) {
    final String provider = '${payload['provider'] ?? ''}'.trim().toLowerCase();
    if (provider.isEmpty) {
      return null;
    }

    final String normalizedRequested =
        requestedProvider?.trim().toLowerCase() ?? '';
    if (normalizedRequested.isNotEmpty && provider != normalizedRequested) {
      return null;
    }

    final dynamic rawData = payload['data'];
    if (rawData is! Map) {
      return null;
    }
    final Map<String, dynamic> data = Map<String, dynamic>.from(rawData);

    final List<String> availableQualityOrder = _readQualityOrder(
      data['availableQualities'] ?? data['available_qualities'],
    );
    final Map<String, StreamQuality> qualities = _readQualities(
      data['qualities'] ?? data['qualityOptions'] ?? data['streams'],
      availableQualities: availableQualityOrder,
    );
    final String? selectedQuality = _pickBestQualityKey(
      qualities,
      preferredOrder: availableQualityOrder,
    );
    final String? qualityUrl = selectedQuality == null
        ? null
        : qualities[selectedQuality]?.url;
    final String? primaryUrl = _readPrimaryUrl(data, qualities: qualities);
    final String? chosenUrl =
        qualityUrl ??
        primaryUrl ??
        _pickBestQualityUrl(qualities);
    if (chosenUrl == null || chosenUrl.isEmpty) {
      return null;
    }

    final String streamType =
        qualities[selectedQuality]?.type ??
        _nullableString(data['type']) ??
        _inferStreamType(chosenUrl);
    _log(
      'choose stream provider=$provider selectedQuality=${selectedQuality ?? '-'} '
      'type=$streamType qualities=${qualities.keys.join('|')} '
      'captions=${_readCaptions(data['subtitles']).length} url=$chosenUrl',
    );

    return StreamResult(
      sourceId: sourceIdForProvider(provider),
      sourceName: labelForProvider(provider),
      embedId: null,
      embedName: null,
      stream: StreamPlayback(
        id: 'xprime-$provider',
        type: streamType,
        playlist: streamType == 'hls' ? chosenUrl : null,
        proxiedPlaylist: null,
        playbackUrl: chosenUrl,
        playbackType: streamType,
        selectedQuality: selectedQuality,
        qualities: qualities,
        headers: const <String, String>{},
        preferredHeaders: const <String, String>{},
        captions: _readCaptions(data['subtitles']),
        flags: const <String>[],
      ),
    );
  }

  static StreamResult _buildWorkerPlaybackResult({
    required String provider,
    required String playbackUrl,
  }) {
    return StreamResult(
      sourceId: sourceIdForProvider(provider),
      sourceName: labelForProvider(provider),
      embedId: null,
      embedName: null,
      stream: StreamPlayback(
        id: 'xprime-$provider-worker',
        type: 'hls',
        playlist: playbackUrl,
        proxiedPlaylist: null,
        playbackUrl: playbackUrl,
        playbackType: 'hls',
        selectedQuality: null,
        qualities: const <String, StreamQuality>{},
        headers: const <String, String>{},
        preferredHeaders: const <String, String>{},
        captions: const <StreamCaption>[],
        flags: const <String>[],
      ),
    );
  }

  static String? _readPrimaryUrl(
    Map<String, dynamic> data, {
    Map<String, StreamQuality> qualities = const <String, StreamQuality>{},
  }) {
    for (final dynamic candidate in <dynamic>[
      data['url'],
      data['stream'],
      data['playlist'],
      data['playbackUrl'],
    ]) {
      final String text = '$candidate'.trim();
      if (text.isNotEmpty && text != 'null') {
        return text;
      }
    }
    final dynamic streams = data['streams'];
    if (streams is List) {
      for (final dynamic entry in streams) {
        if (entry is Map) {
          final String? url = _nullableString(
            entry['url'] ?? entry['file'] ?? entry['src'] ?? entry['stream'],
          );
          if (url != null) {
            return url;
          }
        } else {
          final String? url = _nullableString(entry);
          if (url != null) {
            return url;
          }
        }
      }
    }
    return _pickBestQualityUrl(qualities);
  }

  static List<String> _readQualityOrder(dynamic raw) {
    if (raw is! List) {
      return const <String>[];
    }
    final List<String> order = <String>[];
    for (final dynamic entry in raw) {
      final String? value = _nullableString(entry);
      if (value != null) {
        order.add(value);
      }
    }
    return order;
  }

  static Map<String, StreamQuality> _readQualities(
    dynamic raw, {
    List<String> availableQualities = const <String>[],
  }) {
    final Map<String, StreamQuality> qualities = <String, StreamQuality>{};

    void addQuality(String key, dynamic urlValue, {dynamic type}) {
      final String qualityKey = key.trim();
      final String? url = _nullableString(urlValue);
      if (qualityKey.isEmpty || url == null) {
        return;
      }
      qualities[qualityKey] = StreamQuality(
        url: url,
        type: _nullableString(type) ?? _inferStreamType(url),
      );
    }

    if (raw is Map) {
      raw.forEach((dynamic key, dynamic value) {
        final String qualityKey = '$key'.trim();
        if (qualityKey.isEmpty) {
          return;
        }

        if (value is Map) {
          addQuality(
            qualityKey,
            value['url'] ?? value['file'] ?? value['src'] ?? value['stream'],
            type: value['type'],
          );
          return;
        }

        addQuality(qualityKey, value);
      });
      return _normalizeQualityMap(
        qualities,
        preferredOrder: availableQualities,
      );
    }

    if (raw is List) {
      int index = 0;
      for (final dynamic entry in raw) {
        if (entry is Map) {
          final String key =
              _nullableString(
                entry['quality'] ??
                    entry['label'] ??
                    entry['name'] ??
                    entry['resolution'] ??
                    entry['height'],
              ) ??
              (index < availableQualities.length
                  ? availableQualities[index]
                  : 'q$index');
          addQuality(
            key,
            entry['url'] ?? entry['file'] ?? entry['src'] ?? entry['stream'],
            type: entry['type'],
          );
        } else {
          final String key = index < availableQualities.length
              ? availableQualities[index]
              : 'q$index';
          addQuality(key, entry);
        }
        index += 1;
      }
    }

    return _normalizeQualityMap(
      qualities,
      preferredOrder: availableQualities,
    );
  }

  static List<StreamCaption> _readCaptions(dynamic raw) {
    if (raw == null) {
      return const <StreamCaption>[];
    }

    final List<StreamCaption> captions = <StreamCaption>[];

    void addCaptionFromMap(Map<String, dynamic> map, {String? fallbackLabel}) {
      final String? url = _nullableString(
        map['url'] ??
            map['file'] ??
            map['src'] ??
            map['link'] ??
            map['path'] ??
            map['subtitle'] ??
            map['caption'],
      );
      final String? fallbackUrl = url ?? _findUrlLikeValue(map);
      if (fallbackUrl == null) {
        return;
      }
      final String? label = _nullableString(
        map['label'] ??
            map['display'] ??
            map['name'] ??
            map['title'] ??
            fallbackLabel,
      );
      final String? language = _nullableString(
        map['language'] ?? map['lang'] ?? map['locale'] ?? label,
      );
      captions.add(
        StreamCaption(
          url: fallbackUrl,
          language: language,
          type: _nullableString(map['type']) ?? _inferCaptionType(fallbackUrl),
          label: label,
          raw: map,
        ),
      );
    }

    void addCaptionFromScalar(dynamic entry, {String? fallbackLabel}) {
      final String? url = _nullableString(entry);
      if (url == null) {
        return;
      }
      captions.add(
        StreamCaption(
          url: url,
          language: fallbackLabel,
          type: _inferCaptionType(url),
          label: fallbackLabel,
          raw: <String, dynamic>{
            'url': url,
            'label': fallbackLabel,
          },
        ),
      );
    }

    if (raw is Map) {
      final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
      for (final MapEntry<String, dynamic> entry in map.entries) {
        final String key = entry.key.trim();
        final dynamic value = entry.value;
        if (value is List) {
          for (final dynamic item in value) {
            if (item is Map) {
              addCaptionFromMap(
                Map<String, dynamic>.from(item),
                fallbackLabel: key,
              );
            } else {
              addCaptionFromScalar(item, fallbackLabel: key);
            }
          }
          continue;
        }
        if (value is Map) {
          addCaptionFromMap(Map<String, dynamic>.from(value), fallbackLabel: key);
          continue;
        }
        addCaptionFromScalar(value, fallbackLabel: key);
      }
      return _dedupeCaptions(captions);
    }

    if (raw is! List) {
      return const <StreamCaption>[];
    }

    for (final dynamic entry in raw) {
      if (entry is Map) {
        addCaptionFromMap(Map<String, dynamic>.from(entry));
        continue;
      }
      addCaptionFromScalar(entry);
    }

    return _dedupeCaptions(captions);
  }

  static List<StreamCaption> _dedupeCaptions(List<StreamCaption> captions) {
    final Map<String, StreamCaption> unique = <String, StreamCaption>{};
    for (final StreamCaption caption in captions) {
      final String? url = caption.url?.trim();
      if (url == null || url.isEmpty) {
        continue;
      }
      unique.putIfAbsent(url, () => caption);
    }
    return unique.values.toList(growable: false);
  }

  static String? _findUrlLikeValue(Map<String, dynamic> map) {
    for (final dynamic value in map.values) {
      final String? text = _nullableString(value);
      if (text == null) {
        continue;
      }
      final String lower = text.toLowerCase();
      if (lower.startsWith('http://') ||
          lower.startsWith('https://') ||
          lower.contains('.vtt') ||
          lower.contains('.srt')) {
        return text;
      }
    }
    return null;
  }

  static String _inferCaptionType(String url) {
    final String lower = url.toLowerCase();
    if (lower.contains('.srt')) {
      return 'srt';
    }
    if (lower.contains('.ass') || lower.contains('.ssa')) {
      return 'ass';
    }
    return 'vtt';
  }

  static Map<String, StreamQuality> _normalizeQualityMap(
    Map<String, StreamQuality> qualities, {
    List<String> preferredOrder = const <String>[],
  }) {
    if (qualities.length <= 1 || _hasDescriptiveQualityLabels(qualities.keys)) {
      return qualities;
    }

    final List<MapEntry<String, StreamQuality>> ordered = qualities.entries
        .where((MapEntry<String, StreamQuality> entry) {
          return entry.value.url?.trim().isNotEmpty == true;
        })
        .toList(growable: false);
    if (ordered.length <= 1) {
      return qualities;
    }

    if (preferredOrder.isNotEmpty) {
      final Map<String, int> rank = <String, int>{};
      for (int i = 0; i < preferredOrder.length; i += 1) {
        rank[preferredOrder[i].trim().toLowerCase()] = i;
      }
      ordered.sort((MapEntry<String, StreamQuality> a,
          MapEntry<String, StreamQuality> b) {
        final int aRank = rank[a.key.trim().toLowerCase()] ?? -1;
        final int bRank = rank[b.key.trim().toLowerCase()] ?? -1;
        return aRank.compareTo(bRank);
      });
    }

    final List<String> labels = _syntheticQualityLabels(ordered.length);
    final Map<String, StreamQuality> normalized = <String, StreamQuality>{};
    for (int i = 0; i < ordered.length; i += 1) {
      normalized[labels[i]] = ordered[i].value;
    }
    return normalized;
  }

  static bool _hasDescriptiveQualityLabels(Iterable<String> keys) {
    for (final String rawKey in keys) {
      final String key = rawKey.trim().toLowerCase();
      if (RegExp(r'\b(240|360|480|540|720|1080|1440|2160)p\b').hasMatch(key) ||
          key.contains('4k') ||
          key.contains('uhd') ||
          key.contains('fhd') ||
          key.contains('hd')) {
        return true;
      }
    }
    return false;
  }

  static List<String> _syntheticQualityLabels(int count) {
    const List<String> full = <String>[
      '240p',
      '360p',
      '480p',
      '720p',
      '1080p',
      '1440p',
      '2160p',
    ];
    if (count <= 0) {
      return const <String>[];
    }
    if (count >= full.length) {
      final List<String> expanded = List<String>.from(full);
      for (int i = full.length; i < count; i += 1) {
        expanded.add('Q${i + 1}');
      }
      return expanded;
    }
    return full.sublist(full.length - count);
  }

  static String? _pickBestQualityUrl(Map<String, StreamQuality> qualities) {
    final String? key = _pickBestQualityKey(qualities);
    return key == null ? null : qualities[key]?.url;
  }

  static String? _pickBestQualityKey(
    Map<String, StreamQuality> qualities, {
    List<String> preferredOrder = const <String>[],
  }) {
    final List<MapEntry<String, StreamQuality>> entries = qualities.entries
        .where((MapEntry<String, StreamQuality> entry) {
      return entry.value.url?.trim().isNotEmpty == true;
    }).toList();
    if (entries.isEmpty) {
      return null;
    }
    if (preferredOrder.isNotEmpty) {
      final Map<String, int> orderRank = <String, int>{};
      for (int i = 0; i < preferredOrder.length; i += 1) {
        orderRank[preferredOrder[i].trim().toLowerCase()] = i;
      }
      entries.sort((MapEntry<String, StreamQuality> a,
          MapEntry<String, StreamQuality> b) {
        final int? aRank = orderRank[a.key.trim().toLowerCase()];
        final int? bRank = orderRank[b.key.trim().toLowerCase()];
        if (aRank != null && bRank != null) {
          return bRank.compareTo(aRank);
        }
        if (aRank != null) {
          return 1;
        }
        if (bRank != null) {
          return -1;
        }
        return _qualityRank(b.key).compareTo(_qualityRank(a.key));
      });
      return entries.first.key;
    }
    entries.sort((MapEntry<String, StreamQuality> a,
        MapEntry<String, StreamQuality> b) {
      return _qualityRank(b.key).compareTo(_qualityRank(a.key));
    });
    return entries.first.key;
  }

  static int _qualityRank(String key) {
    final RegExpMatch? match = RegExp(r'(\d{3,4})').firstMatch(key);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  static String _inferStreamType(String url) {
    return url.toLowerCase().contains('.m3u8') ? 'hls' : 'file';
  }

  static String? _nullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    final String text = '$value'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }
}
