import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/live_channel.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/omss_source.dart';
import 'package:pstream_android/models/season.dart';
import 'package:pstream_android/providers/live_provider.dart';
import 'package:pstream_android/screens/player_screen.dart';
import 'package:pstream_android/widgets/channel_card.dart';

/// Live TV browse screen: a category-filtered grid of HLS channels.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  /// Selected category filter; null means "All".
  String? _selectedCat;

  static const List<String> _categories = <String>[
    'Sports',
    'News',
    'Entertainment',
    'Movies',
    'Music',
    'Kids',
    'Docs',
  ];

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<LiveChannel>> channelsAsync =
        ref.watch(liveChannelsProvider);
    final AsyncValue<Map<String, List<LiveProgram>>> epgAsync =
        ref.watch(liveEpgProvider);
    final Map<String, List<LiveProgram>> epg =
        epgAsync.asData?.value ?? const <String, List<LiveProgram>>{};

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: CustomScrollView(
        slivers: <Widget>[
          const SliverAppBar(
            pinned: true,
            title: Text('Live TV'),
          ),
          SliverToBoxAdapter(
            child: _CategoryFilterBar(
              categories: _categories,
              selected: _selectedCat,
              onSelected: (String? cat) {
                setState(() => _selectedCat = cat);
              },
            ),
          ),
          ...channelsAsync.when(
            data: (List<LiveChannel> channels) =>
                _buildGrid(context, channels, epg),
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
    );
  }

  List<Widget> _buildGrid(
    BuildContext context,
    List<LiveChannel> channels,
    Map<String, List<LiveProgram>> epg,
  ) {
    final List<LiveChannel> filtered = _selectedCat == null
        ? channels
        : channels
            .where((LiveChannel c) =>
                c.cat.toLowerCase() == _selectedCat!.toLowerCase())
            .toList(growable: false);

    if (filtered.isEmpty) {
      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Text(
              'No channels in this category.',
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
            childAspectRatio: 0.92,
          ),
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              final LiveChannel channel = filtered[index];
              return ChannelCard(
                channel: channel,
                currentProgram: _currentProgram(channel, epg),
                onTap: () => _openChannel(channel, epg),
              );
            },
            childCount: filtered.length,
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
          childAspectRatio: 0.92,
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
                "Couldn't load live channels.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.typeEmphasis,
                    ),
              ),
              const SizedBox(height: AppSpacing.x4),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(liveChannelsProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Finds the program airing right now for [channel], if EPG data exists.
  String? _currentProgram(
    LiveChannel channel,
    Map<String, List<LiveProgram>> epg,
  ) {
    final List<LiveProgram>? programs = epg[channel.epgKey];
    if (programs == null || programs.isEmpty) {
      return null;
    }
    for (final LiveProgram p in programs) {
      if (p.isNow) {
        return p.title;
      }
    }
    return null;
  }

  void _openChannel(
    LiveChannel channel,
    Map<String, List<LiveProgram>> epg,
  ) {
    context.push('/player', extra: _buildLiveArgs(channel, epg));
  }

  PlayerScreenArgs _buildLiveArgs(
    LiveChannel channel,
    Map<String, List<LiveProgram>> epg,
  ) {
    final OmssSource source = OmssSource(
      url: channel.url,
      type: 'hls',
      quality: null,
      providerId: channel.id,
      providerName: channel.name,
    );
    final OmssResponse response = OmssResponse(
      responseId: null,
      expiresAt: null,
      sources: <OmssSource>[source],
      subtitles: const <OmssSubtitle>[],
      diagnostics: const <String>[],
    );
    return PlayerScreenArgs(
      mediaItem: _liveChannelAsMediaItem(channel),
      omssResponse: response,
      isLive: true,
      liveChannelName: channel.name,
      liveCurrentProgram: _currentProgram(channel, epg),
    );
  }

  /// Builds a minimal synthetic [MediaItem] for the player. Live channels are
  /// not TMDB titles, so most fields are empty — only [title] is meaningful.
  MediaItem _liveChannelAsMediaItem(LiveChannel channel) => MediaItem(
        tmdbId: 0,
        type: 'movie',
        title: channel.name,
        overview: '',
        posterPath: null,
        backdropPath: null,
        year: 0,
        imdbId: null,
        rating: 0,
        seasons: const <Season>[],
      );
}

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSpacing.x16,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
        itemCount: categories.length + 1,
        itemBuilder: (BuildContext context, int index) {
          final bool isAll = index == 0;
          final String? cat = isAll ? null : categories[index - 1];
          final String label = isAll ? 'All' : categories[index - 1];
          final bool isSelected = selected == cat;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.x2),
            child: Center(
              child: ChoiceChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (_) => onSelected(cat),
              ),
            ),
          );
        },
      ),
    );
  }
}
