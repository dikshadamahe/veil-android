import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';
import 'package:pstream_android/providers/stream_provider.dart';
import 'package:pstream_android/screens/player_screen.dart';
import 'package:pstream_android/services/stream_service.dart';
import 'package:pstream_android/widgets/scrape_source_card.dart'
    show ScrapeSourceCard, ScrapeStatus, StatusCircle;

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
  /// Cycles which row shows a spinner (Express does not stream per-source progress).
  Timer? _sourceRotateTimer;
  int _rotateIndex = 0;

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
    _stopSourceRotation();
    _scrapeSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _primeCatalog() async {
    await _fetchAndApplyCatalog();
  }

  /// [SnackBar] without holding [BuildContext] across an async gap.
  void _showSnackBarIfMounted(String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// GET /sources on providers-api. Returns **null** if at least one source id
  /// was merged; otherwise an error string for a [SnackBar].
  Future<String?> _fetchAndApplyCatalog() async {
    final CatalogFetchResult result =
        await _streamService.fetchCatalogWithDiagnostics();
    if (!mounted) {
      return null;
    }

    if (result.catalog.sources.isNotEmpty) {
      _mergeSources(result.catalog.sources);
    }

    for (final ScrapeSourceDefinition embed in result.catalog.embeds) {
      _embedNameByScraperId[embed.id] = embed.name;
    }

    if (result.hasSources) {
      return null;
    }
    return result.failureReason ?? 'No sources in /sources response.';
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
              _handleFailure(_failureMessage ?? 'No sources found');
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
    _stopSourceRotation();
    _setLoading(false);

    final StreamResult? result = event.result;
    if (event.ok && result != null) {
      // Server runs sources in order — anything before the winner was tried
      // and didn't produce a stream, so mark them as failure (red X).
      _markPrecedingSourcesFailed(result.sourceId);
      _updateStatus(result.sourceId, ScrapeStatus.success);
      if (result.embedId != null) {
        _updateStatus(result.embedId!, ScrapeStatus.success);
      }
      _navigateToPlayer(result);
      return;
    }

    _handleFailure(event.errorMessage ?? 'No sources found');
  }

  /// Set every source ordered before [winnerId] to [ScrapeStatus.failure]
  /// unless it already resolved to a non-waiting state.
  void _markPrecedingSourcesFailed(String winnerId) {
    final List<String> ordered = _orderedSourceIdsForUi();
    for (final String id in ordered) {
      if (id == winnerId) {
        return;
      }
      final ScrapeStatus current = _statuses[id] ?? ScrapeStatus.waiting;
      if (current == ScrapeStatus.success) {
        continue;
      }
      _statuses[id] = ScrapeStatus.failure;
    }
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

    _stopSourceRotation();
    final bool hadNoSourcesYet = _sourceOrder.isEmpty;
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
    // If SSE never populated sources (buffering, empty init, etc.), GET /sources
    // often still works — merge so "Choose source manually" can open.
    if (hadNoSourcesYet) {
      unawaited(_fetchAndApplyCatalog());
    }
  }

  void _mergeSources(List<ScrapeSourceDefinition> sources) {
    if (!mounted) {
      return;
    }

    setState(() {
      for (final ScrapeSourceDefinition source in sources) {
        if (source.id.isEmpty) {
          continue;
        }
        if (!_nodes.containsKey(source.id)) {
          _nodes[source.id] = _ScrapeNode(id: source.id, name: source.name);
          _sourceOrder.add(source.id);
        } else if (_nodes[source.id]!.name.isEmpty && source.name.isNotEmpty) {
          _nodes[source.id] = _nodes[source.id]!.copyWith(name: source.name);
        }

        _statuses.putIfAbsent(source.id, () => ScrapeStatus.waiting);
      }

      _isLoading = false;
    });
    if (_sourceOrder.isNotEmpty && _awaitingScrapeResult) {
      _startSourceRotation();
    }
  }

  /// True while the SSE scrape is in progress and we have not failed yet.
  bool get _awaitingScrapeResult =>
      !_allFailure && !_hasSuccess() && _failureMessage == null;

  List<String> _orderedSourceIdsForUi() {
    final Set<String> known = _nodes.keys.toSet();
    if (known.isEmpty) {
      return <String>[];
    }
    final List<String> out = <String>[];
    final List<String>? preferred = AppConfig.scrapeSourceOrderList;
    if (preferred != null) {
      for (final String id in preferred) {
        if (known.contains(id)) {
          out.add(id);
        }
      }
    }
    for (final String id in _sourceOrder) {
      if (!out.contains(id)) {
        out.add(id);
      }
    }
    return out;
  }

  void _startSourceRotation() {
    _sourceRotateTimer?.cancel();
    final List<String> ids = _orderedSourceIdsForUi();
    if (ids.length <= 1) {
      return;
    }
    _rotateIndex = 0;
    _sourceRotateTimer = Timer.periodic(
      const Duration(seconds: 5),
      (Timer t) {
        if (!mounted || !_awaitingScrapeResult) {
          t.cancel();
          return;
        }
        setState(() {
          // Visualise progress: as the rotation moves to the next provider,
          // mark the one we just left as failure (red X) — providers run in
          // order server-side, so by the time we move on the previous one
          // has been "tried" and didn't yield a stream.
          if (_rotateIndex >= 0 && _rotateIndex < ids.length) {
            final String prevId = ids[_rotateIndex];
            final ScrapeStatus current =
                _statuses[prevId] ?? ScrapeStatus.waiting;
            if (current == ScrapeStatus.waiting ||
                current == ScrapeStatus.pending) {
              _statuses[prevId] = ScrapeStatus.failure;
            }
          }
          _rotateIndex = (_rotateIndex + 1) % ids.length;
        });
      },
    );
  }

  void _stopSourceRotation() {
    _sourceRotateTimer?.cancel();
    _sourceRotateTimer = null;
  }

  ScrapeStatus _displayStatusForList(String id) {
    // Active SSE-tracked source wins regardless of any failure mark — keeps
    // the pending spinner on the slot the server says it's currently doing.
    if (_currentPendingSourceId == id) {
      return ScrapeStatus.pending;
    }
    // While the scrape is still running, the rotation pointer is the visual
    // "currently checking" slot. It overrides a stale failure mark left by
    // a previous full rotation cycle so the spinner doesn't get hidden by
    // the cosmetic red-X we set when moving past a slot.
    if (_awaitingScrapeResult) {
      final List<String> ids = _orderedSourceIdsForUi();
      if (ids.isNotEmpty && id == ids[_rotateIndex % ids.length]) {
        return ScrapeStatus.pending;
      }
    }
    final ScrapeStatus real = _statuses[id] ?? ScrapeStatus.waiting;
    if (real == ScrapeStatus.success ||
        real == ScrapeStatus.failure ||
        real == ScrapeStatus.notfound) {
      return real;
    }
    if (_allFailure) {
      if (real == ScrapeStatus.waiting || real == ScrapeStatus.pending) {
        return ScrapeStatus.failure;
      }
      return real;
    }
    return real;
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
          () => _ScrapeNode(id: embed.id, name: embedName),
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
      final String? catalogErr = await _fetchAndApplyCatalog();
      if (!mounted || !context.mounted) {
        return;
      }
      if (catalogErr != null || _sourceOrder.isEmpty) {
        _showSnackBarIfMounted(
          catalogErr ??
              'No sources after /sources. Compare with curl on a PC.',
        );
        return;
      }
    }

    if (!mounted || !context.mounted) {
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

    if (sourceId == null || !context.mounted) {
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

      if (!context.mounted) {
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
      if (!context.mounted) {
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
    if (!context.mounted) {
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
    final List<String> orderedSources = _orderedSourceIdsForUi();
    final _ScrapeNode? activeNode =
        _currentPendingSourceId != null ? _nodes[_currentPendingSourceId] : null;

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundMain,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(
          widget.mediaItem.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_isLoading || _currentPendingSourceId != null)
              const RepaintBoundary(
                child: LinearProgressIndicator(minHeight: AppSpacing.x1),
              ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.x4,
                  AppSpacing.x6,
                  AppSpacing.x4,
                  AppSpacing.x4,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _ScrapingHeader(
                          activeName: activeNode?.name,
                          allFailure: _allFailure,
                          loading: _isLoading,
                        ),
                        const SizedBox(height: AppSpacing.x6),
                        if (orderedSources.isNotEmpty)
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: orderedSources.length,
                            itemBuilder: (BuildContext context, int index) {
                              final String id = orderedSources[index];
                              final _ScrapeNode? node = _nodes[id];
                              if (node == null) {
                                return const SizedBox.shrink();
                              }
                              final ScrapeStatus st = _displayStatusForList(id);
                              return ScrapeSourceCard(
                                sourceName: node.name,
                                status: st,
                                subline: st == ScrapeStatus.pending
                                    ? 'Checking for videos…'
                                    : null,
                              );
                            },
                          )
                        else
                          _IdleScrapeCard(
                            label: _isLoading
                                ? 'Preparing provider list…'
                                : 'Waiting for the next step.',
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_allFailure)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x4,
                    AppSpacing.x2,
                    AppSpacing.x4,
                    AppSpacing.x4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'Tip: Subtitles, quality and source default can be changed in Settings.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.typeSecondary,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.x3),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize:
                                    const Size.fromHeight(AppSpacing.x12),
                              ),
                              onPressed: () =>
                                  Navigator.of(context).maybePop(),
                              child: const Text('Back to home'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.x3),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.buttonsPurple,
                                foregroundColor: AppColors.typeEmphasis,
                                minimumSize:
                                    const Size.fromHeight(AppSpacing.x12),
                              ),
                              onPressed: () async {
                                setState(() {
                                  _allFailure = false;
                                  _failureMessage = null;
                                  _isLoading = true;
                                  _statuses.clear();
                                  for (final String id in _sourceOrder) {
                                    _statuses[id] = ScrapeStatus.waiting;
                                  }
                                });
                                if (_sourceOrder.isEmpty) {
                                  final String? catalogErr =
                                      await _fetchAndApplyCatalog();
                                  if (!context.mounted) {
                                    return;
                                  }
                                  if (catalogErr != null) {
                                    _showSnackBarIfMounted(catalogErr);
                                  }
                                  setState(() {
                                    for (final String id in _sourceOrder) {
                                      _statuses[id] = ScrapeStatus.waiting;
                                    }
                                  });
                                }
                                _startStreamScrape();
                              },
                              child: const Text('Try again'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.x2),
                      TextButton(
                        onPressed: _showManualPicker,
                        child: const Text('Choose source manually'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}

/// Centered hero block above the source list. Mirrors the web scraping
/// page's "Looking for streams" + active provider readout.
class _ScrapingHeader extends StatelessWidget {
  const _ScrapingHeader({
    required this.activeName,
    required this.allFailure,
    required this.loading,
  });

  final String? activeName;
  final bool allFailure;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String headline = allFailure
        ? 'No stream found'
        : (activeName != null
            ? 'Looking for streams'
            : (loading ? 'Looking for streams' : 'Preparing'));
    final String sub = allFailure
        ? 'Every source we tried did not work. Try again or pick one manually.'
        : (activeName != null
            ? 'Currently checking $activeName'
            : 'Picking up the source catalog from the resolver.');

    return Column(
      children: <Widget>[
        Center(
          child: SizedBox(
            width: AppSpacing.x16,
            height: AppSpacing.x16,
            child: allFailure
                ? const StatusCircle(
                    status: ScrapeStatus.failure,
                    size: AppSpacing.x16,
                    strokeWidth: 3,
                  )
                : const StatusCircle(
                    status: ScrapeStatus.pending,
                    size: AppSpacing.x16,
                    strokeWidth: 3,
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.x4),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppColors.typeEmphasis,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          sub,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.typeSecondary,
          ),
        ),
      ],
    );
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

  _ScrapeNode copyWith({String? name, List<String>? embedIds}) {
    return _ScrapeNode(
      id: id,
      name: name ?? this.name,
      embedIds: embedIds ?? this.embedIds,
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
        child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
