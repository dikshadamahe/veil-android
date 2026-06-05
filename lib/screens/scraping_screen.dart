// ScrapingScreen — a thin, transparent loading gate.
//
// cinepro-org/core returns every playable source for a title in a single
// HTTP GET (`/v1/movies/{tmdbId}` or `/v1/tv/{id}/seasons/{s}/episodes/{e}`).
// The old multi-phase cascade (client-side WebView scrapers, then XPrime,
// then per-source blocking scrape, then SSE) is gone. This screen now:
//   1. Issues the single OMSS request on `initState`.
//   2. On success, pushes `/player` with the full OmssResponse.
//   3. On failure, shows a "Couldn't find sources" error state with
//      Try Again / Back actions.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/omss_source.dart';
import 'package:pstream_android/providers/stream_provider.dart';
import 'package:pstream_android/screens/player_screen.dart';
import 'package:pstream_android/services/stream_service.dart';

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
  late final StreamService _streamService;
  Future<OmssResponse>? _request;

  @override
  void initState() {
    super.initState();
    _streamService = ref.read(streamServiceProvider);
    _request = _fetch();
  }

  Future<OmssResponse> _fetch() {
    return _streamService.fetchSources(
      widget.mediaItem,
      season: widget.season,
      episode: widget.episode,
    );
  }

  void _retry() {
    setState(() {
      _request = _fetch();
    });
  }

  void _onSuccess(OmssResponse response) {
    if (!mounted) {
      return;
    }
    context.push(
      '/player',
      extra: PlayerScreenArgs(
        mediaItem: widget.mediaItem,
        omssResponse: response,
        season: widget.season,
        episode: widget.episode,
        seasonTmdbId: widget.seasonTmdbId,
        episodeTmdbId: widget.episodeTmdbId,
        seasonTitle: widget.seasonTitle,
        resumeFrom: widget.resumeFrom,
        replaceEpoch: DateTime.now().microsecondsSinceEpoch,
      ),
    );
  }

  String _describeMedia() {
    final MediaItem m = widget.mediaItem;
    if (m.isShow && widget.season != null && widget.episode != null) {
      return '${m.title} · S${widget.season} E${widget.episode}';
    }
    return m.title;
  }

  @override
  Widget build(BuildContext context) {
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.x6,
                vertical: AppSpacing.x8,
              ),
              child: FutureBuilder<OmssResponse>(
                future: _request,
                builder: (BuildContext context,
                    AsyncSnapshot<OmssResponse> snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return _LoadingState(description: _describeMedia());
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return _ErrorState(
                      error: snapshot.error,
                      description: _describeMedia(),
                      onRetry: _retry,
                      onBack: () => Navigator.of(context).maybePop(),
                    );
                  }
                  final OmssResponse response = snapshot.data!;
                  if (response.isEmpty) {
                    return _ErrorState(
                      error: const _EmptySourcesError(),
                      description: _describeMedia(),
                      onRetry: _retry,
                      onBack: () => Navigator.of(context).maybePop(),
                    );
                  }
                  // Schedule the navigation for the next frame so the
                  // FutureBuilder has finished its build phase.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _onSuccess(response);
                    }
                  });
                  return _LoadingState(description: _describeMedia());
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox(
          width: AppSpacing.x16,
          height: AppSpacing.x16,
          child: RepaintBoundary(
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        const SizedBox(height: AppSpacing.x6),
        Text(
          'Finding sources…',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppColors.typeEmphasis,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          description,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.typeSecondary,
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.description,
    required this.onRetry,
    required this.onBack,
  });

  final Object? error;
  final String description;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  String get _userMessage {
    if (error is OmssException) {
      final OmssException e = error as OmssException;
      return 'The resolver returned HTTP ${e.statusCode}. '
          'Check the cinepro server logs and your network.';
    }
    if (error is TimeoutException) {
      return 'The resolver took too long to respond (over 60 seconds). '
          'Try again or check the cinepro server.';
    }
    if (error is SocketException) {
      return "Couldn't reach the resolver. "
          'Check ORACLE_URL, Wi-Fi, and the cinepro server.';
    }
    if (error is _EmptySourcesError) {
      return 'cinepro returned no playable sources for this title. '
          'It may be too new, region-locked, or temporarily unavailable.';
    }
    if (error is FormatException) {
      return "The resolver returned an unexpected response shape. "
          'Check the cinepro server version.';
    }
    return 'Something went wrong while finding sources.';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(
          Icons.error_outline_rounded,
          color: AppColors.videoContextError,
          size: AppSpacing.x16,
        ),
        const SizedBox(height: AppSpacing.x4),
        Text(
          "Couldn't find sources",
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppColors.typeEmphasis,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          description,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.typeSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        Text(
          _userMessage,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AppColors.typeSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.x6),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppSpacing.x12),
                ),
                onPressed: onBack,
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.x3),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.buttonsPurple,
                  foregroundColor: AppColors.typeEmphasis,
                  minimumSize: const Size.fromHeight(AppSpacing.x12),
                ),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptySourcesError implements Exception {
  const _EmptySourcesError();
}
