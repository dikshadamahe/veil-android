import 'package:pstream_android/config/app_config.dart';

/// A sports event from the `veil-streamed-sports` proxy
/// (streamed.pk `/api/matches/...`).
///
/// Upstream shape (`APIMatch`):
/// ```json
/// {
///   "id": "france-vs-morocco-2515305",
///   "title": "France vs Morocco",
///   "category": "football",
///   "date": 1783627200000,
///   "poster": "/api/images/proxy/....webp",
///   "popular": true,
///   "teams": { "home": {"name","badge"}, "away": {"name","badge"} },
///   "sources": [ {"source":"echo","id":"..."}, ... ]
/// }
/// ```
class SportsMatch {
  const SportsMatch({
    required this.id,
    required this.title,
    required this.category,
    required this.date,
    required this.posterPath,
    required this.popular,
    required this.home,
    required this.away,
    required this.sources,
  });

  final String id;
  final String title;

  /// Sport id (e.g. `"football"`).
  final String category;

  /// Scheduled kickoff/tip-off; null when upstream omits it.
  final DateTime? date;

  /// Raw upstream poster path (e.g. `/api/images/proxy/....webp`).
  final String? posterPath;

  final bool popular;
  final MatchTeam? home;
  final MatchTeam? away;

  /// Playable sources — each yields streams via `GET /v1/stream/:source/:id`.
  final List<MatchSource> sources;

  /// Absolute poster URL routed through the proxy's `/v1/images/*`, or null.
  String? get posterUrl => resolveSportsImageUrl(posterPath);

  bool get hasSources => sources.isNotEmpty;

  /// True once the scheduled start time has passed (used as a soft "live" hint
  /// when the match is not cross-referenced against the live endpoint).
  bool get hasStarted {
    final DateTime? d = date;
    if (d == null) {
      return false;
    }
    return DateTime.now().isAfter(d);
  }

  factory SportsMatch.fromJson(Map<String, dynamic> json) {
    final Object? rawTeams = json['teams'];
    final Map<String, dynamic> teams = rawTeams is Map
        ? Map<String, dynamic>.from(rawTeams)
        : const <String, dynamic>{};

    final int? ms = (json['date'] is num) ? (json['date'] as num).toInt() : null;

    return SportsMatch(
      id: '${json['id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      category: '${json['category'] ?? ''}',
      date: (ms == null || ms <= 0)
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms),
      posterPath: _optionalString(json['poster']),
      popular: json['popular'] == true,
      home: _parseTeam(teams['home']),
      away: _parseTeam(teams['away']),
      sources: ((json['sources'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((Map e) => MatchSource.fromJson(Map<String, dynamic>.from(e)))
          .where((MatchSource s) => s.source.isNotEmpty && s.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  static MatchTeam? _parseTeam(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final MatchTeam team = MatchTeam.fromJson(Map<String, dynamic>.from(raw));
    return team.name.isEmpty ? null : team;
  }
}

/// One side of a match. `badge` is an image id resolved via `/v1/images/badge`.
class MatchTeam {
  const MatchTeam({required this.name, required this.badge});

  final String name;
  final String? badge;

  /// Absolute badge URL routed through the proxy, or null when absent.
  String? get badgeUrl {
    final String? b = badge;
    if (b == null || b.isEmpty) {
      return null;
    }
    return '${AppConfig.sportsApiUrl}/v1/images/badge/$b.webp';
  }

  factory MatchTeam.fromJson(Map<String, dynamic> json) => MatchTeam(
        name: '${json['name'] ?? ''}',
        badge: _optionalString(json['badge']),
      );
}

/// A `{source, id}` pair used to request streams for a match.
class MatchSource {
  const MatchSource({required this.source, required this.id});

  /// Provider identifier (e.g. `"alpha"`, `"echo"`, `"admin"`).
  final String source;

  /// Source-specific match id.
  final String id;

  factory MatchSource.fromJson(Map<String, dynamic> json) => MatchSource(
        source: '${json['source'] ?? ''}',
        id: '${json['id'] ?? ''}',
      );
}

/// Resolves a raw streamed.pk image path to an absolute proxy URL.
///
/// - `/api/images/...`  → `{SPORTS_URL}/v1/images/...`
/// - `/v1/images/...`   → `{SPORTS_URL}/v1/images/...`
/// - absolute `http...`  → unchanged
/// - anything else       → null (no known path)
String? resolveSportsImageUrl(String? path) {
  if (path == null) {
    return null;
  }
  final String trimmed = path.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final String base = AppConfig.sportsApiUrl;
  if (trimmed.startsWith('/api/images/')) {
    return '$base/v1${trimmed.substring(4)}';
  }
  if (trimmed.startsWith('/v1/images/')) {
    return '$base$trimmed';
  }
  return null;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  final String parsed = '$value'.trim();
  return parsed.isEmpty ? null : parsed;
}
