import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/providers/storage_provider.dart';
import 'package:pstream_android/providers/tmdb_provider.dart';
import 'package:pstream_android/widgets/category_row.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.hasTmdbReadToken) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundMain,
        body: SafeArea(
          child: _HomeMessageState(
            title: 'App setup is incomplete.',
            message:
                'This build is missing TMDB_TOKEN. Rebuild or re-release the app with the TMDB read access token configured in GitHub secrets.',
          ),
        ),
      );
    }

    final WindowClass layoutClass = windowClass(context);
    final double topPadding = switch (layoutClass) {
      WindowClass.compact => AppSpacing.x4,
      WindowClass.medium => AppSpacing.x5,
      WindowClass.expanded => AppSpacing.x6,
    };

    final AsyncValue<List<MediaItem>> trendingMovies = ref.watch(
      trendingMoviesProvider,
    );
    final AsyncValue<List<MediaItem>> trendingTv = ref.watch(
      trendingTVProvider,
    );
    final AsyncValue<List<MediaItem>> popular = ref.watch(
      popularMoviesProvider,
    );
    final List<MediaItem> continueWatching = ref.watch(
      continueWatchingProvider,
    );
    final List<MediaItem> bookmarks = ref.watch(bookmarksProvider);
    final Object? error =
        trendingMovies.error ?? trendingTv.error ?? popular.error;

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: topPadding, bottom: AppSpacing.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Veil',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppColors.typeEmphasis,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Container(
                      height: AppSpacing.x1,
                      width: AppSpacing.x10,
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                        gradient: LinearGradient(
                          colors: <Color>[
                            AppColors.purpleC300,
                            AppColors.purpleC100,
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.x5),
              if (error != null)
                _HomeMessageState(
                  title: 'Could not load the home feed.',
                  message: _friendlyMessage(error),
                )
              else if (trendingMovies.isLoading ||
                  trendingTv.isLoading ||
                  popular.isLoading)
                const _HomeLoadingState()
              else ...<Widget>[
                if (continueWatching.isNotEmpty) ...<Widget>[
                  CategoryRow(
                    title: 'Continue Watching',
                    items: continueWatching,
                  ),
                  const SizedBox(height: AppSpacing.x6),
                ],
                if (bookmarks.isNotEmpty) ...<Widget>[
                  CategoryRow(title: 'My List', items: bookmarks),
                  const SizedBox(height: AppSpacing.x6),
                ],
                if ((trendingMovies.value ?? const <MediaItem>[]).isNotEmpty)
                  CategoryRow(
                    title: 'Trending Movies',
                    items: trendingMovies.value ?? const <MediaItem>[],
                  ),
                if ((trendingMovies.value ?? const <MediaItem>[]).isNotEmpty)
                  const SizedBox(height: AppSpacing.x6),
                if ((trendingTv.value ?? const <MediaItem>[]).isNotEmpty)
                  CategoryRow(
                    title: 'Trending TV',
                    items: trendingTv.value ?? const <MediaItem>[],
                  ),
                if ((trendingTv.value ?? const <MediaItem>[]).isNotEmpty)
                  const SizedBox(height: AppSpacing.x6),
                if ((popular.value ?? const <MediaItem>[]).isNotEmpty)
                  CategoryRow(
                    title: 'Popular',
                    items: popular.value ?? const <MediaItem>[],
                  ),
                if ((trendingMovies.value ?? const <MediaItem>[]).isEmpty &&
                    (trendingTv.value ?? const <MediaItem>[]).isEmpty &&
                    (popular.value ?? const <MediaItem>[]).isEmpty)
                  const _HomeMessageState(
                    title: 'Nothing to show yet.',
                    message: 'Trending data came back empty.',
                  ),
              ],
            ],
          ),
        ),
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

class _HomeMessageState extends StatelessWidget {
  const _HomeMessageState({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.x4),
        decoration: BoxDecoration(
          color: AppColors.modalBackground,
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          border: Border.all(color: AppColors.dropdownBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.x2),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

String _friendlyMessage(Object error) {
  final String message = '$error';
  if (message.contains('TMDB authorization failed')) {
    return 'TMDB_TOKEN is invalid or expired in this build. Rebuild the app with the new read access token.';
  }
  if (message.contains('TimeoutException')) {
    return 'TMDB timed out on this network. The app now retries once, but if it still fails, rebuild with the new token and test again on a stable connection.';
  }
  return message;
}
