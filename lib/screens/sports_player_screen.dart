import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/match_stream.dart';
import 'package:pstream_android/models/sports_match.dart';
import 'package:pstream_android/providers/sports_provider.dart';

/// Fullscreen iframe-embed player for a sports match.
///
/// streamed.pk streams are third-party **iframe embeds** (e.g. `embed.st/...`),
/// not HLS/MP4, so playback happens inside an [InAppWebView] rather than
/// ExoPlayer. The user can switch between the match's sources and their
/// individual streams (language / HD).
class SportsPlayerScreen extends ConsumerStatefulWidget {
  const SportsPlayerScreen({super.key, required this.match});

  final SportsMatch match;

  @override
  ConsumerState<SportsPlayerScreen> createState() => _SportsPlayerScreenState();
}

class _SportsPlayerScreenState extends ConsumerState<SportsPlayerScreen> {
  /// Injected at document start so the streamed embed's inner player iframe
  /// never runs under a `sandbox` restriction.
  ///
  /// The `embed.st` embed page renders the real player inside a child
  /// `<iframe sandbox="...">`. That player detects the sandbox and refuses to
  /// start, showing "Remove sandbox attributes on the iframe tag" (or just a
  /// black screen). The outer embed page is same-origin to us, so we strip the
  /// `sandbox` attribute off every iframe element — via a `setAttribute` guard
  /// (blocks it being set), a `MutationObserver` (catches dynamically added or
  /// mutated iframes), and by forcing a reload of any iframe that already
  /// loaded sandboxed.
  static const String _stripSandboxJs = r'''
(function () {
  if (window.__pstreamSandboxStrip) { return; }
  window.__pstreamSandboxStrip = true;

  function strip(frame) {
    try {
      if (!frame || frame.tagName !== 'IFRAME') { return; }
      if (!frame.hasAttribute('sandbox')) { return; }
      frame.removeAttribute('sandbox');
      var src = frame.getAttribute('src');
      if (src) {
        frame.setAttribute('src', src);
      }
    } catch (e) {}
  }

  var nativeSetAttribute = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function (name, value) {
    if (this && this.tagName === 'IFRAME' &&
        String(name).toLowerCase() === 'sandbox') {
      return;
    }
    return nativeSetAttribute.call(this, name, value);
  };

  function sweep(root) {
    try {
      var frames = (root || document).querySelectorAll('iframe[sandbox]');
      for (var i = 0; i < frames.length; i++) { strip(frames[i]); }
    } catch (e) {}
  }

  var observer = new MutationObserver(function (mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var m = mutations[i];
      if (m.type === 'attributes' && m.attributeName === 'sandbox') {
        strip(m.target);
        continue;
      }
      for (var j = 0; j < m.addedNodes.length; j++) {
        var node = m.addedNodes[j];
        if (node && node.nodeType === 1) {
          if (node.tagName === 'IFRAME') { strip(node); }
          if (node.querySelectorAll) { sweep(node); }
        }
      }
    }
  });

  function start() {
    sweep(document);
    var target = document.documentElement || document;
    observer.observe(target, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['sandbox'],
    });
  }

  if (document.documentElement) {
    start();
  } else {
    document.addEventListener('readystatechange', start, { once: true });
  }
})();
''';

  static final UnmodifiableListView<UserScript> _embedUserScripts =
      UnmodifiableListView<UserScript>(<UserScript>[
    UserScript(
      source: _stripSandboxJs,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
  ]);

  late MatchSource _selectedSource;

  /// User's explicit stream choice; null falls back to an auto-picked stream.
  MatchStream? _selectedStream;

  bool _overlayVisible = true;
  bool _webLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedSource = widget.match.sources.first;
    _enterImmersive();
  }

  @override
  void dispose() {
    _exitImmersive();
    super.dispose();
  }

  Future<void> _enterImmersive() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitImmersive() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  /// Best default stream for [streams]: first HD English, else first HD,
  /// else the first stream.
  MatchStream? _autoPick(List<MatchStream> streams) {
    if (streams.isEmpty) {
      return null;
    }
    for (final MatchStream s in streams) {
      if (s.hd && s.language.toLowerCase().contains('en')) {
        return s;
      }
    }
    for (final MatchStream s in streams) {
      if (s.hd) {
        return s;
      }
    }
    return streams.first;
  }

