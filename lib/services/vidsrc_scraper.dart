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
    // Using vidsrcme.ru - direct embed
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

    final url = _embedUrl(tmdbId, season, episode);
    debugPrint('[Vidsrc] Loading URL: $url');

    InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(url),
      ),
      initialSettings: InAppWebViewSettings(
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        userAgent: _userAgent,
      ),
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final String? urlStr = navigationAction.request.url?.toString();
        debugPrint('[Vidsrc] shouldOverrideUrlLoading: $urlStr');
        if (_isStreamUrl(urlStr) && foundStreamUrl == null) {
          foundStreamUrl = urlStr;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onLoadStart: (controller, uri) async {
        final String? urlStr = uri?.toString();
        debugPrint('[Vidsrc] loadStart: $urlStr');
        if (_isStreamUrl(urlStr) && foundStreamUrl == null) {
          foundStreamUrl = urlStr;
        }
      },
      onProgressChanged: (controller, progress) async {
        if (progress == 100 && foundStreamUrl == null) {
          try {
            final String? html = await controller.evaluateJavascript(
              source: 'document.documentElement.outerHTML',
            );
            if (html != null) {
              // Look for data-config attribute
              if (html.contains('data-config')) {
                final startIdx = html.indexOf('data-config=');
                if (startIdx >= 0) {
                  final substring = html.substring(startIdx, startIdx + 200);
                  // Find the value between quotes
                  final firstQuote = substring.indexOf('"');
                  final secondQuote = substring.indexOf('"', firstQuote + 1);
                  if (firstQuote >= 0 && secondQuote > firstQuote) {
                    foundStreamUrl = substring.substring(firstQuote + 1, secondQuote);
                    debugPrint('[Vidsrc] found data-config: $foundStreamUrl');
                  }
                }
              }
            }
          } catch (_) {}
        }
      },
    );

    // Wait for stream or timeout
    Future<void>.delayed(const Duration(seconds: 20), () async {
      overlayEntry?.remove();
      if (!completer.isCompleted) {
        debugPrint('[Vidsrc] timeout reached, found: $foundStreamUrl');
        if (foundStreamUrl != null) {
          completer.complete(StreamResult(
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
          ));
        } else {
          completer.complete(null);
        }
      }
    });

    return completer.future;
  }
}