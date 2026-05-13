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
      return 'https://vidlink.pro/tv/$tmdbId/$season/$episode';
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

    // Poll for iframe element instead of fixed timeout
    final int maxAttempts = 40; // 20 seconds total (40 * 500ms)
    int attempts = 0;
    bool iframeFound = false;

    while (attempts < maxAttempts && !iframeFound && context.mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      attempts++;

      if (controller != null) {
        try {
          final String? html = await controller.evaluateJavascript(
            source: '''(() => {
              const iframe = document.querySelector('iframe');
              return iframe ? iframe.outerHTML : null;
            })()''',
          );
          if (html != null && html.contains('<iframe')) {
            iframeFound = true;
            debugPrint('[Vidlink] iframe found after ${attempts * 500}ms');
            break;
          }
        } catch (e) {
          debugPrint('[Vidlink] polling error: $e');
        }
      }
    }

    // Try to extract stream from iframe
    if (controller != null && foundStreamUrl == null) {
      try {
        final String? html = await controller.evaluateJavascript(
          source: '''(() => {
              const iframe = document.querySelector('iframe');
              return iframe ? iframe.src : null;
            })()''',
        );
        if (html != null && html.isNotEmpty) {
          foundStreamUrl = html;
          debugPrint('[Vidlink] found iframe src: $foundStreamUrl');

          // Validate it looks like a stream URL
          if (!_isStreamUrl(foundStreamUrl)) {
            debugPrint('[Vidlink] WARNING: iframe src does not look like stream URL');
            // Still try to use it - sometimes validation is too strict
          }
        }
      } catch (e) {
        debugPrint('[Vidlink] eval error: $e');
      }
    }

    overlayEntry.remove();
    debugPrint('[Vidlink] done, found: $foundStreamUrl');

    if (foundStreamUrl != null && foundStreamUrl.isNotEmpty) {
      return StreamResult(
        sourceId: 'vidlink',
        sourceName: 'VidLink',
        embedId: null,
        embedName: null,
        stream: StreamPlayback(
          id: 'vidlink-primary',
          type: foundStreamUrl.contains('.m3u8') ? 'hls' : 'file',
          playlist: foundStreamUrl.contains('.m3u8') ? foundStreamUrl : null,
          proxiedPlaylist: null,
          playbackUrl: foundStreamUrl,
          playbackType: foundStreamUrl.contains('.m3u8') ? 'hls' : 'mp4',
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
