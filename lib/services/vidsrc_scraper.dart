import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';

class VidsrcScraper {
  const VidsrcScraper();

  static const List<ScrapeSourceDefinition> sourceDefinitions =
      <ScrapeSourceDefinition>[
    ScrapeSourceDefinition(
      id: 'vidsrc',
      name: 'Vidsrc',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
  ];

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static String _embedUrl(String tmdbId, int? season, int? episode) {
    if (season != null && episode != null) {
      return 'https://vidsrcme.ru/embed/tv?tmdb=$tmdbId&season=$season&episode=$episode';
    }
    return 'https://vidsrcme.ru/embed/movie?tmdb=$tmdbId';
  }

  static bool _isStreamUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('playlist') ||
        lower.contains('stream') ||
        lower.contains('play') ||
        lower.contains('file');
  }

  Future<StreamResult?> scrape({
    required BuildContext context,
    required String tmdbId,
    required String title,
    required int year,
    int? season,
    int? episode,
  }) async {
    debugPrint('[Vidsrc] scrape start tmdbId=$tmdbId season=$season episode=$episode');

    final Completer<StreamResult?> completer = Completer<StreamResult?>();
    String? foundStreamUrl;
    OverlayEntry? overlayEntry;
    InAppWebViewController? controller;

    final url = _embedUrl(tmdbId, season, episode);
    debugPrint('[Vidsrc] Loading URL: $url');

    overlayEntry = OverlayEntry(
      builder: (BuildContext context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.5,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Loading Vidsrc...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(overlayEntry);

    // Wait for the WebView to load and capture stream
    await Future<void>.delayed(const Duration(seconds: 25));

    // Try to get stream URL from WebView if we have controller
    if (controller != null && foundStreamUrl == null) {
      try {
        final String? html = await controller.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        if (html != null && html.contains('data-config')) {
          final startIdx = html.indexOf('data-config=');
          if (startIdx >= 0) {
            final substring = html.substring(startIdx, startIdx + 200);
            final firstQuote = substring.indexOf('"');
            final secondQuote = substring.indexOf('"', firstQuote + 1);
            if (firstQuote >= 0 && secondQuote > firstQuote) {
              foundStreamUrl = substring.substring(firstQuote + 1, secondQuote);
              debugPrint('[Vidsrc] found data-config: $foundStreamUrl');
            }
          }
        }
      } catch (e) {
        debugPrint('[Vidsrc] eval error: $e');
      }
    }

    overlayEntry.remove();
    debugPrint('[Vidsrc] done, found: $foundStreamUrl');

    if (foundStreamUrl != null) {
      return StreamResult(
        sourceId: 'vidsrc',
        sourceName: 'Vidsrc',
        embedId: null,
        embedName: null,
        stream: StreamPlayback(
          id: 'vidsrc-primary',
          type: foundStreamUrl!.contains('.m3u8') ? 'hls' : 'file',
          playlist: foundStreamUrl!.contains('.m3u8') ? foundStreamUrl : null,
          proxiedPlaylist: null,
          playbackUrl: foundStreamUrl,
          playbackType: foundStreamUrl!.contains('.m3u8') ? 'hls' : 'mp4',
          selectedQuality: null,
          qualities: {},
          headers: {'User-Agent': _userAgent},
          preferredHeaders: {},
          captions: const [],
          flags: const [],
        ),
      );
    }

    return null;
  }

  // Static method to be called with context to show WebView
  static Widget buildWebView({
    required String tmdbId,
    int? season,
    int? episode,
    required Function(String) onStreamFound,
  }) {
    final url = _embedUrl(tmdbId, season, episode);
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        userAgent: _userAgent,
      ),
      onWebViewCreated: (InAppWebViewController ctrl) {},
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final urlStr = navigationAction.request.url?.toString();
        if (_isStreamUrl(urlStr)) {
          debugPrint('[Vidsrc] shouldOverrideUrlLoading: $urlStr');
          onStreamFound(urlStr);
        }
        return NavigationActionPolicy.ALLOW;
      },
      onLoadStop: (controller, url) async {
        final urlStr = url?.toString();
        debugPrint('[Vidsrc] loadStop: $urlStr');
      },
    );
  }
}