/// A single Live TV channel from `https://wfs.lol/live-channels.json`.
///
/// Every channel exposes a direct HLS `.m3u8` stream (`src == "hls"`).
class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.cat,
    required this.url,
    required this.logo,
  });

  final String id;
  final String name;
  final String cat;

  /// Direct HLS m3u8 stream URL.
  final String url;
  final String logo;

  /// Derives the EPG lookup key: `"Newsmax2.us"` → `"newsmax2"`.
  String get epgKey => id.split('.').first.toLowerCase();

  factory LiveChannel.fromJson(Map<String, dynamic> json) => LiveChannel(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        cat: '${json['cat'] ?? ''}',
        url: '${json['url'] ?? ''}',
        logo: '${json['logo'] ?? ''}',
      );
}

/// A single EPG program entry from `https://wfs.lol/live-epg.json`.
class LiveProgram {
  const LiveProgram({
    required this.startMs,
    required this.endMs,
    required this.title,
  });

  /// Epoch milliseconds.
  final int startMs;

  /// Epoch milliseconds.
  final int endMs;
  final String title;

  bool get isNow {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return now >= startMs && now < endMs;
  }

  Duration get remaining =>
      Duration(milliseconds: endMs - DateTime.now().millisecondsSinceEpoch);

  factory LiveProgram.fromJson(Map<String, dynamic> json) => LiveProgram(
        startMs: (json['s'] as num).toInt(),
        endMs: (json['e'] as num).toInt(),
        title: '${json['t'] ?? ''}',
      );
}
