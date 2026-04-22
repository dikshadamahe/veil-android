import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/screens/detail_screen.dart';
import 'package:pstream_android/storage/local_storage.dart';
import 'package:shimmer/shimmer.dart';

class MediaCard extends StatelessWidget {
  const MediaCard({super.key, required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    final _MediaCardSize size = _cardSize(context);
    final Map<String, dynamic>? progress = LocalStorage.getProgress(
      LocalStorage.mediaKey(mediaItem),
    );
    final double progressRatio = _progressRatio(progress);
    final bool showProgress = progressRatio >= 0.05 && progressRatio <= 0.90;
    final bool isBookmarked = LocalStorage.isBookmarked(mediaItem);

    return RepaintBoundary(
      child: SizedBox(
        width: size.width,
        height: size.height + _titleAreaHeight,
        child: Material(
          color: Colors.transparent,
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

              if (GoRouter.maybeOf(context) case final GoRouter router) {
                router.push('/detail', extra: mediaItem);
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
                          child: mediaItem.posterUrl() == null
                              ? const _MediaCardPosterPlaceholder()
                              : CachedNetworkImage(
                                  imageUrl: mediaItem.posterUrl()!,
                                  fit: BoxFit.cover,
                                  placeholder: (_, __) =>
                                      const _MediaCardPosterPlaceholder(),
                                  errorWidget: (_, __, ___) =>
                                      const _MediaCardPosterPlaceholder(),
                                ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                Colors.transparent,
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
                          child: Text(
                            mediaItem.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: AppColors.typeEmphasis,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        if (showProgress)
                          Positioned(
                            left: AppSpacing.x3,
                            right: AppSpacing.x3,
                            bottom: AppSpacing.x3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppSpacing.x1,
                              ),
                              child: LinearProgressIndicator(
                                minHeight: AppSpacing.x1,
                                value: progressRatio.clamp(0.0, 1.0),
                                backgroundColor: AppColors.mediaCardBarColor,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.mediaCardBarFillColor,
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

  static const double _titleAreaHeight = 0;

  _MediaCardSize _cardSize(BuildContext context) {
    return switch (windowClass(context)) {
      WindowClass.compact => const _MediaCardSize(130, 195),
      WindowClass.medium => const _MediaCardSize(150, 225),
      WindowClass.expanded => const _MediaCardSize(180, 270),
    };
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
