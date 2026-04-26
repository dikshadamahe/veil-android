import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/providers/storage_provider.dart';
import 'package:pstream_android/widgets/category_row.dart';
import 'package:pstream_android/widgets/media_card.dart';

/// Bookmarks + continue watching (Figma “download” → My list; no downloads).
class MyListScreen extends ConsumerWidget {
  const MyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<MediaItem> bookmarks = ref.watch(bookmarksProvider);
    final List<MediaItem> continueWatching = ref.watch(
      continueWatchingProvider,
    );
    final WindowClass layoutClass = windowClass(context);
    final double horizontal = switch (layoutClass) {
      WindowClass.compact => AppSpacing.x4,
      WindowClass.medium => AppSpacing.x5,
      WindowClass.expanded => AppSpacing.x6,
    };

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: SafeArea(
        child: bookmarks.isEmpty && continueWatching.isEmpty
            ? _MyListEmpty(horizontal: horizontal)
            : CustomScrollView(
                slivers: <Widget>[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      AppSpacing.x4,
                      horizontal,
                      AppSpacing.x2,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _MyListHeader(
                        onSearchTap: () => context.go('/search'),
                      ),
                    ),
                  ),
                  if (bookmarks.isNotEmpty)
                    SliverToBoxAdapter(
                      child: CategoryRow(
                        title: 'Favorites',
                        items: bookmarks,
                        useSectionAccent: true,
                      ),
                    ),
                  if (bookmarks.isNotEmpty)
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.x6),
                    ),
                  if (continueWatching.isNotEmpty)
                    SliverToBoxAdapter(
                      child: CategoryRow(
                        title: 'Continue watching',
                        items: continueWatching,
                        useSectionAccent: true,
                        cardBehavior: MediaCardBehavior.continueWatching,
                        onSeeAll: () => context.go('/'),
                      ),
                    ),
                  if (continueWatching.isNotEmpty)
                    const SliverToBoxAdapter(
                      child: SizedBox(height: AppSpacing.x6),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      AppSpacing.x2,
                      horizontal,
                      AppSpacing.x8,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Saved on this device only. Nothing is downloaded or hosted by Veil.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MyListHeader extends StatelessWidget {
  const _MyListHeader({required this.onSearchTap});

  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              Icons.bookmark_outline_rounded,
              color: AppColors.typeLogo,
              size: AppSpacing.x6,
            ),
            const SizedBox(width: AppSpacing.x2),
            Text(
              'My list',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.typeEmphasis,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x4),
        Material(
          color: AppColors.searchBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
            side: const BorderSide(color: AppColors.dropdownBorder),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
            onTap: onSearchTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x4,
                vertical: AppSpacing.x3,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.search_rounded,
                    color: AppColors.searchIcon,
                    size: AppSpacing.x5,
                  ),
                  const SizedBox(width: AppSpacing.x3),
                  Expanded(
                    child: Text(
                      'Search',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.searchPlaceholder,
                          ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.typeSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MyListEmpty extends StatelessWidget {
  const _MyListEmpty({required this.horizontal});

  final double horizontal;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        AppSpacing.x4,
        horizontal,
        AppSpacing.x6,
      ),
      children: <Widget>[
        _MyListHeader(onSearchTap: () => context.go('/search')),
        const SizedBox(height: AppSpacing.x8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.modalBackground,
                borderRadius: BorderRadius.circular(AppSpacing.x5),
                border: Border.all(color: AppColors.dropdownBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.x6),
                child: Column(
                  children: <Widget>[
                    Icon(
                      Icons.bookmark_add_outlined,
                      size: AppSpacing.x10,
                      color: AppColors.typeLogo,
                    ),
                    const SizedBox(height: AppSpacing.x4),
                    Text(
                      'Your list is empty',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Text(
                      'Bookmark titles from details to see them here. Continue watching appears when you start playback.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
