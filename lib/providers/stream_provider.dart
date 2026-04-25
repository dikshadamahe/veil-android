import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/services/stream_service.dart';

final streamServiceProvider = Provider<StreamService>((Ref ref) {
  return const StreamService();
});

final scrapeStreamProvider =
    StreamProvider.family<ScrapeEvent, ScrapeRequest>((Ref ref, ScrapeRequest request) {
  return ref.read(streamServiceProvider).scrapeStream(
        request.mediaItem,
        season: request.season,
        episode: request.episode,
        seasonTmdbId: request.seasonTmdbId,
        episodeTmdbId: request.episodeTmdbId,
        seasonTitle: request.seasonTitle,
      );
});

class ScrapeRequest {
  const ScrapeRequest({
    required this.mediaItem,
    this.season,
    this.episode,
    this.seasonTmdbId,
    this.episodeTmdbId,
    this.seasonTitle,
  });

  final MediaItem mediaItem;
  final int? season;
  final int? episode;
  final String? seasonTmdbId;
  final String? episodeTmdbId;
  final String? seasonTitle;

  @override
  bool operator ==(Object other) {
    return other is ScrapeRequest &&
        other.mediaItem.hiveKey() == mediaItem.hiveKey() &&
        other.season == season &&
        other.episode == episode &&
        other.seasonTmdbId == seasonTmdbId &&
        other.episodeTmdbId == episodeTmdbId &&
        other.seasonTitle == seasonTitle;
  }

  @override
  int get hashCode => Object.hash(
        mediaItem.hiveKey(),
        season,
        episode,
        seasonTmdbId,
        episodeTmdbId,
        seasonTitle,
      );
}
