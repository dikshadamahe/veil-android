/// One selectable subtitle from Wyzie or OpenSubtitles (not embedded in stream).
class ExternalSubtitleOffer {
  const ExternalSubtitleOffer({
    required this.id,
    required this.title,
    required this.languageLabel,
    required this.providerLabel,
    this.directUrl,
    this.opensubtitlesFileId,
  });

  final String id;
  final String title;
  final String languageLabel;
  final String providerLabel;

  /// Wyzie (and similar): HTTPS URL to SRT/VTT ready for [SubtitleTrack.uri].
  final String? directUrl;

  /// OpenSubtitles file id — resolve to a temporary download URL when selected.
  final int? opensubtitlesFileId;

  bool get needsOpensubtitlesDownload => opensubtitlesFileId != null;
}

/// Result of querying Wyzie and OpenSubtitles in one pass.
class OnlineSubtitleSearchResult {
  const OnlineSubtitleSearchResult({
    required this.offers,
    this.skipReasons = const <String>[],
    this.providerErrors = const <String>[],
  });

  final List<ExternalSubtitleOffer> offers;

  /// Preconditions that prevented any online request (e.g. TV with no episode).
  final List<String> skipReasons;

  /// Non-fatal failures (HTTP/network) for one or both providers.
  final List<String> providerErrors;
}
