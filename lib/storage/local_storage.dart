import 'dart:math' show max;

import 'package:hive_flutter/hive_flutter.dart';
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/media_item.dart';

class LocalStorage {
  LocalStorage._();

  static const String _bookmarksBoxName = 'bookmarks';
  static const String _progressBoxName = 'progress';
  static const String _watchHistoryBoxName = 'watch_history';
  static const String _prefsBoxName = 'prefs';
  static const double _historyRatioThreshold = 0.03;

  // Pref keys
  static const String prefKeyQualityCap = 'pref_quality_cap';
  static const String prefKeySubtitlesDefaultOn = 'pref_subtitles_default_on';
  static const String prefKeySubtitleSize = 'pref_subtitle_size';
  static const String prefKeySubtitleColor = 'pref_subtitle_color';
  static const String prefKeySubtitleBgOpacity = 'pref_subtitle_bg_opacity';
  static const String prefKeyDoubleTapSeekSecs = 'pref_double_tap_seek_secs';

  static const int doubleTapSeekDefaultSecs = 10;
  static const List<int> doubleTapSeekChoicesSecs = <int>[5, 10, 15, 30, 60];

  // Quality cap values
  static const String qualityCapAuto = 'auto';
  static const String qualityCap720 = '720p';
  static const String qualityCap1080 = '1080p';

  // Subtitle style: stored as 0-100 ints / hex strings so Hive doesn't have
  // to track type adapters. Defaults match a comfortable mobile baseline.
  static const int subtitleSizeDefault = 32; // media_kit `sub-font-size`
  static const String subtitleColorDefault = '#FFFFFFFF';
  static const double subtitleBgOpacityDefault = 0.5;

  static Future<void> init() async {
    await Hive.initFlutter();
    await Future.wait(<Future<Box<dynamic>>>[
      Hive.openBox<Map>(_bookmarksBoxName),
      Hive.openBox<Map>(_progressBoxName),
      Hive.openBox<Map>(_watchHistoryBoxName),
      Hive.openBox<dynamic>(_prefsBoxName),
    ]);
  }

  static Future<void> saveProgress(
    String mediaKey,
    int positionSecs,
    int durationSecs,
    MediaItem mediaItem,
  ) async {
    final DateTime now = DateTime.now().toUtc();
    final Map<String, dynamic>? existing = getProgress(mediaKey);
    final int prevDurationSecs = _readInt(existing?['durationSecs']);

    // HLS/DASH often reports a tiny or partial duration before the full run
    // is known. If we persist watchedRatio = position/duration in that window,
    // ratio hits ~1.0 and the title vanishes from Continue Watching.
    final bool durationSuspicious =
        durationSecs > 0 && positionSecs > durationSecs;
    final int storedDurationSecs = durationSuspicious
        ? max(prevDurationSecs, positionSecs + 1)
        : durationSecs;
    final double watchedRatio = durationSecs <= 0
        ? 0
        : durationSuspicious
            ? 0
            : (positionSecs / durationSecs).clamp(0.0, 1.0);

    final Map<String, dynamic> progressEntry = <String, dynamic>{
      'mediaKey': mediaKey,
      'positionSecs': positionSecs,
      'durationSecs': storedDurationSecs,
      'watchedRatio': watchedRatio,
      'updatedAt': now.toIso8601String(),
      'media': _mediaToMap(mediaItem),
    };

    await _progressBox.put(mediaKey, progressEntry);

    if (storedDurationSecs > 0 && watchedRatio >= _historyRatioThreshold) {
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
          final int positionSecs = item['positionSecs'] is num
              ? (item['positionSecs'] as num).toInt()
              : 0;
          // Any saved progress with at least a few seconds of playback and
          // not yet finished. Earlier ratio gate (3%) was too aggressive —
          // a 30-min episode needed ~54s before showing up here.
          return positionSecs >= 5 && ratio < AppConfig.watchedRatio;
        })
        .toList();

