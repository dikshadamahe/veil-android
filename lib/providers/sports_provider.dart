import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/models/match_stream.dart';
import 'package:pstream_android/models/sport_category.dart';
import 'package:pstream_android/models/sports_match.dart';
import 'package:pstream_android/services/sports_service.dart';

final sportsServiceProvider = Provider<SportsService>(
  (_) => const SportsService(),
);

/// Available sport categories (`/v1/sports`).
final sportsCatalogProvider = FutureProvider<List<SportCategory>>((ref) async {
  return ref.read(sportsServiceProvider).fetchSports();
});

/// Matches for a given path key (`live`, `all-today`, `all`, or a sport id).
final matchesProvider =
    FutureProvider.family<List<SportsMatch>, String>((ref, pathKey) async {
  return ref.read(sportsServiceProvider).fetchMatches(pathKey);
});

/// Currently live matches (`/v1/matches/live`).
final liveMatchesProvider = FutureProvider<List<SportsMatch>>((ref) async {
  return ref.read(sportsServiceProvider).fetchMatches('live');
});

/// Set of match ids that are live right now, for cross-referencing LIVE badges
/// in non-live views. Resolves to an empty set until the live list loads.
final liveMatchIdsProvider = Provider<Set<String>>((ref) {
  final AsyncValue<List<SportsMatch>> live = ref.watch(liveMatchesProvider);
  return live.asData?.value
          .map((SportsMatch m) => m.id)
          .toSet() ??
      const <String>{};
});

/// Streams for one `{source, id}` pair (`/v1/stream/:source/:id`).
final matchStreamsProvider =
    FutureProvider.family<List<MatchStream>, MatchStreamKey>((ref, key) async {
  return ref.read(sportsServiceProvider).fetchStreams(key.source, key.id);
});

/// Equatable key for [matchStreamsProvider].
class MatchStreamKey {
  const MatchStreamKey({required this.source, required this.id});

  final String source;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is MatchStreamKey && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);
}
