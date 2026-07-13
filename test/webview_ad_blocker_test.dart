import 'package:flutter_test/flutter_test.dart';
import 'package:pstream_android/utils/webview_ad_blocker.dart';

void main() {
  group('WebViewAdBlocker.isBlockedUrl', () {
    test('blocks Parimatch and common ad networks', () {
      expect(
        WebViewAdBlocker.isBlockedUrl(
          Uri.parse('https://parimatch.com/promo?from=embed'),
        ),
        isTrue,
      );
      expect(
        WebViewAdBlocker.isBlockedUrl(
          Uri.parse('https://securepubads.g.doubleclick.net/gampad/ads'),
        ),
        isTrue,
      );
      expect(
        WebViewAdBlocker.isBlockedUrl(
          Uri.parse('https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js'),
        ),
        isTrue,
      );
    });

    test('allows normal embed and CDN hosts', () {
      expect(
        WebViewAdBlocker.isBlockedUrl(Uri.parse('https://embed.st/abc123')),
        isFalse,
      );
      expect(
        WebViewAdBlocker.isBlockedUrl(
          Uri.parse('https://cdn.example.com/playlist.m3u8'),
        ),
        isFalse,
      );
    });
  });
}
