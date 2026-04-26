import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/storage/local_storage.dart';

final storageRevisionProvider = StateProvider<int>((Ref ref) => 0);

final continueWatchingProvider = Provider<List<MediaItem>>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getContinueWatching()
      .map((Map<String, dynamic> item) => item['media'])
      .whereType<Map>()
      .map((Map<dynamic, dynamic> item) {
        return MediaItem.fromTmdb(Map<String, dynamic>.from(item));
      })
      .toList();
});

final bookmarksProvider = Provider<List<MediaItem>>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getAllBookmarks()
      .map(MediaItem.fromTmdb)
      .toList(growable: false);
});

final historyProvider = Provider<List<MediaItem>>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getHistory()
      .map((Map<String, dynamic> item) => item['media'])
      .whereType<Map>()
      .map((Map<dynamic, dynamic> item) {
        return MediaItem.fromTmdb(Map<String, dynamic>.from(item));
      })
      .toList(growable: false);
});

final bookmarkStatusProvider = Provider.family<bool, MediaItem>((
  Ref ref,
  MediaItem mediaItem,
) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.isBookmarked(mediaItem);
});

final progressEntryProvider =
    Provider.family<Map<String, dynamic>?, ProgressRequest>((
      Ref ref,
      ProgressRequest request,
    ) {
      ref.watch(storageRevisionProvider);
      return LocalStorage.getProgress(
        LocalStorage.mediaKey(
          request.mediaItem,
          season: request.season,
          episode: request.episode,
        ),
      );
    });

final latestEpisodeSelectionProvider =
    Provider.family<LatestEpisodeSelection?, MediaItem>((
      Ref ref,
      MediaItem mediaItem,
    ) {
      ref.watch(storageRevisionProvider);
      final Map<String, dynamic>? latest =
          LocalStorage.getLatestEpisodeProgress(mediaItem);
      final String? mediaKey = latest?['mediaKey'] as String?;
      if (mediaKey == null) {
        return null;
      }
      final EpisodeSelectionData? selection =
          LocalStorage.parseEpisodeSelection(mediaKey);
      if (selection == null) {
        return null;
      }
      return LatestEpisodeSelection(
        season: selection.season,
        episode: selection.episode,
      );
    });

final qualityCapPrefProvider = Provider<String>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getQualityCap();
});

final subtitlesDefaultOnPrefProvider = Provider<bool>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getSubtitlesDefaultOn();
});

final watchStatsProvider = Provider<WatchStats>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getWatchStats();
});

final subtitleSizePrefProvider = Provider<int>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getSubtitleSize();
});

final subtitleColorPrefProvider = Provider<String>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getSubtitleColor();
});

final subtitleBgOpacityPrefProvider = Provider<double>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getSubtitleBgOpacity();
});

final doubleTapSeekSecsPrefProvider = Provider<int>((Ref ref) {
  ref.watch(storageRevisionProvider);
  return LocalStorage.getDoubleTapSeekSecs();
});

final storageControllerProvider = Provider<StorageController>((Ref ref) {
  return StorageController(ref);
});

class StorageController {
  StorageController(this._ref);

  final Ref _ref;

  void _refresh() {
    _ref.read(storageRevisionProvider.notifier).state++;
  }

  Future<bool> toggleBookmark(MediaItem mediaItem) async {
    final bool result = await LocalStorage.toggleBookmark(mediaItem);
    _refresh();
    return result;
  }

  Future<void> clearBookmarks() async {
    await LocalStorage.clearBookmarks();
    _refresh();
  }

  Future<void> clearHistory() async {
    await Future.wait(<Future<void>>[
      LocalStorage.clearHistory(),
      LocalStorage.clearProgress(),
    ]);
    _refresh();
  }

  Future<void> setQualityCap(String value) async {
    await LocalStorage.setQualityCap(value);
    _refresh();
  }

  Future<void> setSubtitlesDefaultOn(bool value) async {
    await LocalStorage.setSubtitlesDefaultOn(value);
    _refresh();
  }

  Future<void> setSubtitleSize(int value) async {
    await LocalStorage.setSubtitleSize(value);
    _refresh();
  }

  Future<void> setSubtitleColor(String value) async {
    await LocalStorage.setSubtitleColor(value);
    _refresh();
  }

  Future<void> setSubtitleBgOpacity(double value) async {
    await LocalStorage.setSubtitleBgOpacity(value);
    _refresh();
  }

  Future<void> setDoubleTapSeekSecs(int value) async {
    await LocalStorage.setDoubleTapSeekSecs(value);
    _refresh();
  }

  Future<void> saveProgress(
    MediaItem mediaItem, {
    required int positionSecs,
    required int durationSecs,
    int? season,
    int? episode,
    bool refresh = true,
  }) async {
    await LocalStorage.saveProgress(
      LocalStorage.mediaKey(mediaItem, season: season, episode: episode),
      positionSecs,
      durationSecs,
      mediaItem,
    );
    if (refresh) {
      _refresh();
    }
  }
}

class ProgressRequest {
  const ProgressRequest({required this.mediaItem, this.season, this.episode});

  final MediaItem mediaItem;
  final int? season;
  final int? episode;

  @override
  bool operator ==(Object other) {
    return other is ProgressRequest &&
        other.mediaItem.hiveKey() == mediaItem.hiveKey() &&
        other.season == season &&
        other.episode == episode;
  }

  @override
  int get hashCode => Object.hash(mediaItem.hiveKey(), season, episode);
}

class LatestEpisodeSelection {
  const LatestEpisodeSelection({required this.season, required this.episode});

  final int season;
  final int episode;
}
