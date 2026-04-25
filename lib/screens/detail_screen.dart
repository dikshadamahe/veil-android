import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/providers/storage_provider.dart';
import 'package:pstream_android/providers/tmdb_provider.dart';
import 'package:pstream_android/screens/scraping_screen.dart';
import 'package:pstream_android/screens/search_screen.dart';
import 'package:pstream_android/widgets/episode_list_sheet.dart';
import 'package:shimmer/shimmer.dart';

class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({
    super.key,
    required this.mediaItem,
  });

  final MediaItem mediaItem;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  bool _overviewExpanded = false;

  Future<void> _toggleBookmark(MediaItem media) async {
    await ref.read(storageControllerProvider).toggleBookmark(media);
  }

  Future<void> _handlePlay(MediaItem media) async {
    int? selectedSeason;
    int? selectedEpisode;

    if (media.isShow) {
      if (media.seasons.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Episode data is not available for this series yet.'),
          ),
        );
        return;
      }

      final EpisodeSelection? selection =
          await showModalBottomSheet<EpisodeSelection>(
            context: context,
            backgroundColor: AppColors.modalBackground,
            isScrollControlled: true,
            builder: (BuildContext context) {
              return EpisodeListSheet(media: media);
            },
          );

      if (selection == null) {
        return;
      }

      selectedSeason = selection.season;
      selectedEpisode = selection.episode;
    }

    final progressRequest = ProgressRequest(
      mediaItem: media,
      season: selectedSeason,
      episode: selectedEpisode,
    );
    final Map<String, dynamic>? progress = ref.read(
      progressEntryProvider(progressRequest),
    );
    final bool shouldResume = await _showResumeDialogIfNeeded(progress);
    final int? resumeFrom = shouldResume
        ? _readInt(progress?['positionSecs'])
        : null;
    if (!mounted) {
      return;
    }

    context.push(
      '/scraping',
      extra: ScrapingScreenArgs(
        mediaItem: media,
        season: selectedSeason,
        episode: selectedEpisode,
        resumeFrom: resumeFrom,
      ),
    );

    if (!shouldResume && progress != null) {
      await ref.read(storageControllerProvider).saveProgress(
            media,
            positionSecs: 0,
            durationSecs: 1,
            season: selectedSeason,
            episode: selectedEpisode,
          );
    }
  }

  void _openCreditSearch(MediaCredit credit) {
    if (credit.name.trim().isEmpty) {
      return;
    }

    context.push(
      '/search',
      extra: SearchScreenArgs(
        initialQuery: credit.name,
        title: '${credit.name} Credits',
      ),
    );
  }

  Future<bool> _showResumeDialogIfNeeded(Map<String, dynamic>? progress) async {
    if (progress == null) {
      return true;
    }

    final double ratio = _progressRatio(progress);
    if (ratio < 0.03 || ratio > 0.90) {
      return true;
    }

    final int positionSecs = _readInt(progress['positionSecs']);
    final bool? resume = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppColors.modalBackground,
          title: const Text('Resume playback'),
          content: Text('Continue from ${_formatDuration(positionSecs)}?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Start Over'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Resume'),
            ),
          ],
        );
      },
    );

    return resume ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final WindowClass layout = windowClass(context);
    final double heroHeight = MediaQuery.sizeOf(context).height *
        (layout == WindowClass.compact ? 0.38 : 0.45);
    final AsyncValue<MediaItem> details = ref.watch(
      detailProvider(
        DetailRequest(
          id: widget.mediaItem.tmdbId,
          type: widget.mediaItem.type,
        ),
      ),
    );
    final MediaItem media = details.value ?? widget.mediaItem;
    final bool isLoading = details.isLoading;
    final Object? loadError = details.hasError ? details.error : null;
    final bool isBookmarked = ref.watch(bookmarkStatusProvider(media));

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: SafeArea(
        child: loadError != null
            ? _DetailErrorState(
                media: widget.mediaItem,
                message: '$loadError',
              )
            : CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                expandedHeight: heroHeight,
                pinned: true,
                backgroundColor: AppColors.backgroundMain,
                flexibleSpace: FlexibleSpaceBar(
                  background: _DetailBackdrop(media: media),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.x4),
                  child: layout == WindowClass.compact
                      ? _DetailBody(
                          media: media,
                          isLoading: isLoading,
                          isBookmarked: isBookmarked,
                          overviewExpanded: _overviewExpanded,
                          onToggleBookmark: () => _toggleBookmark(media),
                          onToggleOverview: () {
                            setState(() {
                              _overviewExpanded = !_overviewExpanded;
                            });
                          },
                          onPlay: () => _handlePlay(media),
                          onCreditTap: _openCreditSearch,
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              flex: 2,
                              child: _DetailBody(
                                media: media,
                                isLoading: isLoading,
                                isBookmarked: isBookmarked,
                                overviewExpanded: _overviewExpanded,
                                onToggleBookmark: () => _toggleBookmark(media),
                                onToggleOverview: () {
                                  setState(() {
                                    _overviewExpanded = !_overviewExpanded;
                                  });
                                },
                                onPlay: () => _handlePlay(media),
                                onCreditTap: _openCreditSearch,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x6),
                            Expanded(child: _PosterPanel(media: media)),
                          ],
                        ),
                ),
              ),
            ],
        ),
      ),
    );
  }

  double _progressRatio(Map<String, dynamic> progress) {
    final dynamic cachedRatio = progress['watchedRatio'];
    if (cachedRatio is num) {
      return cachedRatio.toDouble();
    }

    final int duration = _readInt(progress['durationSecs']);
    if (duration <= 0) {
      return 0;
    }

    return _readInt(progress['positionSecs']) / duration;
  }

  int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value') ?? 0;
  }

  String _formatDuration(int seconds) {
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

class _DetailBackdrop extends StatelessWidget {
  const _DetailBackdrop({required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (media.backdropUrl() != null)
          CachedNetworkImage(
            imageUrl: media.backdropUrl()!,
            fit: BoxFit.cover,
            placeholder: (_, placeholderUrl) =>
                const _BackdropPlaceholder(),
            errorWidget: (_, error, stackTrace) =>
                const _BackdropPlaceholder(),
          )
        else
          const _BackdropPlaceholder(),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                AppColors.blackC50.withValues(alpha: 0.15),
                AppColors.blackC50.withValues(alpha: 0.55),
                AppColors.backgroundMain,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.5),
              radius: 1.2,
              colors: <Color>[
                AppColors.backgroundAccentA.withValues(alpha: 0.45),
                AppColors.backgroundAccentB.withValues(alpha: 0.05),
                AppColors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.media,
    required this.isLoading,
    required this.isBookmarked,
    required this.overviewExpanded,
    required this.onToggleBookmark,
    required this.onToggleOverview,
    required this.onPlay,
    required this.onCreditTap,
  });

  final MediaItem media;
  final bool isLoading;
  final bool isBookmarked;
  final bool overviewExpanded;
  final VoidCallback onToggleBookmark;
  final VoidCallback onToggleOverview;
  final VoidCallback onPlay;
  final void Function(MediaCredit credit) onCreditTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (windowClass(context) == WindowClass.compact)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.x4),
              child: _PosterPanel(media: media),
            ),
          ),
        Text(
          media.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: AppColors.typeEmphasis,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        Wrap(
          spacing: AppSpacing.x2,
          runSpacing: AppSpacing.x2,
          children: <Widget>[
            _MetaChip(label: media.year > 0 ? '${media.year}' : 'Unknown'),
            _MetaChip(
              label: media.rating > 0 ? media.rating.toStringAsFixed(1) : 'NR',
            ),
            ...media.genres.take(4).map((MediaGenre genre) {
              return _MetaChip(label: genre.name);
            }),
          ],
        ),
        const SizedBox(height: AppSpacing.x4),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.buttonsPurple,
                  foregroundColor: AppColors.typeEmphasis,
                  minimumSize: const Size.fromHeight(AppSpacing.x12),
                ),
                onPressed: isLoading ? null : onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play'),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSpacing.x12),
                ),
                onPressed: onToggleBookmark,
                icon: Icon(
                  isBookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_add_outlined,
                ),
                label: Text(isBookmarked ? 'Bookmarked' : 'Bookmark'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.x4),
        GestureDetector(
          onTap: onToggleOverview,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                media.overview.isEmpty
                    ? 'No overview available.'
                    : media.overview,
                maxLines: overviewExpanded ? null : 3,
                overflow: overviewExpanded ? null : TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.typeText),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(
                overviewExpanded ? 'Show less' : 'Tap to expand',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.typeLink),
              ),
            ],
          ),
        ),
        if (media.credits.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.x5),
          Text(
            'Cast',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: AppColors.typeEmphasis),
          ),
          const SizedBox(height: AppSpacing.x3),
          SizedBox(
            height: AppSpacing.x30,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: media.credits.length,
              itemBuilder: (BuildContext context, int index) {
                final MediaCredit credit = media.credits[index];
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.x3),
                  child: SizedBox(
                    width: AppSpacing.x20,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppSpacing.x4),
                      onTap: () => onCreditTap(credit),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.x1),
                        child: Column(
                          children: <Widget>[
                            CircleAvatar(
                              radius: AppSpacing.x8,
                              backgroundColor:
                                  AppColors.mediaCardHoverBackground,
                              backgroundImage: credit.profileUrl('w92') != null
                                  ? CachedNetworkImageProvider(
                                      credit.profileUrl('w92')!,
                                    )
                                  : null,
                              child: credit.profileUrl('w92') == null
                                  ? const Icon(Icons.person_outline_rounded)
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              credit.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            if ((credit.character ?? '').trim().isNotEmpty)
                              Text(
                                credit.character!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _PosterPanel extends StatelessWidget {
  const _PosterPanel({required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        child: Hero(
          tag: 'poster-${media.tmdbId}',
          child: media.posterUrl('w500') == null
              ? const _BackdropPlaceholder()
              : CachedNetworkImage(
                  imageUrl: media.posterUrl('w500')!,
                  fit: BoxFit.cover,
                  placeholder: (_, placeholderUrl) =>
                      const _BackdropPlaceholder(),
                  errorWidget: (_, error, stackTrace) =>
                      const _BackdropPlaceholder(),
                ),
        ),
      ),
    );
  }
}

class _DetailErrorState extends StatelessWidget {
  const _DetailErrorState({
    required this.media,
    required this.message,
  });

  final MediaItem media;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(height: AppSpacing.x4),
          _PosterPanel(media: media),
          const SizedBox(height: AppSpacing.x5),
          Text(
            media.title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppColors.typeEmphasis,
                ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            'Could not load this title right now.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.typeText,
                ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.mediaCardBadge.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(AppSpacing.x4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.typeEmphasis),
        ),
      ),
    );
  }
}

class _BackdropPlaceholder extends StatelessWidget {
  const _BackdropPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.mediaCardHoverBackground,
      highlightColor: AppColors.mediaCardHoverAccent,
      child: const ColoredBox(color: AppColors.mediaCardHoverBackground),
    );
  }
}
