import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';
import 'package:pstream_android/providers/stream_provider.dart';
import 'package:pstream_android/screens/player_screen.dart';
import 'package:pstream_android/services/stream_service.dart';
import 'package:pstream_android/widgets/scrape_source_card.dart' show ScrapeStatus;

class ScrapingScreenArgs {
  const ScrapingScreenArgs({
    required this.mediaItem,
    this.season,
    this.episode,
    this.seasonTmdbId,
    this.episodeTmdbId,
    this.seasonTitle,
    this.resumeFrom,
  });

  final MediaItem mediaItem;
  final int? season;
  final int? episode;
  final String? seasonTmdbId;
  final String? episodeTmdbId;
  final String? seasonTitle;
  final int? resumeFrom;
}

class ScrapingScreen extends ConsumerStatefulWidget {
  const ScrapingScreen({
    super.key,
    required this.mediaItem,
    this.season,
    this.episode,
    this.seasonTmdbId,
    this.episodeTmdbId,
    this.seasonTitle,
    this.resumeFrom,
  });

  final MediaItem mediaItem;
  final int? season;
  final int? episode;
  final String? seasonTmdbId;
  final String? episodeTmdbId;
  final String? seasonTitle;
  final int? resumeFrom;

  @override
  ConsumerState<ScrapingScreen> createState() => _ScrapingScreenState();
}

