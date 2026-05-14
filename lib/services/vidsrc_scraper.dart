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

  Future<StreamResult?> scrape({
    required BuildContext context,
    required String tmdbId,
    required String title,
    required int year,
    int? season,
    int? episode,
  }) async {
    debugPrint('[Vidsrc] scrape start tmdbId=$tmdbId season=$season episode=$episode');

    final url = _embedUrl(tmdbId, season, episode);
    debugPrint('[Vidsrc] Loading URL: $url');

    // Show dialog with web view and loading indicator
    return await showDialog<StreamResult?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(url)),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    userAgent: _userAgent,
                  ),
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    final urlStr = navigationAction.request.url?.toString();
                    if (_isStreamUrl(urlStr) && urlStr != null) {
                      debugPrint('[Vidsrc] shouldOverrideUrlLoading: $urlStr');
                      // Found a stream URL, close dialog and return result
                      if (context.mounted) {
                        Navigator.of(context).pop(StreamResult(
                          sourceId: 'vidsrc',
                          sourceName: 'Vidsrc',
                          embedId: null,
                          embedName: null,
                          stream: StreamPlayback(
                            id: 'vidsrc-primary',
                            type: urlStr.contains('.m3u8') ? 'hls' : 'file',
                            playlist: urlStr.contains('.m3u8') ? urlStr : null,
                            proxiedPlaylist: null,
                            playbackUrl: urlStr,
                            playbackType: urlStr.contains('.m3u8') ? 'hls' : 'mp4',
                            selectedQuality: null,
                            qualities: {},
                            headers: {'User-Agent': _userAgent},
                            preferredHeaders: {},
                            captions: const [],
                            flags: const [],
                          ),
                        ));
                      }
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onLoadStop: (controller, url) async {
                    final urlStr = url?.toString();
                    debugPrint('[Vidsrc] onLoadStop: $urlStr');
                  },
                ),
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.5 - 25,
                  left: MediaQuery.of(context).size.width * 0.5 - 25,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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