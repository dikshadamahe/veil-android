// StreamService — OMSS v1.0 client for the cinepro-org/core resolver.
//
// Two public methods only:
//   - fetchSources(item, season?, episode?)  — GET /v1/movies/{id} or
//                                              GET /v1/tv/{id}/seasons/{s}/episodes/{e}
//   - checkHealth()                          — GET /v1/health
//
// The single request returns every playable source the resolver has for
// the title. `source.url` is already an absolute proxy URL, so the app
// does no header injection, no SSE, no client-side WebView scraping.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/omss_source.dart';

class StreamService {
  const StreamService();

  /// Sole HTTP header. cinepro returns JSON; no User-Agent injection
  /// (the proxy sets Referer / Origin / User-Agent server-side).
  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/json',
  };

  static const Duration _sourcesTimeout = Duration(seconds: 60);
  static const Duration _healthTimeout = Duration(seconds: 5);

  /// Fetches the OMSS v1.0 response for the given [item].
  ///
  /// - If [season] and [episode] are both non-null, calls
  ///   `GET {ORACLE_URL}/v1/tv/{tmdbId}/seasons/{s}/episodes/{e}`.
  /// - Otherwise calls `GET {ORACLE_URL}/v1/movies/{tmdbId}`.
  ///
  /// Throws [OmssException] on a non-200 response, or a [TimeoutException]
  /// / [SocketException] / [FormatException] from the underlying HTTP call.
  Future<OmssResponse> fetchSources(
    MediaItem item, {
    int? season,
    int? episode,
  }) async {
    final Uri uri = _buildSourcesUri(item, season: season, episode: episode);
    final http.Client client = http.Client();
    try {
      final http.Response response = await client
          .get(uri, headers: _headers)
          .timeout(_sourcesTimeout);
      if (response.statusCode != 200) {
        throw OmssException(response.statusCode, response.body);
      }
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('OMSS response is not a JSON object.');
      }
      return OmssResponse.fromJson(Map<String, dynamic>.from(decoded));
    } finally {
      client.close();
    }
  }

  /// Quick liveness probe. Returns `true` on HTTP 200, `false` on any
  /// network failure, timeout, or non-200 status.
  Future<bool> checkHealth() async {
    final Uri uri = Uri.parse('${AppConfig.oracleUrl}/v1/health');
    final http.Client client = http.Client();
    try {
      final http.Response response = await client
          .get(uri, headers: _headers)
          .timeout(_healthTimeout);
      return response.statusCode == 200;
    } on TimeoutException {
      return false;
    } on SocketException {
      return false;
    } on http.ClientException {
      return false;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  Uri _buildSourcesUri(MediaItem item, {int? season, int? episode}) {
    final String base = AppConfig.oracleUrl;
    if (season != null && episode != null) {
      return Uri.parse(
        '$base/v1/tv/${item.tmdbId}/seasons/$season/episodes/$episode',
      );
    }
    return Uri.parse('$base/v1/movies/${item.tmdbId}');
  }
}

/// Raised when cinepro returns a non-200 status from an OMSS endpoint.
class OmssException implements Exception {
  const OmssException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'OmssException($statusCode): $body';
}
