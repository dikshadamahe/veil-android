import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/app_theme.dart';
import '../utils/webview_ad_blocker.dart';

/// Immutable snapshot of the XPass embed player state, pushed upward to the
/// host [PlayerScreen] via [XpassEmbedPlayer.onStateChanged].
class XpassPlayerState {
  const XpassPlayerState({
    this.position = 0,
    this.duration = 0,
    this.isPlaying = false,
    this.hasError = false,
    this.errorMessage,
  });

  /// Current playback position in seconds.
  final double position;

  /// Total duration in seconds (0 when unknown).
  final double duration;

  final bool isPlaying;
  final bool hasError;
  final String? errorMessage;

  XpassPlayerState copyWith({
    double? position,
    double? duration,
    bool? isPlaying,
    bool? hasError,
    String? errorMessage,
  }) {
    return XpassPlayerState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Imperative handle the host screen uses to drive the embed player.
///
/// Bound to the live [XpassEmbedPlayer] state once the widget mounts; calls
/// before that are safely ignored.
class XpassEmbedController {
  _XpassEmbedPlayerState? _state;

  void _attach(_XpassEmbedPlayerState state) => _state = state;
  void _detach(_XpassEmbedPlayerState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  void play() => _state?._play();
  void pause() => _state?._pause();
  void seek(int seconds) => _state?._seek(seconds);
}

/// Renders the `play.xpass.top` iframe embed inside an [InAppWebView] and
/// bridges its `window.postMessage` protocol to/from Flutter.
class XpassEmbedPlayer extends StatefulWidget {
  const XpassEmbedPlayer({
    super.key,
    required this.embedUrl,
    required this.onStateChanged,
    this.controller,
    this.resumeFrom,
  });

  final String embedUrl;
  final ValueChanged<XpassPlayerState> onStateChanged;
  final XpassEmbedController? controller;

  /// Seconds to resume from — sent as a `playAt` action on the `ready` event.
  final int? resumeFrom;

  @override
  State<XpassEmbedPlayer> createState() => _XpassEmbedPlayerState();
}

class _XpassEmbedPlayerState extends State<XpassEmbedPlayer> {
  static const String _listenerJs = '''
window.addEventListener('message', function(e) {
  try {
    if (e.data && e.data.type === 'player.event') {
      window.flutter_inappwebview.callHandler('xpassEvent', JSON.stringify(e.data));
    }
  } catch (err) {}
});
''';

  InAppWebViewController? _webController;
  XpassPlayerState _state = const XpassPlayerState();

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(covariant XpassEmbedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  void _emit(XpassPlayerState next) {
    _state = next;
    widget.onStateChanged(next);
  }

  void _postAction(Map<String, Object?> action) {
    final String payload = jsonEncode(action);
    _webController?.evaluateJavascript(
      source: "window.postMessage($payload, '*');",
    );
  }

  void _play() => _postAction(<String, Object?>{
    'type': 'player.action',
    'action': 'play',
  });

  void _pause() => _postAction(<String, Object?>{
    'type': 'player.action',
    'action': 'pause',
  });

  void _seek(int seconds) => _postAction(<String, Object?>{
    'type': 'player.action',
    'action': 'seek',
    'position': seconds,
  });

  void _playAt(int seconds) => _postAction(<String, Object?>{
    'type': 'player.action',
    'action': 'playAt',
    'position': seconds,
  });

  void _handleEvent(List<dynamic> args) {
    if (args.isEmpty) {
      return;
    }
    Map<String, dynamic>? data;
    try {
      data = jsonDecode('${args.first}') as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final Object? rawEvent = data['event'];
    if (rawEvent is! Map) {
      return;
    }
    final Map<String, dynamic> event = Map<String, dynamic>.from(rawEvent);
    final String name = '${event['name'] ?? ''}';

    switch (name) {
      case 'ready':
        final int? resume = widget.resumeFrom;
        if (resume != null && resume > 0) {
          _playAt(resume);
        }
        break;
      case 'position':
        _emit(
          _state.copyWith(
            position: _toDouble(event['position']) ?? _state.position,
            duration: _toDouble(event['duration']) ?? _state.duration,
          ),
        );
        break;
      case 'play':
        _emit(_state.copyWith(isPlaying: true));
        break;
      case 'pause':
        _emit(_state.copyWith(isPlaying: false));
        break;
      case 'end':
        _emit(_state.copyWith(isPlaying: false));
        break;
      case 'error':
        _emit(
          _state.copyWith(
            hasError: true,
            errorMessage: '${event['message'] ?? event['code'] ?? 'Embed error'}',
            isPlaying: false,
          ),
        );
        break;
      default:
        break;
    }
  }

  static double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value');
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.blackC50,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.embedUrl)),
        initialUserScripts: WebViewAdBlocker.antiPopupUserScripts,
        initialSettings: WebViewAdBlocker.embedSettings(),
        shouldOverrideUrlLoading: (
          InAppWebViewController controller,
          NavigationAction action,
        ) async {
          return WebViewAdBlocker.shouldAllowNavigation(
            action: action,
            embedOrigin: Uri.parse(widget.embedUrl),
          );
        },
        onWebViewCreated: (InAppWebViewController controller) {
          _webController = controller;
          controller.addJavaScriptHandler(
            handlerName: 'xpassEvent',
            callback: (List<dynamic> args) {
              _handleEvent(args);
              return null;
            },
          );
        },
        onLoadStop: (InAppWebViewController controller, WebUri? url) async {
          await controller.evaluateJavascript(source: _listenerJs);
        },
        onCreateWindow: WebViewAdBlocker.refuseCreateWindow,
        onReceivedError: (
          InAppWebViewController controller,
          WebResourceRequest request,
          WebResourceError error,
        ) {
          if (request.isForMainFrame ?? false) {
            _emit(
              _state.copyWith(
                hasError: true,
                errorMessage: error.description,
                isPlaying: false,
              ),
            );
          }
        },
      ),
    );
  }
}
