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
  });

  final String title;
  final List<MediaItem> items;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final double rowHeight = _heightFor(context);
    final int itemCount = isLoading ? _placeholderCount(context) : items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.typeEmphasis,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        SizedBox(
          height: rowHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
            itemCount: itemCount,
            itemBuilder: (BuildContext context, int index) {
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.x3),
                child: isLoading
                    ? const MediaCardSkeleton()
                    : MediaCard(mediaItem: items[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  double _heightFor(BuildContext context) {
    return switch (windowClass(context)) {
      WindowClass.compact => 230,
      WindowClass.medium => 265,
      WindowClass.expanded => 310,
    };
  }

  int _placeholderCount(BuildContext context) {
    return switch (windowClass(context)) {
      WindowClass.compact => 4,
      WindowClass.medium => 5,
      WindowClass.expanded => 6,
    };
  }
}
