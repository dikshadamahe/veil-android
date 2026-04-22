import 'package:pstream_android/models/season.dart';

class MediaItem {
  const MediaItem({
    required this.tmdbId,
    required this.type,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.backdropPath,
    required this.year,
    required this.imdbId,
    required this.rating,
    required this.seasons,
    this.genres = const <MediaGenre>[],
    this.credits = const <MediaCredit>[],
    this.runtimeMins,
  });

  final int tmdbId;
  final String type;
  final String title;
  final String overview;
  final String? posterPath;
  final String? backdropPath;
  final int year;
  final String? imdbId;
  final double rating;
  final List<Season> seasons;
  final List<MediaGenre> genres;
  final List<MediaCredit> credits;
  final int? runtimeMins;

  bool get isMovie => type == 'movie';
  bool get isShow => type == 'show';

  factory MediaItem.fromTmdb(Map<String, dynamic> json) {
    final String type = _parseType(json);

    return MediaItem(
      tmdbId: _parseInt(json['id'] ?? json['tmdbId']),
      type: type,
      title: (json['title'] ?? json['name'] ?? '') as String,
      overview: (json['overview'] ?? '') as String,
      posterPath: _parseStringOrNull(
        json['poster_path'] ?? json['posterPath'] ?? json['poster'],
      ),
      backdropPath: _parseStringOrNull(
        json['backdrop_path'] ?? json['backdropPath'],
      ),
      year: _parseYear(
        json['release_date'] ??
            json['first_air_date'] ??
            json['air_date'] ??
            json['year'],
      ),
      imdbId: _parseStringOrNull(
        json['imdb_id'] ?? (json['external_ids'] as Map?)?['imdb_id'],
      ),
      rating: _parseDouble(json['vote_average'] ?? json['rating']),
      seasons: ((json['seasons'] as List?) ?? const <dynamic>[])
          .map((dynamic season) => Season.fromTmdb(_asMap(season)))
          .toList(),
      genres: ((json['genres'] as List?) ?? const <dynamic>[])
          .map((dynamic genre) => MediaGenre.fromJson(_asMap(genre)))
          .where((MediaGenre genre) => genre.name.isNotEmpty)
          .toList(),
      credits:
          ((((json['credits'] as Map?)?['cast']) as List?) ??
                  (json['credits'] as List?) ??
                  const <dynamic>[])
              .map((dynamic credit) => MediaCredit.fromJson(_asMap(credit)))
              .where((MediaCredit credit) => credit.name.isNotEmpty)
              .toList(),
      runtimeMins: _parseNullableInt(
        json['runtime'] ?? json['episode_run_time']?.first,
      ),
    );
  }

  String hiveKey() => '$type-$tmdbId';

  String? posterUrl([String size = 'w342']) {
    if (posterPath == null || posterPath!.isEmpty) {
      return null;
    }

    return 'https://image.tmdb.org/t/p/$size$posterPath';
  }

  String? backdropUrl([String size = 'original']) {
    if (backdropPath == null || backdropPath!.isEmpty) {
      return null;
    }

    return 'https://image.tmdb.org/t/p/$size$backdropPath';
  }

  Map<String, String> toScrapeQueryParameters({
    int? season,
    int? episode,
    List<String>? sourceOrder,
  }) {
    return <String, String>{
      'type': isShow ? 'tv' : 'movie',
      'tmdbId': '$tmdbId',
      'title': title,
      if (year > 0) 'year': '$year',
      if (season != null) 'season': '$season',
      if (episode != null) 'episode': '$episode',
      if (sourceOrder != null && sourceOrder.isNotEmpty)
        'sourceOrder': sourceOrder.join(','),
    };
  }

  static String _parseType(Map<String, dynamic> json) {
    final String rawType = '${json['media_type'] ?? json['type'] ?? ''}'
        .trim()
        .toLowerCase();
    if (rawType == 'tv' || rawType == 'show' || rawType == 'series') {
      return 'show';
    }
    if (rawType == 'movie') {
      return 'movie';
    }
    return json.containsKey('first_air_date') || json.containsKey('seasons')
        ? 'show'
        : 'movie';
  }

  static int _parseYear(dynamic value) {
    if (value is int) {
      return value;
    }

    final String text = '$value';
    if (text.length < 4) {
      return 0;
    }

    return int.tryParse(text.substring(0, 4)) ?? 0;
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value') ?? 0;
  }

  static int? _parseNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse('$value');
  }

  static double _parseDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }

  static String? _parseStringOrNull(dynamic value) {
    if (value == null) {
      return null;
    }

    final String parsed = '$value'.trim();
    return parsed.isEmpty ? null : parsed;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    return Map<String, dynamic>.from(
      value as Map? ?? const <String, dynamic>{},
    );
  }
}

class MediaGenre {
  const MediaGenre({required this.id, required this.name});

  final int id;
  final String name;

  factory MediaGenre.fromJson(Map<String, dynamic> json) {
    return MediaGenre(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      name: '${json['name'] ?? ''}'.trim(),
    );
  }
}

class MediaCredit {
  const MediaCredit({
    required this.id,
    required this.name,
    this.character,
    this.profilePath,
  });

  final int id;
  final String name;
  final String? character;
  final String? profilePath;

  factory MediaCredit.fromJson(Map<String, dynamic> json) {
    return MediaCredit(
      id: json['id'] is int
          ? json['id'] as int
          : int.tryParse('${json['id']}') ?? 0,
      name: '${json['name'] ?? ''}'.trim(),
      character: _parseStringOrNull(json['character']),
      profilePath: _parseStringOrNull(
        json['profile_path'] ?? json['profilePath'],
      ),
    );
  }

  String? profileUrl([String size = 'w185']) {
    if (profilePath == null || profilePath!.isEmpty) {
      return null;
    }
    return 'https://image.tmdb.org/t/p/$size$profilePath';
  }

  static String? _parseStringOrNull(dynamic value) {
    if (value == null) {
      return null;
    }

    final String parsed = '$value'.trim();
    return parsed.isEmpty ? null : parsed;
  }
}
