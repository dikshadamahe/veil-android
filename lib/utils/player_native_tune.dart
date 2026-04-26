import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Optional libmpv tuning for Android native [Player] (playback parity / headroom).
///
/// Safe no-ops on web or non-native backends.
Future<void> applyNativePlaybackTune(Player player) async {
  if (kIsWeb) {
    return;
  }
  final PlatformPlayer? platform = player.platform;
  if (platform is! NativePlayer) {
    return;
  }
  try {
    await platform.setProperty('volume-max', '150');
    await platform.setProperty('demuxer-readahead-secs', '20');
  } catch (error, stackTrace) {
    debugPrint('applyNativePlaybackTune: $error\n$stackTrace');
  }
}

/// Push subtitle style to libmpv so the on-screen render matches the user's
/// Customize choices. [size] is in libmpv `sub-font-size` units, [colorHex]
/// is `#AARRGGBB`, and [bgOpacity] is 0..1 mapped onto the alpha channel of
/// `sub-back-color` (RGB always black for legibility).
Future<void> applyNativeSubtitleStyle(
  Player player, {
  required int size,
  required String colorHex,
  required double bgOpacity,
}) async {
  if (kIsWeb) {
    return;
  }
  final PlatformPlayer? platform = player.platform;
  if (platform is! NativePlayer) {
    return;
  }
  try {
    final int alpha = (bgOpacity.clamp(0.0, 1.0) * 255).round();
    final String alphaHex =
        alpha.toRadixString(16).padLeft(2, '0').toUpperCase();
    final String bgColor = '#${alphaHex}000000';
    await platform.setProperty('sub-font-size', '$size');
    await platform.setProperty('sub-color', colorHex);
    await platform.setProperty('sub-back-color', bgColor);
    await platform.setProperty('sub-border-color', '#FF000000');
    await platform.setProperty('sub-border-size', '2');
  } catch (error, stackTrace) {
    debugPrint('applyNativeSubtitleStyle: $error\n$stackTrace');
  }
}