  Future<void> _openStreamPicker() async {
    final ({MatchSource source, MatchStream stream})? result =
        await showModalBottomSheet<({MatchSource source, MatchStream stream})>(
      context: context,
      backgroundColor: AppColors.modalBackground,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return _StreamPickerSheet(
          match: widget.match,
          initialSource: _selectedSource,
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _selectedSource = result.source;
        _selectedStream = result.stream;
        _webLoading = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MatchStream>> streamsAsync = ref.watch(
      matchStreamsProvider(
        MatchStreamKey(source: _selectedSource.source, id: _selectedSource.id),
      ),
    );

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: AppColors.blackC50,
        body: streamsAsync.when(
          data: (List<MatchStream> streams) {
            final MatchStream? active = _resolveActive(streams);
            if (active == null) {
              return _MessageView(
                icon: Icons.videocam_off_rounded,
                message: 'No playable streams for this source.',
                actionLabel: 'Change source',
                onAction: _openStreamPicker,
              );
            }
            return _buildPlayer(active);
          },
          loading: () => const _MessageView(
            icon: null,
            message: 'Loading stream…',
          ),
          error: (Object error, StackTrace _) => _MessageView(
            icon: Icons.cloud_off_rounded,
            message: "Couldn't load this stream.",
            actionLabel: 'Retry',
            onAction: () => ref.invalidate(
              matchStreamsProvider(
                MatchStreamKey(
                  source: _selectedSource.source,
                  id: _selectedSource.id,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Returns the user's chosen stream when it still exists in [streams],
  /// otherwise an auto-picked default.
  MatchStream? _resolveActive(List<MatchStream> streams) {
    final MatchStream? chosen = _selectedStream;
    if (chosen != null) {
      for (final MatchStream s in streams) {
        if (s.id == chosen.id && s.streamNo == chosen.streamNo) {
          return chosen;
        }
      }
    }
    return _autoPick(streams);
  }

  Widget _buildPlayer(MatchStream stream) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        GestureDetector(
          onTap: () => setState(() => _overlayVisible = !_overlayVisible),
          child: InAppWebView(
            key: ValueKey<String>(stream.embedUrl),
            initialUrlRequest: URLRequest(url: WebUri(stream.embedUrl)),
            initialUserScripts: _embedUserScripts,
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: false,
              supportZoom: false,
              transparentBackground: true,
            ),
            onLoadStop: (InAppWebViewController controller, WebUri? url) {
              if (mounted) {
                setState(() => _webLoading = false);
              }
            },
            onReceivedError: (
              InAppWebViewController controller,
              WebResourceRequest request,
              WebResourceError error,
            ) {
              if ((request.isForMainFrame ?? false) && mounted) {
                setState(() => _webLoading = false);
              }
            },
            // Block ad popups from opening new windows.
            onCreateWindow: (
              InAppWebViewController controller,
              CreateWindowAction action,
            ) async {
              return false;
            },
          ),
        ),
        if (_webLoading)
          const IgnorePointer(
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_overlayVisible) _buildTopOverlay(stream),
      ],
    );
  }

  Widget _buildTopOverlay(MatchStream stream) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              AppColors.blackC50.withValues(alpha: 0.8),
              AppColors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x2,
              vertical: AppSpacing.x1,
            ),
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: AppColors.typeEmphasis,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        widget.match.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppColors.typeEmphasis,
                                ),
                      ),
                      Text(
                        '${_selectedSource.source} · ${stream.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.typeSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _openStreamPicker,
                  icon: const Icon(Icons.playlist_play_rounded),
                  label: const Text('Streams'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet to pick a source and one of its streams. Pops with the
/// selected `(source, stream)` record.
class _StreamPickerSheet extends ConsumerStatefulWidget {
  const _StreamPickerSheet({required this.match, required this.initialSource});

  final SportsMatch match;
  final MatchSource initialSource;

  @override
  ConsumerState<_StreamPickerSheet> createState() => _StreamPickerSheetState();
}

class _StreamPickerSheetState extends ConsumerState<_StreamPickerSheet> {
  late MatchSource _source;

  @override
  void initState() {
    super.initState();
    _source = widget.initialSource;
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<MatchStream>> streamsAsync = ref.watch(
      matchStreamsProvider(
        MatchStreamKey(source: _source.source, id: _source.id),
      ),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x4,
          AppSpacing.x0,
          AppSpacing.x4,
          AppSpacing.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Streams',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.x1),
            Text(
              'Pick a source, then a stream. Sources vary in language and quality.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.x3),
            SizedBox(
              height: AppSpacing.x10,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: widget.match.sources.length,
                itemBuilder: (BuildContext context, int index) {
                  final MatchSource s = widget.match.sources[index];
                  final bool selected = s.source == _source.source &&
                      s.id == _source.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.x2),
                    child: Center(
                      child: ChoiceChip(
                        label: Text(s.source),
                        selected: selected,
                        onSelected: (_) => setState(() => _source = s),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: streamsAsync.when(
                data: (List<MatchStream> streams) {
                  if (streams.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.x6),
                      child: Text('No streams for this source.'),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: streams.length,
                    itemBuilder: (BuildContext context, int index) {
                      final MatchStream stream = streams[index];
                      return ListTile(
                        leading: Icon(
                          stream.hd
                              ? Icons.hd_rounded
                              : Icons.sd_rounded,
                          color: stream.hd
                              ? AppColors.typeLink
                              : AppColors.typeSecondary,
                        ),
                        title: Text(stream.label),
                        subtitle: Text('Stream ${stream.streamNo}'),
                        onTap: () => Navigator.of(context).pop(
                          (source: _source, stream: stream),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.x6),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (Object error, StackTrace _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.typeSecondary,
                      ),
                      const SizedBox(width: AppSpacing.x2),
                      const Expanded(
                        child: Text("Couldn't load streams for this source."),
                      ),
                      TextButton(
                        onPressed: () => ref.invalidate(
                          matchStreamsProvider(
                            MatchStreamKey(source: _source.source, id: _source.id),
                          ),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData? icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon == null)
                  const CircularProgressIndicator()
                else
                  Icon(icon, color: AppColors.typeSecondary, size: AppSpacing.x12),
                const SizedBox(height: AppSpacing.x3),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.typeEmphasis,
                      ),
                ),
                if (actionLabel != null && onAction != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.x4),
                  OutlinedButton(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.typeEmphasis,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ],
    );
  }
}
