import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';

class VidlinkScraper {
  const VidlinkScraper();

  static const List<ScrapeSourceDefinition> sourceDefinitions =
      <ScrapeSourceDefinition>[
    ScrapeSourceDefinition(
      id: 'vidlink',
      name: 'VidLink',
      type: 'source',
      mediaTypes: <String>['movie', 'show'],
    ),
  ];

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static String _watchUrl(String tmdbId, int? season, int? episode) {
    if (season != null && episode != null) {
      return 'https://vidlink.pro/tv/$tmdbId/s/$season/e/$episode';
    }
    return 'https://vidlink.pro/movie/$tmdbId';
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
    debugPrint('[Vidlink] scrape start tmdbId=$tmdbId season=$season episode=$episode');

    final Completer<StreamResult?> completer = Completer<StreamResult?>();
    String? foundStreamUrl;
    OverlayEntry? overlayEntry;
    InAppWebViewController? controller;

    final url = _watchUrl(tmdbId, season, episode);
    debugPrint('[Vidlink] Loading URL: $url');

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
                  'Loading VidLink...',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(overlayEntry);

    // Wait for the WebView to load
    await Future<void>.delayed(const Duration(seconds: 25));

    // Try to extract stream from page
    if (controller != null && foundStreamUrl == null) {
      try {
        final String? html = await controller.evaluateJavascript(
          source: 'document.documentElement.outerHTML',
        );
        if (html != null) {
          // Look for iframe src
          final srcStart = html.indexOf('<iframe');
          if (srcStart >= 0) {
            final srcSubstr = html.substring(srcStart, srcStart + 300);
            final srcIdx = srcSubstr.indexOf('src=');
            if (srcIdx >= 0) {
              final afterSrc = srcSubstr.substring(srcIdx + 4);
              final firstQuote = afterSrc.indexOf('"');
              final secondQuote = afterSrc.indexOf('"', firstQuote + 1);
              if (firstQuote >= 0 && secondQuote > firstQuote) {
                final src = afterSrc.substring(firstQuote + 1, secondQuote);
                if (_isStreamUrl(src)) {
                  foundStreamUrl = src;
                  debugPrint('[Vidlink] found src: $foundStreamUrl');
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Vidlink] eval error: $e');
      }
    }

    overlayEntry.remove();
    debugPrint('[Vidlink] done, found: $foundStreamUrl');

    if (foundStreamUrl != null) {
      return StreamResult(
        sourceId: 'vidlink',
        sourceName: 'VidLink',
        embedId: null,
        embedName: null,
        stream: StreamPlayback(
          id: 'vidlink-primary',
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
}