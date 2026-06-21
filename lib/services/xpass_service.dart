import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/omss_source.dart';

/// Builds the synthetic [OmssSource] for the XPass iframe embed player.
///
/// `play.xpass.top` is an iframe embed player (loaded in a WebView), not a raw
/// stream URL. These helpers are pure and stateless — no HTTP, no extra deps.
class XpassService {
  XpassService._();

  static const String _base = 'https://play.xpass.top';
  static const String _providerId = 'xpass';
  static const String _providerName = 'XPass';

  static String buildMovieEmbedUrl(String tmdbId) => '$_base/e/movie/$tmdbId';

  static String buildTvEmbedUrl(String tmdbId, int season, int episode) =>
      '$_base/e/tv/$tmdbId/$season/$episode';

  /// Builds the synthetic [OmssSource] to inject into any [OmssResponse].
  static OmssSource buildSource(MediaItem item, {int? season, int? episode}) {
    final String tmdbId = '${item.tmdbId}';
    final String url = (season != null && episode != null)
        ? buildTvEmbedUrl(tmdbId, season, episode)
        : buildMovieEmbedUrl(tmdbId);
    return OmssSource(
      url: url,
      type: 'embed',
      quality: null,
      providerId: _providerId,
      providerName: _providerName,
    );
  }
}
