import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/episode.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/screens/scraping_screen.dart';
import 'package:pstream_android/services/tmdb_service.dart';
import 'package:pstream_android/storage/local_storage.dart';
import 'package:shimmer/shimmer.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.mediaItem,
    this.tmdbService = const TmdbService(),
  });

  final MediaItem mediaItem;
  final TmdbService tmdbService;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Future<MediaItem> _detailsFuture;
  bool _overviewExpanded = false;
  bool _isBookmarked = false;

  @override
  void initState() {
    super.initState();
    _detailsFuture = widget.tmdbService.getDetails(
      widget.mediaItem.tmdbId,
      widget.mediaItem.type,
    );
    _isBookmarked = LocalStorage.isBookmarked(widget.mediaItem);
  }

  Future<void> _toggleBookmark(MediaItem media) async {
    final bool added = await LocalStorage.toggleBookmark(media);
    if (!mounted) {
      return;
    }

    setState(() {
      _isBookmarked = added;
    });
  }

  Future<void> _handlePlay(MediaItem media) async {
    int? selectedSeason;
    int? selectedEpisode;

    if (media.isShow) {
      final _EpisodeSelection? selection =
          await showModalBottomSheet<_EpisodeSelection>(
            context: context,
            backgroundColor: AppColors.modalBackground,
            isScrollControlled: true,
            builder: (BuildContext context) {
              return _EpisodePickerSheet(
                media: media,
                tmdbService: widget.tmdbService,
              );
            },
          );

      if (selection == null) {
        return;
      }

      selectedSeason = selection.season;
      selectedEpisode = selection.episode;
    }

    final String mediaKey = LocalStorage.mediaKey(
      media,
      season: selectedSeason,
      episode: selectedEpisode,
    );
    final Map<String, dynamic>? progress = LocalStorage.getProgress(mediaKey);
    final bool shouldResume = await _showResumeDialogIfNeeded(progress);
    if (!mounted) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScrapingScreen(
          mediaItem: media,
          season: selectedSeason,
          episode: selectedEpisode,
        ),
      ),
    );

    if (!shouldResume && progress != null) {
      await LocalStorage.saveProgress(mediaKey, 0, 1, media);
    }
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

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: FutureBuilder<MediaItem>(
        future: _detailsFuture,
        initialData: widget.mediaItem,
        builder: (BuildContext context, AsyncSnapshot<MediaItem> snapshot) {
          final MediaItem media = snapshot.data ?? widget.mediaItem;
          final bool isLoading =
              snapshot.connectionState != ConnectionState.done;

          return CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                expandedHeight: layout == WindowClass.compact ? 320 : 420,
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
                          isBookmarked: _isBookmarked,
                          overviewExpanded: _overviewExpanded,
                          onToggleBookmark: () => _toggleBookmark(media),
                          onToggleOverview: () {
                            setState(() {
                              _overviewExpanded = !_overviewExpanded;
                            });
                          },
                          onPlay: () => _handlePlay(media),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              flex: 2,
                              child: _DetailBody(
                                media: media,
                                isLoading: isLoading,
                                isBookmarked: _isBookmarked,
                                overviewExpanded: _overviewExpanded,
                                onToggleBookmark: () => _toggleBookmark(media),
                                onToggleOverview: () {
                                  setState(() {
                                    _overviewExpanded = !_overviewExpanded;
                                  });
                                },
                                onPlay: () => _handlePlay(media),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x6),
                            Expanded(child: _PosterPanel(media: media)),
                          ],
                        ),
                ),
              ),
            ],
          );
        },
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
            placeholder: (_, __) => const _BackdropPlaceholder(),
            errorWidget: (_, __, ___) => const _BackdropPlaceholder(),
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
                Colors.transparent,
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
  });

  final MediaItem media;
  final bool isLoading;
  final bool isBookmarked;
  final bool overviewExpanded;
  final VoidCallback onToggleBookmark;
  final VoidCallback onToggleOverview;
  final VoidCallback onPlay;

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
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: media.credits.length,
              itemBuilder: (BuildContext context, int index) {
                final MediaCredit credit = media.credits[index];
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.x3),
                  child: SizedBox(
                    width: 84,
                    child: Column(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppColors.mediaCardHoverBackground,
                          backgroundImage: credit.profileUrl() != null
                              ? CachedNetworkImageProvider(credit.profileUrl()!)
                              : null,
                          child: credit.profileUrl() == null
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
                      ],
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
                  placeholder: (_, __) => const _BackdropPlaceholder(),
                  errorWidget: (_, __, ___) => const _BackdropPlaceholder(),
                ),
        ),
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

class _EpisodePickerSheet extends StatefulWidget {
  const _EpisodePickerSheet({required this.media, required this.tmdbService});

  final MediaItem media;
  final TmdbService tmdbService;

  @override
  State<_EpisodePickerSheet> createState() => _EpisodePickerSheetState();
}

class _EpisodePickerSheetState extends State<_EpisodePickerSheet> {
  late int _seasonNumber;
  List<Episode> _episodes = const <Episode>[];
  bool _loadingEpisodes = true;

  @override
  void initState() {
    super.initState();
    _seasonNumber = widget.media.seasons.isNotEmpty
        ? widget.media.seasons.first.number
        : 1;
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    setState(() {
      _loadingEpisodes = true;
    });

    final List<Episode> episodes = await widget.tmdbService.getSeasonEpisodes(
      widget.media.tmdbId,
      _seasonNumber,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _episodes = episodes;
      _loadingEpisodes = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Choose Episode',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: AppColors.typeEmphasis),
            ),
            const SizedBox(height: AppSpacing.x4),
            DropdownButtonFormField<int>(
              value: _seasonNumber,
              dropdownColor: AppColors.dropdownBackground,
              items: widget.media.seasons.map((Season season) {
                return DropdownMenuItem<int>(
                  value: season.number,
                  child: Text(season.title),
                );
              }).toList(),
              onChanged: (int? value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _seasonNumber = value;
                });
                _loadEpisodes();
              },
            ),
            const SizedBox(height: AppSpacing.x4),
            if (_loadingEpisodes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.x4),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _episodes.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Episode episode = _episodes[index];
                    return ListTile(
                      minTileHeight: 48,
                      contentPadding: EdgeInsets.zero,
                      title: Text('E${episode.number} ${episode.title}'),
                      subtitle: episode.overview.isEmpty
                          ? null
                          : Text(
                              episode.overview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () {
                        Navigator.of(context).pop(
                          _EpisodeSelection(
                            season: _seasonNumber,
                            episode: episode.number,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeSelection {
  const _EpisodeSelection({required this.season, required this.episode});

  final int season;
  final int episode;
}
