import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:pstream_android/config/app_config.dart';
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
      // Vidlink API response has { sourceId, stream: { type, qualities, playlist, captions, headers } }
      final dynamic streamData = data['stream'];
      if (streamData is! Map) return null;

      final Map<String, dynamic> stream =
          Map<String, dynamic>.from(streamData);

      // Read qualities map from the API response
      final Map<String, StreamQuality> qualities =
          _readQualities(stream['qualities']);

      // Find the best playback URL
      // Priority: stormvv mp4 > stormvv HLS > any mp4 > any HLS > playlist fallback
      String? playbackUrl;
      String playbackType = 'file';

      // 1. Check qualities for stormvv.vodvidl.site mp4 URLs (working domain)
      for (final MapEntry<String, StreamQuality> entry in qualities.entries) {
        final String? url = entry.value.url;
        if (url != null &&
            url.contains('stormvv.vodvidl.site') &&
            url.contains('.mp4')) {
          playbackUrl = url;
          playbackType = 'mp4';
          break;
        }
      }

      // 2. Check qualities for any mp4 URL
      if (playbackUrl == null) {
        for (final MapEntry<String, StreamQuality> entry in qualities.entries) {
          final String? url = entry.value.url;
          if (url != null && url.contains('.mp4')) {
            playbackUrl = url;
            playbackType = 'mp4';
            break;
          }
        }
      }

      // 3. Check for m3u8 in qualities
      if (playbackUrl == null) {
        for (final MapEntry<String, StreamQuality> entry in qualities.entries) {
          final String? url = entry.value.url;
          if (url != null && url.contains('.m3u8')) {
            playbackUrl = url;
            playbackType = 'hls';
            break;
          }
        }
      }

      // 4. Fall back to playlist URL
      if (playbackUrl == null) {
        final String? playlist = _readString(stream['playlist']);
        if (playlist != null && playlist.isNotEmpty) {
          playbackUrl = playlist;
          playbackType = playlist.contains('.m3u8') ? 'hls' : 'file';
        }
      }

      // 5. Fall back to any URL in the stream object
      if (playbackUrl == null) {
        final String? fallback = _readString(stream['url']) ??
            _readString(stream['playbackUrl']);
        if (fallback != null && fallback.isNotEmpty) {
          playbackUrl = fallback;
          playbackType = fallback.contains('.m3u8') ? 'hls' : 'file';
        }
      }

      if (playbackUrl == null || playbackUrl.isEmpty) return null;

      // Read captions
      final List<StreamCaption> captions = _readCaptions(stream['captions']);

      // Build headers for media_kit playback
      // The proxy URL already has upstream CDN headers in the 'headers' query param.
      // The proxy itself needs Referer from the Vidlink page.
      Map<String, String> headers = <String, String>{
        'Referer': 'https://vidlink.pro/',
        'Origin': 'https://vidlink.pro',
      };

      _log('built stream url=$playbackUrl type=$playbackType '
          'qualities=${qualities.keys.join(',')} captions=${captions.length}');

      return StreamResult(
        sourceId: 'vidlink-client',
        sourceName: 'VidLink (Client)',
        embedId: null,
        embedName: null,
        stream: StreamPlayback(
          id: 'vidlink-primary',
          type: playbackType,
          playlist: playbackType == 'hls' ? playbackUrl : null,
          proxiedPlaylist: null,
          playbackUrl: playbackUrl,
          playbackType: playbackType,
          selectedQuality:
              qualities.isNotEmpty ? _pickBestQuality(qualities) : null,
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
      StreamResult? result = buildStreamResultFromData(payload);
      if (result == null) return;

      // If we got an HLS URL, try to fetch and parse quality variants
      final String? playlistUrl = result.stream.playlist;
      if (playlistUrl != null && playlistUrl.contains('.m3u8')) {
        _log('fetching HLS variants from: $playlistUrl');
        final Map<String, StreamQuality> hlsVariants =
            await _fetchHlsVariants(playlistUrl);
        if (hlsVariants.isNotEmpty) {
          _log('HLS variants parsed: ${hlsVariants.keys.join(',')}');
          final String defaultQuality = _pickBestQuality(hlsVariants) ?? '';
          result = StreamResult(
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
              selectedQuality: defaultQuality.isNotEmpty ? defaultQuality : null,
              qualities: hlsVariants,
              headers: result.stream.headers,
              preferredHeaders: result.stream.preferredHeaders,
              captions: result.stream.captions,
              flags: result.stream.flags,
            ),
          );
        }
      }

      await finish(result);
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
                      sourceName: 'VidLink (Client)',
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
                      sourceName: 'VidLink (Client)',
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
    try {
      // Look for m3u8 URLs in the response body
      final RegExp m3u8Regex =
          RegExp(r'https?://[^\s"\\<>]+?\.m3u8[^\s"\\<>]*');
      final Iterable<RegExpMatch> m3u8Matches = m3u8Regex.allMatches(body);
      for (final RegExpMatch match in m3u8Matches) {
        final String m3u8Url = match.group(0) ?? '';
        if (m3u8Url.isNotEmpty && !m3u8Url.contains('{v')) {
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

      // Look for mp4 URLs from known Vidlink CDN domains
      final RegExp mp4Regex =
          RegExp(r'https?://[^\s"\\<>]+?\.mp4[^\s"\\<>]*');
      final Iterable<RegExpMatch> mp4Matches = mp4Regex.allMatches(body);
      for (final RegExpMatch match in mp4Matches) {
        final String mp4Url = match.group(0) ?? '';
        if (mp4Url.isNotEmpty &&
            (mp4Url.contains('vodvidl.site') ||
                mp4Url.contains('videostr.net'))) {
          _log('found mp4 in response: $mp4Url');
          unawaited(handlePayload(<String, dynamic>{
            'stream': <String, dynamic>{
              'url': mp4Url,
              'type': 'mp4',
            },
          }));
          return;
        }
      }
    } catch (_) {}
  }

  static bool _isMediaUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    // Vidlink CDN domains
    if (lower.contains('vodvidl.site') &&
        (lower.contains('.mp4') || lower.contains('.m3u8'))) {
      return true;
    }
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        (lower.contains('.ts') && lower.contains('segment'));
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
    // Prefer 720p for mobile (good balance of quality and bandwidth)
    const List<String> preferred = <String>[
      '720p',
      '720',
      '480p',
      '480',
      '1080p',
      '1080',
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

  /// Fetch HLS master playlist and parse quality variants
  static Future<Map<String, StreamQuality>> _fetchHlsVariants(
    String m3u8Url,
  ) async {
    final Map<String, StreamQuality> result = <String, StreamQuality>{};

    // Try proxy first (bypasses geo/CORS blocks), then direct
    final String proxyBase = AppConfig.proxyBaseUrl.replaceFirst(':3001', ':3000');
    String? playlistContent;
    final List<String> urlsToTry = <String>[
      '$proxyBase/proxy?url=${Uri.encodeComponent(m3u8Url)}',
      m3u8Url,
    ];

    for (final String url in urlsToTry) {
      try {
        final Map<String, String> headers = <String, String>{
          'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*',
          'Referer': 'https://vidlink.pro/',
          'Origin': 'https://vidlink.pro',
        };
        final http.Response resp = await http
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          playlistContent = resp.body;
          break;
        }
      } catch (e) {
        continue;
      }
    }

    if (playlistContent == null) {
      _log('_fetchHlsVariants: failed to fetch playlist');
      return result;
    }
    _log('_fetchHlsVariants: got playlist, length=${playlistContent.length}');

    // Check if this is a master playlist (has #EXT-X-STREAM-INF)
    if (!playlistContent.contains('#EXT-X-STREAM-INF')) {
      _log('_fetchHlsVariants: not a master playlist');
      return result;
    }

    // Parse each quality variant
    final List<String> lines = playlistContent.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF')) continue;

      // Extract resolution: RESOLUTION=1920x1080
      final RegExp resRegex = RegExp(r'RESOLUTION=(\d+)x(\d+)');
      final RegExpMatch? resMatch = resRegex.firstMatch(line);
      String qualityLabel = '';
      if (resMatch != null) {
        final int height = int.tryParse(resMatch.group(2) ?? '0') ?? 0;
        qualityLabel = '${height}p';
      }

      // Extract bandwidth
      final RegExp bwRegex = RegExp(r'BANDWIDTH=(\d+)');
      final RegExpMatch? bwMatch = bwRegex.firstMatch(line);
      final int bandwidth = int.tryParse(bwMatch?.group(1) ?? '0') ?? 0;

      // Next non-comment line is the URL
      String variantUrl = '';
      for (int j = i + 1; j < lines.length; j++) {
        final String nextLine = lines[j].trim();
        if (nextLine.isEmpty || nextLine.startsWith('#')) continue;
        variantUrl = nextLine;
        break;
      }

      if (variantUrl.isEmpty) continue;

      // Resolve relative URLs
      if (!variantUrl.startsWith('http')) {
        final Uri baseUri = Uri.parse(m3u8Url);
        final String basePath = baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
        variantUrl = '${baseUri.scheme}://${baseUri.host}$basePath$variantUrl';
      }

      // Generate quality label from bandwidth if resolution not available
      if (qualityLabel.isEmpty) {
        if (bandwidth > 15000000) {
          qualityLabel = '4K';
        } else if (bandwidth > 8000000) {
          qualityLabel = '1440p';
        } else if (bandwidth > 5000000) {
          qualityLabel = '1080p';
        } else if (bandwidth > 2500000) {
          qualityLabel = '720p';
        } else if (bandwidth > 1000000) {
          qualityLabel = '480p';
        } else {
          qualityLabel = '360p';
        }
      }

      if (qualityLabel.isNotEmpty && variantUrl.isNotEmpty) {
        result[qualityLabel] = StreamQuality(
          url: variantUrl,
          type: 'hls',
        );
        _log('variant: $qualityLabel -> $variantUrl');
      }
    }

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
