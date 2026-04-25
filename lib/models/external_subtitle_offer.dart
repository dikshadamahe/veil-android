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
