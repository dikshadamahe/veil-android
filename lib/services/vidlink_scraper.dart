import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';

class VidlinkScraper {
  const VidlinkScraper();

  static const List<ScrapeSourceDefinition> sourceDefinitions =
      <ScrapeSourceDefinition>[
    ScrapeSourceDefinition(
      id: 'vidlink-client',
      name: 'VidLink',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
  ];

  static const String _handlerName = 'veilVidlinkResult';
  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static void _log(String message) {
    debugPrint('[Vidlink] $message');
  }

  static String _embedUrl(String tmdbId, int? season, int? episode) {
    if (season != null && episode != null) {
      return 'https://vidlink.pro/tv/$tmdbId/$season/$episode';
    }
    return 'https://vidlink.pro/movie/$tmdbId';
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

    StreamResult? buildStreamResultFromData(Map<String, dynamic> data) {
      // Look for stream object in the data
      final dynamic streamData = data['stream'] ?? data;
      if (streamData is! Map) return null;

      final Map<String, dynamic> stream =
          Map<String, dynamic>.from(streamData);

      // Check for direct URL
      final String? directUrl = _readString(stream['url']) ??
          _readString(stream['playlist']) ??
          _readString(stream['playbackUrl']);

      // Check for qualities map
      final Map<String, StreamQuality> qualities =
          _readQualities(stream['qualities']);

      // Determine the best playback URL
      String? playbackUrl;
      String playbackType = 'file';

      if (directUrl != null && directUrl.isNotEmpty) {
        playbackUrl = directUrl;
        playbackType = directUrl.contains('.m3u8') ? 'hls' : 'file';
      } else if (qualities.isNotEmpty) {
        // Pick best quality (prefer 1080p -> 720p -> 480p)
        final String? bestKey = _pickBestQuality(qualities);
        if (bestKey != null) {
          playbackUrl = qualities[bestKey]?.url;
          playbackType = 'hls';
        }
      }

      if (playbackUrl == null || playbackUrl.isEmpty) return null;

      // Read captions
      final List<StreamCaption> captions = _readCaptions(stream['captions']);

      // Read headers
      final Map<String, String> headers = _readStringMap(stream['headers']);

      _log('built stream url=$playbackUrl type=$playbackType '
          'qualities=${qualities.keys.join(',')} captions=${captions.length}');

      return StreamResult(
        sourceId: 'vidlink-client',
        sourceName: 'VidLink',
        embedId: null,
        embedName: null,
        stream: StreamPlayback(
          id: 'vidlink-primary',
          type: playbackType,
          playlist: playbackType == 'hls' ? playbackUrl : null,
          proxiedPlaylist: null,
          playbackUrl: playbackUrl,
          playbackType: playbackType,
          selectedQuality: qualities.isNotEmpty ? _pickBestQuality(qualities) : null,
          qualities: qualities,
          headers: headers,
          preferredHeaders: headers,
          captions: captions,
          flags: const <String>[],
        ),
      );
    }

    Future<void> handlePayload(Map<String, dynamic> payload) async {
      _log('payload keys=${payload.keys.join(',')}');
      final StreamResult? result = buildStreamResultFromData(payload);
      if (result != null) {
        await finish(result);
      }
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
                      unawaited(handlePayload(
                          Map<String, dynamic>.from(payload)));
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
                      _tryExtractFromResponse(url, body, handlePayload);
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
                  if (_isMediaUrl(url) && seenUrls.add(url)) {
                    _log('media resource intercepted: $url');
                    final StreamResult result = StreamResult(
                      sourceId: 'vidlink-client',
                      sourceName: 'VidLink',
                      embedId: null,
                      embedName: null,
                      stream: StreamPlayback(
                        id: 'vidlink-intercepted',
                        type: url.contains('.m3u8') ? 'hls' : 'file',
                        playlist: url.contains('.m3u8') ? url : null,
                        proxiedPlaylist: null,
                        playbackUrl: url,
                        playbackType: url.contains('.m3u8') ? 'hls' : 'mp4',
                        selectedQuality: null,
                        qualities: const <String, StreamQuality>{},
                        headers: const <String, String>{
                          'User-Agent': _userAgent,
                          'Referer': 'https://vidlink.pro/',
                        },
                        preferredHeaders: const <String, String>{},
                        captions: const <StreamCaption>[],
                        flags: const <String>[],
                      ),
                    );
                    unawaited(finish(result));
                  }
                  return null;
                },
                onLoadResource: (
                  InAppWebViewController controller,
                  LoadedResource resource,
                ) {
                  final String url = resource.url.toString();
                  if (_isMediaUrl(url) && seenUrls.add(url)) {
                    _log('onLoadResource media: $url');
                    final StreamResult result = StreamResult(
                      sourceId: 'vidlink-client',
                      sourceName: 'VidLink',
                      embedId: null,
                      embedName: null,
                      stream: StreamPlayback(
                        id: 'vidlink-resource',
                        type: url.contains('.m3u8') ? 'hls' : 'file',
                        playlist: url.contains('.m3u8') ? url : null,
                        proxiedPlaylist: null,
                        playbackUrl: url,
                        playbackType: url.contains('.m3u8') ? 'hls' : 'mp4',
                        selectedQuality: null,
                        qualities: const <String, StreamQuality>{},
                        headers: const <String, String>{
                          'User-Agent': _userAgent,
                          'Referer': 'https://vidlink.pro/',
                        },
                        preferredHeaders: const <String, String>{},
                        captions: const <StreamCaption>[],
                        flags: const <String>[],
                      ),
                    );
                    unawaited(finish(result));
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
                  if (msg.contains('vidlink') ||
                      msg.contains('stream') ||
                      msg.contains('m3u8')) {
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

  static void _tryExtractFromResponse(
    String url,
    String body,
    Future<void> Function(Map<String, dynamic>) handlePayload,
  ) {
    // Try to parse as JSON and look for stream data
    try {
      // Look for m3u8 URLs in the response body
      final RegExp m3u8Regex =
          RegExp(r'https?://[^\s"\\<>]+?\.m3u8[^\s"\\<>]*');
      final Iterable<RegExpMatch> m3u8Matches = m3u8Regex.allMatches(body);
      for (final RegExpMatch match in m3u8Matches) {
        final String m3u8Url = match.group(0) ?? '';
        if (m3u8Url.isNotEmpty) {
          _log('found m3u8 in response: $m3u8Url');
          unawaited(handlePayload(<String, dynamic>{
            'stream': <String, dynamic>{
              'url': m3u8Url,
              'type': 'hls',
            },
          }));
          return;
        }
      }

      // Try JSON parse
      // (dynamic decoded) - skip if not valid JSON
    } catch (_) {}
  }

  static bool _isMediaUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.ts') && lower.contains('segment');
  }

  static Map<String, StreamQuality> _readQualities(dynamic raw) {
    final Map<String, StreamQuality> qualities = <String, StreamQuality>{};
    if (raw is! Map) return qualities;

    raw.forEach((dynamic key, dynamic value) {
      final String qualityKey = '$key'.trim();
      if (qualityKey.isEmpty) return;

      if (value is Map) {
        final String? url = _readString(value['url'] ?? value['file']);
        if (url != null && url.isNotEmpty) {
          qualities[qualityKey] =
              StreamQuality(url: url, type: url.contains('.m3u8') ? 'hls' : 'file');
        }
      } else if (value is String && value.trim().isNotEmpty) {
        qualities[qualityKey] = StreamQuality(
            url: value.trim(),
            type: value.contains('.m3u8') ? 'hls' : 'file');
      }
    });

    return qualities;
  }

  static String? _pickBestQuality(Map<String, StreamQuality> qualities) {
    const List<String> preferred = <String>[
      '1080p',
      '1080',
      '720p',
      '720',
      '480p',
      '480',
      '360p',
      '360',
    ];
    for (final String q in preferred) {
      if (qualities.containsKey(q) && qualities[q]?.url != null) {
        return q;
      }
    }
    // Fallback: return first key with a URL
    for (final MapEntry<String, StreamQuality> entry in qualities.entries) {
      if (entry.value.url != null && entry.value.url!.isNotEmpty) {
        return entry.key;
      }
    }
    return null;
  }

  static List<StreamCaption> _readCaptions(dynamic raw) {
    if (raw is! List) return const <StreamCaption>[];
    final List<StreamCaption> captions = <StreamCaption>[];
    for (final dynamic entry in raw) {
      if (entry is Map) {
        final String? url = _readString(entry['url'] ?? entry['file']);
        if (url != null && url.isNotEmpty) {
          captions.add(StreamCaption(
            url: url,
            language: _readString(entry['language'] ?? entry['lang']),
            type: _readString(entry['type']) ?? 'vtt',
            label: _readString(entry['label'] ?? entry['language']),
            raw: Map<String, dynamic>.from(entry),
          ));
        }
      }
    }
    return captions;
  }

  static Map<String, String> _readStringMap(dynamic raw) {
    if (raw is! Map) return const <String, String>{};
    final Map<String, String> result = <String, String>{};
    raw.forEach((dynamic key, dynamic value) {
      if (value != null) {
        result['$key'] = '$value';
      }
    });
    return result;
  }

  static String? _readString(dynamic value) {
    if (value == null) return null;
    final String s = '$value'.trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  String get _hookScript {
    return '''
(function() {
  if (window.__veilVidlinkInstalled) return;
  window.__veilVidlinkInstalled = true;

  function sendPayload(payload) {
    try {
      if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
        window.flutter_inappwebview.callHandler('$_handlerName', payload);
      }
    } catch (_) {}
  }

  function isStreamUrl(url) {
    if (!url) return false;
    var lower = url.toLowerCase();
    return lower.indexOf('.m3u8') !== -1 ||
           lower.indexOf('.mp4') !== -1 ||
           lower.indexOf('playlist') !== -1 ||
           lower.indexOf('/stream/') !== -1;
  }

  function isVidlinkApi(url) {
    if (!url) return false;
    return url.indexOf('vidlink.pro') !== -1 ||
           url.indexOf('enc-dec.app') !== -1;
  }

  function tryParseAndSend(body, url) {
    if (!body) return;
    try {
      var data = JSON.parse(body);
      if (data && data.stream) {
        sendPayload(data);
        return;
      }
      // Check for direct URL in various formats
      var streamUrl = data.url || data.playlist || data.file || data.src;
      if (streamUrl && isStreamUrl(streamUrl)) {
        sendPayload({ stream: { url: streamUrl, type: streamUrl.indexOf('.m3u8') !== -1 ? 'hls' : 'file' } });
        return;
      }
      // Check nested streams array
      if (data.streams && Array.isArray(data.streams)) {
        for (var i = 0; i < data.streams.length; i++) {
          var s = data.streams[i];
          var sUrl = s.url || s.file || s.src || s.stream;
          if (sUrl && isStreamUrl(sUrl)) {
            sendPayload({ stream: { url: sUrl, type: sUrl.indexOf('.m3u8') !== -1 ? 'hls' : 'file', qualities: data.qualities || {} } });
            return;
          }
        }
      }
    } catch (_) {}
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

  // Hook fetch
  var originalFetch = window.fetch;
  if (typeof originalFetch === 'function') {
    window.fetch = async function(input, init) {
      var response = await originalFetch.apply(this, arguments);
      try {
        var responseUrl = response && response.url ? response.url : (input && input.url ? input.url : input);
        if (isVidlinkApi(responseUrl) || isStreamUrl(responseUrl)) {
          var clone = response.clone();
          clone.text().then(function(body) {
            tryParseAndSend(body, responseUrl);
            var m3u8 = extractM3u8(body);
            if (m3u8) {
              sendPayload({ stream: { url: m3u8, type: 'hls' } });
            }
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
    this.__veilVidlinkUrl = url;
    return originalOpen.apply(this, arguments);
  };

  XMLHttpRequest.prototype.send = function(body) {
    var self = this;
    this.addEventListener('readystatechange', function() {
      if (self.readyState !== 4) return;
      var url = self.responseURL || self.__veilVidlinkUrl;
      if (!url) return;
      if (isVidlinkApi(url) || isStreamUrl(url)) {
        var responseText = typeof self.responseText === 'string' ? self.responseText : '';
        tryParseAndSend(responseText, url);
        var m3u8 = extractM3u8(responseText);
        if (m3u8) {
          sendPayload({ stream: { url: m3u8, type: 'hls' } });
        }
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
