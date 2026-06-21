import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pstream_android/models/live_channel.dart';

/// Fetches Live TV channels + EPG from the public `wfs.lol` endpoints.
///
/// Uses the existing `http` package and an in-memory cache shared across
/// instances (channels: 24h TTL, EPG: 1h TTL) so tab switches and rebuilds do
/// not re-hit the network. No new dependencies.
class LiveService {
  const LiveService();

  static const String _channelsUrl = 'https://wfs.lol/live-channels.json';
  static const String _epgUrl = 'https://wfs.lol/live-epg.json';

  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/json',
  };

  static const Duration _timeout = Duration(seconds: 20);
  static const Duration _channelsTtl = Duration(hours: 24);
  static const Duration _epgTtl = Duration(hours: 1);

  static List<LiveChannel>? _channelsCache;
  static DateTime? _channelsFetchedAt;
  static Map<String, List<LiveProgram>>? _epgCache;
  static DateTime? _epgFetchedAt;

  Future<List<LiveChannel>> fetchChannels() async {
    final List<LiveChannel>? cached = _channelsCache;
    final DateTime? at = _channelsFetchedAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _channelsTtl) {
      return cached;
    }

    final dynamic decoded = await _getJson(_channelsUrl);
    if (decoded is! List) {
      throw const FormatException('live-channels.json is not a JSON array.');
    }

    final List<LiveChannel> channels = decoded
        .whereType<Map>()
        .map((Map e) => LiveChannel.fromJson(Map<String, dynamic>.from(e)))
        .where((LiveChannel c) => c.url.isNotEmpty && c.name.isNotEmpty)
        .toList(growable: false);

    _channelsCache = channels;
    _channelsFetchedAt = DateTime.now();
    return channels;
  }

  Future<Map<String, List<LiveProgram>>> fetchEpg() async {
    final Map<String, List<LiveProgram>>? cached = _epgCache;
    final DateTime? at = _epgFetchedAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _epgTtl) {
      return cached;
    }

    final dynamic decoded = await _getJson(_epgUrl);
    if (decoded is! Map) {
      throw const FormatException('live-epg.json is not a JSON object.');
    }

    final Map<String, List<LiveProgram>> epg = <String, List<LiveProgram>>{};
    decoded.forEach((dynamic key, dynamic value) {
      if (value is! List) {
        return;
      }
      final List<LiveProgram> programs = value
          .whereType<Map>()
          .map(
            (Map e) => LiveProgram.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList(growable: false);
      epg['$key'.toLowerCase()] = programs;
    });

    _epgCache = epg;
    _epgFetchedAt = DateTime.now();
    return epg;
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
