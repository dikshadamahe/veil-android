import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/episode.dart';
import 'package:pstream_android/models/media_item.dart';

class TmdbService {
  const TmdbService();

  static final Map<String, _CacheEntry<dynamic>> _cache =
      <String, _CacheEntry<dynamic>>{};
  static const Duration _cacheTtl = Duration(minutes: 60);
  static const Duration _requestTimeout = Duration(seconds: 30);
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

    final List<Map<String, dynamic>> results =
        ((json['results'] as List?) ?? const <dynamic>[])
            .map(
              (dynamic item) => Map<String, dynamic>.from(
                item as Map? ?? const <String, dynamic>{},
              ),
            )
            .toList();

    final List<MediaItem> directMatches = results
        .where(_isSearchableMedia)
        .map(MediaItem.fromTmdb)
        .where((MediaItem item) => item.tmdbId > 0)
        .toList();

    final List<MediaItem> peopleMatches = results
        .where((Map<String, dynamic> item) {
          return '${item['media_type'] ?? ''}'.toLowerCase() == 'person';
        })
        .expand(_knownForMedia)
        .map(MediaItem.fromTmdb)
        .where((MediaItem item) => item.tmdbId > 0)
        .toList();

    return _dedupeMediaItems(<MediaItem>[
      ...directMatches,
      ...peopleMatches,
    ]);
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
      final http.Response response = await _sendWithRetry(
        client,
        uri,
        token,
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) {
          throw Exception(
            'TMDB authorization failed. Check TMDB_TOKEN and rebuild the app.',
          );
        }
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
    } on Exception catch (error) {
      throw Exception('TMDB request failed: $error');
    } finally {
      client.close();
    }
  }

  Future<http.Response> _sendWithRetry(
    http.Client client,
    Uri uri,
    String token,
  ) async {
    try {
      return await _send(client, uri, token);
    } on TimeoutException {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return _send(client, uri, token);
    }
  }

  Future<http.Response> _send(
    http.Client client,
    Uri uri,
    String token,
  ) {
    return client
        .get(
          uri,
          headers: <String, String>{
            'accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(_requestTimeout);
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

  static bool _isSearchableMedia(Map<String, dynamic> item) {
    final String mediaType = '${item['media_type'] ?? ''}'.toLowerCase();
    return mediaType == 'movie' || mediaType == 'tv';
  }

  static Iterable<Map<String, dynamic>> _knownForMedia(
    Map<String, dynamic> person,
  ) sync* {
    final List<dynamic> knownFor =
        (person['known_for'] as List?) ?? const <dynamic>[];
    for (final dynamic item in knownFor) {
      final Map<String, dynamic> media = Map<String, dynamic>.from(
        item as Map? ?? const <String, dynamic>{},
      );
      if (_isSearchableMedia(media)) {
        yield media;
      }
    }
  }

  static List<MediaItem> _dedupeMediaItems(List<MediaItem> items) {
    final Map<String, MediaItem> deduped = <String, MediaItem>{};
    for (final MediaItem item in items) {
      deduped.putIfAbsent(item.hiveKey(), () => item);
    }
    return deduped.values.toList();
  }
}

class _CacheEntry<T> {
  const _CacheEntry(this.value, this.storedAt);

  final T value;
  final DateTime storedAt;
}
