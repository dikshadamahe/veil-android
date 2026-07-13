import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/app_theme.dart';
import '../utils/webview_ad_blocker.dart';

/// Fullscreen third-party iframe embed (e.g. `embed.st/...`) rendered inside an
/// [InAppWebView].
///
/// streamed.pk sources are third-party iframe embeds, not HLS/MP4, so playback
/// happens inside a WebView rather than ExoPlayer. [WebViewAdBlocker] suppresses
/// ad / betting popups and click-outs, and its document-start scripts strip the
/// iframe `sandbox` attribute so the embedded player is allowed to run. This is
/// the lightweight replacement for the former GeckoView + uBlock stack.
class SportsEmbedView extends StatelessWidget {
  const SportsEmbedView({
    super.key,
    required this.url,
    required this.userAgent,
    this.onLoadStart,
    this.onLoadStop,
    this.onError,
  });

  final String url;
  final String userAgent;

  /// Fires when the main frame starts loading, with the target URL.
  final ValueChanged<String?>? onLoadStart;

  /// Fires when a load settles; `true` on success, `false` on main-frame error.
  final ValueChanged<bool>? onLoadStop;

  /// Fires with an error description on main-frame load failure.
  final ValueChanged<String?>? onError;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.blackC50,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialUserScripts: WebViewAdBlocker.embedUserScripts,
        initialSettings: WebViewAdBlocker.embedSettings(userAgent: userAgent),
        shouldOverrideUrlLoading: (
          InAppWebViewController controller,
          NavigationAction action,
        ) async {
          return WebViewAdBlocker.shouldAllowNavigation(
            action: action,
            embedOrigin: Uri.parse(url),
          );
        },
        onLoadStart: (InAppWebViewController controller, WebUri? uri) {
          onLoadStart?.call(uri?.toString());
        },
        onLoadStop: (InAppWebViewController controller, WebUri? uri) {
          onLoadStop?.call(true);
        },
        onCreateWindow: WebViewAdBlocker.refuseCreateWindow,
        onReceivedError: (
          InAppWebViewController controller,
          WebResourceRequest request,
          WebResourceError error,
        ) {
          if (request.isForMainFrame ?? false) {
            onLoadStop?.call(false);
            onError?.call(error.description);
          }
        },
      ),
    );
  }
}
