import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/external_subtitle_offer.dart';
import 'package:pstream_android/models/media_item.dart';

/// Wyzie + OpenSubtitles.com search/download for the player.
///
/// API keys must be supplied via `--dart-define` (never commit secrets).
class ExternalSubtitleService {
  const ExternalSubtitleService();

  static final Uri _wyzieSearch = Uri.parse('https://sub.wyzie.io/search');
  static final Uri _osBase = Uri.parse('https://api.opensubtitles.com/api/v1');

  static String? _osBearer;
  static DateTime? _osBearerUntil;

  /// Combined online offers (Wyzie first, then OpenSubtitles).
  /// Failures are silent; use [searchOnlineDetailed] for error text in the UI.
  Future<List<ExternalSubtitleOffer>> searchOnline({
    required MediaItem media,
    int? season,
    int? episode,
  }) async {
    final OnlineSubtitleSearchResult r = await searchOnlineDetailed(
      media: media,
      season: season,
      episode: episode,
    );
    return r.offers;
  }

  /// Wyzie + OpenSubtitles with per-provider errors and skip reasons (e.g. TV
  /// without episode). This is what the player uses so "empty" is explainable.
  Future<OnlineSubtitleSearchResult> searchOnlineDetailed({
    required MediaItem media,
    int? season,
    int? episode,
  }) async {
    final List<ExternalSubtitleOffer> out = <ExternalSubtitleOffer>[];
    final List<String> errors = <String>[];

    if (media.isShow && (season == null || episode == null)) {
      return OnlineSubtitleSearchResult(
        offers: out,
        skipReasons: <String>[
          'For TV series, open a specific episode first. '
              'Online libraries need a season and episode number.',
        ],
      );
    }

    if (AppConfig.hasWyzieApiKey) {
      if (!media.isShow || (season != null && episode != null)) {
        try {
          out.addAll(await _searchWyzie(media, season, episode));
        } catch (e) {
          errors.add('Wyzie: $e');
        }
      }
    }

    if (AppConfig.hasOpensubtitlesApiKey) {
      if (!media.isShow || (season != null && episode != null)) {
        try {
          out.addAll(await _searchOpensubtitles(media, season, episode));
        } catch (e) {
          errors.add('OpenSubtitles: $e');
        }
      }
    }

    return OnlineSubtitleSearchResult(
      offers: out,
      providerErrors: errors,
    );
  }

  /// Resolve OpenSubtitles [fileId] to a single-use HTTPS link (SRT).
  Future<String?> resolveOpensubtitlesDownloadUrl(int fileId) async {
    if (!AppConfig.hasOpensubtitlesApiKey) {
      return null;
    }

    Future<String?> postDownload(bool useBearer) async {
      final http.Response response = await http
          .post(
            _osBase.resolve('download'),
            headers: _opensubtitlesHeaders(
              includeBearer: useBearer && (_osBearer?.isNotEmpty ?? false),
            ),
            body: jsonEncode(<String, Object>{'file_id': fileId}),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final Map<String, dynamic> json = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );
      return _parseNullableString(json['link']);
    }

    await _ensureOpensubtitlesSession();

    if (_osBearer != null && _osBearer!.isNotEmpty) {
      final String? withBearer = await postDownload(true);
      if (withBearer != null) {
        return withBearer;
      }
    }

    final String? apiKeyOnly = await postDownload(false);
    if (apiKeyOnly != null) {
      return apiKeyOnly;
    }

    if (AppConfig.hasOpensubtitlesLogin) {
      _osBearer = null;
      _osBearerUntil = null;
      await _ensureOpensubtitlesSession();
      if (_osBearer != null && _osBearer!.isNotEmpty) {
        return postDownload(true);
      }
    }

    return null;
  }

