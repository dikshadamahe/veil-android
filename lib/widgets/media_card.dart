import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/providers/storage_provider.dart';
import 'package:pstream_android/screens/detail_screen.dart';
import 'package:pstream_android/screens/scraping_screen.dart';
import 'package:shimmer/shimmer.dart';

/// What happens when [MediaCard] is tapped. [detail] (default) opens the
/// title's detail page; [continueWatching] skips detail and re-enters the
/// scrape/play flow with the saved resume position.
enum MediaCardBehavior { detail, continueWatching }

class MediaCard extends ConsumerWidget {
  const MediaCard({
    super.key,
    required this.mediaItem,
    this.posterSize = 'w342',
    this.behavior = MediaCardBehavior.detail,
  });

  final MediaItem mediaItem;
  final String posterSize;
  final MediaCardBehavior behavior;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final _MediaCardSize size = _cardSize(context);

    // For TV, show & progress live at the episode level. Look up the latest
    // episode the user touched, then use that episode's progress so the
    // Continue Watching tile (and progress bar) tracks "S{n}E{m}" instead
    // of an always-empty show-level entry.
    final LatestEpisodeSelection? latestEpisode = mediaItem.isShow
        ? ref.watch(latestEpisodeSelectionProvider(mediaItem))
        : null;
    final Map<String, dynamic>? progress = ref.watch(
      progressEntryProvider(
        ProgressRequest(
          mediaItem: mediaItem,
          season: latestEpisode?.season,
          episode: latestEpisode?.episode,
        ),
      ),
    );
    final double progressRatio = _progressRatio(progress);
    final bool showProgress = progressRatio >= 0.05 && progressRatio <= 0.90;
    final bool isBookmarked = ref.watch(bookmarkStatusProvider(mediaItem));
    final String? episodeBadge = latestEpisode == null
        ? null
        : 'S${latestEpisode.season} E${latestEpisode.episode}';

