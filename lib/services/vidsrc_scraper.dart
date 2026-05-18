import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';

class VidsrcScraper {
  const VidsrcScraper();

  static const List<ScrapeSourceDefinition> sourceDefinitions =
      <ScrapeSourceDefinition>[
    ScrapeSourceDefinition(
      id: 'vidsrc-client',
      name: 'Vidsrc',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
  ];

  static const String _handlerName = 'veilVidsrcResult';
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static void _log(String message) {
    debugPrint('[Vidsrc] $message');
  }

  static String _embedUrl(String tmdbId, int? season, int? episode) {
    if (season != null && episode != null) {
      return 'https://vidsrcme.ru/embed/tv?tmdb=$tmdbId&season=$season&episode=$episode';
    }
    return 'https://vidsrcme.ru/embed/movie?tmdb=$tmdbId';
  }

  Future<StreamResult?> scrape({
    required BuildContext context,
    required String tmdbId,
    required String title,
    required int year,
    int? season,
    int? episode,
  }) async {
    _log('scrape start tmdbId=$tmdbId season=$season episode=$episode');

    final Completer<StreamResult?> completer = Completer<StreamResult?>();
    OverlayEntry? overlayEntry;
    bool closed = false;
    final Set<String> seenUrls = <String>{};

    Future<void> finish(StreamResult? result) async {
      if (closed) return;
      closed = true;
      _log('finish result=${result == null ? 'null' : result.sourceId} '
          'playback=${result?.stream.playbackUrl ?? '-'}');
      try {
        overlayEntry?.remove();
        overlayEntry = null;
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.complete(result);
      }
    }

    void tryStreamUrl(String url, {String? referer}) {
      if (closed) return;
      if (!_isMediaUrl(url)) return;
      if (!seenUrls.add(url)) return;

      _log('stream found: $url');

      final Map<String, String> headers = <String, String>{
        'User-Agent': _userAgent,
      };
      if (referer != null && referer.isNotEmpty) {
        headers['Referer'] = referer;
        try {
          final Uri refUri = Uri.parse(referer);
          headers['Origin'] = refUri.origin;
        } catch (_) {}
      }

      final StreamResult result = StreamResult(
        sourceId: 'vidsrc-client',
        sourceName: 'Vidsrc',
        embedId: null,
        embedName: null,
        stream: StreamPlayback(
          id: 'vidsrc-primary',
          type: url.contains('.m3u8') ? 'hls' : 'file',
          playlist: url.contains('.m3u8') ? url : null,
          proxiedPlaylist: null,
          playbackUrl: url,
          playbackType: url.contains('.m3u8') ? 'hls' : 'mp4',
          selectedQuality: null,
          qualities: const <String, StreamQuality>{},
          headers: headers,
          preferredHeaders: headers,
          captions: const <StreamCaption>[],
          flags: const <String>[],
        ),
      );
      unawaited(finish(result));
    }

    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final String watchUrl = _embedUrl(tmdbId, season, episode);

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
                initialUrlRequest: URLRequest(url: WebUri(watchUrl)),
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
                  userAgent: _userAgent,
                ),
                initialUserScripts: UnmodifiableListView<UserScript>(
                  <UserScript>[
                    UserScript(
                      source: _hookScript,
                      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                    ),
                  ],
                ),
                onWebViewCreated: (InAppWebViewController controller) {
                  _log('webview created');
                  controller.addJavaScriptHandler(
                    handlerName: _handlerName,
                    callback: (dynamic args) {
                      final List<dynamic> values =
                          args is List ? args : const <dynamic>[];
                      if (values.isEmpty) return null;
                      final dynamic payload = values.first;
                      if (payload is! Map) return null;
                      final Map<String, dynamic> data =
                          Map<String, dynamic>.from(payload);
                      final String? url = _readString(data['url']);
                      if (url != null) {
                        tryStreamUrl(url,
                            referer: _readString(data['referer']));
                      }
                      return null;
                    },
                  );
                },
                shouldInterceptAjaxRequest: (
                  InAppWebViewController controller,
                  AjaxRequest ajaxRequest,
                ) async {
                  if (ajaxRequest.readyState == AjaxRequestReadyState.DONE) {
                    final String? url = ajaxRequest.responseURL?.toString() ??
                        ajaxRequest.url?.toString();
                    final String? body = ajaxRequest.responseText;
                    if (url != null && body != null && body.isNotEmpty) {
                      _extractFromResponse(url, body, tryStreamUrl);
                    }
                  }
                  return ajaxRequest;
                },
                shouldInterceptFetchRequest: (
                  InAppWebViewController controller,
                  FetchRequest fetchRequest,
                ) async {
                  return fetchRequest;
                },
                shouldInterceptRequest: (
                  InAppWebViewController controller,
                  WebResourceRequest request,
                ) async {
                  final String url = request.url.toString();
                  // Catch media URLs from any iframe level
                  if (_isMediaUrl(url)) {
                    _log('media resource intercepted: $url');
                    tryStreamUrl(url, referer: 'https://vidsrcme.ru/');
                  }
                  return null;
                },
                onLoadResource: (
                  InAppWebViewController controller,
                  LoadedResource resource,
                ) {
                  final String url = resource.url.toString();
                  if (_isMediaUrl(url)) {
                    _log('onLoadResource media: $url');
                    tryStreamUrl(url, referer: 'https://vidsrcme.ru/');
                  }
                },
                onLoadStart: (InAppWebViewController controller, WebUri? url) {
                  _log('load start: ${url?.toString() ?? '-'}');
                },
                onLoadStop: (InAppWebViewController controller, WebUri? url) {
                  _log('load stop: ${url?.toString() ?? '-'}');
                },
                onConsoleMessage: (
                  InAppWebViewController controller,
                  ConsoleMessage consoleMessage,
                ) {
                  final String msg = consoleMessage.message;
                  if (msg.contains('m3u8') ||
                      msg.contains('stream') ||
                      msg.contains('vidsrc') ||
                      msg.contains('prorcp') ||
                      msg.contains('rcp')) {
                    _log('console: $msg');
                  }
                },
                onReceivedError: (
                  InAppWebViewController controller,
                  WebResourceRequest request,
                  WebResourceError error,
                ) {
                  _log('error: ${error.type} url=${request.url} '
                      'mainFrame=${request.isForMainFrame}');
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
      _log('overlay inserted url=$watchUrl');
      return await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          _log('timeout after 30s');
          unawaited(finish(null));
          return null;
        },
      );
    } finally {
      await finish(null);
    }
  }

  static void _extractFromResponse(
    String url,
    String body,
    void Function(String url, {String? referer}) tryStreamUrl,
  ) {
    // Look for m3u8 URLs in the response body
    final RegExp m3u8Regex =
        RegExp(r'https?://[^\s"\\<>]+?\.m3u8[^\s"\\<>]*');
    final Iterable<RegExpMatch> matches = m3u8Regex.allMatches(body);
    for (final RegExpMatch match in matches) {
      final String m3u8Url = match.group(0) ?? '';
      if (m3u8Url.isNotEmpty && !m3u8Url.contains('{v')) {
        _log('found m3u8 in response from $url: $m3u8Url');
        tryStreamUrl(m3u8Url);
        return;
      }
    }

    // Try JSON parse for structured responses
    try {
      // Check for common patterns
      if (body.contains('"file"') || body.contains('"src"') || body.contains('"playlist"')) {
        // Look for URL-like values
        final RegExp urlRegex =
            RegExp(r'"(?:file|src|playlist|url)"\s*:\s*"([^"]+)"');
        final Iterable<RegExpMatch> urlMatches = urlRegex.allMatches(body);
        for (final RegExpMatch urlMatch in urlMatches) {
          final String foundUrl = urlMatch.group(1) ?? '';
          if (foundUrl.isNotEmpty && _isMediaUrl(foundUrl)) {
            _log('found media URL in JSON from $url: $foundUrl');
            tryStreamUrl(foundUrl);
            return;
          }
        }
      }
    } catch (_) {}
  }

  static bool _isMediaUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        (lower.contains('.ts') && (lower.contains('segment') || lower.contains('chunk')));
  }

  static String? _readString(dynamic value) {
    if (value == null) return null;
    final String s = '$value'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  String get _hookScript {
    return '''
(function() {
  if (window.__veilVidsrcInstalled) return;
  window.__veilVidsrcInstalled = true;

  function sendPayload(payload) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('$_handlerName', payload);
      }
    } catch (_) {}
  }

  function isMediaUrl(url) {
    if (!url) return false;
    var lower = url.toLowerCase();
    return lower.indexOf('.m3u8') !== -1 ||
           lower.indexOf('.mp4') !== -1;
  }

  function extractM3u8(text) {
    var regex = /(https?:\\/\\/[^\\s"'\\\\<>]+?\\.m3u8[^\\s"'\\\\<>]*)/gi;
    var match;
    while ((match = regex.exec(text)) !== null) {
      var url = match[1];
      if (url && url.indexOf('{v') === -1) {
        return url;
      }
    }
    return null;
  }

  function isInterestingUrl(url) {
    if (!url) return false;
    return url.indexOf('vidsrcme.ru') !== -1 ||
           url.indexOf('vsembed.ru') !== -1 ||
           url.indexOf('prorcp') !== -1 ||
           url.indexOf('/rcp/') !== -1 ||
           url.indexOf('cloudnestra') !== -1 ||
           isMediaUrl(url);
  }

  // Hook fetch
  var originalFetch = window.fetch;
  if (typeof originalFetch === 'function') {
    window.fetch = async function(input, init) {
      var response = await originalFetch.apply(this, arguments);
      try {
        var responseUrl = response && response.url ? response.url : (input && input.url ? input.url : input);
        if (isInterestingUrl(responseUrl) || isMediaUrl(String(responseUrl))) {
          var clone = response.clone();
          clone.text().then(function(body) {
            var m3u8 = extractM3u8(body);
            if (m3u8) {
              sendPayload({ url: m3u8, referer: String(responseUrl) });
            }
            // Check for JSON with file/src/playlist
            try {
              var data = JSON.parse(body);
              var streamUrl = data.file || data.src || data.playlist || data.url;
              if (streamUrl && isMediaUrl(streamUrl)) {
                sendPayload({ url: streamUrl, referer: String(responseUrl) });
              }
            } catch (_) {}
          }).catch(function() {});
        }
      } catch (_) {}
      return response;
    };
  }

  // Hook XMLHttpRequest
  var originalOpen = XMLHttpRequest.prototype.open;
  var originalSend = XMLHttpRequest.prototype.send;

  XMLHttpRequest.prototype.open = function(method, url) {
    this.__veilVidsrcUrl = url;
    return originalOpen.apply(this, arguments);
  };

  XMLHttpRequest.prototype.send = function(body) {
    var self = this;
    this.addEventListener('readystatechange', function() {
      if (self.readyState !== 4) return;
      var url = self.responseURL || self.__veilVidsrcUrl;
      if (!url) return;
      if (isInterestingUrl(url) || isMediaUrl(url)) {
        var responseText = typeof self.responseText === 'string' ? self.responseText : '';
        var m3u8 = extractM3u8(responseText);
        if (m3u8) {
          sendPayload({ url: m3u8, referer: url });
        }
        // Check for JSON
        try {
          var data = JSON.parse(responseText);
          var streamUrl = data.file || data.src || data.playlist || data.url;
          if (streamUrl && isMediaUrl(streamUrl)) {
            sendPayload({ url: streamUrl, referer: url });
          }
        } catch (_) {}
      }
    });
    return originalSend.apply(this, arguments);
  };

  // Silence media elements
  function silenceMedia(element) {
    try {
      element.muted = true;
      element.volume = 0;
      element.autoplay = false;
    } catch (_) {}
  }
  document.querySelectorAll('video, audio').forEach(silenceMedia);
  var observer = new MutationObserver(function() {
    document.querySelectorAll('video, audio').forEach(silenceMedia);
  });
  observer.observe(document.documentElement || document, { childList: true, subtree: true });
})();
''';
  }
}
