import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/match_stream.dart';
import 'package:pstream_android/models/sport_category.dart';
import 'package:pstream_android/models/sports_match.dart';

/// Client for the `veil-streamed-sports` proxy (streamed.pk mirror) on the
/// Oracle VM, port 3003.
///
/// Streams are **iframe embeds**, not HLS — playback happens in a WebView.
/// Uses the existing `http` package plus a process-local in-memory TTL cache so
/// tab switches and rebuilds do not re-hit the network. TTLs mirror the backend
/// (sports 1h, matches 2m, live 45s, streams 20s). No new dependencies.
class SportsService {
  const SportsService();

  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/json',
  };

  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _sportsTtl = Duration(hours: 1);
  static const Duration _matchesTtl = Duration(minutes: 2);
  static const Duration _liveTtl = Duration(seconds: 45);
  static const Duration _streamTtl = Duration(seconds: 20);

  static final Map<String, _CacheEntry> _cache = <String, _CacheEntry>{};

  String get _base => AppConfig.sportsApiUrl;

  Future<List<SportCategory>> fetchSports() async {
    final dynamic decoded = await _cachedJson(
      cacheKey: 'sports',
      url: '$_base/v1/sports',
      ttl: _sportsTtl,
    );
    if (decoded is! List) {
      throw const FormatException('/v1/sports did not return a JSON array.');
    }
    return decoded
        .whereType<Map>()
        .map((Map e) => SportCategory.fromJson(Map<String, dynamic>.from(e)))
        .where((SportCategory s) => s.id.isNotEmpty && s.name.isNotEmpty)
        .toList(growable: false);
  }

  /// Fetches matches for [pathKey], where [pathKey] is one of `live`,
  /// `all-today`, `all`, or a sport id (optionally suffixed with `/popular`).
  Future<List<SportsMatch>> fetchMatches(String pathKey) async {
    final String normalized = pathKey.replaceAll(RegExp(r'^/+|/+$'), '');
    final bool isLive =
        normalized == 'live' || normalized == 'live/popular';
    final dynamic decoded = await _cachedJson(
      cacheKey: 'matches:$normalized',
      url: '$_base/v1/matches/$normalized',
      ttl: isLive ? _liveTtl : _matchesTtl,
    );
    if (decoded is! List) {
      throw FormatException('/v1/matches/$normalized did not return an array.');
    }
    return decoded
        .whereType<Map>()
        .map((Map e) => SportsMatch.fromJson(Map<String, dynamic>.from(e)))
        .where((SportsMatch m) => m.id.isNotEmpty && m.title.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<MatchStream>> fetchStreams(String source, String id) async {
    final dynamic decoded = await _cachedJson(
      cacheKey: 'stream:$source:$id',
      url: '$_base/v1/stream/'
          '${Uri.encodeComponent(source)}/${Uri.encodeComponent(id)}',
      ttl: _streamTtl,
    );
    if (decoded is! List) {
      throw FormatException('/v1/stream/$source/$id did not return an array.');
    }
    return decoded
        .whereType<Map>()
        .map((Map e) => MatchStream.fromJson(Map<String, dynamic>.from(e)))
        .where((MatchStream s) => s.embedUrl.isNotEmpty)
        .toList(growable: false);
  }

  Future<dynamic> _cachedJson({
    required String cacheKey,
    required String url,
    required Duration ttl,
  }) async {
    final _CacheEntry? hit = _cache[cacheKey];
    if (hit != null && DateTime.now().isBefore(hit.expiresAt)) {
      return hit.value;
    }

    final dynamic decoded = await _getJson(url);
    _cache[cacheKey] = _CacheEntry(
      value: decoded,
      expiresAt: DateTime.now().add(ttl),
    );
    return decoded;
  }

  Future<dynamic> _getJson(String url) async {
    final http.Client client = http.Client();
    try {
      final http.Response response =
          await client.get(Uri.parse(url), headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) {
        throw HttpException(
          'HTTP ${response.statusCode} from $url',
          uri: Uri.parse(url),
        );
      }
      return jsonDecode(response.body);
    } finally {
      client.close();
    }
  }
}

class _CacheEntry {
  const _CacheEntry({required this.value, required this.expiresAt});

  final dynamic value;
  final DateTime expiresAt;
}
