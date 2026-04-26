import 'package:flutter/material.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/widgets/media_card.dart';

class CategoryRow extends StatelessWidget {
  const CategoryRow({
    super.key,
    required this.title,
    required this.items,
    this.isLoading = false,
    this.onSeeAll,
    this.useSectionAccent = false,
    this.cardBehavior = MediaCardBehavior.detail,
  });

  final String title;
  final List<MediaItem> items;
  final bool isLoading;
  final VoidCallback? onSeeAll;
  final bool useSectionAccent;
  /// Forwarded to each [MediaCard] in the row. Continue-watching rows pass
  /// [MediaCardBehavior.continueWatching] so taps re-enter playback directly.
  final MediaCardBehavior cardBehavior;

  @override
  Widget build(BuildContext context) {
    final double rowHeight = _heightFor(context);
    final int itemCount = isLoading ? _placeholderCount(context) : items.length;
    final TextStyle? titleStyle = Theme.of(context).textTheme.titleLarge
        ?.copyWith(
          color: useSectionAccent ? AppColors.typeLogo : AppColors.typeEmphasis,
          fontWeight: FontWeight.w700,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(child: Text(title, style: titleStyle)),
              if (onSeeAll != null)
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.typeLink,
                  ),
                  onPressed: onSeeAll,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'See all',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: AppColors.typeLink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.x1),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: AppSpacing.x5,
                        color: AppColors.typeLink,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        SizedBox(
          height: rowHeight,
          // Each horizontal row gets its own layer — scrolling or rebuilds in
          // one row no longer trigger repaints of every other row above /
          // below it on the home page.
          child: RepaintBoundary(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
              itemCount: itemCount,
              itemBuilder: (BuildContext context, int index) {
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.x3),
                  child: isLoading
                      ? const MediaCardSkeleton()
                      : MediaCard(
                          mediaItem: items[index],
                          behavior: cardBehavior,
                        ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  double _heightFor(BuildContext context) {
    return MediaCard.cardHeightFor(context) + AppSpacing.x6;
  }

  int _placeholderCount(BuildContext context) {
    return switch (windowClass(context)) {
      WindowClass.compact => 4,
      WindowClass.medium => 5,
      WindowClass.expanded => 6,
    };
  }
}
