import 'package:flutter/material.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/services/tmdb_service.dart';
import 'package:pstream_android/storage/local_storage.dart';
import 'package:pstream_android/widgets/category_row.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.tmdbService = const TmdbService()});

  final TmdbService tmdbService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeSections> _sectionsFuture;

  @override
  void initState() {
    super.initState();
    _sectionsFuture = _loadSections();
  }

  Future<_HomeSections> _loadSections() async {
    final List<Map<String, dynamic>> continueWatching =
        LocalStorage.getContinueWatching();
    final List<Map<String, dynamic>> bookmarks = LocalStorage.getAllBookmarks();

    final List<MediaItem> trendingMovies = await widget.tmdbService.getTrending(
      'movie',
      'week',
    );
    final List<MediaItem> trendingTv = await widget.tmdbService.getTrending(
      'tv',
      'week',
    );
    final List<MediaItem> popular = await widget.tmdbService.getTrending(
      'movie',
      'day',
    );

    return _HomeSections(
      continueWatching: continueWatching
          .map(_mediaItemFromStoredProgress)
          .whereType<MediaItem>()
          .toList(),
      bookmarks: bookmarks
          .map(_mediaItemFromBookmark)
          .whereType<MediaItem>()
          .toList(),
      trendingMovies: trendingMovies,
      trendingTv: trendingTv,
      popular: popular,
    );
  }

  MediaItem? _mediaItemFromStoredProgress(Map<String, dynamic> item) {
    final dynamic media = item['media'];
    if (media is! Map) {
      return null;
    }
    return MediaItem.fromTmdb(Map<String, dynamic>.from(media));
  }

  MediaItem? _mediaItemFromBookmark(Map<String, dynamic> item) {
    return MediaItem.fromTmdb(item);
  }

  @override
  Widget build(BuildContext context) {
    final WindowClass layoutClass = windowClass(context);
    final double topPadding = switch (layoutClass) {
      WindowClass.compact => AppSpacing.x4,
      WindowClass.medium => AppSpacing.x5,
      WindowClass.expanded => AppSpacing.x6,
    };

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: FutureBuilder<_HomeSections>(
        future: _sectionsFuture,
        builder: (BuildContext context, AsyncSnapshot<_HomeSections> snapshot) {
          final bool isLoading =
              snapshot.connectionState != ConnectionState.done;
          final _HomeSections? data = snapshot.data;

          return SingleChildScrollView(
            padding: EdgeInsets.only(top: topPadding, bottom: AppSpacing.x6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.x4,
                  ),
                  child: Text(
                    'PStream',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.typeEmphasis,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.x5),
                if (isLoading)
                  const _HomeLoadingState()
                else ...<Widget>[
                  if ((data?.continueWatching.isNotEmpty ?? false)) ...<Widget>[
                    CategoryRow(
                      title: 'Continue Watching',
                      items: data!.continueWatching,
                    ),
                    const SizedBox(height: AppSpacing.x6),
                  ],
                  if ((data?.bookmarks.isNotEmpty ?? false)) ...<Widget>[
                    CategoryRow(title: 'My List', items: data!.bookmarks),
                    const SizedBox(height: AppSpacing.x6),
                  ],
                  CategoryRow(
                    title: 'Trending Movies',
                    items: data?.trendingMovies ?? const <MediaItem>[],
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  CategoryRow(
                    title: 'Trending TV',
                    items: data?.trendingTv ?? const <MediaItem>[],
                  ),
                  const SizedBox(height: AppSpacing.x6),
                  CategoryRow(
                    title: 'Popular',
                    items: data?.popular ?? const <MediaItem>[],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        CategoryRow(
          title: 'Continue Watching',
          items: <MediaItem>[],
          isLoading: true,
        ),
        SizedBox(height: AppSpacing.x6),
        CategoryRow(title: 'My List', items: <MediaItem>[], isLoading: true),
        SizedBox(height: AppSpacing.x6),
        CategoryRow(
          title: 'Trending Movies',
          items: <MediaItem>[],
          isLoading: true,
        ),
        SizedBox(height: AppSpacing.x6),
        CategoryRow(
          title: 'Trending TV',
          items: <MediaItem>[],
          isLoading: true,
        ),
        SizedBox(height: AppSpacing.x6),
        CategoryRow(title: 'Popular', items: <MediaItem>[], isLoading: true),
      ],
    );
  }
}

class _HomeSections {
  const _HomeSections({
    required this.continueWatching,
    required this.bookmarks,
    required this.trendingMovies,
    required this.trendingTv,
    required this.popular,
  });

  final List<MediaItem> continueWatching;
  final List<MediaItem> bookmarks;
  final List<MediaItem> trendingMovies;
  final List<MediaItem> trendingTv;
  final List<MediaItem> popular;
}