class _ScrapingScreenState extends ConsumerState<ScrapingScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, ScrapeStatus> _statuses = <String, ScrapeStatus>{};
  final Map<String, _ScrapeNode> _nodes = <String, _ScrapeNode>{};
  final List<String> _sourceOrder = <String>[];
  final Map<String, String> _embedNameByScraperId = <String, String>{};

  StreamSubscription<ScrapeEvent>? _scrapeSubscription;
  late final StreamService _streamService;
  bool _isLoading = true;
  bool _allFailure = false;
  String? _failureMessage;
  String? _currentPendingSourceId;

  @override
  void initState() {
    super.initState();
    _streamService = ref.read(streamServiceProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startStreamScrape();
      unawaited(_primeCatalog());
    });
  }

  @override
  void dispose() {
    _scrapeSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _primeCatalog() async {
    try {
      final ScrapeCatalog catalog = await _streamService.fetchCatalog();
      if (!mounted) {
        return;
      }

      if (catalog.sources.isNotEmpty) {
        _mergeSources(catalog.sources);
      }

      for (final ScrapeSourceDefinition embed in catalog.embeds) {
        _embedNameByScraperId[embed.id] = embed.name;
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
    }
  }

  void _startStreamScrape() {
    _scrapeSubscription?.cancel();
    _scrapeSubscription = _streamService
        .scrapeStream(
          widget.mediaItem,
          season: widget.season,
          episode: widget.episode,
          seasonTmdbId: widget.seasonTmdbId,
          episodeTmdbId: widget.episodeTmdbId,
          seasonTitle: widget.seasonTitle,
        )
        .listen(
      _handleEvent,
      onError: _handleError,
      onDone: () {
        if (!_hasSuccess() && mounted) {
          setState(() {
            _isLoading = false;
            _allFailure = true;
            _failureMessage ??= 'No sources found';
          });
        }
      },
    );
  }

  void _handleEvent(ScrapeEvent event) {
    switch (event.type) {
      case 'init':
        _mergeSources(event.sources);
        break;
      case 'start':
        final String? sourceId = event.sourceId;
        if (sourceId != null) {
          _updateStatus(sourceId, ScrapeStatus.pending);
        }
        _setLoading(false);
        break;
      case 'update':
        final String? sourceId = event.sourceId;
        if (sourceId != null) {
          final ScrapeStatus status = _statusFromString(event.updateStatus);
          _updateStatus(sourceId, status);
        }
        _setLoading(false);
        break;
      case 'embeds':
        _addEmbeds(event.sourceId, event.embeds);
        _setLoading(false);
        break;
      case 'done':
        _handleDone(event);
        break;
      case 'error':
        _handleFailure(event.errorMessage ?? 'Scraping failed.');
        break;
      default:
        break;
    }
  }

  void _handleDone(ScrapeEvent event) {
    _setLoading(false);

    final StreamResult? result = event.result;
    if (event.ok && result != null) {
      _updateStatus(result.sourceId, ScrapeStatus.success);
      if (result.embedId != null) {
        _updateStatus(result.embedId!, ScrapeStatus.success);
      }
      _navigateToPlayer(result);
      return;
    }

    _handleFailure(event.errorMessage ?? 'No sources found');
  }

  void _handleError(Object error, [StackTrace? stackTrace]) {
    if (!mounted) {
      return;
    }

    final String message = error is TimeoutException
        ? error.message ?? 'Scrape timed out.'
        : '$error';
    _handleFailure(message);
  }

  void _handleFailure(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
      _failureMessage = message;
      if (!_hasSuccess()) {
        _allFailure = true;
        for (final String sourceId in _sourceOrder) {
          if (_statuses[sourceId] == ScrapeStatus.pending ||
              _statuses[sourceId] == ScrapeStatus.waiting) {
            _statuses[sourceId] = ScrapeStatus.failure;
          }
        }
      }
    });
  }

  void _mergeSources(List<ScrapeSourceDefinition> sources) {
    if (!mounted) {
      return;
    }

    setState(() {
      for (final ScrapeSourceDefinition source in sources) {
        if (!_nodes.containsKey(source.id)) {
          _nodes[source.id] = _ScrapeNode(
            id: source.id,
            name: source.name,
          );
          _sourceOrder.add(source.id);
        } else if (_nodes[source.id]!.name.isEmpty && source.name.isNotEmpty) {
          _nodes[source.id] = _nodes[source.id]!.copyWith(name: source.name);
        }

        _statuses.putIfAbsent(source.id, () => ScrapeStatus.waiting);
      }

      _isLoading = false;
    });
  }

  void _addEmbeds(String? sourceId, List<ScrapeSourceDefinition> embeds) {
    if (!mounted || sourceId == null || !_nodes.containsKey(sourceId)) {
      return;
    }

    setState(() {
      final _ScrapeNode sourceNode = _nodes[sourceId]!;
      final List<String> children = List<String>.from(sourceNode.embedIds);

      for (final ScrapeSourceDefinition embed in embeds) {
        final String embedName = embed.name.isNotEmpty
            ? embed.name
            : _embedNameByScraperId[embed.embedScraperId] ??
                embed.embedScraperId ??
                embed.id;

        _nodes.putIfAbsent(
          embed.id,
          () => _ScrapeNode(
            id: embed.id,
            name: embedName,
          ),
        );
        _statuses.putIfAbsent(embed.id, () => ScrapeStatus.waiting);
        if (!children.contains(embed.id)) {
          children.add(embed.id);
        }
      }

      _nodes[sourceId] = sourceNode.copyWith(embedIds: children);
    });
  }

  void _updateStatus(String id, ScrapeStatus status) {
    if (!mounted) {
      return;
    }

    setState(() {
      _statuses[id] = status;
      if (status == ScrapeStatus.pending) {
        _currentPendingSourceId = id;
      } else if (_currentPendingSourceId == id) {
        _currentPendingSourceId = null;
      }
    });
  }

  void _setLoading(bool value) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = value;
    });
  }

  bool _hasSuccess() {
    return _statuses.values.contains(ScrapeStatus.success);
  }

  Future<void> _showManualPicker() async {
    if (_sourceOrder.isEmpty) {
      return;
    }

    final String? sourceId = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: ListView.builder(
            itemCount: _sourceOrder.length,
            itemBuilder: (BuildContext context, int index) {
              final String id = _sourceOrder[index];
              final _ScrapeNode? node = _nodes[id];
              if (node == null) {
                return const SizedBox.shrink();
              }

              return ListTile(
                minTileHeight: AppSpacing.x12,
                title: Text(node.name),
                onTap: () => Navigator.of(context).pop(id),
              );
            },
          ),
        );
      },
    );

    if (sourceId == null || !mounted) {
      return;
    }

    await _retrySingleSource(sourceId);
  }

  Future<void> _retrySingleSource(String sourceId) async {
    setState(() {
      _allFailure = false;
      _failureMessage = null;
      _isLoading = true;
      _statuses[sourceId] = ScrapeStatus.pending;
      _currentPendingSourceId = sourceId;
    });

    try {
      final StreamResult? result = await _streamService.scrapeSingleSource(
        widget.mediaItem,
        sourceId: sourceId,
        season: widget.season,
        episode: widget.episode,
        seasonTmdbId: widget.seasonTmdbId,
        episodeTmdbId: widget.episodeTmdbId,
        seasonTitle: widget.seasonTitle,
      );

      if (!mounted) {
        return;
      }

      if (result == null) {
        setState(() {
          _isLoading = false;
          _statuses[sourceId] = ScrapeStatus.notfound;
          _allFailure = true;
          _failureMessage = 'No sources found';
        });
        return;
      }

      setState(() {
        _isLoading = false;
        _statuses[sourceId] = ScrapeStatus.success;
        if (result.embedId != null) {
          _statuses[result.embedId!] = ScrapeStatus.success;
        }
      });
      _navigateToPlayer(result);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _statuses[sourceId] = ScrapeStatus.failure;
        _allFailure = true;
        _failureMessage = '$error';
      });
    }
  }

  void _navigateToPlayer(StreamResult result) {
    if (!mounted) {
      return;
    }

    context.pushReplacement(
      '/player',
      extra: PlayerScreenArgs(
        mediaItem: widget.mediaItem,
        streamResult: result,
        season: widget.season,
        episode: widget.episode,
        seasonTmdbId: widget.seasonTmdbId,
        episodeTmdbId: widget.episodeTmdbId,
        seasonTitle: widget.seasonTitle,
        resumeFrom: widget.resumeFrom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final _ScrapeNode? activeSource = _activeSource;
    final int attemptedCount = _attemptedSourceIds.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finding stream'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_isLoading || _currentPendingSourceId != null)
              const RepaintBoundary(
                child: LinearProgressIndicator(minHeight: AppSpacing.x1),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(AppSpacing.x4),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Text(
                                widget.mediaItem.title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: AppSpacing.x2),
                              Text(
                                _statusMessage(attemptedCount),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.typeText,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.x5),
                              if (activeSource != null)
                                _ActiveSourceCard(
                                  sourceName: activeSource.name,
                                  embedCount: activeSource.embedIds.length,
                                )
                              else
                                _IdleScrapeCard(
                                  label: _isLoading
                                      ? 'Preparing providers...'
                                      : 'Waiting for the next source.',
                                ),
                              if (_attemptedSourceIds.isNotEmpty) ...<Widget>[
                                const SizedBox(height: AppSpacing.x5),
                                Text(
                                  'Recent attempts',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: AppSpacing.x3),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: AppSpacing.x2,
                                  runSpacing: AppSpacing.x2,
                                  children: _attemptedSourceIds
                                      .take(6)
                                      .map((String sourceId) {
                                    final _ScrapeNode? node = _nodes[sourceId];
                                    if (node == null) {
                                      return const SizedBox.shrink();
                                    }
                                    return _AttemptChip(
                                      label: node.name,
                                      status: _statuses[sourceId] ?? ScrapeStatus.waiting,
                                    );
                                  }).toList(growable: false),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_allFailure)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x4,
                  AppSpacing.x0,
                  AppSpacing.x4,
                  AppSpacing.x6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      _failureMessage ?? 'No sources found',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.x3),
                    FilledButton(
                      onPressed: _showManualPicker,
                      child: const Text('Choose source'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  _ScrapeNode? get _activeSource {
    if (_currentPendingSourceId != null) {
      return _nodes[_currentPendingSourceId!];
    }

    for (final String sourceId in _sourceOrder) {
      if ((_statuses[sourceId] ?? ScrapeStatus.waiting) == ScrapeStatus.pending) {
        return _nodes[sourceId];
      }
    }

    return null;
  }

  Iterable<String> get _attemptedSourceIds sync* {
    for (final String sourceId in _sourceOrder.reversed) {
      final ScrapeStatus status = _statuses[sourceId] ?? ScrapeStatus.waiting;
      if (status == ScrapeStatus.failure ||
          status == ScrapeStatus.notfound ||
          status == ScrapeStatus.success) {
        yield sourceId;
      }
    }
  }

  String _statusMessage(int attemptedCount) {
    if (_allFailure) {
      return 'Every automatic source failed. Pick one manually.';
    }
    if (_currentPendingSourceId != null) {
      return attemptedCount == 0
          ? 'Trying the first available source.'
          : 'Trying another source after $attemptedCount attempt${attemptedCount == 1 ? '' : 's'}.';
    }
    if (_sourceOrder.isEmpty && _isLoading) {
      return 'Loading source catalog.';
    }
    return 'Preparing playback.';
  }
}

ScrapeStatus _statusFromString(String? value) {
  return switch (value) {
    'pending' => ScrapeStatus.pending,
    'success' => ScrapeStatus.success,
    'failure' => ScrapeStatus.failure,
    'notfound' => ScrapeStatus.notfound,
    _ => ScrapeStatus.waiting,
  };
}

class _ScrapeNode {
  const _ScrapeNode({
    required this.id,
    required this.name,
    this.embedIds = const <String>[],
  });

  final String id;
  final String name;
  final List<String> embedIds;

  _ScrapeNode copyWith({
    String? name,
    List<String>? embedIds,
  }) {
    return _ScrapeNode(
      id: id,
      name: name ?? this.name,
      embedIds: embedIds ?? this.embedIds,
    );
  }
}

class _ActiveSourceCard extends StatefulWidget {
  const _ActiveSourceCard({
    required this.sourceName,
    required this.embedCount,
  });

  final String sourceName;
  final int embedCount;

  @override
  State<_ActiveSourceCard> createState() => _ActiveSourceCardState();
}

class _ActiveSourceCardState extends State<_ActiveSourceCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double glow = 0.4 + (_controller.value * 0.6);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(AppSpacing.x5),
            decoration: BoxDecoration(
              color: AppColors.videoContextBackground.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(AppSpacing.x4),
              border: Border.all(
                color: AppColors.buttonsPurple.withValues(alpha: glow),
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.buttonsPurple.withValues(alpha: 0.16 * glow),
                  blurRadius: AppSpacing.x6,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Row(
          children: <Widget>[
            const _ScanningIndicator(),
            const SizedBox(width: AppSpacing.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Trying ${widget.sourceName}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    widget.embedCount > 0
                        ? 'Checking ${widget.embedCount} embed option${widget.embedCount == 1 ? '' : 's'}.'
                        : 'Checking the best stream path for this source.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.typeText,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanningIndicator extends StatefulWidget {
  const _ScanningIndicator();

  @override
  State<_ScanningIndicator> createState() => _ScanningIndicatorState();
}

class _ScanningIndicatorState extends State<_ScanningIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSpacing.x10,
      height: AppSpacing.x10,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return Stack(
            alignment: Alignment.center,
            children: List<Widget>.generate(3, (int index) {
              final double phase = ((_controller.value + (index * 0.2)) % 1.0);
              final double scale = 0.55 + (phase * 0.45);
              final double opacity = 1.0 - phase;
              return Opacity(
                opacity: opacity.clamp(0.2, 1.0),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.buttonsPurple,
                        width: AppSpacing.x1,
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _IdleScrapeCard extends StatelessWidget {
  const _IdleScrapeCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.videoContextBackground.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        border: Border.all(
          color: AppColors.videoContextBorder.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _AttemptChip extends StatelessWidget {
  const _AttemptChip({
    required this.label,
    required this.status,
  });

  final String label;
  final ScrapeStatus status;

  @override
  Widget build(BuildContext context) {
    final Color tint = switch (status) {
      ScrapeStatus.success => AppColors.videoScrapingSuccess,
      ScrapeStatus.failure || ScrapeStatus.notfound =>
        AppColors.videoScrapingError,
      ScrapeStatus.pending => AppColors.videoScrapingLoading,
      ScrapeStatus.waiting => AppColors.typeSecondary,
    };
    final IconData icon = switch (status) {
      ScrapeStatus.success => Icons.check_rounded,
      ScrapeStatus.failure || ScrapeStatus.notfound => Icons.close_rounded,
      ScrapeStatus.pending => Icons.more_horiz_rounded,
      ScrapeStatus.waiting => Icons.circle_outlined,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3,
          vertical: AppSpacing.x2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: AppSpacing.x4, color: tint),
            const SizedBox(width: AppSpacing.x2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppColors.typeEmphasis,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
