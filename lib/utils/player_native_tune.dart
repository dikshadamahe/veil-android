// No-op stubs: video_player (ExoPlayer) handles playback tuning natively.
//
// These functions existed for media_kit/libmpv property injection. Kept as
// no-ops so any stale call-sites compile without error until fully removed.

/// Previously configured libmpv demuxer/volume-max properties.
Future<void> applyNativePlaybackTune(dynamic player) async {
  // No-op: video_player (ExoPlayer) handles tuning natively.
}

/// Previously pushed subtitle style to libmpv sub-* properties.
Future<void> applyNativeSubtitleStyle(
  dynamic player, {
  required int size,
  required String colorHex,
  required double bgOpacity,
}) async {
  // No-op: video_player does not expose native subtitle style properties.
  // TODO: implement subtitle styling with video_player if needed.
}
