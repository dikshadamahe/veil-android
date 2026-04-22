class Episode {
  const Episode({
    required this.id,
    required this.number,
    required this.title,
    required this.airDate,
    required this.stillPath,
    required this.overview,
  });

  final String id;
  final int number;
  final String title;
  final String? airDate;
  final String? stillPath;
  final String overview;

  factory Episode.fromTmdb(Map<String, dynamic> json) {
    return Episode(
      id: '${json['id'] ?? ''}',
      number: _parseInt(json['episode_number'] ?? json['number']),
      title: (json['name'] ?? json['title'] ?? '') as String,
      airDate: _parseStringOrNull(json['air_date'] ?? json['airDate']),
      stillPath: _parseStringOrNull(json['still_path'] ?? json['stillPath']),
      overview: (json['overview'] ?? '') as String,
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value') ?? 0;
  }

  static String? _parseStringOrNull(dynamic value) {
    if (value == null) {
      return null;
    }

    final String parsed = '$value'.trim();
    return parsed.isEmpty ? null : parsed;
  }
}
