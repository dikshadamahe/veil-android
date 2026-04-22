import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/episode.dart';
import 'package:pstream_android/models/media_item.dart';

class TmdbService {
  const TmdbService();

  static final Map<String, _CacheEntry<dynamic>> _cache =
      <String, _CacheEntry<dynamic>>{};
  static const Duration _cacheTtl = Duration(minutes: 60);
  static final Uri _baseUri = Uri.parse('https://api.themoviedb.org/3/');

  Future<List<MediaItem>> getTrending(String type, String window) async {
    final String tmdbType = _normalizeTrendingType(type);
    final Map<String, dynamic> json = await _getJson(
      'trending/$tmdbType/$window',
    );

    return ((json['results'] as List?) ?? const <dynamic>[])
        .map(
          (dynamic item) => MediaItem.fromTmdb(
            Map<String, dynamic>.from(item as Map? ?? const {}),
          ),
        )
        .where((MediaItem item) => item.tmdbId > 0)
        .toList();
  }

  Future<List<MediaItem>> search(String query) async {
    final String trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const <MediaItem>[];
    }

    final Map<String, dynamic> json = await _getJson(
      'search/multi',
      queryParameters: <String, String>{
        'query': trimmedQuery,
        'include_adult': 'false',
        'page': '1',
      },
    );

    return ((json['results'] as List?) ?? const <dynamic>[])
        .map(
          (dynamic item) => Map<String, dynamic>.from(
            item as Map? ?? const <String, dynamic>{},
          ),
        )
        .where((Map<String, dynamic> item) {
          final String mediaType = '${item['media_type'] ?? ''}'.toLowerCase();
          return mediaType == 'movie' || mediaType == 'tv';
        })
        .map(MediaItem.fromTmdb)
        .where((MediaItem item) => item.tmdbId > 0)
        .toList();
  }

  Future<MediaItem> getDetails(int id, String type) async {
    final String endpointType = _normalizeDetailType(type);
    final Map<String, dynamic> json = await _getJson(
      '$endpointType/$id',
      queryParameters: const <String, String>{
        'append_to_response': 'external_ids,credits',
      },
    );

    return MediaItem.fromTmdb(json);
  }

  Future<List<Episode>> getSeasonEpisodes(int showId, int seasonNum) async {
    final Map<String, dynamic> json = await _getJson(
      'tv/$showId/season/$seasonNum',
    );

    return ((json['episodes'] as List?) ?? const <dynamic>[])
        .map(
          (dynamic episode) => Episode.fromTmdb(
            Map<String, dynamic>.from(episode as Map? ?? const {}),
          ),
        )
        .toList();
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
  }) async {
    final String token = AppConfig.tmdbReadToken.trim();
    if (token.isEmpty) {
      throw StateError('TMDB_TOKEN is missing.');
    }

    final Uri uri = _baseUri
        .resolve(path)
        .replace(
          queryParameters: queryParameters.isEmpty ? null : queryParameters,
        );
    final String cacheKey = _cacheKey(uri);
    final DateTime now = DateTime.now();
    final _CacheEntry<dynamic>? cached = _cache[cacheKey];
    if (cached != null && now.difference(cached.storedAt) < _cacheTtl) {
      return Map<String, dynamic>.from(cached.value as Map);
    }

    final http.Client client = http.Client();
    try {
      final http.Response response = await client.get(
        uri,
        headers: <String, String>{
          'accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'TMDB request failed (${response.statusCode}) for $uri',
          uri,
        );
      }

      final Map<String, dynamic> json = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );
      _cache[cacheKey] = _CacheEntry<dynamic>(json, now);
      return json;
    } finally {
      client.close();
    }
  }

  static String _normalizeTrendingType(String value) {
    return switch (value.trim().toLowerCase()) {
      'show' => 'tv',
      'tv' => 'tv',
      'movie' => 'movie',
      'all' => 'all',
      _ => throw ArgumentError.value(
        value,
        'type',
        'Expected movie, show, tv, or all.',
      ),
    };
  }

  static String _normalizeDetailType(String value) {
    return switch (value.trim().toLowerCase()) {
      'show' => 'tv',
      'tv' => 'tv',
      'movie' => 'movie',
      _ => throw ArgumentError.value(value, 'type', 'Expected movie or show.'),
    };
  }

  static String _cacheKey(Uri uri) => uri.toString();
}

class _CacheEntry<T> {
  const _CacheEntry(this.value, this.storedAt);

  final T value;
  final DateTime storedAt;
}