    return RepaintBoundary(
      child: SizedBox(
        width: size.width,
        height: size.height + _titleAreaHeight,
        child: Material(
          color: AppColors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.x4),
            splashColor: AppColors.mediaCardHoverAccent.withValues(alpha: 0.35),
            highlightColor: AppColors.mediaCardHoverBackground.withValues(
              alpha: 0.35,
            ),
            onTap: () async {
              await HapticFeedback.lightImpact();
              if (!context.mounted) {
                return;
              }

              if (behavior == MediaCardBehavior.continueWatching) {
                _continueWatchingTap(context, ref, latestEpisode, progress);
                return;
              }

              if (GoRouter.maybeOf(context) case final GoRouter router) {
                router.push('/detail/${mediaItem.tmdbId}', extra: mediaItem);
                return;
              }

              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DetailScreen(mediaItem: mediaItem),
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.x4),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        ColoredBox(
                          color: AppColors.mediaCardHoverBackground,
                          child: Hero(
                            tag: 'poster-${mediaItem.tmdbId}',
                            child: mediaItem.posterUrl() == null
                                ? const _MediaCardPosterPlaceholder()
                                : CachedNetworkImage(
                                    imageUrl: mediaItem.posterUrl(posterSize)!,
                                    fit: BoxFit.cover,
                                    placeholder: (_, placeholderUrl) =>
                                        const _MediaCardPosterPlaceholder(),
                                    errorWidget: (_, error, stackTrace) =>
                                        const _MediaCardPosterPlaceholder(),
                                  ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                AppColors.transparent,
                                AppColors.transparent,
                                AppColors.blackC50,
                              ],
                              stops: <double>[0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                        if (isBookmarked)
                          const Positioned(
                            top: AppSpacing.x3,
                            right: AppSpacing.x3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: AppColors.purpleC100,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox.square(dimension: AppSpacing.x3),
                            ),
                          ),
                        Positioned(
                          left: AppSpacing.x3,
                          right: AppSpacing.x3,
                          bottom: showProgress ? AppSpacing.x5 : AppSpacing.x3,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                mediaItem.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: AppColors.typeEmphasis,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              if (episodeBadge != null) ...<Widget>[
                                const SizedBox(height: AppSpacing.x1),
                                Text(
                                  episodeBadge,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: AppColors.typeEmphasis
                                            .withValues(alpha: 0.85),
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (showProgress)
                          Positioned(
                            left: AppSpacing.x3,
                            right: AppSpacing.x3,
                            bottom: AppSpacing.x3,
                            child: RepaintBoundary(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.x1,
                                ),
                                child: LinearProgressIndicator(
                                  minHeight: AppSpacing.x1,
                                  value: progressRatio.clamp(0.0, 1.0),
                                  backgroundColor: AppColors.mediaCardBarColor,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        AppColors.mediaCardBarFillColor,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Re-enter the scrape→player flow at the saved position. Movies use the
  /// title's progress directly; TV uses [latestEpisode] season/episode and
  /// that episode's progress. No detail page in between.
  void _continueWatchingTap(
    BuildContext context,
    WidgetRef ref,
    LatestEpisodeSelection? latestEpisode,
    Map<String, dynamic>? progress,
  ) {
    final int? resumeFromSecs = (progress?['positionSecs'] as num?)?.toInt();

    final ScrapingScreenArgs args = ScrapingScreenArgs(
      mediaItem: mediaItem,
      season: latestEpisode?.season,
      episode: latestEpisode?.episode,
      // seasonTmdbId / episodeTmdbId / seasonTitle: server has sane defaults
      // when these are null (`Season N`, `${tmdb}-s${n}-e${m}`), so skipping
      // the TMDB detail fetch here keeps the tap instant.
      resumeFrom: resumeFromSecs,
    );

    if (GoRouter.maybeOf(context) case final GoRouter router) {
      router.push('/scraping', extra: args);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScrapingScreen(
          mediaItem: args.mediaItem,
          season: args.season,
          episode: args.episode,
          resumeFrom: args.resumeFrom,
        ),
      ),
    );
  }

  static const double _titleAreaHeight = AppSpacing.x0;

  static double cardHeightFor(BuildContext context) {
    return _cardSize(context).height;
  }

  static _MediaCardSize _cardSize(BuildContext context) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final double width = switch (windowClass(context)) {
      WindowClass.compact => screenWidth * 0.34,
      WindowClass.medium => screenWidth * 0.22,
      WindowClass.expanded => screenWidth * 0.16,
    };
    return _MediaCardSize(width, width * _posterAspectHeight);
  }

  static const double _posterAspectHeight = 1.5;
}

double _progressRatio(Map<String, dynamic>? progress) {
  if (progress == null) {
    return 0;
  }

  final dynamic cachedRatio = progress['watchedRatio'];
  if (cachedRatio is num) {
    return cachedRatio.toDouble();
  }

  final int position = int.tryParse('${progress['positionSecs']}') ?? 0;
  final int duration = int.tryParse('${progress['durationSecs']}') ?? 0;
  if (duration <= 0) {
    return 0;
  }

  return position / duration;
}

class _MediaCardPosterPlaceholder extends StatelessWidget {
  const _MediaCardPosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.mediaCardHoverBackground,
      highlightColor: AppColors.mediaCardHoverAccent,
      child: const ColoredBox(color: AppColors.mediaCardHoverBackground),
    );
  }
}

class _MediaCardSize {
  const _MediaCardSize(this.width, this.height);

  final double width;
  final double height;
}

class MediaCardSkeleton extends StatelessWidget {
  const MediaCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final _MediaCardSize size = MediaCard._cardSize(context);

    return SizedBox(
      width: size.width,
      height: size.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        child: Shimmer.fromColors(
          baseColor: AppColors.mediaCardHoverBackground,
          highlightColor: AppColors.mediaCardHoverAccent,
          child: const ColoredBox(color: AppColors.mediaCardHoverBackground),
        ),
      ),
    );
  }
}