    items.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      return _readDateTime(
        b['updatedAt'],
      ).compareTo(_readDateTime(a['updatedAt']));
    });

    // Collapse multiple episode entries down to a single card per show
    // (movies are already 1:1). Keeps the latest entry — list above is
    // sorted by [updatedAt] desc so the first occurrence per show wins.
    final Map<String, Map<String, dynamic>> latestPerShow =
        <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> item in items) {
      final String groupKey = _showGroupKey(item);
      latestPerShow.putIfAbsent(groupKey, () => item);
    }
    return latestPerShow.values.toList(growable: false);
  }

  /// Group key for Continue Watching de-dup: show-level (`type-tmdbId`) for
  /// TV so all episodes of one series collapse, otherwise the entry's own
  /// `mediaKey`. Uses the stored `media` blob so we don't need to rebuild a
  /// [MediaItem] just to read `hiveKey()`.
  static String _showGroupKey(Map<String, dynamic> item) {
    final dynamic mediaRaw = item['media'];
    if (mediaRaw is Map) {
      final Map<String, dynamic> media = Map<String, dynamic>.from(mediaRaw);
      final String type = '${media['type'] ?? ''}';
      final dynamic tmdbId = media['tmdbId'] ?? media['id'];
      if (type.isNotEmpty && tmdbId != null) {
        return '$type-$tmdbId';
      }
    }
    return '${item['mediaKey'] ?? ''}';
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
  static Box<dynamic> get _prefsBox => Hive.box<dynamic>(_prefsBoxName);

  /// Default stream quality cap. One of [qualityCapAuto], [qualityCap720],
  /// [qualityCap1080]. Defaults to [qualityCapAuto] when unset.
  static String getQualityCap() {
    final dynamic raw = _prefsBox.get(prefKeyQualityCap);
    final String value = raw is String ? raw : qualityCapAuto;
    if (value != qualityCapAuto &&
        value != qualityCap720 &&
        value != qualityCap1080) {
      return qualityCapAuto;
    }
    return value;
  }

  static Future<void> setQualityCap(String value) async {
    await _prefsBox.put(prefKeyQualityCap, value);
  }

  /// Whether subtitles should turn on by default at the start of a stream
  /// when the source has captions available.
  static bool getSubtitlesDefaultOn() {
    final dynamic raw = _prefsBox.get(prefKeySubtitlesDefaultOn);
    return raw is bool ? raw : false;
  }

  static Future<void> setSubtitlesDefaultOn(bool value) async {
    await _prefsBox.put(prefKeySubtitlesDefaultOn, value);
  }

  /// Subtitle font size in points (media_kit `sub-font-size`). Range 16–56.
  static int getSubtitleSize() {
    final dynamic raw = _prefsBox.get(prefKeySubtitleSize);
    if (raw is int) {
      return raw.clamp(16, 56);
    }
    return subtitleSizeDefault;
  }

  static Future<void> setSubtitleSize(int value) async {
    await _prefsBox.put(prefKeySubtitleSize, value.clamp(16, 56));
  }

  /// Subtitle text color, stored as `#AARRGGBB` hex string.
  static String getSubtitleColor() {
    final dynamic raw = _prefsBox.get(prefKeySubtitleColor);
    if (raw is String && raw.startsWith('#') && raw.length == 9) {
      return raw;
    }
    return subtitleColorDefault;
  }

  static Future<void> setSubtitleColor(String value) async {
    await _prefsBox.put(prefKeySubtitleColor, value);
  }

  /// Subtitle background opacity, 0.0..1.0.
  static double getSubtitleBgOpacity() {
    final dynamic raw = _prefsBox.get(prefKeySubtitleBgOpacity);
    if (raw is num) {
      return raw.toDouble().clamp(0.0, 1.0);
    }
    return subtitleBgOpacityDefault;
  }

  static Future<void> setSubtitleBgOpacity(double value) async {
    await _prefsBox.put(
      prefKeySubtitleBgOpacity,
      value.clamp(0.0, 1.0),
    );
  }

  /// Seek interval (in seconds) when the user double-taps the player. Stored
  /// as an int so the picker in Settings round-trips cleanly. Falls back to
  /// [doubleTapSeekDefaultSecs] when unset or out of range.
  static int getDoubleTapSeekSecs() {
    final dynamic raw = _prefsBox.get(prefKeyDoubleTapSeekSecs);
    if (raw is int && doubleTapSeekChoicesSecs.contains(raw)) {
      return raw;
    }
    return doubleTapSeekDefaultSecs;
  }

  static Future<void> setDoubleTapSeekSecs(int value) async {
    final int safe = doubleTapSeekChoicesSecs.contains(value)
        ? value
        : doubleTapSeekDefaultSecs;
    await _prefsBox.put(prefKeyDoubleTapSeekSecs, safe);
  }

  /// Aggregate watch statistics derived from existing boxes; no extra Hive
  /// schema needed.
  static WatchStats getWatchStats() {
    final List<Map<String, dynamic>> progressEntries = _progressBox.values
        .whereType<Map>()
        .map((Map<dynamic, dynamic> value) => Map<String, dynamic>.from(value))
        .toList();

    int totalWatchedSecs = 0;
    int finishedTitles = 0;
    int inProgressTitles = 0;

    for (final Map<String, dynamic> entry in progressEntries) {
      final int positionSecs = _readInt(entry['positionSecs']);
      final double ratio = _readDouble(entry['watchedRatio']);
      totalWatchedSecs += positionSecs;
      if (ratio >= AppConfig.watchedRatio) {
        finishedTitles += 1;
      } else if (ratio >= 0.03) {
        inProgressTitles += 1;
      }
    }

    return WatchStats(
      finishedTitles: finishedTitles,
      inProgressTitles: inProgressTitles,
      totalWatchedSecs: totalWatchedSecs,
      historyEntries: _watchHistoryBox.length,
      bookmarks: _bookmarksBox.length,
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value') ?? 0;
  }

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

/// Aggregate watch numbers shown in the Watch statistics screen.
class WatchStats {
  const WatchStats({
    required this.finishedTitles,
    required this.inProgressTitles,
    required this.totalWatchedSecs,
    required this.historyEntries,
    required this.bookmarks,
  });

  final int finishedTitles;
  final int inProgressTitles;
  final int totalWatchedSecs;
  final int historyEntries;
  final int bookmarks;

  Duration get totalWatched => Duration(seconds: totalWatchedSecs);
}
