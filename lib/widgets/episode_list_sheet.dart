import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/episode.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/season.dart';
import 'package:pstream_android/providers/storage_provider.dart';
import 'package:pstream_android/providers/tmdb_provider.dart';
import 'package:shimmer/shimmer.dart';

class EpisodeSelection {
  const EpisodeSelection({
    required this.season,
    required this.episode,
    this.seasonTmdbId,
    this.episodeTmdbId,
    this.seasonTitle,
  });

  final int season;
  final int episode;
  final String? seasonTmdbId;
  final String? episodeTmdbId;
  final String? seasonTitle;
}

class EpisodeListSheet extends ConsumerStatefulWidget {
  const EpisodeListSheet({
    super.key,
    required this.media,
  });

  final MediaItem media;

  @override
  ConsumerState<EpisodeListSheet> createState() => _EpisodeListSheetState();
}

class _EpisodeListSheetState extends ConsumerState<EpisodeListSheet>
    with TickerProviderStateMixin {
  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    if (widget.media.seasons.isEmpty) {
      return;
    }
    final int initialIndex = _initialSeasonIndex();
    _tabController = TabController(
      length: widget.media.seasons.length,
      vsync: this,
      initialIndex: initialIndex,
    )..addListener(_handleTabChange);
  }

  @override
  void dispose() {
    _tabController
      ?..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController == null || _tabController!.indexIsChanging) {
      return;
    }
    setState(() {});
  }

  int _initialSeasonIndex() {
    final LatestEpisodeSelection? selection = ref.read(
      latestEpisodeSelectionProvider(widget.media),
    );
    if (selection == null) {
      return 0;
    }

    final int index = widget.media.seasons.indexWhere(
      (Season season) => season.number == selection.season,
    );
    return index >= 0 ? index : 0;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.media.seasons.isEmpty || _tabController == null) {
      return const _EpisodeSheetMessage(
        title: 'No episodes available',
        message: 'This series is missing season data right now.',
      );
    }

    final Season activeSeason = widget.media.seasons[_tabController!.index];
    final int seasonNumber = activeSeason.number;
    final AsyncValue<List<Episode>> seasonEpisodes = ref.watch(
      seasonEpisodesProvider(
        SeasonEpisodesRequest(
          showId: widget.media.tmdbId,
          seasonNum: seasonNumber,
        ),
      ),
    );
    final LatestEpisodeSelection? currentSelection = ref.watch(
      latestEpisodeSelectionProvider(widget.media),
    );
    final List<Episode> episodes =
        seasonEpisodes.value ?? const <Episode>[];
    final bool isLoading = seasonEpisodes.isLoading;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.82,
      minChildSize: 0.48,
      maxChildSize: 0.95,
      builder: (BuildContext context, ScrollController scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.modalBackground,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppSpacing.x5),
            ),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: AppSpacing.x3),
              Container(
                width: AppSpacing.x12,
                height: AppSpacing.x1,
                decoration: BoxDecoration(
                  color: AppColors.typeSecondary,
                  borderRadius: BorderRadius.circular(AppSpacing.x1),
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: widget.media.seasons
                    .map((Season season) {
                      return Tab(text: 'Season ${season.number}');
                    })
                    .toList(growable: false),
              ),
              const SizedBox(height: AppSpacing.x2),
              Expanded(
                child: seasonEpisodes.hasError
                    ? const _EpisodeSheetMessageBody(
                        title: 'Could not load episodes',
                        message: 'Try this series again in a moment.',
                      )
                    : isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : episodes.isEmpty
                    ? const _EpisodeSheetMessageBody(
                        title: 'No episodes available',
                        message: 'This season does not have episode data yet.',
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.x4,
                          AppSpacing.x2,
                          AppSpacing.x4,
                          AppSpacing.x6,
                        ),
                        itemCount: episodes.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Episode episode = episodes[index];
                          final Map<String, dynamic>? progress = ref.watch(
                            progressEntryProvider(
                              ProgressRequest(
                                mediaItem: widget.media,
                                season: seasonNumber,
                                episode: episode.number,
                              ),
                            ),
                          );
                          final bool isCurrent =
                              currentSelection?.season == seasonNumber &&
                              currentSelection?.episode == episode.number;

                          return _EpisodeRow(
                            episode: episode,
                            progress: progress,
                            isCurrent: isCurrent,
                            onTap: () {
                              Navigator.of(context).pop(
                                EpisodeSelection(
                                  season: seasonNumber,
                                  episode: episode.number,
                                  seasonTmdbId:
                                      activeSeason.id.trim().isNotEmpty
                                          ? activeSeason.id.trim()
                                          : null,
                                  episodeTmdbId: episode.id.trim().isNotEmpty
                                      ? episode.id.trim()
                                      : null,
                                  seasonTitle: activeSeason.title,
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EpisodeSheetMessage extends StatelessWidget {
  const _EpisodeSheetMessage({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.48,
      minChildSize: 0.36,
      maxChildSize: 0.6,
      builder: (BuildContext context, ScrollController scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.modalBackground,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppSpacing.x5),
            ),
          ),
          child: _EpisodeSheetMessageBody(
            title: title,
            message: message,
          ),
        );
      },
    );
  }
}

class _EpisodeSheetMessageBody extends StatelessWidget {
  const _EpisodeSheetMessageBody({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.x3),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.typeText,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.episode,
    required this.progress,
    required this.isCurrent,
    required this.onTap,
  });

  final Episode episode;
  final Map<String, dynamic>? progress;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final int positionSecs = _readInt(progress?['positionSecs']);
    final int durationSecs = _readInt(progress?['durationSecs']);
    final double ratio = durationSecs > 0 ? positionSecs / durationSecs : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x3),
      child: Material(
        color: isCurrent
            ? AppColors.mediaCardHoverBackground
            : AppColors.dropdownAltBackground,
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.x3),
                  child: SizedBox(
                    width: AppSpacing.x30,
                    height: AppSpacing.x16,
                    child: episode.stillPath == null
                        ? const _StillPlaceholder()
                        : CachedNetworkImage(
                            imageUrl:
                                'https://image.tmdb.org/t/p/w300${episode.stillPath}',
                            fit: BoxFit.cover,
                            placeholder: (_, placeholderUrl) =>
                                const _StillPlaceholder(),
                            errorWidget: (_, error, stackTrace) =>
                                const _StillPlaceholder(),
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'E${episode.number} ${episode.title}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: AppColors.typeEmphasis,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.x2,
                                vertical: AppSpacing.x1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.buttonsPurple,
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.x3,
                                ),
                              ),
                              child: Text(
                                'Watching',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: AppColors.typeEmphasis),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      Text(
                        episode.overview.isEmpty
                            ? 'No overview available.'
                            : episode.overview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.typeText,
                        ),
                      ),
                      if (progress != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.x3),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppSpacing.x1,
                                ),
                                child: RepaintBoundary(
                                  child: LinearProgressIndicator(
                                    minHeight: AppSpacing.x1,
                                    value: ratio.clamp(0.0, 1.0),
                                    backgroundColor:
                                        AppColors.mediaCardBarColor,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                      AppColors.mediaCardBarFillColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x2),
                            Text(
                              _formatDuration(positionSecs),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: AppColors.typeSecondary),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value') ?? 0;
  }

  static String _formatDuration(int seconds) {
    final Duration duration = Duration(seconds: seconds);
    final int minutes = duration.inMinutes.remainder(60);
    final int hours = duration.inHours;
    final int secs = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}

class _StillPlaceholder extends StatelessWidget {
  const _StillPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.mediaCardHoverBackground,
      highlightColor: AppColors.mediaCardHoverAccent,
      child: const ColoredBox(color: AppColors.mediaCardHoverBackground),
    );
  }
}
