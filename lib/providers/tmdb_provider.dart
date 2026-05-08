import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/models/episode.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/services/tmdb_service.dart';

final tmdbServiceProvider = Provider<TmdbService>((Ref ref) {
  return const TmdbService();
});

final trendingMoviesProvider = FutureProvider<List<MediaItem>>((Ref ref) {
  return ref.read(tmdbServiceProvider).getTrending('movie', 'week');
});

final popularMoviesProvider = FutureProvider<List<MediaItem>>((Ref ref) {
  return ref.read(tmdbServiceProvider).getTrending('movie', 'day');
});

final trendingTVProvider = FutureProvider<List<MediaItem>>((Ref ref) {
  return ref.read(tmdbServiceProvider).getTrending('tv', 'week');
});

final searchProvider = FutureProvider.family<List<MediaItem>, String>((
  Ref ref,
  String query,
) {
  return ref.read(tmdbServiceProvider).search(query);
});

final detailProvider = FutureProvider.family<MediaItem, DetailRequest>((
  Ref ref,
  DetailRequest request,
) {
  return ref.read(tmdbServiceProvider).getDetails(
        request.id,
        request.type,
        fallback: request.fallback,
      );
});

final seasonEpisodesProvider =
    FutureProvider.family<List<Episode>, SeasonEpisodesRequest>((
      Ref ref,
      SeasonEpisodesRequest request,
    ) {
      return ref
          .read(tmdbServiceProvider)
          .getSeasonEpisodes(request.showId, request.seasonNum);
    });

class DetailRequest {
  const DetailRequest({
    required this.id,
    required this.type,
    this.fallback,
  });

  final int id;
  final String type;
  final MediaItem? fallback;

  @override
  bool operator ==(Object other) {
    return other is DetailRequest &&
        other.id == id &&
        other.type == type &&
        other.fallback?.hiveKey() == fallback?.hiveKey();
  }

  @override
  int get hashCode => Object.hash(id, type, fallback?.hiveKey());
}

class SeasonEpisodesRequest {
  const SeasonEpisodesRequest({required this.showId, required this.seasonNum});

  final int showId;
  final int seasonNum;

  @override
  bool operator ==(Object other) {
    return other is SeasonEpisodesRequest &&
        other.showId == showId &&
        other.seasonNum == seasonNum;
  }

  @override
  int get hashCode => Object.hash(showId, seasonNum);
}
