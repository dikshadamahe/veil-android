/// A single playable stream for a match, from
/// `GET {SPORTS_URL}/v1/stream/:source/:id` (streamed.pk `/api/stream/...`).
///
/// Upstream shape:
/// ```json
/// {
///   "id": "stream_456",
///   "streamNo": 1,
///   "language": "English",
///   "hd": true,
///   "embedUrl": "https://embed.st/...",
///   "source": "alpha"
/// }
/// ```
///
/// `embedUrl` is an **iframe embed** (not HLS) and must be opened in a WebView.
class MatchStream {
  const MatchStream({
    required this.id,
    required this.streamNo,
    required this.language,
    required this.hd,
    required this.embedUrl,
    required this.source,
  });

  final String id;
  final int streamNo;
  final String language;
  final bool hd;

  /// Iframe embed URL loaded in an InAppWebView.
  final String embedUrl;

  /// Source identifier this stream belongs to.
  final String source;

  /// Compact label, e.g. `"English · HD"` / `"Stream 2 · SD"`.
  String get label {
    final String lang = language.trim().isEmpty ? 'Stream $streamNo' : language.trim();
    return '$lang · ${hd ? 'HD' : 'SD'}';
  }

  factory MatchStream.fromJson(Map<String, dynamic> json) => MatchStream(
        id: '${json['id'] ?? ''}',
        streamNo: (json['streamNo'] is num)
            ? (json['streamNo'] as num).toInt()
            : 0,
        language: '${json['language'] ?? ''}',
        hd: json['hd'] == true,
        embedUrl: '${json['embedUrl'] ?? ''}',
        source: '${json['source'] ?? ''}',
      );
}
