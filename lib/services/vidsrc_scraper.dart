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

  static String _embedUrl(String tmdbId, int? season, int? episode, {String? imdbId}) {
    // Use the vsembed.su domain as it redirects from vidsrc-embed.ru
    final String baseUrl = 'https://vsembed.su';

    if (season != null && episode != null) {
      // TV show episode
      if (tmdbId.isNotEmpty) {
        return '$baseUrl/embed/tv/$tmdbId/$season-$episode';
      } else if (imdbId != null && imdbId.isNotEmpty) {
        return '$baseUrl/embed/tv/$imdbId/$season-$episode';
      }
    } else {
      // Movie
      if (tmdbId.isNotEmpty) {
        return '$baseUrl/embed/movie/$tmdbId';
      } else if (imdbId != null && imdbId.isNotEmpty) {
        return '$baseUrl/embed/movie/$imdbId';
      }
    }

    // Fallback to old format if no IDs provided
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

    // Poll for video element or network activity instead of fixed timeout
    final int maxAttempts = 30; // 15 seconds total (30 * 500ms)
    int attempts = 0;
    bool ready = false;

    while (attempts < maxAttempts && !ready && context.mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      attempts++;

      if (controller != null) {
        final controllerNotNull = controller;
        try {
          // Check if video element exists or if we have network activity indicating stream loading
          final String? status = await controllerNotNull.evaluateJavascript(
            source: '''(() => {
              // Check for video element
              const video = document.querySelector('video');
              if (video && (video.src || video.currentSrc)) {
                return 'video_ready';
              }

              // Check for common player containers that might indicate stream is loading
              const players = document.querySelectorAll('[id*="player"], [class*="player"], video');
              if (players.length > 0) {
                return 'player_present';
              }

              // Check if network tab would show activity (indirect check)
              return 'waiting';
            })()''',
          );

          if (status == 'video_ready' || status == 'player_present') {
            ready = true;
            debugPrint('[Vidsrc] ready after ${attempts * 500}ms: $status');
            break;
          }
        } catch (e) {
          debugPrint('[Vidsrc] polling error: $e');
        }
      }
    }

    // Try to get stream URL from the page
    if (controller != null && foundStreamUrl == null) {
      final controllerNotNull = controller;
      try {
        // First try to get any video element src directly
        final String? videoSrc = await controllerNotNull.evaluateJavascript(
          source: '''(() => {
              const video = document.querySelector('video');
              if (video) {
                return video.src || video.currentSrc || null;
              }
              return null;
            })()''',
        );

        if (videoSrc != null && videoSrc.isNotEmpty && _isStreamUrl(videoSrc)) {
          foundStreamUrl = videoSrc;
          debugPrint('[Vidsrc] found video src: $foundStreamUrl');
        } else {
          // Try to get iframe src as fallback
          final String? iframeSrc = await controllerNotNull.evaluateJavascript(
            source: '''(() => {
                const iframe = document.querySelector('iframe');
                return iframe ? iframe.src : null;
              })()''',
          );

          if (iframeSrc != null && iframeSrc.isNotEmpty && _isStreamUrl(iframeSrc)) {
            foundStreamUrl = iframeSrc;
            debugPrint('[Vidsrc] found iframe src: $foundStreamUrl');
          } else {
            // Try to extract from potential config or data attributes
            final String? configData = await controllerNotNull.evaluateJavascript(
              source: "(() => {\n"
                  "  const scripts = document.querySelectorAll('script');\n"
                  "  for (let script of scripts) {\n"
                  "    if (script.textContent) {\n"
                  "      const text = script.textContent;\n"
                  "      if (text.includes('src:') || text.includes('file:') || text.includes('videoUrl')) {\n"
                  "        const urlMatches = text.match(/https?:\\/\\/[^\\s\"']+/g);\n"
                  "        if (urlMatches) {\n"
                  "          for (const url of urlMatches) {\n"
                  "            if (url.includes('.m3u8') || url.includes('.mp4')) {\n"
                  "              return url;\n"
                  "            }\n"
                  "          }\n"
                  "        }\n"
                  "      }\n"
                  "    }\n"
                  "  }\n"
                  "  return null;\n"
                  "})()",
            );

            if (configData != null && configData.isNotEmpty && _isStreamUrl(configData)) {
              foundStreamUrl = configData;
              debugPrint('[Vidsrc] found config data: $foundStreamUrl');
            }
          }
        }
      } catch (e) {
        debugPrint('[Vidsrc] eval error: $e');
      }
    }

    overlayEntry.remove();
    debugPrint('[Vidsrc] done, found: $foundStreamUrl');

    if (foundStreamUrl != null && foundStreamUrl.isNotEmpty) {
      return StreamResult(
        sourceId: 'vidsrc',
        sourceName: 'Vidsrc',
        embedId: null,
        embedName: null,
        stream: StreamPlayback(
          id: 'vidsrc-primary',
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
        if (_isStreamUrl(urlStr) && urlStr != null) {
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