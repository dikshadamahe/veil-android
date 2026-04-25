import 'package:hive_flutter/hive_flutter.dart';
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/media_item.dart';

class LocalStorage {
  LocalStorage._();

  static const String _bookmarksBoxName = 'bookmarks';
  static const String _progressBoxName = 'progress';
  static const String _watchHistoryBoxName = 'watch_history';
  static const double _historyRatioThreshold = 0.03;

  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait(<Future<Box<dynamic>>>[
      Hive.openBox<Map>(_bookmarksBoxName),
      Hive.openBox<Map>(_progressBoxName),
      Hive.openBox<Map>(_watchHistoryBoxName),
    ]);
  }

  static Future<void> saveProgress(
    String mediaKey,
    int positionSecs,
    int durationSecs,
    MediaItem mediaItem,
  ) async {
    final DateTime now = DateTime.now().toUtc();
    final double watchedRatio = durationSecs > 0
        ? positionSecs / durationSecs
        : 0;
    final Map<String, dynamic> progressEntry = <String, dynamic>{
      'mediaKey': mediaKey,
      'positionSecs': positionSecs,
      'durationSecs': durationSecs,
      'watchedRatio': watchedRatio,
      'updatedAt': now.toIso8601String(),
      'media': _mediaToMap(mediaItem),
    };

    await _progressBox.put(mediaKey, progressEntry);

    if (durationSecs > 0 && watchedRatio >= _historyRatioThreshold) {
      await _watchHistoryBox.put(mediaKey, <String, dynamic>{
        'mediaKey': mediaKey,
        'watchedAt': now.toIso8601String(),
        'media': _mediaToMap(mediaItem),
      });
    }
  }

  static Map<String, dynamic>? getProgress(String mediaKey) {
    final dynamic value = _progressBox.get(mediaKey);
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  static List<Map<String, dynamic>> getContinueWatching() {
    final List<Map<String, dynamic>> items = _progressBox.values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> value) => Map<String, dynamic>.from(value))
        .where((Map<String, dynamic> item) {
          final double ratio = _readDouble(item['watchedRatio']);
          return ratio >= 0.03 && ratio <= AppConfig.watchedRatio;
        })
        .toList();

    items.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      return _readDateTime(
        b['updatedAt'],
      ).compareTo(_readDateTime(a['updatedAt']));
    });

    return items;
  }

  static Future<bool> toggleBookmark(MediaItem mediaItem) async {
    final String key = mediaKey(mediaItem);
    if (_bookmarksBox.containsKey(key)) {
      await _bookmarksBox.delete(key);
      return false;
    }

    await _bookmarksBox.put(key, <String, dynamic>{
      ..._mediaToMap(mediaItem),
      'mediaKey': key,
      'bookmarkedAt': DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  }

  static bool isBookmarked(MediaItem mediaItem) {
    return _bookmarksBox.containsKey(mediaKey(mediaItem));
  }

  static List<Map<String, dynamic>> getAllBookmarks() {
    final List<Map<String, dynamic>> items = _bookmarksBox.values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> value) => Map<String, dynamic>.from(value))
        .toList();

    items.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      return _readDateTime(
        b['bookmarkedAt'],
      ).compareTo(_readDateTime(a['bookmarkedAt']));
    });

    return items;
  }

  static Future<void> addToHistory(MediaItem mediaItem) async {
    final String key = mediaKey(mediaItem);
    await _watchHistoryBox.put(key, <String, dynamic>{
      'mediaKey': key,
      'watchedAt': DateTime.now().toUtc().toIso8601String(),
      'media': _mediaToMap(mediaItem),
    });
  }

  static List<Map<String, dynamic>> getHistory() {
    final List<Map<String, dynamic>> items = _watchHistoryBox.values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> value) => Map<String, dynamic>.from(value))
        .toList();

    items.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      return _readDateTime(
        b['watchedAt'],
      ).compareTo(_readDateTime(a['watchedAt']));
    });

    return items;
  }

  static Future<void> clearProgress() async {
    await _progressBox.clear();
  }

  static Future<void> clearBookmarks() async {
    await _bookmarksBox.clear();
  }

  static Future<void> clearHistory() async {
    await _watchHistoryBox.clear();
  }

  static List<Map<String, dynamic>> getEpisodeProgressEntries(
    MediaItem mediaItem,
  ) {
    final String prefix = '${mediaItem.hiveKey()}-s';
    final List<Map<String, dynamic>> items = _progressBox.values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> value) => Map<String, dynamic>.from(value))
        .where((Map<String, dynamic> item) {
          final String mediaKey = '${item['mediaKey'] ?? ''}';
          return mediaKey.startsWith(prefix);
        })
        .toList();

    items.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      return _readDateTime(
        b['updatedAt'],
      ).compareTo(_readDateTime(a['updatedAt']));
    });

    return items;
  }

  static Map<String, dynamic>? getLatestEpisodeProgress(MediaItem mediaItem) {
    final List<Map<String, dynamic>> items = getEpisodeProgressEntries(
      mediaItem,
    );
    return items.isEmpty ? null : items.first;
  }

  static String mediaKey(MediaItem mediaItem, {int? season, int? episode}) {
    final String baseKey = mediaItem.hiveKey();
    if (season != null && episode != null) {
      return '$baseKey-s${season}e$episode';
    }
    return baseKey;
  }

  static EpisodeSelectionData? parseEpisodeSelection(String mediaKey) {
    final RegExpMatch? match = RegExp(r'-s(\d+)e(\d+)$').firstMatch(mediaKey);
    if (match == null) {
      return null;
    }

    final int? season = int.tryParse(match.group(1)!);
    final int? episode = int.tryParse(match.group(2)!);
    if (season == null || episode == null) {
      return null;
    }

    return EpisodeSelectionData(season: season, episode: episode);
  }

  static Box<Map> get _bookmarksBox => Hive.box<Map>(_bookmarksBoxName);
  static Box<Map> get _progressBox => Hive.box<Map>(_progressBoxName);
  static Box<Map> get _watchHistoryBox => Hive.box<Map>(_watchHistoryBoxName);

  static Map<String, dynamic> _mediaToMap(MediaItem mediaItem) {
    return <String, dynamic>{
      'tmdbId': mediaItem.tmdbId,
      'type': mediaItem.type,
      'title': mediaItem.title,
      'overview': mediaItem.overview,
      'posterPath': mediaItem.posterPath,
      'backdropPath': mediaItem.backdropPath,
      'year': mediaItem.year,
      'imdbId': mediaItem.imdbId,
      'rating': mediaItem.rating,
      'runtimeMins': mediaItem.runtimeMins,
      'genres': mediaItem.genres
          .map((genre) => <String, dynamic>{'id': genre.id, 'name': genre.name})
          .toList(),
      'credits': mediaItem.credits
          .map(
            (credit) => <String, dynamic>{
              'id': credit.id,
              'name': credit.name,
              'character': credit.character,
              'profilePath': credit.profilePath,
            },
          )
          .toList(),
      'seasons': mediaItem.seasons
          .map(
            (season) => <String, dynamic>{
              'id': season.id,
              'number': season.number,
              'title': season.title,
              'episodes': season.episodes
                  .map(
                    (episode) => <String, dynamic>{
                      'id': episode.id,
                      'number': episode.number,
                      'title': episode.title,
                      'airDate': episode.airDate,
                      'stillPath': episode.stillPath,
                      'overview': episode.overview,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };
  }

  static DateTime _readDateTime(dynamic value) {
    return DateTime.tryParse('$value') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  static double _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }
}

class EpisodeSelectionData {
  const EpisodeSelectionData({required this.season, required this.episode});

  final int season;
  final int episode;
}
