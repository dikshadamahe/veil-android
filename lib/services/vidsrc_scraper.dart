import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static const Map<String, String> _cloudnestraHeaders = <String, String>{
    'Referer': 'https://cloudnestra.com/',
    'Origin': 'https://cloudnestra.com',
    'User-Agent': _userAgent,
  };

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

    try {
      // Step 1: Fetch embed HTML
      final String embedUrl = _embedUrl(tmdbId, season, episode);
      _log('fetching embed: $embedUrl');
      final http.Response embedResponse = await http
          .get(Uri.parse(embedUrl), headers: <String, String>{
        'User-Agent': _userAgent,
        'Accept': 'text/html,application/xhtml+xml',
        'Referer': 'https://vidsrcme.ru/',
      }).timeout(const Duration(seconds: 15));

      if (embedResponse.statusCode != 200) {
        _log('embed fetch failed: ${embedResponse.statusCode}');
        return null;
      }

      final String embedHtml = embedResponse.body;
      _log('embed html length: ${embedHtml.length}');

      // Step 2: Extract prorcp URL from embed HTML
      final String? prorcpUrl = _extractProrcpUrl(embedHtml);
      if (prorcpUrl == null) {
        _log('no prorcp URL found in embed HTML');
        return null;
      }
      _log('prorcp URL: $prorcpUrl');

      // Step 3: Fetch prorcp page
      final String fullProrcpUrl = prorcpUrl.startsWith('http')
          ? prorcpUrl
          : 'https://cloudnestra.com$prorcpUrl';
      _log('fetching prorcp: $fullProrcpUrl');
      final http.Response prorcpResponse = await http
          .get(Uri.parse(fullProrcpUrl), headers: <String, String>{
        'User-Agent': _userAgent,
        'Accept': 'text/html,application/xhtml+xml',
        ..._cloudnestraHeaders,
      }).timeout(const Duration(seconds: 15));

      if (prorcpResponse.statusCode != 200) {
        _log('prorcp fetch failed: ${prorcpResponse.statusCode}');
        return null;
      }

      final String prorcpHtml = prorcpResponse.body;
      _log('prorcp html length: ${prorcpHtml.length}');

      // Step 4: Extract m3u8 URL from prorcp page
      final String? m3u8Url = _extractM3u8Url(prorcpHtml);
      if (m3u8Url == null) {
        _log('no m3u8 URL found in prorcp HTML');
        // Try extracting from nested iframes
        final String? nestedUrl = _extractNestedIframeUrl(prorcpHtml);
        if (nestedUrl != null) {
          _log('found nested iframe: $nestedUrl');
          final StreamResult? nestedResult =
              await _fetchNestedIframe(nestedUrl);
          if (nestedResult != null) return nestedResult;
        }
        return null;
      }

      _log('m3u8 URL found: $m3u8Url');

      return StreamResult(
        sourceId: 'vidsrc-client',
        sourceName: 'Vidsrc',
        embedId: null,
        embedName: null,
        stream: StreamPlayback(
          id: 'vidsrc-primary',
          type: 'hls',
          playlist: m3u8Url,
          proxiedPlaylist: null,
          playbackUrl: m3u8Url,
          playbackType: 'hls',
          selectedQuality: null,
          qualities: const <String, StreamQuality>{},
          headers: _cloudnestraHeaders,
          preferredHeaders: _cloudnestraHeaders,
          captions: const <StreamCaption>[],
          flags: const <String>[],
        ),
      );
    } catch (e) {
      _log('error: $e');
      return null;
    }
  }

  /// Extract prorcp URL from embed HTML
  /// Looks for iframe src containing /prorcp/ or cloudnestra.com
  static String? _extractProrcpUrl(String html) {
    // Pattern 1: iframe with src containing prorcp
    final RegExp prorcpRegex = RegExp(
      r'''<iframe[^>]*src=["']([^"']*(?:prorcp|rcp)[^"']*)["']''',
      caseSensitive: false,
    );
    final RegExpMatch? prorcpMatch = prorcpRegex.firstMatch(html);
    if (prorcpMatch != null) {
      return prorcpMatch.group(1);
    }

    // Pattern 2: iframe with cloudnestra.com
    final RegExp cloudnestraRegex = RegExp(
      r'''<iframe[^>]*src=["']([^"']*cloudnestra\.com[^"']*)["']''',
      caseSensitive: false,
    );
    final RegExpMatch? cloudnestraMatch = cloudnestraRegex.firstMatch(html);
    if (cloudnestraMatch != null) {
      return cloudnestraMatch.group(1);
    }

    // Pattern 3: any iframe src
    final RegExp iframeRegex = RegExp(
      r'''<iframe[^>]*src=["']([^"']+)["']''',
      caseSensitive: false,
    );
    final RegExpMatch? iframeMatch = iframeRegex.firstMatch(html);
    if (iframeMatch != null) {
      final String src = iframeMatch.group(1) ?? '';
      if (src.isNotEmpty && !src.startsWith('data:')) {
        return src;
      }
    }

    // Pattern 4: data-src attribute
    final RegExp dataSrcRegex = RegExp(
      r'''data-src=["']([^"']+)["']''',
      caseSensitive: false,
    );
    final RegExpMatch? dataSrcMatch = dataSrcRegex.firstMatch(html);
    if (dataSrcMatch != null) {
      final String src = dataSrcMatch.group(1) ?? '';
      if (src.isNotEmpty && !src.startsWith('data:')) {
        return src;
      }
    }

    return null;
  }

  /// Extract m3u8 URL from player page HTML/JS
  static String? _extractM3u8Url(String html) {
    // Pattern 1: Direct m3u8 URL in HTML
    final RegExp m3u8Regex = RegExp(r'https?://[^\s"\\<>]+?\.m3u8[^\s"\\<>]*');
    final Iterable<RegExpMatch> m3u8Matches = m3u8Regex.allMatches(html);
    for (final RegExpMatch match in m3u8Matches) {
      final String url = match.group(0) ?? '';
      if (url.isNotEmpty && !url.contains('{')) {
        return url;
      }
    }

    // Pattern 2: file: "..." or src: "..." in JS
    final RegExp fileRegex = RegExp(
      r'''(?:file|src|source|playlist|url)\s*[:=]\s*["']([^"']*\.m3u8[^"']*)["']''',
      caseSensitive: false,
    );
    final RegExpMatch? fileMatch = fileRegex.firstMatch(html);
    if (fileMatch != null) {
      return fileMatch.group(1);
    }

    // Pattern 3: options.file or player.src
    final RegExp optionsRegex = RegExp(
      r'''(?:options|player|config)\s*\.\s*(?:file|src|source)\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    final RegExpMatch? optionsMatch = optionsRegex.firstMatch(html);
    if (optionsMatch != null) {
      final String url = optionsMatch.group(1) ?? '';
      if (url.contains('.m3u8') || url.contains('tmstr')) {
        return url;
      }
    }

    // Pattern 4: tmstr CDN URL
    final RegExp tmstrRegex = RegExp(r'https?://[^\s"\\<>]*tmstr[^\s"\\<>]*');
    final RegExpMatch? tmstrMatch = tmstrRegex.firstMatch(html);
    if (tmstrMatch != null) {
      return tmstrMatch.group(0);
    }

    return null;
  }

  /// Extract nested iframe URL from prorcp page
  static String? _extractNestedIframeUrl(String html) {
    final RegExp iframeRegex = RegExp(
      r'''<iframe[^>]*src=["']([^"']+)["']''',
      caseSensitive: false,
    );
    final RegExpMatch? iframeMatch = iframeRegex.firstMatch(html);
    if (iframeMatch != null) {
      final String src = iframeMatch.group(1) ?? '';
      if (src.isNotEmpty && !src.startsWith('data:')) {
        return src;
      }
    }
    return null;
  }

  /// Fetch nested iframe and extract stream URL
  Future<StreamResult?> _fetchNestedIframe(String url) async {
    try {
      final String fullUrl =
          url.startsWith('http') ? url : 'https://cloudnestra.com$url';
      _log('fetching nested iframe: $fullUrl');
      final http.Response response =
          await http.get(Uri.parse(fullUrl), headers: <String, String>{
        'User-Agent': _userAgent,
        'Accept': 'text/html,application/xhtml+xml',
        ..._cloudnestraHeaders,
      }).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        _log('nested iframe fetch failed: ${response.statusCode}');
        return null;
      }

      final String html = response.body;
      final String? m3u8Url = _extractM3u8Url(html);
      if (m3u8Url == null) {
        _log('no m3u8 in nested iframe');
        return null;
      }

      _log('m3u8 from nested iframe: $m3u8Url');
      return StreamResult(
        sourceId: 'vidsrc-client',
        sourceName: 'Vidsrc',
        embedId: null,
        embedName: null,
        stream: StreamPlayback(
          id: 'vidsrc-nested',
          type: 'hls',
          playlist: m3u8Url,
          proxiedPlaylist: null,
          playbackUrl: m3u8Url,
          playbackType: 'hls',
          selectedQuality: null,
          qualities: const <String, StreamQuality>{},
          headers: _cloudnestraHeaders,
          preferredHeaders: _cloudnestraHeaders,
          captions: const <StreamCaption>[],
          flags: const <String>[],
        ),
      );
    } catch (e) {
      _log('nested iframe error: $e');
      return null;
    }
  }
}