  Future<void> _ensureOpensubtitlesSession() async {
    if (!AppConfig.hasOpensubtitlesLogin) {
      return;
    }
    final DateTime now = DateTime.now();
    if (_osBearer != null &&
        _osBearerUntil != null &&
        now.isBefore(_osBearerUntil!)) {
      return;
    }

    final http.Response response = await http.post(
      _osBase.resolve('login'),
      headers: _opensubtitlesHeaders(includeBearer: false),
      body: jsonEncode(<String, String>{
        'username': AppConfig.opensubtitlesUsername,
        'password': AppConfig.opensubtitlesPassword,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _osBearer = null;
      _osBearerUntil = null;
      return;
    }

    final Map<String, dynamic> json = Map<String, dynamic>.from(
      jsonDecode(response.body) as Map,
    );
    final String? token = _parseNullableString(json['token']);
    if (token == null || token.isEmpty) {
      _osBearer = null;
      _osBearerUntil = null;
      return;
    }

    _osBearer = token;
    _osBearerUntil = now.add(const Duration(minutes: 12));
  }

  Map<String, String> _opensubtitlesHeaders({required bool includeBearer}) {
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Api-Key': AppConfig.opensubtitlesApiKey,
      'User-Agent': AppConfig.subtitleHttpUserAgent,
    };
    if (includeBearer && _osBearer != null && _osBearer!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_osBearer';
    }
    return headers;
  }

  static const int _idempotentGetMaxAttempts = 3;
  static const Duration _idempotentGetTimeout = Duration(seconds: 25);

  static bool _isRetryableIdempotentGetError(Object e) {
    if (e is SocketException) {
      return true;
    }
    if (e is TimeoutException) {
      return true;
    }
    if (e is http.ClientException) {
      return true;
    }
    final String m = e.toString().toLowerCase();
    return m.contains('connection reset') ||
        m.contains('connection closed') ||
        m.contains('broken pipe') ||
        m.contains('network is unreachable') ||
        m.contains('host lookup') ||
        m.contains('handshake');
  }

  /// [OpenSubtitles] / Wyzie occasionally drop the TLS socket on mobile; a few
  /// short retries usually succeeds without changing the API contract.
  Future<http.Response> _getIdempotentWithRetry(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    for (int attempt = 0; attempt < _idempotentGetMaxAttempts; attempt++) {
      try {
        return await http
            .get(uri, headers: headers)
            .timeout(_idempotentGetTimeout);
      } catch (e) {
        if (attempt < _idempotentGetMaxAttempts - 1 &&
            _isRetryableIdempotentGetError(e)) {
          await Future<void>.delayed(
            Duration(milliseconds: 300 * (attempt + 1)),
          );
        } else {
          rethrow;
        }
      }
    }
    throw StateError('ID GET retry: unreachable');
  }

  Future<List<ExternalSubtitleOffer>> _searchWyzie(
    MediaItem media,
    int? season,
    int? episode,
  ) async {
    final Uri uri = _wyzieSearch.replace(
      queryParameters: <String, String>{
        'id': '${media.tmdbId}',
        if (season != null) 'season': '$season',
        if (episode != null) 'episode': '$episode',
        'format': 'srt',
        'key': AppConfig.wyzieApiKey,
      },
    );

    final http.Response response = await _getIdempotentWithRetry(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'User-Agent': AppConfig.subtitleHttpUserAgent,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpFailureMessage(response);
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('unexpected response (not a JSON list)');
    }

    final List<ExternalSubtitleOffer> offers = <ExternalSubtitleOffer>[];
    int index = 0;
    for (final dynamic item in decoded) {
      if (item is! Map) {
        continue;
      }
      final Map<String, dynamic> row = Map<String, dynamic>.from(item);
      final String? url = _parseNullableString(row['url']);
      if (url == null || url.isEmpty) {
        continue;
      }
      final String language =
          _parseNullableString(row['display']) ??
          _parseNullableString(row['language']) ??
          'Unknown';
      final String release =
          _parseNullableString(row['release']) ??
          _parseNullableString(row['fileName']) ??
          '';
      final String source =
          _parseNullableString(row['source']?.toString()) ?? 'Wyzie';
      final String title = release.isNotEmpty ? release : language;

      offers.add(
        ExternalSubtitleOffer(
          id: 'wyzie-$index-${row['url']}',
          title: title,
          languageLabel: language,
          providerLabel: 'Wyzie · $source',
          directUrl: url,
        ),
      );
      index++;
    }
    return offers;
  }

  Future<List<ExternalSubtitleOffer>> _searchOpensubtitles(
    MediaItem media,
    int? season,
    int? episode,
  ) async {
    final Map<String, String> byIds = <String, String>{};
    final String? imdb = _imdbForOpensubtitles(media.imdbId);
    if (media.isMovie) {
      byIds['tmdb_id'] = '${media.tmdbId}';
      if (imdb != null) {
        byIds['imdb_id'] = imdb;
      }
    } else {
      byIds['parent_tmdb_id'] = '${media.tmdbId}';
      if (season != null) {
        byIds['season_number'] = '$season';
      }
      if (episode != null) {
        byIds['episode_number'] = '$episode';
      }
      if (imdb != null) {
        byIds['parent_imdb_id'] = imdb;
      }
    }

    final List<ExternalSubtitleOffer> fromIds = await _fetchOpensubtitleOffers(
      byIds,
    );
    if (fromIds.isNotEmpty || !media.isMovie) {
      return fromIds;
    }
    // Title query fallback: TMDb-based search can return 0 files if ids are
    // out of sync or the catalog is sparse (users reported this for some
    // release titles, e.g. "Search online" finding files by name).
    final String title = media.title.trim();
    if (title.isEmpty) {
      return fromIds;
    }
    final String textQuery = media.year > 0 ? '$title ${media.year}' : title;
    return _fetchOpensubtitleOffers(
      <String, String>{'query': textQuery},
    );
  }

  /// Parses a single [GET /api/v1/subtitles] response into offers.
  Future<List<ExternalSubtitleOffer>> _fetchOpensubtitleOffers(
    Map<String, String> query,
  ) async {
    final Uri uri = _osBase.resolve('subtitles').replace(queryParameters: query);

    final http.Response response = await _getIdempotentWithRetry(
      uri,
      headers: _opensubtitlesHeaders(includeBearer: false),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _httpFailureMessage(response);
    }

    final Map<String, dynamic> json = Map<String, dynamic>.from(
      jsonDecode(response.body) as Map,
    );
    final List<dynamic> data = (json['data'] as List?) ?? const <dynamic>[];

    final List<ExternalSubtitleOffer> offers = <ExternalSubtitleOffer>[];
    int index = 0;
    for (final dynamic raw in data) {
      if (raw is! Map) {
        continue;
      }
      final Map<String, dynamic> item = Map<String, dynamic>.from(raw);
      final Map<String, dynamic> attributes = Map<String, dynamic>.from(
        item['attributes'] as Map? ?? const {},
      );
      final List<dynamic> files =
          (attributes['files'] as List?) ?? const <dynamic>[];
      if (files.isEmpty) {
        continue;
      }
      final Map<String, dynamic> firstFile = Map<String, dynamic>.from(
        files.first as Map? ?? const {},
      );
      final int? fileId = _parsePositiveInt(firstFile['file_id']);
      if (fileId == null) {
        continue;
      }

      final String language =
          _parseNullableString(attributes['language']) ?? 'unknown';
      final String release =
          _parseNullableString(attributes['release']) ?? 'OpenSubtitles';
      final String featureId = _parseNullableString(item['id']) ?? 'os-$fileId';

      offers.add(
        ExternalSubtitleOffer(
          id: 'os-$index-$featureId',
          title: release,
          languageLabel: language,
          providerLabel: 'OpenSubtitles',
          opensubtitlesFileId: fileId,
        ),
      );
      index++;
      if (index >= 40) {
        break;
      }
    }

    return offers;
  }

  static String? _imdbForOpensubtitles(String? raw) {
    if (raw == null) {
      return null;
    }
    final String t = raw.trim();
    if (t.isEmpty) {
      return null;
    }
    return t.startsWith('tt') ? t : 'tt$t';
  }

  static String _httpFailureMessage(http.Response r) {
    final String body = r.body;
    String detail = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (detail.length > 200) {
      detail = '${detail.substring(0, 200)}…';
    }
    if (detail.isEmpty) {
      return 'HTTP ${r.statusCode} ${r.request?.url}';
    }
    return 'HTTP ${r.statusCode} — $detail';
  }

  static String? _parseNullableString(dynamic value) {
    if (value == null) {
      return null;
    }
    final String s = '$value'.trim();
    return s.isEmpty ? null : s;
  }

  static int? _parsePositiveInt(dynamic value) {
    if (value is int) {
      return value > 0 ? value : null;
    }
    return int.tryParse('$value');
  }
}
