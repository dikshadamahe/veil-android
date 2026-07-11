import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef GeckoLoadErrorCallback = void Function(GeckoLoadError error);

@immutable
class GeckoLoadError {
  const GeckoLoadError({
    required this.url,
    required this.category,
    required this.code,
  });

  final String? url;
  final int? category;
  final int? code;
}

class GeckoEmbedController {
  MethodChannel? _channel;

  Future<void> loadUrl(String url) async {
    await _channel?.invokeMethod<void>('loadUrl', <String, Object?>{'url': url});
  }

  Future<void> reload() async {
    await _channel?.invokeMethod<void>('reload');
  }

  void _attach(MethodChannel channel) => _channel = channel;
  void _detach(MethodChannel channel) {
    if (identical(_channel, channel)) {
      _channel = null;
    }
  }
}

/// Android GeckoView surface used only for third-party iframe embeds.
///
/// Sandbox removal and popup suppression are document-start content scripts in
/// the bundled `veil_embed_guard` WebExtension. uBlock Origin is installed once
/// on the shared native GeckoRuntime.
class GeckoEmbedView extends StatefulWidget {
  const GeckoEmbedView({
    super.key,
    required this.url,
    required this.userAgent,
    this.controller,
    this.onLoadStart,
    this.onLoadStop,
    this.onError,
    this.onCreateWindowRefused,
  });

  final String url;
  final String userAgent;
  final GeckoEmbedController? controller;
  final ValueChanged<String?>? onLoadStart;
  final ValueChanged<bool>? onLoadStop;
  final GeckoLoadErrorCallback? onError;
  final ValueChanged<String?>? onCreateWindowRefused;

  @override
  State<GeckoEmbedView> createState() => _GeckoEmbedViewState();
}

class _GeckoEmbedViewState extends State<GeckoEmbedView> {
  MethodChannel? _channel;

  @override
  void didUpdateWidget(covariant GeckoEmbedView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      final MethodChannel? channel = _channel;
      if (channel != null) {
        oldWidget.controller?._detach(channel);
        widget.controller?._attach(channel);
      }
    }
    if (oldWidget.url != widget.url) {
      widget.controller?.loadUrl(widget.url);
    }
  }

  @override
  void dispose() {
    final MethodChannel? channel = _channel;
    if (channel != null) {
      widget.controller?._detach(channel);
      channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ?? <Object?, Object?>{};
    switch (call.method) {
      case 'loadStart':
        widget.onLoadStart?.call(args['url'] as String?);
      case 'loadStop':
        widget.onLoadStop?.call(args['success'] as bool? ?? false);
      case 'loadError':
        widget.onError?.call(
          GeckoLoadError(
            url: args['url'] as String?,
            category: args['category'] as int?,
            code: args['code'] as int?,
          ),
        );
      case 'createWindowRefused':
        widget.onCreateWindowRefused?.call(args['url'] as String?);
    }
  }

  void _onPlatformViewCreated(int viewId) {
    final MethodChannel channel = MethodChannel('veil/gecko_embed/$viewId');
    _channel = channel;
    channel.setMethodCallHandler(_handleNativeCall);
    widget.controller?._attach(channel);
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: Text('Gecko embeds require Android')),
      );
    }
    return AndroidView(
      viewType: 'veil/gecko_embed',
      creationParams: <String, Object?>{
        'url': widget.url,
        'userAgent': widget.userAgent,
      },
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }
}
