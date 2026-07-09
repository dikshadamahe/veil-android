import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/sport_category.dart';
import 'package:pstream_android/models/sports_match.dart';
import 'package:pstream_android/providers/sports_provider.dart';
import 'package:pstream_android/widgets/match_card.dart';

/// Sports live-matches browse screen: a filterable grid of matches whose
/// streams open as iframe embeds in a WebView.
class SportsScreen extends ConsumerStatefulWidget {
  const SportsScreen({super.key});

  @override
  ConsumerState<SportsScreen> createState() => _SportsScreenState();
}

class _SportsScreenState extends ConsumerState<SportsScreen> {
  /// Selected match path key (`live`, `all-today`, `all`, or a sport id).
  String _selectedKey = 'live';

  static const List<_SportsFilter> _staticFilters = <_SportsFilter>[
    _SportsFilter(key: 'live', label: 'Live'),
    _SportsFilter(key: 'all-today', label: 'Today'),
    _SportsFilter(key: 'all', label: 'All'),
  ];

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<SportsMatch>> matchesAsync =
        ref.watch(matchesProvider(_selectedKey));
    final AsyncValue<List<SportCategory>> catalogAsync =
        ref.watch(sportsCatalogProvider);
    final Set<String> liveIds = ref.watch(liveMatchIdsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(liveMatchesProvider);
          ref.invalidate(matchesProvider(_selectedKey));
          await ref.read(matchesProvider(_selectedKey).future);
        },
        child: CustomScrollView(
          slivers: <Widget>[
            const SliverAppBar(
              pinned: true,
              title: Text('Sports'),
            ),
            SliverToBoxAdapter(
              child: _FilterBar(
                filters: _buildFilters(catalogAsync.asData?.value),
                selectedKey: _selectedKey,
                onSelected: (String key) {
                  setState(() => _selectedKey = key);
                },
              ),
            ),
            ...matchesAsync.when(
              data: (List<SportsMatch> matches) =>
                  _buildGrid(context, matches, liveIds),
              loading: () => <Widget>[_buildLoadingGrid(context)],
              error: (Object error, StackTrace _) => <Widget>[
                _buildError(context),
              ],
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSpacing.x16),
            ),
          ],
        ),
      ),
    );
  }

  List<_SportsFilter> _buildFilters(List<SportCategory>? catalog) {
    return <_SportsFilter>[
      ..._staticFilters,
      if (catalog != null)
        for (final SportCategory c in catalog)
          _SportsFilter(key: c.id, label: c.name),
    ];
  }

  List<Widget> _buildGrid(
    BuildContext context,
    List<SportsMatch> matches,
    Set<String> liveIds,
  ) {
    final bool liveView = _selectedKey == 'live';
    if (matches.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              liveView
                  ? 'No matches are live right now.'
                  : 'No matches found here.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.typeSecondary),
            ),
          ),
        ),
      ];
    }

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: gridCols(context),
            crossAxisSpacing: AppSpacing.x3,
            mainAxisSpacing: AppSpacing.x3,
            childAspectRatio: 0.86,
          ),
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              final SportsMatch match = matches[index];
              final bool isLive = liveView || liveIds.contains(match.id);
              return _MatchTile(match: match, isLive: isLive);
            },
            childCount: matches.length,
          ),
        ),
      ),
    ];
  }

  Widget _buildLoadingGrid(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(AppSpacing.x4),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridCols(context),
          crossAxisSpacing: AppSpacing.x3,
          mainAxisSpacing: AppSpacing.x3,
          childAspectRatio: 0.86,
        ),
        delegate: SliverChildBuilderDelegate(
          (BuildContext context, int index) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.x4),
              child: Shimmer.fromColors(
                baseColor: AppColors.mediaCardHoverBackground,
                highlightColor: AppColors.mediaCardHoverAccent,
                child: const ColoredBox(
                  color: AppColors.mediaCardHoverBackground,
                ),
              ),
            );
          },
          childCount: gridCols(context) * 3,
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.cloud_off_rounded,
                color: AppColors.typeSecondary,
                size: AppSpacing.x12,
              ),
              const SizedBox(height: AppSpacing.x3),
              Text(
                "Couldn't load matches.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.typeEmphasis,
                    ),
              ),
              const SizedBox(height: AppSpacing.x4),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(matchesProvider(_selectedKey)),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A match tile that navigates to the embed player on tap.
class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.isLive});

  final SportsMatch match;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return MatchCard(
      match: match,
      isLive: isLive,
      onTap: () {
        if (!match.hasSources) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No streams available for this match')),
          );
          return;
        }
        context.push('/sports-player', extra: match);
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.selectedKey,
    required this.onSelected,
  });

  final List<_SportsFilter> filters;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.x16,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
        itemCount: filters.length,
        itemBuilder: (BuildContext context, int index) {
          final _SportsFilter filter = filters[index];
          final bool isSelected = filter.key == selectedKey;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.x2),
            child: Center(
              child: ChoiceChip(
                label: Text(filter.label),
                selected: isSelected,
                onSelected: (_) => onSelected(filter.key),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SportsFilter {
  const _SportsFilter({required this.key, required this.label});

  final String key;
  final String label;
}
