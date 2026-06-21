// OMSS v1.0 data shapes returned by the cinepro-org/core resolver.
//
// Endpoint: GET {ORACLE_URL}/v1/movies/{tmdbId}
//           GET {ORACLE_URL}/v1/tv/{tmdbId}/seasons/{s}/episodes/{e}
//
// Response:
//   {
//     "responseId": "uuid",
//     "expiresAt": "ISO-8601",
//     "sources": [
//       {
//         "url": "http://.../v1/proxy?data=…",   // absolute proxy URL
//         "type": "hls" | "mp4",
//         "quality": "1080p",
//         "audioTracks": [{ "language": "en", "label": "English" }],
//         "provider": { "id": "vidsrc", "name": "VidSrc" }
//       }
//     ],
//     "subtitles": [{ "url": "...", "label": "English", "format": "vtt" }],
//     "diagnostics": []
//   }
//
// `source.url` is already absolute — the app opens it via video_player (ExoPlayer).
// without prepending ORACLE_URL or injecting any headers. The proxy
// sets Referer / Origin / User-Agent server-side.

import 'package:pstream_android/config/app_config.dart';

class OmssSource {
  const OmssSource({
    required this.url,
    required this.type,
    required this.quality,
    required this.providerId,
    required this.providerName,
    this.audioTracks = const <OmssAudioTrack>[],
  });

  /// Absolute proxy URL (cinepro returns these already absolute).
  final String url;

  /// `"hls"` or `"mp4"`.
  final String type;

  /// Free-form quality label (e.g. `"1080p"`, `"720p"`, `"4K"`).
  final String? quality;

  /// Provider id from the cinepro catalog (one of the 14 built-ins).
  final String providerId;

  /// Human-readable provider name (e.g. `"VidSrc"`).
  final String providerName;

  final List<OmssAudioTrack> audioTracks;

  /// Resolved absolute URL. cinepro returns absolute URLs already;
  /// this guards against future relative paths by prefixing [AppConfig.oracleUrl].
  String get resolvedUrl => AppConfig.resolveOmssUrl(url);

  /// True if the source advertises an HLS playlist.
  bool get isHls => type == 'hls';

  /// True if the source is an iframe embed player (e.g. XPass) rather than a
  /// raw stream URL. Embed sources are rendered in a WebView, not video_player.
  bool get isEmbed => type == 'embed';

  factory OmssSource.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> provider = (json['provider'] is Map)
        ? Map<String, dynamic>.from(json['provider'] as Map)
        : const <String, dynamic>{};

    return OmssSource(
      url: _parseString(json['url']),
      type: _parseString(json['type']).toLowerCase(),
      quality: _parseOptionalString(json['quality']),
      providerId: _parseString(
        provider['id'] ?? json['providerId'] ?? json['provider_id'],
      ),
      providerName: _parseString(
        provider['name'] ?? json['providerName'] ?? json['provider_name'],
      ),
      audioTracks: ((json['audioTracks'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map e) => OmssAudioTrack.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }
}

class OmssAudioTrack {
  const OmssAudioTrack({required this.language, required this.label});

  /// BCP-47 primary language tag, e.g. `"en"`, `"es"`.
  final String? language;

  /// Free-form label, e.g. `"English"`.
  final String? label;

  factory OmssAudioTrack.fromJson(Map<String, dynamic> json) {
    return OmssAudioTrack(
      language: _parseOptionalString(json['language']),
      label: _parseOptionalString(json['label']),
    );
  }
}

class OmssSubtitle {
  const OmssSubtitle({
    required this.url,
    required this.label,
    required this.format,
  });

  final String url;
  final String? label;
  final String? format;

  /// Resolved absolute URL.
  String get resolvedUrl => AppConfig.resolveOmssUrl(url);

  factory OmssSubtitle.fromJson(Map<String, dynamic> json) {
    return OmssSubtitle(
      url: _parseString(json['url']),
      label: _parseOptionalString(json['label']),
      format: _parseOptionalString(json['format']),
    );
  }
}

class OmssResponse {
  const OmssResponse({
    required this.responseId,
    required this.expiresAt,
    required this.sources,
    required this.subtitles,
    required this.diagnostics,
  });

  final String? responseId;
  final DateTime? expiresAt;
  final List<OmssSource> sources;
  final List<OmssSubtitle> subtitles;
  final List<String> diagnostics;

  bool get isEmpty => sources.isEmpty;

  factory OmssResponse.fromJson(Map<String, dynamic> json) {
    final List<OmssSource> sources = ((json['sources'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((Map e) => OmssSource.fromJson(Map<String, dynamic>.from(e)))
        .where((OmssSource s) => s.url.isNotEmpty)
        .toList(growable: false);

    final List<OmssSubtitle> subtitles =
        ((json['subtitles'] as List?) ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map e) => OmssSubtitle.fromJson(Map<String, dynamic>.from(e)))
            .where((OmssSubtitle s) => s.url.isNotEmpty)
            .toList(growable: false);

    final List<String> diagnostics = ((json['diagnostics'] as List?) ??
            const <dynamic>[])
        .map((dynamic d) => '$d')
        .where((String d) => d.trim().isNotEmpty)
        .toList(growable: false);

    final String? expiresAtRaw = _parseOptionalString(json['expiresAt']);
    final DateTime? expiresAt = (expiresAtRaw == null)
        ? null
        : DateTime.tryParse(expiresAtRaw);

    return OmssResponse(
      responseId: _parseOptionalString(json['responseId']),
      expiresAt: expiresAt,
      sources: sources,
      subtitles: subtitles,
      diagnostics: diagnostics,
    );
  }
}

String _parseString(dynamic value) {
  return '$value'.trim();
}

String? _parseOptionalString(dynamic value) {
  if (value == null) {
    return null;
  }
  final String parsed = '$value'.trim();
  return parsed.isEmpty ? null : parsed;
}
