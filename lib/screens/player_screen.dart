import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/external_subtitle_offer.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/episode.dart';
import 'package:pstream_android/models/omss_source.dart';
import 'package:pstream_android/models/season.dart';
import 'package:pstream_android/models/stream_result.dart';
import 'package:pstream_android/providers/storage_provider.dart';
import 'package:pstream_android/providers/stream_provider.dart';
import 'package:pstream_android/screens/scraping_screen.dart';
import 'package:pstream_android/services/external_subtitle_service.dart';
import 'package:pstream_android/services/stream_service.dart';
import 'package:pstream_android/storage/local_storage.dart';

import 'package:pstream_android/widgets/player_controls.dart';
import 'package:screen_brightness/screen_brightness.dart';

enum _PlayerEdgeSwipe { none, brightness, volume }

/// Per-source probe result for the "check streams" UI.
/// One row in the subtitles sheet: embedded tracks + online offers for a language.
class _MergedSubtitleLang {
  const _MergedSubtitleLang({
    required this.displayName,
    required this.captions,
    required this.offers,
  });

  final String displayName;
  final List<StreamCaption> captions;
  final List<ExternalSubtitleOffer> offers;

  int get count => captions.length + offers.length;

  String? get primaryLanguageCode {
    for (final StreamCaption c in captions) {
      if (c.language != null && c.language!.trim().isNotEmpty) {
        return c.language;
      }
    }
    return null;
  }
}

class PlayerScreenArgs {
  const PlayerScreenArgs({
    required this.mediaItem,
    required this.omssResponse,
    int? initialSourceIndex,
    this.season,
    this.episode,
    this.seasonTmdbId,
    this.episodeTmdbId,
    this.seasonTitle,
    this.resumeFrom,
    this.replaceEpoch,
    this.preservedCaption,
    this.preservedExternalOfferId,
    this.preservedExternalSummary,
  }) : _initialSourceIndex = initialSourceIndex;

  final MediaItem mediaItem;

  /// The full OMSS v1.0 response for this title. The player uses it
  /// to populate the source picker and to switch sources without
  /// re-fetching unless [refresh] is invoked from the sheet.
  final OmssResponse omssResponse;

  /// Index of the source the caller wants to start with. Defaults to
  /// "first hls at 1080p, else first hls, else first source" when null.
  final int? _initialSourceIndex;

  final int? season;
  final int? episode;
  final String? seasonTmdbId;
  final String? episodeTmdbId;
  final String? seasonTitle;
  final int? resumeFrom;

  /// Bumps on each [context.go] to `/player` so the route [ValueKey] changes
  /// even when the server returns the same source for a fresh OMSS fetch.
  final int? replaceEpoch;

  /// Subtitle state preserved across source switches so the user does not
  /// lose their active track when changing provider.
  final StreamCaption? preservedCaption;
  final String? preservedExternalOfferId;
  final String? preservedExternalSummary;

  /// The [OmssSource] the player should open with. Computed once at
  /// construction; the source sheet may swap to a different source by
  /// constructing a fresh [PlayerScreenArgs] with a new index.
  OmssSource get initialSource {
    final List<OmssSource> sources = omssResponse.sources;
    if (sources.isEmpty) {
      throw StateError('OmssResponse has no sources.');
    }
    final int? idx = _initialSourceIndex;
    if (idx != null && idx >= 0 && idx < sources.length) {
      return sources[idx];
    }
    return _pickInitialSource(sources);
  }

  static OmssSource _pickInitialSource(List<OmssSource> sources) {
    for (final OmssSource s in sources) {
      if (s.isHls && (s.quality ?? '').contains('1080')) {
        return s;
      }
    }
    for (final OmssSource s in sources) {
      if (s.isHls) {
        return s;
      }
    }
    return sources.first;
  }
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args});

  final PlayerScreenArgs args;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  /// Parsed subtitle entries from the active caption file.
  List<Caption> _parsedCaptions = const <Caption>[];
  /// Current subtitle text to display, updated every position tick.
  String _currentSubtitleText = '';
  Timer? _controlsHideTimer;
  Timer? _progressTimer;
  String? _subtitleToast;
  Timer? _subtitleToastTimer;
  Timer? _gestureHintTimer;
  int _playerLogSeq = 0;
  int _lastLoggedPositionBucket = -1;
  int _lastLoggedBufferBucket = -1;

  /// Drives [ValueListenableBuilder] around the open player settings sheet.
  /// Modal routes do not rebuild when this screen [setState]s, so the
  /// Subtitles card must listen here to pick up [_currentSubtitleLabel].
  final ValueNotifier<int> _playerSettingsLabelRev = ValueNotifier<int>(0);

  /// Software volume (0–150 after [applyNativePlaybackTune] raises `volume-max`).
  double _softwareVolume = 100;
  double _screenBrightness = 0.55;
  bool _screenBrightnessPrimed = false;
  _PlayerEdgeSwipe _edgeSwipe = _PlayerEdgeSwipe.none;
  double _edgeSwipeAccumDy = 0;
  double _edgeSwipeStartBrightness = 0.55;
  double _edgeSwipeStartVolume = 100;
  String? _gestureHint;
  IconData? _gestureHintIcon;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _controlsVisible = true;
  bool _subtitlesEnabled = false;
  bool _resumeApplied = false;
  bool _playerReady = false;
  bool _openingStream = false;
  bool _hasPlaybackError = false;
  bool _sourceSwitching = false;
  String? _pendingSourceId;
  String? _pendingSourceLabel;
  /// When set, the matching [ExternalSubtitleOffer.id] is the active online track.
  String? _activeExternalOfferId;
  /// Short label for settings card when an online track is active.
  String? _activeExternalSummary;
  bool _wasBackgrounded = false;
  String? _playbackError;
  int? _resumeFromOverride;
  String? _selectedQualityKey;
  String? _selectedQualityUrl;
  StreamCaption? _selectedCaption;

  /// In-memory cache: resolved subtitle URL → `file://…` path written to
  /// temp storage. Avoids re-downloading the same track on source switches.
  final Map<String, String> _subtitleUrlCache = <String, String>{};

  late final StorageController _storageController;
  late final StreamService _streamService;

  /// The [OmssSource] the player is currently playing. Set from
  /// [PlayerScreenArgs.initialSource] on init and updated when the user
  /// switches sources via the Sources sheet. The synthesized
  /// [_activeStreamResult] is derived from this.
  late OmssSource _activeSource;

  /// The [StreamResult] the rest of the player reads from. Synthesized
  /// once per source change from the active [OmssSource] +
  /// [OmssResponse.subtitles] so the deep playback code
  /// (subtitles, qualities, captions, headers) keeps working unchanged.
  late StreamResult _activeStreamResult;

  /// When true, player only allows landscape orientations (auto-flips between
  /// left/right). When false, follows the device — phones can stay portrait.
  /// Toggled by the rotate button in [PlayerControls].
  bool _landscapeLocked = true;

  /// When true, all player controls are hidden and gestures (tap to show /
  /// edge-swipe brightness/volume) are ignored. A small unlock pill in the
  /// top-right is the only affordance until the user taps it.
  bool _controlsLocked = false;

  /// True once the video surface has decoded at least one frame.
  /// The [Video] widget stays invisible until this flag so the surface
  /// never flashes an empty / wrong-ratio frame that causes the visual
  /// "jumping" reported by users.
  bool _hasFirstVideoFrame = false;

  /// Fires after [_openStream] if no video frame arrives within a
  /// deadline.  Automatically retries with software decoding.
  Timer? _videoStallTimer;

  /// True after one software-decode retry so we don't loop forever.
  bool _hwdecFallbackAttempted = false;

  void _debugPlayer(String event, [Map<String, Object?> data = const {}]) {
    final Map<String, Object?> fields = <String, Object?>{
      'ready': _playerReady,
      'opening': _openingStream,
      'buffering': _buffering,
      'playing': _playing,
      'pos': _position.inSeconds,
      'dur': _duration.inSeconds,
      'buf': _buffer.inSeconds,
      ...data,
      ..._debugPlayerStateSnapshot(),
    };
    final String payload = fields.entries
        .map((MapEntry<String, Object?> entry) {
          return '${entry.key}=${entry.value}';
        })
        .join(' ');
    _playerLogSeq += 1;
    debugPrint('[VEIL_PLAYER] #$_playerLogSeq $event $payload');
  }

  Map<String, Object?> _debugPlayerStateSnapshot() {
    try {
      final VideoPlayerValue? v = _controller?.value;
      if (v == null) {
        return const <String, Object?>{'state': 'no_controller'};
      }
      return <String, Object?>{
        'statePlaying': v.isPlaying,
        'stateBuffering': v.isBuffering,
        'videoSize': '${v.size.width.toInt()}x${v.size.height.toInt()}',
      };
    } catch (_) {
      return const <String, Object?>{'state': 'unavailable'};
    }
  }

  String _debugUrl(String? url) {
    if (url == null || url.isEmpty) {
      return 'empty';
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return 'invalid len=${url.length}';
    }
    final String queryKeys = uri.queryParameters.keys.join(',');
    return '${uri.scheme}://${uri.host}${uri.path} '
        'queryKeys=[$queryKeys] len=${url.length}';
  }

  Map<String, Object?> _debugSourceFields() {
    return <String, Object?>{
      'provider': _activeSource.providerName,
      'providerId': _activeSource.providerId,
      'sourceType': _activeSource.type,
      'sourceQuality': _activeSource.quality ?? 'unknown',
      'selectedQuality': _selectedQualityKey ?? 'auto',
    };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storageController = ref.read(storageControllerProvider);
    _streamService = ref.read(streamServiceProvider);
    _activeSource = widget.args.initialSource;
    _omssResponse = widget.args.omssResponse;
    _activeStreamResult = _synthesizeStreamResult(
      _omssResponse,
      _activeSource,
    );

    _debugPlayer('init', <String, Object?>{
      'media': widget.args.mediaItem.hiveKey(),
      ..._debugSourceFields(),
    });

    _applyUserPlaybackPrefs();
    _applyPlayerChrome();
    _bindPlayerStreams();
    _openStream();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _persistProgress(),
    );
    _armControlsHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_primeScreenBrightness());
    });
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_playbackArgsDiffer(oldWidget.args, widget.args)) {
      return;
    }
    unawaited(_reloadStreamForUpdatedPlaybackArgs());
  }

  bool _playbackArgsDiffer(PlayerScreenArgs a, PlayerScreenArgs b) {
    if (a.replaceEpoch != b.replaceEpoch) {
      return true;
    }
    return _activeStreamResult.stream.playbackUrl !=
        _synthesizeStreamResult(b.omssResponse, b.initialSource)
            .stream
            .playbackUrl;
  }

  Future<void> _reloadStreamForUpdatedPlaybackArgs() async {
    if (!mounted) {
      return;
    }
    _debugPlayer('reload.begin', <String, Object?>{
      ..._debugSourceFields(),
    });
    _playerSettingsLabelRev.value++;
    final int resume = _position.inSeconds;
    await _persistProgress();
    if (!mounted) {
      return;
    }
    _videoStallTimer?.cancel();
    setState(() {
      _sourceSwitching = false;
      _pendingSourceId = null;
      _pendingSourceLabel = null;
      _openingStream = false;
      _playerReady = false;
      _hasPlaybackError = false;
      _playbackError = null;
      _buffering = true;
      _hasFirstVideoFrame = false;
      _hwdecFallbackAttempted = false;
      // Restore subtitle state from the preserved args so the user keeps
      // their active track across source switches.
      _activeExternalOfferId = widget.args.preservedExternalOfferId;
      _activeExternalSummary = widget.args.preservedExternalSummary;
      // Resync the synthesized stream result from the new args.
      _activeSource = widget.args.initialSource;
      _activeStreamResult = _synthesizeStreamResult(
        widget.args.omssResponse,
        _activeSource,
      );
    });
    _resumeFromOverride = resume > 0 ? resume : null;
    _resumeApplied = false;
    _selectedCaption = widget.args.preservedCaption;
    _subtitlesEnabled = (_selectedCaption != null ||
        _activeExternalOfferId != null);
    if (LocalStorage.getQualityCap() == LocalStorage.qualityCapAuto) {
      _selectedQualityKey = null;
      _selectedQualityUrl = null;
    }
    _applyUserPlaybackPrefs();
    if (!mounted) {
      return;
    }
    await _openStream(resumeFrom: resume > 0 ? resume : null);
    if (mounted) {
      _playerSettingsLabelRev.value++;
      _debugPlayer('reload.done');
    }
  }

  @override
  void dispose() {
    _debugPlayer('dispose.begin');
    WidgetsBinding.instance.removeObserver(this);
    // Capture before subscriptions/player tear-down so async persist does not
    // read mpv state after [Player.dispose] (race that dropped progress).
    final int snapPos = _position.inSeconds;
    final int snapDur = _duration.inSeconds;
    final bool snapReady = _playerReady;
    unawaited(
      _persistProgressValues(
        positionSecs: snapPos,
        durationSecs: snapDur,
        playerReady: snapReady,
        refresh: true,
      ),
    );
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _controlsHideTimer?.cancel();
    _progressTimer?.cancel();
    _subtitleToastTimer?.cancel();
    _gestureHintTimer?.cancel();
    _videoStallTimer?.cancel();
    _playerSettingsLabelRev.dispose();
    unawaited(_restoreScreenBrightness());
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    super.dispose();
  }

  /// Apply Hive-stored Playback prefs from Settings before [_openStream] runs.
  /// Quality cap picks the highest available quality at-or-below the cap.
  /// Subtitles-default-on flips [_subtitlesEnabled] so the first subtitle
  /// track is auto-selected when the stream has captions.
  void _applyUserPlaybackPrefs() {
    final String cap = LocalStorage.getQualityCap();
    if (cap != LocalStorage.qualityCapAuto) {
      final int? capLines = _qualityCapToLines(cap);
      if (capLines != null) {
        final MapEntry<String, StreamQuality>? best =
            _bestQualityAtOrBelow(capLines);
        if (best != null && (best.value.url?.isNotEmpty ?? false)) {
          _selectedQualityKey = best.key;
          _selectedQualityUrl = best.value.url;
        }
      }
    }

    if (LocalStorage.getSubtitlesDefaultOn() &&
        _availableCaptions.isNotEmpty) {
      _subtitlesEnabled = true;
    }
  }

  static int? _qualityCapToLines(String cap) {
    return switch (cap) {
      LocalStorage.qualityCap720 => 720,
      LocalStorage.qualityCap1080 => 1080,
      _ => null,
    };
  }

  /// Pick the highest [StreamQuality] whose key (e.g. `1080`, `720p`) parses
  /// to a height ≤ [maxLines]. Falls back to null when no quality fits.
  MapEntry<String, StreamQuality>? _bestQualityAtOrBelow(int maxLines) {
    final List<MapEntry<String, StreamQuality>> candidates = _availableQualities
        .where((MapEntry<String, StreamQuality> entry) {
          final int? lines = _parseQualityLines(entry.key);
          return lines != null && lines <= maxLines;
        })
        .toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) {
      final int aLines = _parseQualityLines(a.key) ?? 0;
      final int bLines = _parseQualityLines(b.key) ?? 0;
      return bLines.compareTo(aLines);
    });
    return candidates.first;
  }

  static int? _parseQualityLines(String key) {
    final RegExpMatch? match = RegExp(r'(\d{3,4})').firstMatch(key);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  /// Map a sidecar caption to the country flag emoji that the web UI shows
  /// next to each language. We use a tight ISO-639 → ISO-3166 table that
  /// covers every language code our scrapers emit; falls back to a globe
  /// glyph for unmapped codes so layout never collapses.
  static String _flagForLanguage(String? code) {
    final String? country = _countryForLanguage(code);
    if (country == null) {
      return String.fromCharCode(0x1F310); // 🌐
    }
    return _flagFromCountry(country);
  }

  static String _flagFromCountry(String country) {
    final String upper = country.toUpperCase();
    if (upper.length != 2) {
      return String.fromCharCode(0x1F310);
    }
    final int a = upper.codeUnitAt(0);
    final int b = upper.codeUnitAt(1);
    return String.fromCharCodes(<int>[0x1F1A5 + a, 0x1F1A5 + b]);
  }

  static String? _countryForLanguage(String? code) {
    if (code == null || code.trim().isEmpty) {
      return null;
    }
    // Normalise BCP-47 / locale strings: take the lowercase primary tag.
    final String lower = code.trim().toLowerCase().replaceAll('_', '-');
    final String primary = lower.split('-').first;
    const Map<String, String> table = <String, String>{
      'en': 'US',
      'es': 'ES',
      'pt': 'PT',
      'fr': 'FR',
      'de': 'DE',
      'it': 'IT',
      'nl': 'NL',
      'sv': 'SE',
      'no': 'NO',
      'nb': 'NO',
      'nn': 'NO',
      'da': 'DK',
      'fi': 'FI',
      'is': 'IS',
      'pl': 'PL',
      'cs': 'CZ',
      'sk': 'SK',
      'sl': 'SI',
      'hu': 'HU',
      'ro': 'RO',
      'el': 'GR',
      'tr': 'TR',
      'ru': 'RU',
      'uk': 'UA',
      'bg': 'BG',
      'sr': 'RS',
      'hr': 'HR',
      'mk': 'MK',
      'sq': 'AL',
      'he': 'IL',
      'ar': 'SA',
      'fa': 'IR',
      'ur': 'PK',
      'hi': 'IN',
      'bn': 'BD',
      'ta': 'IN',
      'te': 'IN',
      'ml': 'IN',
      'kn': 'IN',
      'mr': 'IN',
      'gu': 'IN',
      'pa': 'IN',
      'ja': 'JP',
      'ko': 'KR',
      'zh': 'CN',
      'th': 'TH',
      'vi': 'VN',
      'id': 'ID',
      'ms': 'MY',
      'tl': 'PH',
      'sw': 'KE',
      'am': 'ET',
      'lt': 'LT',
      'lv': 'LV',
      'et': 'EE',
    };
    return table[primary];
  }

  /// Detect hearing-impaired captions from common provider markers. Most
  /// scrapers expose the flag in `raw['hearingImpaired']`, `raw['hi']`,
  /// or by appending "(SDH)" / "[CC]" to the label.
  static bool _isHearingImpaired(StreamCaption caption) {
    final dynamic raw = caption.raw;
    if (raw is Map) {
      final dynamic hi = raw['hearingImpaired'] ?? raw['hi'] ?? raw['sdh'];
      if (hi is bool) {
        return hi;
      }
      if (hi is String) {
        final String norm = hi.toLowerCase().trim();
        if (norm == 'true' || norm == 'yes' || norm == '1') {
          return true;
        }
      }
    }
    final String haystack =
        '${caption.label ?? ''} ${caption.type ?? ''}'.toLowerCase();
    return haystack.contains('sdh') ||
        haystack.contains('cc') ||
        haystack.contains('hearing');
  }

  Future<void> _applyNativeSubtitleStyleFromPrefs() async {
    // Subtitle styling is handled by the custom overlay in build().
    // Re-trigger a rebuild so the overlay picks up new prefs.
    if (mounted) {
      setState(() {});
    }
  }

  /// Parse a local subtitle file (VTT or SRT) and populate [_parsedCaptions].
  /// The file must already exist on disk (downloaded by [_subtitleTrackForCaption]).
  Future<void> _loadAndApplySubtitleFile(String filePathOrUrl) async {
    try {
      String content;
      if (filePathOrUrl.startsWith('file://')) {
        final File f = File(filePathOrUrl.replaceFirst('file://', ''));
        content = await f.readAsString();
      } else if (filePathOrUrl.startsWith('http://') ||
                 filePathOrUrl.startsWith('https://')) {
        final http.Response r = await http
            .get(Uri.parse(filePathOrUrl))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
          _debugPlayer('subtitle.download_fail', <String, Object?>{
            'status': r.statusCode,
          });
          return;
        }
        content = r.body;
      } else {
        final File f = File(filePathOrUrl);
        content = await f.readAsString();
      }

      // Detect format and parse using video_player's built-in parsers.
      ClosedCaptionFile parsed;
      final String trimmed = content.trimLeft();
      if (trimmed.startsWith('WEBVTT') ||
          filePathOrUrl.contains('.vtt')) {
        parsed = WebVTTCaptionFile(content);
      } else {
        parsed = SubRipCaptionFile(content);
      }

      _debugPlayer('subtitle.loaded', <String, Object?>{
        'entries': parsed.captions.length,
        'source': filePathOrUrl.length > 60
            ? '...${filePathOrUrl.substring(filePathOrUrl.length - 40)}'
            : filePathOrUrl,
      });

      if (mounted) {
        setState(() {
          _parsedCaptions = parsed.captions;
          _currentSubtitleText = '';
        });
      }
    } catch (e) {
      _debugPlayer('subtitle.parse_error', <String, Object?>{'error': '$e'});
      if (mounted) {
        setState(() {
          _parsedCaptions = const <Caption>[];
          _currentSubtitleText = '';
        });
      }
    }
  }

  /// Clear active subtitles.
  void _clearParsedSubtitles() {
    _parsedCaptions = const <Caption>[];
    _currentSubtitleText = '';
  }

  /// Find the caption entry matching the current playback position.
  String _captionForPosition(Duration position) {
    for (final Caption c in _parsedCaptions) {
      if (position >= c.start && position <= c.end) {
        return c.text;
      }
    }
    return '';
  }


  /// Hex parser for `#AARRGGBB`. Same logic as the customize sheet but
  /// kept duplicated here so the player file does not have to import the
  /// private helper.
  static Color _hexToColorPlayer(String hex) {
    final String clean = hex.startsWith('#') ? hex.substring(1) : hex;
    final int parsed = int.tryParse(clean, radix: 16) ?? 0xFFFFFFFF;
    return Color(parsed);
  }

  /// Persist [bytes] (or [text]) to a fresh file under the app cache dir
  /// and return the absolute filesystem path. Used by the Drop/Upload and
  /// Paste subtitle flows so libmpv can load the track via `file://` —
  /// data URIs and `content://` schemes are unreliable across Android
  /// versions and decoder paths.
  Future<String?> _writeSubtitleToCache({
    required String suffix,
    List<int>? bytes,
    String? text,
  }) async {
    try {
      final Directory dir = await getTemporaryDirectory();
      final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
      final File file = File('${dir.path}/veil_sub_$stamp.$suffix');
      if (bytes != null) {
        await file.writeAsBytes(bytes, flush: true);
      } else if (text != null) {
        await file.writeAsString(text, flush: true);
      } else {
        return null;
      }
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// Resolves relative caption URLs against the active playlist / playback URL.
  static Uri? _resolveStreamCaptionUri(String captionUrl, StreamPlayback playback) {
    final String trimmed = captionUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final Uri? direct = Uri.tryParse(trimmed);
    if (direct != null &&
        direct.hasScheme &&
        direct.scheme != 'file' &&
        direct.host.isNotEmpty) {
      return direct;
    }
    final String baseStr = (playback.proxiedPlaylist?.isNotEmpty == true
            ? playback.proxiedPlaylist
            : null) ??
        (playback.playlist?.isNotEmpty == true ? playback.playlist : null) ??
        (playback.playbackUrl?.isNotEmpty == true ? playback.playbackUrl : null) ??
        '';
    if (baseStr.isEmpty) {
      return Uri.tryParse(trimmed);
    }
    try {
      return Uri.parse(baseStr).resolve(trimmed);
    } catch (_) {
      return Uri.tryParse(trimmed);
    }
  }

  /// Same header merge as transcript / HTTP subtitle fetch so CDNs see a browser-like client.
  Map<String, String> _mergedSubtitleRequestHeaders(
    StreamCaption caption,
    StreamPlayback playback,
  ) {
    final Map<String, String> h = <String, String>{};
    if (playback.preferredHeaders.isNotEmpty) {
      h.addAll(playback.preferredHeaders);
    } else {
      h.addAll(playback.headers);
    }
    h.putIfAbsent('User-Agent', () => AppConfig.subtitleHttpUserAgent);
    h.putIfAbsent('Accept', () => '*/*');
    final dynamic raw = caption.raw;
    if (raw is Map) {
      for (final MapEntry<dynamic, dynamic> e in raw.entries) {
        final String key = '${e.key}'.toLowerCase().trim();
        final String? val = e.value?.toString().trim();
        if (val == null || val.isEmpty) {
          continue;
        }
        if (key == 'referer') {
          h['Referer'] = val;
        } else if (key == 'origin') {
          h['Origin'] = val;
        }
      }
    }
    return h;
  }

  String _subtitleSuffixFromCaptionAndResponse(
    StreamCaption caption,
    http.Response response,
  ) {
    final String? ct = response.headers['content-type']?.toLowerCase();
    if (ct != null && ct.contains('x-subrip')) {
      return 'srt';
    }
    final String? u = caption.url?.toLowerCase();
    if (u != null) {
      if (u.endsWith('.vtt') || u.contains('.vtt?')) {
        return 'vtt';
      }
      if (u.endsWith('.srt') || u.contains('.srt?')) {
        return 'srt';
      }
    }
    return 'vtt';
  }

  /// Loads remote captions through our HTTP stack (headers + UA) into cache so
  /// libmpv reads a `file://` track — many hosts reject anonymous subtitle URLs.
  /// Loads remote captions through our HTTP stack (headers + UA) into cache.
  /// Returns the resolved subtitle file URI string, or null if unavailable.
  /// TODO: integrate with video_player's setClosedCaptionFile when supported.
  Future<String?> _subtitleTrackForCaption(StreamCaption caption) async {
    final StreamPlayback playback = _activeStreamResult.stream;
    final String rawUrl = caption.url?.trim() ?? '';
    if (rawUrl.isEmpty) {
      return null;
    }
    final Uri? resolved = _resolveStreamCaptionUri(rawUrl, playback);
    final String uriStr = resolved?.toString() ?? rawUrl;
    if (resolved == null ||
        !resolved.hasScheme ||
        resolved.scheme == 'file' ||
        (resolved.scheme != 'http' && resolved.scheme != 'https')) {
      return uriStr;
    }
    // Return from in-memory cache if this URL was already downloaded.
    final String cacheKey = resolved.toString();
    if (_subtitleUrlCache.containsKey(cacheKey)) {
      return _subtitleUrlCache[cacheKey]!;
    }
    final Map<String, String> headers =
        _mergedSubtitleRequestHeaders(caption, playback);
    try {
      final http.Response r = await http
          .get(resolved, headers: headers)
          .timeout(const Duration(seconds: 28));
      if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
        final String ext = _subtitleSuffixFromCaptionAndResponse(caption, r);
        final String? path = await _writeSubtitleToCache(
          suffix: ext,
          bytes: r.bodyBytes,
        );
        if (path != null) {
          _subtitleUrlCache[cacheKey] = 'file://$path';
          return 'file://$path';
        }
      }
    } catch (_) {
      // Fall through to direct URI (may still work for open CDNs).
    }
    return uriStr;
  }

  Future<void> _applyPlayerChrome() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await _applyOrientationPref();
  }

  /// Force landscape while [_landscapeLocked]; otherwise allow all orientations
  /// (phones held portrait will stay portrait until the user rotates).
  Future<void> _applyOrientationPref() async {
    if (_landscapeLocked) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
  }

  Future<void> _toggleAutoRotate() async {
    setState(() {
      _landscapeLocked = !_landscapeLocked;
    });
    await _applyOrientationPref();
  }

  void _lockControls() {
    setState(() {
      _controlsLocked = true;
      _controlsVisible = false;
    });
    _controlsHideTimer?.cancel();
  }

  void _unlockControls() {
    setState(() {
      _controlsLocked = false;
      _controlsVisible = true;
    });
    _armControlsHideTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _debugPlayer('lifecycle', <String, Object?>{'state': state.name});
    switch (state) {
      // Do not treat [inactive] as background: opening the notification shade,
      // volume HUD, or brief focus loss fires [inactive] then [resumed] without
      // [paused]. Re-opening the stream there restarts playback from scratch.
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _wasBackgrounded = true;
        if (_position.inSeconds > 0) {
          _resumeFromOverride = _position.inSeconds;
        }
        unawaited(_persistProgress());
        break;
      case AppLifecycleState.inactive:
        if (_position.inSeconds > 0) {
          _resumeFromOverride = _position.inSeconds;
        }
        unawaited(_persistProgress());
        break;
      case AppLifecycleState.resumed:
        unawaited(_recoverFromBackground());
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  void _bindPlayerStreams() {
    // No-op: with video_player, we use a single listener attached
    // per-controller in _openStream via _onControllerUpdate.
  }

  /// Unified listener for [VideoPlayerController.addListener]. Replaces the
  /// individual stream subscriptions that media_kit used.
  void _onControllerUpdate() {
    if (!mounted || _controller == null) {
      return;
    }
    final VideoPlayerValue v = _controller!.value;

    // Position (~4×/s). Skip setState while controls are hidden.
    if (v.position != _position) {
      final int bucket = v.position.inSeconds ~/ 5;
      if (bucket != _lastLoggedPositionBucket) {
        _lastLoggedPositionBucket = bucket;
        _debugPlayer('stream.position', <String, Object?>{
          'eventPos': v.position.inSeconds,
        });
      }
      if (_controlsVisible) {
        setState(() { _position = v.position; });
      } else {
        _position = v.position;
      }
    }

    // Duration
    if (v.duration != _duration && v.duration.inMilliseconds > 0) {
      _debugPlayer('stream.duration', <String, Object?>{
        'eventDur': v.duration.inSeconds,
      });
      setState(() { _duration = v.duration; });
      if (!_resumeApplied) {
        unawaited(_seekToResumePositionIfNeeded());
      }
    }

    // Buffer
    if (v.buffered.isNotEmpty) {
      final Duration newBuffer = v.buffered.last.end;
      if (newBuffer != _buffer) {
        if (_controlsVisible) {
          setState(() { _buffer = newBuffer; });
        } else {
          _buffer = newBuffer;
        }
      }
    }

    // Playing state
    final bool nowPlaying = v.isPlaying;
    if (nowPlaying != _playing) {
      _debugPlayer('stream.playing', <String, Object?>{'eventPlaying': nowPlaying});
      setState(() { _playing = nowPlaying; });
      if (nowPlaying && !_resumeApplied) {
        _seekToResumePositionIfNeeded();
      }
    }

    // Buffering
    if (v.isBuffering != _buffering) {
      _debugPlayer('stream.buffering', <String, Object?>{'eventBuffering': v.isBuffering});
      setState(() { _buffering = v.isBuffering; });
    }

    // First video frame detection
    if (v.isInitialized && v.size != Size.zero && !_hasFirstVideoFrame) {
      _videoStallTimer?.cancel();
      _debugPlayer('stream.firstVideoFrame', <String, Object?>{
        'width': v.size.width.toInt(),
      });
      setState(() { _hasFirstVideoFrame = true; });
    }

    // Subtitle text tracking
    if (_subtitlesEnabled && _parsedCaptions.isNotEmpty) {
      final String newText = _captionForPosition(v.position);
      if (newText != _currentSubtitleText) {
        setState(() { _currentSubtitleText = newText; });
      }
    }

    // Error
    if (v.hasError) {
      _debugPlayer('stream.error', <String, Object?>{'error': v.errorDescription});
      setState(() {
        _openingStream = false;
        _hasPlaybackError = true;
        _playerReady = false;
        _buffering = false;
        _playbackError = v.errorDescription ?? 'Playback failed';
        _controlsLocked = false;
        _controlsVisible = true;
      });
    }
  }

  Future<void> _openStream({int? resumeFrom}) async {
    final StreamPlayback playback = _activeStreamResult.stream;
    final String? url = _selectedQualityUrl ?? _resolvePlayableUrl(playback);
    // cinepro sets Referer / Origin / User-Agent server-side on the proxy URL.
    // The app passes no headers; libmpv opens the URL as-is.
    const Map<String, String> headers = <String, String>{};

    if (url == null || url.isEmpty) {
      _debugPlayer('open.no_url', _debugSourceFields());
      if (!mounted) {
        return;
      }
      setState(() {
        _openingStream = false;
        _hasPlaybackError = true;
        _playerReady = false;
        _buffering = false;
        _playbackError = 'No playable stream URL was provided.';
      });
      return;
    }

    try {
      final Stopwatch openWatch = Stopwatch()..start();
      if (resumeFrom != null && resumeFrom > 0) {
        _resumeFromOverride = resumeFrom;
      }
      _resumeApplied = false;
      final int? resumeStartSec = _resolvedResumeFrom;
      _debugPlayer('open.begin', <String, Object?>{
        'resumeFromArg': resumeFrom ?? 0,
        'resumeStart': resumeStartSec ?? 0,
        'url': _debugUrl(url),
        ..._debugSourceFields(),
      });

      _videoStallTimer?.cancel();
      if (mounted) {
        setState(() {
          _openingStream = true;
          _playerReady = false;
          _hasPlaybackError = false;
          _playbackError = null;
          _buffering = true;
          _controlsLocked = false;
          _controlsVisible = true;
          _hasFirstVideoFrame = false;
        });
        _debugPlayer('open.surface_requested');
        await WidgetsBinding.instance.endOfFrame;
        _debugPlayer('open.surface_frame_complete');
        if (!mounted) {
          return;
        }
      }

      // Dispose previous controller if any (source switch / quality change).
      _controller?.removeListener(_onControllerUpdate);
      _controller?.dispose();
      _controller = null;

      _debugPlayer('open.creating_controller', <String, Object?>{
        'url': _debugUrl(url),
      });
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: headers,
      );
      _controller!.addListener(_onControllerUpdate);
      await _controller!.initialize();
      _debugPlayer('open.controller_initialized', <String, Object?>{
        'elapsedMs': openWatch.elapsedMilliseconds,
      });
      await _controller!.setVolume((_softwareVolume / 100.0).clamp(0.0, 1.0));
      await _controller!.play();
      _debugPlayer('open.play_called', <String, Object?>{
        'elapsedMs': openWatch.elapsedMilliseconds,
      });
      if (resumeStartSec != null && resumeStartSec > 0) {
        await _controller!.seekTo(Duration(seconds: resumeStartSec));
        _resumeApplied = true;
        _debugPlayer('open.resume_seek', <String, Object?>{
          'seekTo': resumeStartSec,
        });
      }
      // Load subtitle asynchronously — do not block video ready state.
      unawaited(_applySelectedSubtitleTrack());
      if (!mounted) {
        return;
      }
      setState(() {
        _openingStream = false;
        _playerReady = true;
        _hasPlaybackError = false;
        _buffering = false;
        _playbackError = null;
      });
      // Start video-stall watchdog — if no video frame arrives within
      // the deadline, retry with software decoding.
      _videoStallTimer?.cancel();
      _videoStallTimer = Timer(
        const Duration(seconds: 8),
        _handleVideoStall,
      );
      _debugPlayer('open.ready', <String, Object?>{
        'elapsedMs': openWatch.elapsedMilliseconds,
      });
    } catch (error) {
      _debugPlayer('open.catch', <String, Object?>{'error': '$error'});
      if (!mounted) {
        return;
      }
      setState(() {
        _openingStream = false;
        _hasPlaybackError = true;
        _playerReady = false;
        _buffering = false;
        _playbackError = '$error';
      });
    }
  }

  /// Map common English language names (as emitted by OMSS labels) to
  /// BCP-47 primary subtags. Also passes through raw 2/3-letter codes.
  static String? _languageCodeFromLabel(String? label) {
    if (label == null || label.trim().isEmpty) {
      return null;
    }
    final String l = label.trim().toLowerCase();
    // Handle "English (SDH)", "English [CC]" etc.
    final String base = l.replaceAll(RegExp(r'[\(\[].*'), '').trim();
    const Map<String, String> table = <String, String>{
      'english': 'en', 'spanish': 'es', 'french': 'fr',
      'german': 'de', 'italian': 'it', 'portuguese': 'pt',
      'dutch': 'nl', 'russian': 'ru', 'japanese': 'ja',
      'korean': 'ko', 'chinese': 'zh', 'arabic': 'ar',
      'hindi': 'hi', 'turkish': 'tr', 'polish': 'pl',
      'swedish': 'sv', 'norwegian': 'no', 'danish': 'da',
      'finnish': 'fi', 'greek': 'el', 'hebrew': 'he',
      'romanian': 'ro', 'czech': 'cs', 'hungarian': 'hu',
      'thai': 'th', 'vietnamese': 'vi', 'indonesian': 'id',
      'malay': 'ms', 'ukrainian': 'uk', 'bulgarian': 'bg',
    };
    // Also handle 2/3-letter codes passed directly.
    if (base.length == 2 || base.length == 3) {
      return base;
    }
    return table[base];
  }

  /// Builds the [StreamResult] the rest of the player reads from, given
  /// the active [OmssSource] and the surrounding [OmssResponse]. The
  /// player's deep subtitle / quality / caption code is built around
  /// [StreamResult]; synthesizing one from the OMSS shape keeps those
  /// code paths untouched.
  ///
  /// cinepro returns a single playable URL per source (no qualities
  /// map), so the synthesized `StreamPlayback.qualities` is empty.
  /// `headers` / `preferredHeaders` are empty — the cinepro proxy sets
  /// Referer / Origin / User-Agent server-side.
  static StreamResult _synthesizeStreamResult(
    OmssResponse response,
    OmssSource source,
  ) {
    final List<StreamCaption> captions = response.subtitles
        .map((OmssSubtitle s) {
          return StreamCaption(
            url: s.resolvedUrl,
            language: _languageCodeFromLabel(s.label),
            type: s.format,
            label: s.label,
            raw: <String, dynamic>{
              'url': s.resolvedUrl,
              'label': s.label,
              'format': s.format,
            },
          );
        })
        .toList(growable: false);

    return StreamResult(
      sourceId: source.providerId,
      sourceName: source.providerName,
      embedId: null,
      embedName: null,
      stream: StreamPlayback(
        id: 'omss-${source.providerId}',
        type: source.type,
        playlist: source.type == 'hls' ? source.resolvedUrl : null,
        proxiedPlaylist: null,
        playbackUrl: source.resolvedUrl,
        playbackType: source.type,
        selectedQuality: source.quality,
        qualities: const <String, StreamQuality>{},
        headers: const <String, String>{},
        preferredHeaders: const <String, String>{},
        captions: captions,
        flags: const <String>[],
      ),
    );
  }

  Future<void> _seekToResumePositionIfNeeded() async {
    if (_resumeApplied) {
      return;
    }

    final int? resumeFrom = _resolvedResumeFrom;
    if (resumeFrom == null || resumeFrom <= 0) {
      _resumeApplied = true;
      return;
    }

    // Skip the seek until libmpv has loaded the duration — otherwise the
    // request is dropped and playback restarts from 00:00.
    if (_duration.inMilliseconds <= 0) {
      return;
    }

    final int durationSec = _duration.inSeconds;
    int targetSec = resumeFrom;
    if (durationSec > 0) {
      targetSec = targetSec.clamp(0, durationSec > 2 ? durationSec - 2 : durationSec);
    }
    await _controller?.seekTo(Duration(seconds: targetSec));
    _resumeApplied = true;
  }

  int? get _resolvedResumeFrom {
    if (_resumeFromOverride != null && _resumeFromOverride! > 0) {
      return _resumeFromOverride;
    }
    if (widget.args.resumeFrom != null && widget.args.resumeFrom! > 0) {
      return widget.args.resumeFrom;
    }

    final Map<String, dynamic>? progress = ref.read(
      progressEntryProvider(
        ProgressRequest(
          mediaItem: widget.args.mediaItem,
          season: widget.args.season,
          episode: widget.args.episode,
        ),
      ),
    );
    if (progress == null) {
      return null;
    }

    final int positionSecs = _readInt(progress['positionSecs']);
    return positionSecs > 0 ? positionSecs : null;
  }

  Future<void> _recoverFromBackground() async {
    _debugPlayer('recover.begin', <String, Object?>{
      'wasBackgrounded': _wasBackgrounded,
    });
    await _applyPlayerChrome();
    if (!_wasBackgrounded || !mounted) {
      _debugPlayer('recover.skip');
      return;
    }

    _wasBackgrounded = false;
    _resumeApplied = false;
    await _openStream(resumeFrom: _position.inSeconds);
    if (mounted) {
      setState(() {});
      _debugPlayer('recover.done');
    }
  }

  /// Watchdog callback: if no video frame has arrived after opening a
  /// stream, retry with software decoding (hardware codecs sometimes
  /// silently fail on HEVC / VP9 while audio continues).
  void _handleVideoStall() {
    if (!mounted || _hasFirstVideoFrame) {
      return;
    }
    _debugPlayer('stall.check', <String, Object?>{
      'playing': _playing,
      'hwdecFallbackAttempted': _hwdecFallbackAttempted,
    });
    if (!_hwdecFallbackAttempted && _playing) {
      // Audio is playing but video never decoded — likely a hardware
      // codec failure.  Retry the stream with software decoding.
      _debugPlayer('stall.hwdec_fallback');
      _hwdecFallbackAttempted = true;
      unawaited(_retryWithSoftwareDecoding());
    } else {
      // Either already retried or player isn't even playing yet.
      // Show the surface as-is so controls remain functional.
      _debugPlayer('stall.force_show');
      if (mounted) {
        setState(() {
          _hasFirstVideoFrame = true;
        });
      }
    }
  }

  Future<void> _retryWithSoftwareDecoding() async {
    _debugPlayer('retry_sw.begin');
    final int resumePos = _position.inSeconds;
    await _openStream(resumeFrom: resumePos > 0 ? resumePos : null);
  }

  Future<void> _persistProgress({bool refresh = true}) async {
    await _persistProgressValues(
      positionSecs: _position.inSeconds,
      durationSecs: _duration.inSeconds,
      playerReady: _playerReady,
      refresh: refresh,
    );
  }

  /// Writes watch progress. [durationSecs] may be 0 while HLS/DASH duration is
  /// still unknown — we still persist [positionSecs] so Continue Watching and
  /// resume survive an early back press.
  Future<void> _persistProgressValues({
    required int positionSecs,
    required int durationSecs,
    required bool playerReady,
    bool refresh = true,
  }) async {
    if (!playerReady || positionSecs <= 0) {
      return;
    }

    await _storageController.saveProgress(
      widget.args.mediaItem,
      positionSecs: positionSecs,
      durationSecs: durationSecs,
      season: widget.args.season,
      episode: widget.args.episode,
      refresh: refresh,
    );
  }

  Future<void> _togglePlayback() async {
    _debugPlayer('play_toggle.begin', <String, Object?>{
      'wasPlaying': _playing,
    });
    if (_playing) {
      await _controller?.pause();
      _debugPlayer('play_toggle.pause_sent');
    } else {
      await _controller?.play();
      _debugPlayer('play_toggle.play_sent');
    }
    _showControls();
  }

  void _exitPlayer() {
    _debugPlayer('exit.begin');
    final NavigatorState navigator = Navigator.of(context);
    unawaited(_persistProgress());
    unawaited(navigator.maybePop());
  }

  Future<void> _seekRelative(int seconds, {bool showControls = true}) async {
    final int targetMs =
        ((_position.inMilliseconds + (seconds * 1000)).clamp(
                  0,
                  _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 0,
                )
                as num)
            .toInt();
    await _controller?.seekTo(Duration(milliseconds: targetMs));
    if (showControls) {
      _showControls();
    }
  }

  Future<void> _seekToFraction(double fraction) async {
    if (_duration.inMilliseconds <= 0) {
      return;
    }

    final int targetMs =
        ((_duration.inMilliseconds * fraction).round().clamp(
                  0,
                  _duration.inMilliseconds,
                )
                as num)
            .toInt();
    await _controller?.seekTo(Duration(milliseconds: targetMs));
    _showControls();
  }

  void _showControls() {
    if (!mounted) {
      return;
    }
    setState(() {
      _controlsVisible = true;
    });
    _armControlsHideTimer();
  }

  void _armControlsHideTimer() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      if (!_playerReady ||
          _openingStream ||
          _hasPlaybackError ||
          _sourceSwitching) {
        return;
      }
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  void _notifyPlayerSettingsSubtitleLabel() {
    if (!mounted) {
      return;
    }
    _playerSettingsLabelRev.value = _playerSettingsLabelRev.value + 1;
  }

  Future<T?> _showPlayerSheet<T>({required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
      barrierColor: AppColors.transparent,
      builder: (BuildContext context) {
        return builder(context);
      },
    );
  }

  Future<void> _openPlayerSettingsSheet() async {
    _showControls();

    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        // [StatefulBuilder] so the home sheet rebuilds with fresh labels
        // after each sub-sheet returns.
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return _PlayerSheetScaffold(
              child: ValueListenableBuilder<int>(
                valueListenable: _playerSettingsLabelRev,
                builder: (BuildContext context, int _, Widget? child) {
                  return _PlayerSettingsHomeSheet(
                    qualityLabel: _currentQualityLabel,
                    sourceLabel: _sourceLabelForSettings,
                    subtitleLabel: _currentSubtitleLabel,
                    sourceSwitching: _sourceSwitching,
                    onQualityTap: () async {
                      await _openQualitySheet();
                      setSheetState(() {});
                    },
                    onSourceTap: () async {
                      await _openSourceSheet();
                      setSheetState(() {});
                    },
                    onSubtitlesTap: () async {
                      await _openSubtitlesSheet();
                      setSheetState(() {});
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  /// Refreshes the cached OMSS response and replaces [_omssResponse].
  /// cinepro returns every playable source in a single HTTP GET, so there
  /// is no per-source probe to run — but a fresh fetch may surface
  /// different providers when one is temporarily down.
  Future<void> _runSourceProbeForCatalog() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _refreshingSources = true;
    });
    try {
      final OmssResponse fresh = await _streamService.fetchSources(
        widget.args.mediaItem,
        season: widget.args.season,
        episode: widget.args.episode,
      );
      if (!mounted) {
        return;
      }
      _omssResponse = fresh;
    } catch (_) {
      if (mounted) {
        _setSubtitleState(
          enabled: _subtitlesEnabled,
          message: "Couldn't refresh sources",
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _refreshingSources = false;
        });
      }
    }
  }

  /// True while the Sources sheet's "Refresh sources" button is in flight.
  bool _refreshingSources = false;

  /// The most recent OMSS response; initialized from
  /// [PlayerScreenArgs.omssResponse] on init and re-assigned by
  /// [_runSourceProbeForCatalog] when the user refreshes.
  late OmssResponse _omssResponse;

  Future<void> _openSourceSheet() async {
    _showControls();
    final OmssSource? selectedSource = await _showPlayerSheet<OmssSource>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: _PlayerOptionSheet(
            title: 'Sources',
            trailingText: 'Find next source',
            onBack: () => Navigator.of(context).pop(),
            onTrailingTap: () async {
              final NavigatorState modalNavigator = Navigator.of(context);
              final NavigatorState screenNavigator = Navigator.of(this.context);
              await _persistProgress();
              if (!mounted) {
                return;
              }
              modalNavigator.pop();
              await screenNavigator.pushReplacement(
                MaterialPageRoute<void>(
                  builder: (_) => ScrapingScreen(
                    mediaItem: widget.args.mediaItem,
                    season: widget.args.season,
                    episode: widget.args.episode,
                    seasonTmdbId: widget.args.seasonTmdbId,
                    episodeTmdbId: widget.args.episodeTmdbId,
                    seasonTitle: widget.args.seasonTitle,
                    resumeFrom: _position.inSeconds,
                  ),
                ),
              );
            },
            child: _SourcesCatalogSheet(
              sources: _omssResponse.sources,
              currentSourceId: _activeSource.providerId,
              refreshing: _refreshingSources,
              switchingSourceId: _pendingSourceId,
              onRefreshSources: () {
                unawaited(_runSourceProbeForCatalog());
              },
              onPick: (OmssSource source) {
                Navigator.of(context).pop(source);
              },
            ),
          ),
        );
      },
    );

    if (selectedSource == null ||
        selectedSource.providerId == _activeSource.providerId) {
      return;
    }

    await _switchSource(selectedSource);
  }

  Future<void> _openQualitySheet() async {
    _showControls();
    final List<MapEntry<String, StreamQuality>> qualities = _availableQualities;
    final bool hasQualities = qualities.isNotEmpty;
    final bool hasMultipleQualities = qualities.length > 1;

    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        // Sheet stays open after selection; the tick on the picked row
        // updates instantly via [setSheetState].
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return _PlayerSheetScaffold(
              child: _PlayerOptionSheet(
                title: 'Quality',
                onBack: () => Navigator.of(context).pop(),
                footer: hasMultipleQualities
                    ? _PlayerToggleRow(
                        title: 'Automatic quality',
                        subtitle:
                            'Use the source default unless you explicitly select a stream quality.',
                        value: _selectedQualityKey == null,
                        onChanged: (bool value) {
                          if (value) {
                            _selectQuality(null);
                          }
                          setSheetState(() {});
                        },
                      )
                    : null,
                child: hasQualities
                    ? ListView.builder(
                        shrinkWrap: true,
                        itemCount: qualities.length,
                        itemBuilder: (BuildContext context, int index) {
                          final MapEntry<String, StreamQuality> quality =
                              qualities[index];
                          final bool isSelected =
                              _selectedQualityKey == quality.key ||
                              (_selectedQualityKey == null &&
                                  _activeStreamResult.stream
                                          .selectedQuality ==
                                      quality.key);

                          return _PlayerOptionRow(
                            title: quality.key,
                            subtitle: quality.value.type,
                            selected: isSelected,
                            onTap: () {
                              _selectQuality(quality.key);
                              setSheetState(() {});
                            },
                          );
                        },
                      )
                    : const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.x4,
                          vertical: AppSpacing.x6,
                        ),
                        child: Text(
                          'This source exposes a single stream quality. '
                          'The player is using the source default.',
                          textAlign: TextAlign.left,
                          style: TextStyle(color: AppColors.typeSecondary),
                        ),
                      ),
              ),
            );
          },
        );
      },
    );
  }

  Future<OnlineSubtitleSearchResult> _loadOnlineSubtitleSearch() async {
    final bool wantKeys =
        AppConfig.hasWyzieApiKey || AppConfig.hasOpensubtitlesApiKey;
    if (!wantKeys) {
      return const OnlineSubtitleSearchResult(offers: <ExternalSubtitleOffer>[]);
    }
    // Subtitle service runs searches in parallel with per-source timeouts
    return const ExternalSubtitleService().searchOnlineDetailed(
      media: widget.args.mediaItem,
      season: widget.args.season,
      episode: widget.args.episode,
    );
  }

  Future<void> _openSubtitlesSheet() async {
    _showControls();

    int searchGen = 0;
    Future<OnlineSubtitleSearchResult> searchFuture = _loadOnlineSubtitleSearch();

    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final bool wantKeys =
                AppConfig.hasWyzieApiKey || AppConfig.hasOpensubtitlesApiKey;
            return _PlayerSheetScaffold(
              child: _PlayerOptionSheet(
                title: 'Subtitles',
                titleTrailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (wantKeys)
                      IconButton(
                        tooltip: 'Search again',
                        onPressed: () {
                          setSheetState(() {
                            searchGen++;
                            searchFuture = _loadOnlineSubtitleSearch();
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    TextButton(
                      onPressed: () async {
                        await _openCustomizeSubtitlesSheet();
                        setSheetState(() {});
                      },
                      child: const Text('Customize'),
                    ),
                  ],
                ),
                onBack: () => Navigator.of(context).pop(),
                child: FutureBuilder<OnlineSubtitleSearchResult>(
                  key: ValueKey<int>(searchGen),
                  future: searchFuture,
                  builder: (
                    BuildContext context,
                    AsyncSnapshot<OnlineSubtitleSearchResult> snapshot,
                  ) {
                    final bool showOnlineSpinner = wantKeys &&
                        snapshot.connectionState != ConnectionState.done;
                    final OnlineSubtitleSearchResult? r = snapshot.data;
                    final List<ExternalSubtitleOffer> offers =
                        r?.offers ?? const <ExternalSubtitleOffer>[];
                    final List<String> skipReasons =
                        r?.skipReasons ?? const <String>[];
                    final List<String> providerErrors =
                        r?.providerErrors ?? const <String>[];
                    final List<_MergedSubtitleLang> merged =
                        _mergeSubtitleLanguages(offers);

                    return ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        if (!wantKeys) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.x4,
                              0,
                              AppSpacing.x4,
                              AppSpacing.x3,
                            ),
                            child: Text(
                              'For OpenSubtitles and Wyzie, add WYZIE_API_KEY '
                              'and/or OPENSUBTITLES_API_KEY to your build '
                              '(--dart-define) and rebuild the app.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.typeSecondary),
                            ),
                          ),
                        ] else if (skipReasons.isNotEmpty) ...<Widget>[
                          for (final String s in skipReasons)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.x4,
                                0,
                                AppSpacing.x4,
                                AppSpacing.x2,
                              ),
                              child: Text(
                                s,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.typeSecondary),
                              ),
                            ),
                        ] else if (offers.isEmpty && !showOnlineSpinner) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.x4,
                              0,
                              AppSpacing.x4,
                              AppSpacing.x2,
                            ),
                            child: Text(
                              providerErrors.isNotEmpty
                                  ? providerErrors.join(' ')
                                  : 'No online files matched this title. '
                                      'Touch the refresh icon to try again, '
                                      'or use the web tracks from the source below.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.typeSecondary),
                            ),
                          ),
                        ],
                        _PlayerOptionRow(
                          title: 'Off',
                          selected: !_subtitlesEnabled,
                          onTap: () {
                            _disableSubtitles();
                            setSheetState(() {});
                          },
                        ),
                        _PlayerOptionRow(
                          title: 'Drop or upload file',
                          subtitle: '.srt or .vtt from this device',
                          showChevron: true,
                          onTap: () async {
                            await _pickSubtitleFile();
                            setSheetState(() {});
                          },
                        ),
                        _PlayerOptionRow(
                          title: 'Paste subtitle data',
                          subtitle: 'Paste raw VTT or SRT text',
                          showChevron: true,
                          onTap: () async {
                            await _openPasteSubtitleSheet();
                            setSheetState(() {});
                          },
                        ),
                        if (showOnlineSpinner) ...<Widget>[
                          const SizedBox(height: AppSpacing.x3),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: AppSpacing.x4,
                            ),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                          const SizedBox(height: AppSpacing.x3),
                        ],
                        if (snapshot.hasError)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.x4,
                              vertical: AppSpacing.x2,
                            ),
                            child: Text(
                              'Online subtitles: ${snapshot.error}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.typeSecondary,
                                  ),
                            ),
                          ),
                        for (final _MergedSubtitleLang row in merged)
                          _PlayerLanguageRow(
                            flag: _flagForLanguage(row.primaryLanguageCode),
                            name: row.displayName,
                            count: row.count,
                            selected: row.offers.any(
                                  (ExternalSubtitleOffer o) =>
                                      o.id == _activeExternalOfferId,
                                ) ||
                                (_selectedCaption != null &&
                                    row.captions.any(
                                      (StreamCaption c) =>
                                          _captionMatchesSelected(c),
                                    )),
                            onTap: () async {
                              await _openSubtitleLanguageSheet(
                                row.displayName,
                                row.captions,
                                row.offers,
                              );
                              setSheetState(() {});
                            },
                          ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openSubtitleLanguageSheet(
    String language,
    List<StreamCaption> captions,
    List<ExternalSubtitleOffer> onlineOffers,
  ) async {
    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final int rowCount = captions.length + onlineOffers.length;
            return _PlayerSheetScaffold(
              child: _PlayerOptionSheet(
                title: language,
                trailingText: 'Customize',
                onBack: () => Navigator.of(context).pop(),
                onTrailingTap: () async {
                  await _openCustomizeSubtitlesSheet();
                  setSheetState(() {});
                },
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: rowCount,
                  itemBuilder: (BuildContext context, int index) {
                    if (index < captions.length) {
                      final StreamCaption caption = captions[index];
                      final bool isSelected = _captionMatchesSelected(caption);

                      return _PlayerCaptionRow(
                        caption: caption,
                        selected: isSelected,
                        flag: _flagForLanguage(caption.language),
                        hearingImpaired: _isHearingImpaired(caption),
                        onTap: () {
                          _selectCaption(caption);
                          setSheetState(() {});
                        },
                      );
                    }
                    final ExternalSubtitleOffer offer =
                        onlineOffers[index - captions.length];
                    final bool isSelected = offer.id == _activeExternalOfferId;
                    return _PlayerExternalOfferRow(
                      offer: offer,
                      badge: _onlineSubtitleProviderBadge(offer),
                      selected: isSelected,
                      onTap: () {
                        unawaited(_applyExternalSubtitleOffer(offer));
                        setSheetState(() {});
                      },
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Picks a local subtitle file via the system file picker, then loads it
  /// as the active track. Honors `.srt` / `.vtt` extensions.
  ///
  /// Android scoped storage may return a `null` filesystem path with bytes
  /// instead, or hand back a `content://` URI that libmpv cannot read. We
  /// cope by writing the picked content to the app cache directory and
  /// loading it via `file://`.
  Future<void> _pickSubtitleFile() async {
    try {
      final FilePickerResult? picked = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const <String>['srt', 'vtt'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }
      final PlatformFile single = picked.files.single;
      final String suffix = (single.extension ?? 'vtt').toLowerCase();

      String? resolvedPath;
      if (single.bytes != null && single.bytes!.isNotEmpty) {
        resolvedPath = await _writeSubtitleToCache(
          suffix: suffix,
          bytes: single.bytes,
        );
      } else if (single.path != null && single.path!.isNotEmpty) {
        // Re-copy into our cache so we always control the lifetime and
        // avoid issues with content provider URIs disappearing.
        try {
          final List<int> bytes = await File(single.path!).readAsBytes();
          resolvedPath = await _writeSubtitleToCache(
            suffix: suffix,
            bytes: bytes,
          );
        } catch (_) {
          resolvedPath = single.path;
        }
      }

      if (resolvedPath == null || resolvedPath.isEmpty || !mounted) {
        if (mounted) {
          _setSubtitleState(
            enabled: _subtitlesEnabled,
            message: 'Could not read that file',
          );
        }
        return;
      }

      _selectedCaption = null;
      _activeExternalOfferId = null;
      _activeExternalSummary = null;
      _subtitlesEnabled = true;
      await _loadAndApplySubtitleFile('file://$resolvedPath');
      _setSubtitleState(enabled: true, message: 'Loaded ${single.name}');
    } catch (_) {
      if (mounted) {
        _setSubtitleState(
          enabled: _subtitlesEnabled,
          message: 'Could not load that file',
        );
      }
    }
  }

  /// Inline subtitle editor: paste raw VTT/SRT text and load it as a data
  /// URI so the player can render it without disk I/O.
  Future<void> _openPasteSubtitleSheet() async {
    final TextEditingController controller = TextEditingController();
    final String? raw = await _showPlayerSheet<String>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Paste subtitle data',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: AppColors.typeEmphasis,
                            ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(controller.text),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  'Paste raw VTT or SRT text. The player will treat it as the active subtitle track until playback ends.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.x3),
                TextField(
                  controller: controller,
                  minLines: 10,
                  maxLines: 16,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.typeEmphasis,
                      ),
                  decoration: InputDecoration(
                    hintText: 'WEBVTT\n\n00:00:00.000 --> 00:00:02.000\nHello',
                    hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.typeSecondary,
                        ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.x3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();

    if (raw == null) {
      return;
    }
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final bool isVtt = trimmed.toUpperCase().startsWith('WEBVTT');
    // libmpv accepts `file://` reliably; it does not always resolve
    // `data:` URIs across Android versions, so we materialise the pasted
    // text to the cache dir first and load that.
    final String suffix = isVtt ? 'vtt' : 'srt';
    final String? path = await _writeSubtitleToCache(
      suffix: suffix,
      text: trimmed,
    );
    if (path == null || path.isEmpty || !mounted) {
      if (mounted) {
        _setSubtitleState(
          enabled: _subtitlesEnabled,
          message: 'Could not save pasted subtitle',
        );
      }
      return;
    }

    _selectedCaption = null;
    _activeExternalOfferId = null;
    _activeExternalSummary = null;
    _subtitlesEnabled = true;
    try {
      await _loadAndApplySubtitleFile('file://$path');
      _setSubtitleState(enabled: true, message: 'Pasted subtitle applied');
    } catch (_) {
      if (mounted) {
        _setSubtitleState(
          enabled: _subtitlesEnabled,
          message: 'Could not apply pasted subtitle',
        );
      }
    }
  }

  /// Customize the on-screen subtitle render: font size, text color, and
  /// background opacity. Persists each change via [storageControllerProvider]
  /// and pushes the new style into libmpv immediately.
  Future<void> _openCustomizeSubtitlesSheet() async {
    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: _SubtitleCustomizeSheet(
            initialSize: LocalStorage.getSubtitleSize(),
            initialColor: LocalStorage.getSubtitleColor(),
            initialBgOpacity: LocalStorage.getSubtitleBgOpacity(),
            onChanged: ({int? size, String? color, double? bgOpacity}) async {
              if (size != null) {
                await ref.read(storageControllerProvider).setSubtitleSize(size);
              }
              if (color != null) {
                await ref
                    .read(storageControllerProvider)
                    .setSubtitleColor(color);
              }
              if (bgOpacity != null) {
                await ref
                    .read(storageControllerProvider)
                    .setSubtitleBgOpacity(bgOpacity);
              }
              await _applyNativeSubtitleStyleFromPrefs();
            },
            onBack: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
  }

  Future<void> _applyExternalSubtitleOffer(ExternalSubtitleOffer offer) async {
    if (!mounted) {
      return;
    }

    try {
      _selectedCaption = null;
      _activeExternalOfferId = offer.id;
      _activeExternalSummary = offer.languageLabel.trim().isNotEmpty
          ? offer.languageLabel
          : offer.title;
      _subtitlesEnabled = true;
      if (mounted) {
        setState(() {});
      }
      _notifyPlayerSettingsSubtitleLabel();

      String? url = offer.directUrl;
      if (offer.opensubtitlesFileId != null) {
        const ExternalSubtitleService service = ExternalSubtitleService();
        url ??= await service.resolveOpensubtitlesDownloadUrl(
          offer.opensubtitlesFileId!,
        );
      }

      if (url == null || url.isEmpty) {
        if (mounted) {
          setState(() {
            _activeExternalOfferId = null;
            _activeExternalSummary = null;
            _subtitlesEnabled = false;
          });
        }
        _setSubtitleState(
          enabled: false,
          message:
              'Could not open subtitle (try OPENSUBTITLES_USERNAME/PASSWORD for OpenSubtitles)',
        );
        return;
      }

      if (!mounted) {
        return;
      }

      await _loadAndApplySubtitleFile(url);
      _setSubtitleState(enabled: true, message: offer.providerLabel);
      _showControls();
    } catch (_) {
      if (mounted) {
        setState(() {
          _activeExternalOfferId = null;
          _activeExternalSummary = null;
          _subtitlesEnabled = false;
        });
        _setSubtitleState(
          enabled: false,
          message: 'Subtitle failed',
        );
      }
    }
  }

  Future<void> _switchSource(OmssSource source) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _sourceSwitching = true;
      _pendingSourceId = source.providerId;
      _pendingSourceLabel = source.providerName;
    });
    _playerSettingsLabelRev.value++;

    try {
      await _persistProgress();
      if (!mounted) {
        return;
      }

      // cinepro already validated the URL when it returned this source in
      // the OmssResponse. No re-scrape, no headers — just push a fresh
      // PlayerScreenArgs pointing at the new source.
      _navigateReplacePlayerWithResult(source);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sourceSwitching = false;
        _pendingSourceId = null;
        _pendingSourceLabel = null;
      });
      _playerSettingsLabelRev.value++;
      _setSubtitleState(
        enabled: _subtitlesEnabled,
        message: 'Could not switch source',
      );
    }
  }

  void _handleScreenTap() {
    // Locked: ignore taps. Only the unlock pill (top-right) re-enables UI.
    if (_controlsLocked) {
      return;
    }
    if (!_playerReady ||
        _openingStream ||
        _hasPlaybackError ||
        _sourceSwitching) {
      setState(() {
        _controlsVisible = true;
      });
      return;
    }
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _armControlsHideTimer();
    } else {
      _controlsHideTimer?.cancel();
    }
  }

  /// Double-tap left side → seek backwards, right side → forwards. Distance
  /// reads from [LocalStorage.getDoubleTapSeekSecs] (5/10/15/30/60).
  void _handleDoubleTapDown(TapDownDetails details) {
    if (_controlsLocked || !_playerReady) {
      return;
    }
    final double width = MediaQuery.sizeOf(context).width;
    if (width <= 0) {
      return;
    }
    final double x = details.globalPosition.dx;
    final int seekSecs = LocalStorage.getDoubleTapSeekSecs();
    // Center 30% is a dead zone so accidental double-taps near the play
    // button don't seek either direction.
    final double thirdLeft = width * 0.35;
    final double thirdRight = width * 0.65;
    if (x < thirdLeft) {
      unawaited(_seekRelative(-seekSecs, showControls: false));
      _flashGestureHint(
        icon: _doubleTapSeekIcon(-seekSecs),
        label: '-${seekSecs}s',
      );
    } else if (x > thirdRight) {
      unawaited(_seekRelative(seekSecs, showControls: false));
      _flashGestureHint(
        icon: _doubleTapSeekIcon(seekSecs),
        label: '+${seekSecs}s',
      );
    }
  }

  /// Material numbered skip icons only exist for 5/10/15/30/60 — never mix a
  /// hardcoded glyph (e.g. forward_30) with a different configured interval.
  static IconData _doubleTapSeekIcon(int signedSecs) {
    final int s = signedSecs.abs();
    // Only 5 / 10 / 30 have matching Material *rounded* replay/forward glyphs in
    // all SDKs; 15 / 60 fall back to generic skip icons.
    if (signedSecs < 0) {
      return switch (s) {
        5 => Icons.replay_5_rounded,
        10 => Icons.replay_10_rounded,
        30 => Icons.replay_30_rounded,
        _ => Icons.fast_rewind_rounded,
      };
    }
    return switch (s) {
      5 => Icons.forward_5_rounded,
      10 => Icons.forward_10_rounded,
      30 => Icons.forward_30_rounded,
      _ => Icons.fast_forward_rounded,
    };
  }

  Future<void> _primeScreenBrightness() async {
    if (_screenBrightnessPrimed || !mounted) {
      return;
    }
    try {
      final double value = await ScreenBrightness.instance.application;
      if (!mounted) {
        return;
      }
      setState(() {
        _screenBrightness = value.clamp(0.03, 1.0);
        _screenBrightnessPrimed = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _screenBrightnessPrimed = true;
        });
      }
    }
  }

  Future<void> _restoreScreenBrightness() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {
      // Ignore: plugin may be unavailable on some devices.
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    // Locked: no brightness/volume edge-swipe gestures either.
    if (_controlsLocked || !_playerReady) {
      _edgeSwipe = _PlayerEdgeSwipe.none;
      return;
    }
    final MediaQueryData mq = MediaQuery.of(context);
    final double width = mq.size.width - mq.padding.left - mq.padding.right;
    if (width <= 0) {
      return;
    }
    final double x = details.globalPosition.dx - mq.padding.left;
    final double side = (x / width).clamp(0.0, 1.0);
    if (side < 0.32) {
      _edgeSwipe = _PlayerEdgeSwipe.brightness;
      _edgeSwipeStartBrightness = _screenBrightness;
    } else if (side > 0.68) {
      _edgeSwipe = _PlayerEdgeSwipe.volume;
      _edgeSwipeStartVolume = _softwareVolume;
    } else {
      _edgeSwipe = _PlayerEdgeSwipe.none;
      return;
    }
    _edgeSwipeAccumDy = 0;
  }

  Future<void> _onVerticalDragUpdate(DragUpdateDetails details) async {
    if (_edgeSwipe == _PlayerEdgeSwipe.none) {
      return;
    }
    _edgeSwipeAccumDy += details.primaryDelta ?? 0;
    final double height = MediaQuery.sizeOf(context).height;
    final double travel = height * 0.38;
    if (travel <= 0) {
      return;
    }

    if (_edgeSwipe == _PlayerEdgeSwipe.brightness) {
      final double next =
          (_edgeSwipeStartBrightness + (-_edgeSwipeAccumDy / travel)).clamp(
            0.03,
            1.0,
          );
      if ((next - _screenBrightness).abs() < 0.004) {
        return;
      }
      _screenBrightness = next;
      try {
        await ScreenBrightness.instance.setApplicationScreenBrightness(
          _screenBrightness,
        );
      } catch (_) {
        // Ignore device-specific failures.
      }
      if (!mounted) {
        return;
      }
      _flashGestureHint(
        icon: Icons.brightness_6_rounded,
        label: 'Brightness ${(_screenBrightness * 100).round()}%',
      );
      return;
    }

    if (_edgeSwipe == _PlayerEdgeSwipe.volume) {
      final double next =
          (_edgeSwipeStartVolume + (-_edgeSwipeAccumDy / travel) * 150).clamp(
            0,
            150,
          );
      if ((next - _softwareVolume).abs() < 0.5) {
        return;
      }
      _softwareVolume = next;
      await _controller?.setVolume((_softwareVolume / 100.0).clamp(0.0, 1.0));
      if (!mounted) {
        return;
      }
      _flashGestureHint(
        icon: Icons.volume_up_rounded,
        label: 'Volume ${_softwareVolume.round()}',
      );
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _edgeSwipe = _PlayerEdgeSwipe.none;
    _edgeSwipeAccumDy = 0;
  }

  void _flashGestureHint({required IconData icon, required String label}) {
    _gestureHintTimer?.cancel();
    setState(() {
      _gestureHintIcon = icon;
      _gestureHint = label;
    });
    _gestureHintTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _gestureHint = null;
        _gestureHintIcon = null;
      });
    });
  }

  Future<void> _openBrightnessSheet() async {
    _showControls();
    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Brightness',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.typeEmphasis,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _restoreScreenBrightness();
                        if (!context.mounted) {
                          return;
                        }
                        try {
                          final double value =
                              await ScreenBrightness.instance.application;
                          if (!context.mounted) {
                            return;
                          }
                          setState(() {
                            _screenBrightness = value.clamp(0.03, 1.0);
                          });
                        } catch (_) {
                          // Keep previous value if the platform cannot read brightness.
                        }
                        if (!context.mounted) {
                          return;
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text('System default'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x3),
                StatefulBuilder(
                  builder: (BuildContext context, StateSetter setModal) {
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: AppSpacing.x1,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: AppSpacing.x3,
                        ),
                      ),
                      child: Slider(
                        value: _screenBrightness,
                        min: 0.03,
                        max: 1,
                        onChanged: (double value) {
                          setModal(() {
                            setState(() {
                              _screenBrightness = value;
                            });
                          });
                          unawaited(
                            ScreenBrightness.instance
                                .setApplicationScreenBrightness(value),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  'Drag vertically on the left edge of the screen for quick brightness.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openVolumeSheet() async {
    _showControls();
    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Volume',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.typeEmphasis,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        setState(() {
                          _softwareVolume = 100;
                        });
                        await _controller?.setVolume((_softwareVolume / 100.0).clamp(0.0, 1.0));
                        if (!context.mounted) {
                          return;
                        }
                        Navigator.of(context).pop();
                      },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.x3),
                StatefulBuilder(
                  builder: (BuildContext context, StateSetter setModal) {
                    return SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: AppSpacing.x1,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: AppSpacing.x3,
                        ),
                      ),
                      child: Slider(
                        value: _softwareVolume.clamp(0, 150),
                        min: 0,
                        max: 150,
                        divisions: 30,
                        label: '${_softwareVolume.round()}',
                        onChanged: (double value) {
                          setModal(() {
                            setState(() {
                              _softwareVolume = value;
                            });
                          });
                          unawaited(_controller?.setVolume((_softwareVolume / 100.0).clamp(0.0, 1.0)));
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.x2),
                Text(
                  'Drag vertically on the right edge for quick volume. Values above 100 boost quiet streams.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  _NextEpisodeTarget? get _nextEpisodeTarget {
    if (!widget.args.mediaItem.isShow ||
        widget.args.season == null ||
        widget.args.episode == null) {
      return null;
    }

    final List<Season> seasons = widget.args.mediaItem.seasons;
    final int currentSeasonNumber = widget.args.season!;
    final int currentEpisodeNumber = widget.args.episode!;
    final int seasonIndex = seasons.indexWhere(
      (Season season) => season.number == currentSeasonNumber,
    );
    if (seasonIndex == -1) {
      return null;
    }

    final Season currentSeason = seasons[seasonIndex];
    final int episodeIndex = currentSeason.episodes.indexWhere(
      (Episode episode) => episode.number == currentEpisodeNumber,
    );
    if (episodeIndex == -1) {
      return null;
    }

    if (episodeIndex + 1 < currentSeason.episodes.length) {
      final Episode nextEpisode = currentSeason.episodes[episodeIndex + 1];
      return _NextEpisodeTarget(
        season: currentSeason.number,
        episode: nextEpisode.number,
        label: 'S${currentSeason.number}:E${nextEpisode.number}',
      );
    }

    if (seasonIndex + 1 < seasons.length &&
        seasons[seasonIndex + 1].episodes.isNotEmpty) {
      final Season nextSeason = seasons[seasonIndex + 1];
      final Episode nextEpisode = nextSeason.episodes.first;
      return _NextEpisodeTarget(
        season: nextSeason.number,
        episode: nextEpisode.number,
        label: 'S${nextSeason.number}:E${nextEpisode.number}',
      );
    }

    return null;
  }

  Future<void> _playNextEpisode() async {
    final _NextEpisodeTarget? nextEpisode = _nextEpisodeTarget;
    if (nextEpisode == null) {
      return;
    }

    final NavigatorState navigator = Navigator.of(context);
    await _persistProgress();
    if (!mounted) {
      return;
    }
    await navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ScrapingScreen(
          mediaItem: widget.args.mediaItem,
          season: nextEpisode.season,
          episode: nextEpisode.episode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String title;
    if (widget.args.mediaItem.isShow &&
        widget.args.season != null &&
        widget.args.episode != null) {
      title =
          '${widget.args.mediaItem.title} - S${widget.args.season}E${widget.args.episode}';
    } else {
      title = widget.args.mediaItem.title;
    }

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: AppColors.blackC50,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleScreenTap,
          onDoubleTapDown: _handleDoubleTapDown,
          // [onDoubleTap] required so the framework actually waits for a
          // potential second tap before firing onTap (slight delay) instead
          // of dropping our [onDoubleTapDown] handler.
          onDoubleTap: () {},
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: (DragUpdateDetails details) {
            unawaited(_onVerticalDragUpdate(details));
          },
          onVerticalDragEnd: _onVerticalDragEnd,
          child: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _PlayerBackdrop(mediaItem: widget.args.mediaItem),
                Positioned.fill(
                  child: IgnorePointer(
                    child: (_playerReady && _controller != null && _controller!.value.isInitialized)
                        ? AnimatedOpacity(
                            opacity: _hasFirstVideoFrame ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 300),
                            child: SizedBox.expand(
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: _controller!.value.size.width > 0
                                      ? _controller!.value.size.width
                                      : 1920,
                                  height: _controller!.value.size.height > 0
                                      ? _controller!.value.size.height
                                      : 1080,
                                  child: VideoPlayer(_controller!),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
                Center(
                  child: _hasPlaybackError
                      ? _PlaybackErrorCard(
                          message: _playbackError ?? 'Playback failed.',
                        )
                      : _sourceSwitching
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.x10,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const RepaintBoundary(
                                child: SizedBox(
                                  width: AppSpacing.x10,
                                  height: AppSpacing.x10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.x4),
                              Text(
                                'Switching source…',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: AppColors.typeEmphasis),
                              ),
                            ],
                          ),
                        )
                      : !_playerReady
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const RepaintBoundary(
                              child: SizedBox(
                                width: 36,
                                height: 36,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: AppColors.purple,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            Text(
                              'Loading stream...',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: AppColors.typeEmphasis,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                if (_buffering && !_hasPlaybackError && !_sourceSwitching)
                  const Center(
                    child: RepaintBoundary(child: CircularProgressIndicator()),
                  ),
                if (_subtitleToast != null)
                  Positioned(
                    top: AppSpacing.x8,
                    left: AppSpacing.x0,
                    right: AppSpacing.x0,
                    child: RepaintBoundary(
                      child: AnimatedOpacity(
                        opacity: _subtitleToast == null ? 0 : 1,
                        duration: const Duration(milliseconds: 180),
                        child: Center(
                          child: PlayerInfoPill(label: _subtitleToast!),
                        ),
                      ),
                    ),
                  ),
                if (_gestureHint != null)
                  Positioned(
                    left: AppSpacing.x4,
                    right: AppSpacing.x4,
                    bottom: MediaQuery.sizeOf(context).height * 0.22,
                    child: RepaintBoundary(
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.videoContextBackground.withValues(
                              alpha: 0.82,
                            ),
                            borderRadius: BorderRadius.circular(AppSpacing.x4),
                            border: Border.all(
                              color: AppColors.videoContextBorder,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.x4,
                              vertical: AppSpacing.x3,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                if (_gestureHintIcon != null)
                                  Icon(
                                    _gestureHintIcon,
                                    color: AppColors.typeEmphasis,
                                    size: AppSpacing.x6,
                                  ),
                                if (_gestureHintIcon != null)
                                  const SizedBox(width: AppSpacing.x2),
                                Flexible(
                                  child: Text(
                                    _gestureHint!,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: AppColors.typeEmphasis,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                PlayerControls(
                  visible: _controlsVisible && !_controlsLocked,
                  mediaTitle: title,
                  isPlaying: _playing,
                  position: _position,
                  duration: _duration,
                  buffered: _buffer,
                  showNextEpisode: _shouldShowNextEpisode,
                  nextEpisodeLabel: _nextEpisodeTarget?.label,
                  onBack: _exitPlayer,
                  onPlayPause: _togglePlayback,
                  onSeekBack: () => _seekRelative(-10),
                  onSeekForward: () => _seekRelative(10),
                  onSeek: _seekToFraction,
                  onOpenSettings: _openPlayerSettingsSheet,
                  onOpenBrightness: _openBrightnessSheet,
                  onOpenVolume: _openVolumeSheet,
                  autoRotate: !_landscapeLocked,
                  onToggleAutoRotate: _toggleAutoRotate,
                  onLock: _lockControls,
                  onNextEpisode: _playNextEpisode,
                ),
                if (_subtitlesEnabled && _currentSubtitleText.isNotEmpty && _playerReady)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    left: AppSpacing.x4,
                    right: AppSpacing.x4,
                    bottom: (_controlsVisible && !_controlsLocked)
                        ? AppSpacing.x20 + AppSpacing.x10
                        : AppSpacing.x6,
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: Container(
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.x3,
                              vertical: AppSpacing.x1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(
                                alpha: ref.watch(subtitleBgOpacityPrefProvider),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _currentSubtitleText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _hexToColorPlayer(
                                  ref.watch(subtitleColorPrefProvider),
                                ),
                                fontSize: ref.watch(subtitleSizePrefProvider).toDouble(),
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                                shadows: const <Shadow>[
                                  Shadow(
                                    color: Colors.black,
                                    blurRadius: 3,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (_controlsLocked)
                  Positioned(
                    top: AppSpacing.x4,
                    right: AppSpacing.x4,
                    child: SafeArea(
                      child: _LockedUnlockPill(onUnlock: _unlockControls),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _shouldShowNextEpisode {
    if (!widget.args.mediaItem.isShow || _nextEpisodeTarget == null) {
      return false;
    }
    if (_duration.inMilliseconds <= 0) {
      return false;
    }
    return _position.inMilliseconds / _duration.inMilliseconds > 0.90;
  }

  int _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value') ?? 0;
  }

  List<StreamCaption> get _availableCaptions {
    return _activeStreamResult.stream.captions
        .where((StreamCaption caption) => caption.url?.isNotEmpty == true)
        .toList(growable: false);
  }

  List<MapEntry<String, StreamQuality>> get _availableQualities {
    return _activeStreamResult.stream.qualities.entries
        .where((MapEntry<String, StreamQuality> entry) {
          return entry.value.url?.isNotEmpty == true;
        })
        .toList(growable: false);
  }

  Map<String, List<StreamCaption>> get _groupedCaptionsByLanguage {
    final Map<String, List<StreamCaption>> grouped =
        <String, List<StreamCaption>>{};
    for (final StreamCaption caption in _availableCaptions) {
      final String key = caption.language ?? caption.label ?? 'Unknown';
      grouped.putIfAbsent(key, () => <StreamCaption>[]).add(caption);
    }
    return grouped;
  }

  static String _subtitleLanguageBucket(String raw) {
    final String t = raw.trim().toLowerCase();
    return t.isEmpty ? 'unknown' : t;
  }

  /// Wyzie vs OpenSubtitles chip for merged subtitle rows.
  static String _onlineSubtitleProviderBadge(ExternalSubtitleOffer offer) {
    final String haystack =
        '${offer.providerLabel} ${offer.title}'.toLowerCase();
    if (haystack.contains('wyzie')) {
      return 'W';
    }
    if (haystack.contains('opensubtitles') || haystack.contains('open subtitle')) {
      return 'O';
    }
    return '?';
  }

  List<_MergedSubtitleLang> _mergeSubtitleLanguages(
    List<ExternalSubtitleOffer> offers,
  ) {
    final Map<String, _MergedSubtitleLang> map = <String, _MergedSubtitleLang>{};

    for (final MapEntry<String, List<StreamCaption>> e
        in _groupedCaptionsByLanguage.entries) {
      final String b = _subtitleLanguageBucket(e.key);
      map[b] = _MergedSubtitleLang(
        displayName: e.key,
        captions: List<StreamCaption>.from(e.value),
        offers: <ExternalSubtitleOffer>[],
      );
    }

    for (final ExternalSubtitleOffer o in offers) {
      final String rawLang =
          o.languageLabel.trim().isEmpty ? 'Unknown' : o.languageLabel.trim();
      final String b = _subtitleLanguageBucket(rawLang);
      final _MergedSubtitleLang? cur = map[b];
      if (cur != null) {
        map[b] = _MergedSubtitleLang(
          displayName: cur.displayName,
          captions: cur.captions,
          offers: <ExternalSubtitleOffer>[...cur.offers, o],
        );
      } else {
        map[b] = _MergedSubtitleLang(
          displayName: rawLang,
          captions: const <StreamCaption>[],
          offers: <ExternalSubtitleOffer>[o],
        );
      }
    }

    final List<_MergedSubtitleLang> list = map.values.toList();
    list.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return list;
  }

  void _navigateReplacePlayerWithResult(OmssSource source) {
    if (!mounted) {
      return;
    }
    final int epoch = DateTime.now().microsecondsSinceEpoch;
    // [extra] alone is not always enough for GoRouter to treat this as a new
    // navigation; a unique query + [replaceEpoch] pairs with [didUpdateWidget].
    context.go(
      Uri(
        path: '/player',
        queryParameters: <String, String>{'r': '$epoch'},
      ).toString(),
      extra: PlayerScreenArgs(
        mediaItem: widget.args.mediaItem,
        omssResponse: _omssResponse,
        initialSourceIndex: _omssResponse.sources.indexOf(source),
        season: widget.args.season,
        episode: widget.args.episode,
        seasonTmdbId: widget.args.seasonTmdbId,
        episodeTmdbId: widget.args.episodeTmdbId,
        seasonTitle: widget.args.seasonTitle,
        resumeFrom: _position.inSeconds,
        replaceEpoch: epoch,
        preservedCaption: _selectedCaption,
        preservedExternalOfferId: _activeExternalOfferId,
        preservedExternalSummary: _activeExternalSummary,
      ),
    );
  }

  String get _sourceLabelForSettings {
    if (_sourceSwitching &&
        _pendingSourceLabel != null &&
        _pendingSourceLabel!.trim().isNotEmpty) {
      return '${_pendingSourceLabel!.trim()}...';
    }
    return _activeSource.providerName;
  }

  String get _currentQualityLabel {
    return _selectedQualityKey ??
        _activeStreamResult.stream.selectedQuality ??
        (_availableQualities.isNotEmpty
            ? _availableQualities.first.key
            : 'Auto');
  }

  String get _currentSubtitleLabel {
    if (!_subtitlesEnabled) {
      return 'Off';
    }
    if (_activeExternalOfferId != null) {
      final String s = _activeExternalSummary?.trim() ?? '';
      if (s.isNotEmpty) {
        return s;
      }
      return 'Online';
    }
    if (_selectedCaption != null) {
      return _displayLabelForSelectedCaption(_selectedCaption!);
    }
    return 'On';
  }

  /// Settings card + consistent naming with the per-language sheet (e.g. "English").
  String _displayLabelForSelectedCaption(StreamCaption c) {
    for (final MapEntry<String, List<StreamCaption>> e
        in _groupedCaptionsByLanguage.entries) {
      for (final StreamCaption x in e.value) {
        if (identical(c, x) || _sameCaptionUrl(c, x)) {
          return e.key;
        }
      }
    }
    final String? lab = c.label?.trim();
    if (lab != null && lab.isNotEmpty) {
      return lab;
    }
    final String? lang = c.language?.trim();
    if (lang != null && lang.isNotEmpty) {
      return lang;
    }
    return 'On';
  }

  static bool _sameCaptionUrl(StreamCaption a, StreamCaption b) {
    final String? au = a.url?.trim();
    final String? bu = b.url?.trim();
    return au != null && au.isNotEmpty && au == bu;
  }

  bool _captionMatchesSelected(StreamCaption c) {
    final StreamCaption? s = _selectedCaption;
    if (s == null) {
      return false;
    }
    return identical(s, c) || _sameCaptionUrl(s, c);
  }

  Future<void> _applySelectedSubtitleTrack() async {
    if (!_subtitlesEnabled) {
      _clearParsedSubtitles();
      if (mounted) setState(() {});
      return;
    }

    if (_selectedCaption?.url?.isNotEmpty == true) {
      final String? uri = await _subtitleTrackForCaption(_selectedCaption!);
      if (uri != null && uri.isNotEmpty) {
        await _loadAndApplySubtitleFile(uri);
      }
      return;
    }

    if (_availableCaptions.isNotEmpty) {
      final StreamCaption caption = _availableCaptions.first;
      _selectedCaption = caption;
      final String? uri = await _subtitleTrackForCaption(caption);
      if (uri != null && uri.isNotEmpty) {
        await _loadAndApplySubtitleFile(uri);
      }
      return;
    }

    _subtitlesEnabled = false;
  }

  Future<void> _selectQuality(String? qualityKey) async {
    final int resumeFrom = _position.inSeconds;
    final String? qualityUrl = qualityKey == null
        ? null
        : _activeStreamResult.stream.qualities[qualityKey]?.url;

    if (qualityKey != null && (qualityUrl == null || qualityUrl.isEmpty)) {
      _setSubtitleState(
        enabled: _subtitlesEnabled,
        message: 'Selected quality is unavailable',
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedQualityKey = qualityKey;
      _selectedQualityUrl = qualityUrl;
      _playerReady = false;
      _buffering = true;
    });

    await _openStream(resumeFrom: resumeFrom);
    _setSubtitleState(
      enabled: _subtitlesEnabled,
      message: qualityKey == null
          ? 'Automatic quality enabled'
          : 'Quality: $qualityKey',
    );
  }

  Future<void> _disableSubtitles() async {
    _selectedCaption = null;
    _activeExternalOfferId = null;
    _activeExternalSummary = null;
    _clearParsedSubtitles();
    if (mounted) setState(() {});
    _setSubtitleState(enabled: false, message: 'Subtitles off');
    _showControls();
  }

  Future<void> _selectCaption(StreamCaption caption) async {
    if (caption.url?.isEmpty != false) {
      _setSubtitleState(enabled: false, message: 'Subtitle track unavailable');
      return;
    }

    _selectedCaption = caption;
    _activeExternalOfferId = null;
    _activeExternalSummary = null;
    _subtitlesEnabled = true;
    if (mounted) {
      setState(() {});
    }
    _notifyPlayerSettingsSubtitleLabel();
    final String? trackUri = await _subtitleTrackForCaption(caption);
    if (!mounted) {
      return;
    }
    if (trackUri != null && trackUri.isNotEmpty) {
      await _loadAndApplySubtitleFile(trackUri);
    }
    _setSubtitleState(
      enabled: true,
      message: _displayLabelForSelectedCaption(caption),
    );
    _showControls();
  }

  void _setSubtitleState({required bool enabled, required String message}) {
    if (!mounted) {
      return;
    }

    setState(() {
      _subtitlesEnabled = enabled;
      _subtitleToast = message;
    });
    _notifyPlayerSettingsSubtitleLabel();

    _subtitleToastTimer?.cancel();
    _subtitleToastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _subtitleToast = null;
      });
    });
  }

  String? _resolvePlayableUrl(StreamPlayback playback) {
    if (playback.playbackUrl?.isNotEmpty == true) {
      return playback.playbackUrl;
    }
    if (playback.proxiedPlaylist?.isNotEmpty == true) {
      return playback.proxiedPlaylist;
    }
    if (playback.playlist?.isNotEmpty == true) {
      return playback.playlist;
    }

    final String? selectedQuality = playback.selectedQuality;
    if (selectedQuality != null &&
        playback.qualities[selectedQuality]?.url?.isNotEmpty == true) {
      return playback.qualities[selectedQuality]?.url;
    }

    for (final StreamQuality quality in playback.qualities.values) {
      if (quality.url?.isNotEmpty == true) {
        return quality.url;
      }
    }

    return null;
  }
}

class _PlayerBackdrop extends StatelessWidget {
  const _PlayerBackdrop({required this.mediaItem});

  final MediaItem mediaItem;

  @override
  Widget build(BuildContext context) {
    final String? backdropUrl = mediaItem.backdropUrl();

    if (backdropUrl == null) {
      return const ColoredBox(color: AppColors.blackC50);
    }

    return CachedNetworkImage(
      imageUrl: backdropUrl,
      fit: BoxFit.cover,
      errorWidget: (_, loadError, stackTrace) =>
          const ColoredBox(color: AppColors.blackC50),
    );
  }
}

class _PlaybackErrorCard extends StatelessWidget {
  const _PlaybackErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.7,
      ),
      padding: const EdgeInsets.all(AppSpacing.x4),
      decoration: BoxDecoration(
        color: AppColors.videoContextBackground.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        border: Border.all(color: AppColors.videoContextError),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.videoContextError,
            size: AppSpacing.x10,
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            'Playback failed',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _NextEpisodeTarget {
  const _NextEpisodeTarget({
    required this.season,
    required this.episode,
    required this.label,
  });

  final int season;
  final int episode;
  final String label;
}

/// Source list backed by the cached OMSS v1.0 response. The refresh
/// button re-issues the same `GET /v1/...` against the resolver; per-
/// source probes are not needed because every source already carries
/// a playable URL.
class _SourcesCatalogSheet extends StatelessWidget {
  const _SourcesCatalogSheet({
    required this.sources,
    required this.currentSourceId,
    required this.refreshing,
    required this.switchingSourceId,
    required this.onRefreshSources,
    required this.onPick,
  });

  final List<OmssSource> sources;
  final String currentSourceId;
  final bool refreshing;
  final String? switchingSourceId;
  final VoidCallback onRefreshSources;
  final void Function(OmssSource source) onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: ListView.builder(
            primary: false,
            shrinkWrap: true,
            itemCount: sources.length,
            itemBuilder: (BuildContext context, int index) {
              final OmssSource source = sources[index];
              final bool isCurrent = source.providerId == currentSourceId;
              final bool isSwitching = source.providerId == switchingSourceId;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppColors.selectedGlow
                      : AppColors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.x4),
                  border: isCurrent
                      ? Border.all(color: AppColors.glassCardBorder)
                      : null,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: isSwitching ? null : () => onPick(source),
                    borderRadius: BorderRadius.circular(AppSpacing.x4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x2,
                        vertical: AppSpacing.x3,
                      ),
                      child: Row(
                        children: <Widget>[
                          if (isCurrent)
                            Container(
                              width: 3,
                              height: AppSpacing.x6,
                              margin: const EdgeInsets.only(
                                right: AppSpacing.x2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.purpleC200,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  source.providerName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: isCurrent
                                            ? AppColors.typeEmphasis
                                            : AppColors.typeText,
                                        fontWeight: isCurrent
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: AppSpacing.x1),
                                Row(
                                  children: <Widget>[
                                    // Quality pill badge
                                    if (source.quality != null &&
                                        source.quality!.isNotEmpty)
                                      Container(
                                        margin: const EdgeInsets.only(
                                          right: AppSpacing.x2,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.x2,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.purpleC600
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(
                                            AppSpacing.x2,
                                          ),
                                        ),
                                        child: Text(
                                          source.quality!.toUpperCase(),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: AppColors.purpleC100,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.5,
                                              ),
                                        ),
                                      ),
                                    // Type pill badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.x2,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.blackC125
                                            .withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(
                                          AppSpacing.x2,
                                        ),
                                      ),
                                      child: Text(
                                        source.type.toUpperCase(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: AppColors.typeSecondary,
                                              letterSpacing: 0.5,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (isSwitching)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.x1,
                                    ),
                                    child: Text(
                                      'Switching...',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: AppColors.typeSecondary,
                                          ),
                                    ),
                                  )
                                else if (isCurrent)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: AppSpacing.x1,
                                    ),
                                    child: Text(
                                      'Now playing',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: AppColors.purpleC200,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (isSwitching)
                            const Padding(
                              padding:
                                  EdgeInsets.only(right: AppSpacing.x2),
                              child: SizedBox(
                                width: AppSpacing.x5,
                                height: AppSpacing.x5,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          else if (isCurrent)
                            const Padding(
                              padding:
                                  EdgeInsets.only(right: AppSpacing.x2),
                              child: Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.purpleC100,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(color: AppColors.utilsDivider, height: AppSpacing.x4),
        Text(
          'cinepro returned these playable sources for this title. '
          'Pick one to switch. "Refresh sources" re-issues the same request '
          'in case a previously unavailable provider is back.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.typeSecondary,
              ),
        ),
        const SizedBox(height: AppSpacing.x2),
        TextButton(
          onPressed: refreshing ? null : onRefreshSources,
          child: Text(
            refreshing ? 'Refreshing…' : 'Refresh sources',
          ),
        ),
      ],
    );
  }
}

class _PlayerSheetScaffold extends StatelessWidget {
  const _PlayerSheetScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final _PlayerSheetMetrics metrics = _PlayerSheetMetrics.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          metrics.outerInset,
          metrics.outerInset,
          metrics.outerInset,
          metrics.bottomInset,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.glassSheet,
            borderRadius: BorderRadius.circular(metrics.sheetRadius),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.blackC50.withValues(alpha: 0.45),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(metrics.sheetRadius),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PlayerSettingsHomeSheet extends StatelessWidget {
  const _PlayerSettingsHomeSheet({
    required this.qualityLabel,
    required this.sourceLabel,
    required this.subtitleLabel,
    required this.sourceSwitching,
    required this.onQualityTap,
    required this.onSourceTap,
    required this.onSubtitlesTap,
  });

  final String qualityLabel;
  final String sourceLabel;
  final String subtitleLabel;
  final bool sourceSwitching;
  final VoidCallback onQualityTap;
  final VoidCallback onSourceTap;
  final VoidCallback onSubtitlesTap;

  @override
  Widget build(BuildContext context) {
    final _PlayerSheetMetrics metrics = _PlayerSheetMetrics.of(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(metrics.contentPadding),
      child: Column(
        // [stretch] so the lone Subtitles card fills the full sheet width.
        // Row children already fill internally, coming-soon tiles too.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Two cards side-by-side: Quality + Source.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool stackCards = constraints.maxWidth < 360;
              if (stackCards) {
                return Column(
                  children: <Widget>[
                    _PlayerSettingsCard(
                      title: 'Quality',
                      subtitle: qualityLabel,
                      onTap: onQualityTap,
                    ),
                    SizedBox(height: metrics.itemGap),
                    _PlayerSettingsCard(
                      title: 'Source',
                      subtitle: sourceLabel,
                      loading: sourceSwitching,
                      onTap: onSourceTap,
                    ),
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(
                    child: _PlayerSettingsCard(
                      title: 'Quality',
                      subtitle: qualityLabel,
                      onTap: onQualityTap,
                    ),
                  ),
                  SizedBox(width: metrics.itemGap),
                  Expanded(
                    child: _PlayerSettingsCard(
                      title: 'Source',
                      subtitle: sourceLabel,
                      loading: sourceSwitching,
                      onTap: onSourceTap,
                    ),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: metrics.itemGap),
          // Subtitles spans full width — replaces the old 2x2 layout that
          // also held a non-clickable "Audio" tile (always HLS).
          _PlayerSettingsCard(
            title: 'Subtitles',
            subtitle: subtitleLabel,
            onTap: onSubtitlesTap,
          ),
          SizedBox(height: metrics.sectionGap),
          // Web-parity rows (Download / Watch Party) kept as coming-soon
          // affordances so users know the feature surface exists.
          const _PlayerComingSoonTile(
            icon: Icons.download_rounded,
            title: 'Download',
          ),
          const SizedBox(height: AppSpacing.x2),
          const _PlayerComingSoonTile(
            icon: Icons.podcasts_rounded,
            title: 'Watch Party',
          ),
          SizedBox(height: metrics.itemGap),
          const _PlayerComingSoonTile(
            icon: Icons.skip_next_rounded,
            title: 'Skip Segments',
          ),
        ],
      ),
    );
  }
}

/// Visual placeholder row used in the player settings hub for features that
/// match web parity (Download, Watch Party, Skip Segments) but are gated to
/// a later milestone in this aggregator build.
class _PlayerComingSoonTile extends StatelessWidget {
  const _PlayerComingSoonTile({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppColors.typeLink),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            'Soon',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.typeSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _PlayerSettingsCard extends StatelessWidget {
  const _PlayerSettingsCard({
    required this.title,
    required this.subtitle,
    this.loading = false,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final _PlayerSheetMetrics metrics = _PlayerSheetMetrics.of(context);
    // Now used inside Row+Expanded for a true 2x2 grid; the card simply
    // fills its column. Fixed inner height keeps the four cards aligned
    // even when subtitle/source labels wrap to two lines.
    return SizedBox(
      height: metrics.settingsCardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.glassCard,
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          border: Border.all(color: AppColors.glassCardBorder, width: 0.8),
        ),
        child: Material(
          color: AppColors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.x4),
            hoverColor: AppColors.activeCardTint,
            splashColor: AppColors.purpleC600.withValues(alpha: 0.15),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: metrics.contentPadding,
                vertical: metrics.contentPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppColors.typeEmphasis,
                              ),
                        ),
                      ),
                      if (loading)
                        const SizedBox(
                          width: AppSpacing.x4,
                          height: AppSpacing.x4,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x1),
                  Text(
                    subtitle,
                    maxLines: metrics.settingsSubtitleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.typeSecondary,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerOptionSheet extends StatelessWidget {
  const _PlayerOptionSheet({
    required this.title,
    required this.child,
    required this.onBack,
    this.footer,
    this.trailingText,
    this.onTrailingTap,
    this.titleTrailing,
  });

  final String title;
  final Widget child;
  final VoidCallback onBack;
  final Widget? footer;
  final String? trailingText;
  final VoidCallback? onTrailingTap;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    final _PlayerSheetMetrics metrics = _PlayerSheetMetrics.of(context);
    return Padding(
      padding: EdgeInsets.all(metrics.contentPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: onBack,
                visualDensity: VisualDensity.compact,
                constraints: metrics.optionIconConstraints,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              SizedBox(width: metrics.itemGap),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.typeEmphasis,
                  ),
                ),
              ),
              if (titleTrailing != null)
                titleTrailing!
              else if (trailingText != null)
                TextButton(
                  onPressed: onTrailingTap,
                  child: Text(trailingText!),
                ),
            ],
          ),
          SizedBox(height: metrics.itemGap),
          const Divider(color: AppColors.utilsDivider, height: AppSpacing.x0),
          SizedBox(height: metrics.itemGap),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: metrics.optionBodyMaxHeight(context),
            ),
            child: child,
          ),
          if (footer != null) ...<Widget>[
            SizedBox(height: metrics.itemGap),
            const Divider(color: AppColors.utilsDivider, height: AppSpacing.x0),
            SizedBox(height: metrics.itemGap),
            footer!,
          ],
        ],
      ),
    );
  }
}

class _PlayerSheetMetrics {
  const _PlayerSheetMetrics({
    required this.outerInset,
    required this.bottomInset,
    required this.sheetRadius,
    required this.contentPadding,
    required this.itemGap,
    required this.sectionGap,
    required this.settingsCardHeight,
    required this.settingsSubtitleMaxLines,
    required this.optionIconConstraints,
    required this.optionRowPadding,
    required this.externalRowPadding,
    required this.externalBadgeSize,
  });

  final double outerInset;
  final double bottomInset;
  final double sheetRadius;
  final double contentPadding;
  final double itemGap;
  final double sectionGap;
  final double settingsCardHeight;
  final int settingsSubtitleMaxLines;
  final BoxConstraints optionIconConstraints;
  final EdgeInsetsGeometry optionRowPadding;
  final EdgeInsetsGeometry externalRowPadding;
  final double externalBadgeSize;

  static _PlayerSheetMetrics of(BuildContext context) {
    final bool small = isSmallHandset(context);
    return _PlayerSheetMetrics(
      outerInset: small ? AppSpacing.x2 : AppSpacing.x3,
      bottomInset: small ? AppSpacing.x3 : AppSpacing.x4,
      sheetRadius: small ? AppSpacing.x4 : AppSpacing.x5,
      contentPadding: small ? AppSpacing.x3 : AppSpacing.x4,
      itemGap: small ? AppSpacing.x2 : AppSpacing.x3,
      sectionGap: small ? AppSpacing.x3 : AppSpacing.x4,
      settingsCardHeight: small ? 68 : AppSpacing.x20,
      settingsSubtitleMaxLines: small ? 2 : 1,
      optionIconConstraints: BoxConstraints.tightFor(
        width: small ? 40 : 44,
        height: small ? 40 : 44,
      ),
      optionRowPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: small ? AppSpacing.x2 : AppSpacing.x3,
      ),
      externalRowPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: small ? AppSpacing.x2 : AppSpacing.x3,
      ),
      externalBadgeSize: small ? AppSpacing.x8 : AppSpacing.x10,
    );
  }

  double optionBodyMaxHeight(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final double shortestSide = size.shortestSide;
    if (shortestSide < 380) {
      return size.height * 0.42;
    }
    if (shortestSide < 430) {
      return size.height * 0.44;
    }
    return size.height * 0.46;
  }
}

class _PlayerOptionRow extends StatelessWidget {
  const _PlayerOptionRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.showChevron = false,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool selected;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final _PlayerSheetMetrics metrics = _PlayerSheetMetrics.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? AppColors.selectedGlow : AppColors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        border: selected
            ? Border.all(color: AppColors.glassCardBorder)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          child: Padding(
            padding: metrics.optionRowPadding,
            child: Row(
              children: <Widget>[
                if (selected)
                  Container(
                    width: 3,
                    height: AppSpacing.x6,
                    margin: const EdgeInsets.only(right: AppSpacing.x2),
                    decoration: BoxDecoration(
                      color: AppColors.purpleC200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: selected
                              ? AppColors.typeEmphasis
                              : AppColors.typeText,
                        ),
                      ),
                      if (subtitle != null) ...<Widget>[
                        const SizedBox(height: AppSpacing.x1),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                if (showChevron)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.typeSecondary,
                  ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.x2),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.purpleC100,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// OpenSubtitles / Wyzie row in the per-language subtitle sheet (O / W badge).
class _PlayerExternalOfferRow extends StatelessWidget {
  const _PlayerExternalOfferRow({
    required this.offer,
    required this.badge,
    required this.selected,
    required this.onTap,
  });

  final ExternalSubtitleOffer offer;
  final String badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final _PlayerSheetMetrics metrics = _PlayerSheetMetrics.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        child: Padding(
          padding: metrics.externalRowPadding,
          child: Row(
            children: <Widget>[
              Container(
                width: metrics.externalBadgeSize,
                height: metrics.externalBadgeSize,
                decoration: BoxDecoration(
                  color: AppColors.blackC125,
                  borderRadius: BorderRadius.circular(AppSpacing.x3),
                ),
                alignment: Alignment.center,
                child: Text(
                  badge,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.typeEmphasis,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      offer.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.typeEmphasis,
                          ),
                    ),
                    const SizedBox(height: AppSpacing.x2),
                    Wrap(
                      spacing: AppSpacing.x2,
                      runSpacing: AppSpacing.x2,
                      children: <Widget>[
                        _CaptionBadge(label: offer.providerLabel),
                      ],
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.purpleC100,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single subtitle track row used in the language detail sheet. Mirrors
/// the web `SubtitleTrackList.tsx` layout: flag + name + format / provider
/// chips + optional hearing-impaired tag + selected check. Long-press
/// reveals the source URL so the user can verify or copy it.
class _PlayerCaptionRow extends StatelessWidget {
  const _PlayerCaptionRow({
    required this.caption,
    required this.selected,
    required this.onTap,
    required this.flag,
    required this.hearingImpaired,
  });

  final StreamCaption caption;
  final bool selected;
  final VoidCallback onTap;
  final String flag;
  final bool hearingImpaired;

  void _showSourceTooltip(BuildContext context) {
    final String url = caption.url ?? '';
    if (url.isEmpty) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.modalBackground,
      barrierColor: AppColors.transparent,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x4,
              AppSpacing.x0,
              AppSpacing.x4,
              AppSpacing.x4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  caption.label ?? caption.language ?? 'Subtitle source',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.x2),
                if (hearingImpaired)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.x2),
                    child: Text(
                      'Hearing impaired: yes',
                      style: Theme.of(sheetContext).textTheme.bodySmall,
                    ),
                  ),
                SelectableText(
                  url,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                        color: AppColors.typeText,
                      ),
                ),
                const SizedBox(height: AppSpacing.x3),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (sheetContext.mounted) {
                        Navigator.of(sheetContext).pop();
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copy URL'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> badges = <String>[
      if (caption.type?.isNotEmpty == true) caption.type!,
      if (caption.raw['source'] != null) '${caption.raw['source']}',
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _showSourceTooltip(context),
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x3,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: AppSpacing.x10,
                height: AppSpacing.x10,
                decoration: BoxDecoration(
                  color: AppColors.blackC125,
                  borderRadius: BorderRadius.circular(AppSpacing.x3),
                ),
                alignment: Alignment.center,
                child: Text(
                  flag,
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      caption.label ?? caption.language ?? 'Subtitle track',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.typeEmphasis,
                          ),
                    ),
                    if (badges.isNotEmpty || hearingImpaired) ...<Widget>[
                      const SizedBox(height: AppSpacing.x2),
                      Wrap(
                        spacing: AppSpacing.x2,
                        runSpacing: AppSpacing.x2,
                        children: <Widget>[
                          for (final String badge in badges)
                            _CaptionBadge(label: badge.toUpperCase()),
                          if (hearingImpaired)
                            const _CaptionBadge(
                              label: 'SDH',
                              accent: true,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.purpleC100,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptionBadge extends StatelessWidget {
  const _CaptionBadge({required this.label, this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x1,
      ),
      decoration: BoxDecoration(
        color: accent ? AppColors.buttonsPurple : AppColors.blackC125,
        borderRadius: BorderRadius.circular(AppSpacing.x2),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.typeEmphasis,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Subtitle root sheet entry per language. Mirrors image 3: flag avatar +
/// language name + count chip + chevron. Selecting drills into
/// `_PlayerCaptionRow` for the per-track picker.
class _PlayerLanguageRow extends StatelessWidget {
  const _PlayerLanguageRow({
    required this.flag,
    required this.name,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String flag;
  final String name;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x2,
            vertical: AppSpacing.x3,
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: AppSpacing.x10,
                height: AppSpacing.x10,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.blackC125,
                  borderRadius: BorderRadius.circular(AppSpacing.x3),
                ),
                child: Text(flag, style: const TextStyle(fontSize: 22)),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: selected
                            ? AppColors.typeEmphasis
                            : AppColors.typeText,
                      ),
                ),
              ),
              if (count > 1)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.x2),
                  child: Text(
                    '$count',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.typeSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.typeSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerToggleRow extends StatelessWidget {
  const _PlayerToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  static const bool enabled = true;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: enabled
                      ? AppColors.typeEmphasis
                      : AppColors.typeSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.x3),
        // Pin off-state colors so the pill is grey when off (Material 3
        // defaults give a purple thumb on dark backgrounds).
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeThumbColor: AppColors.typeEmphasis,
          activeTrackColor: AppColors.buttonsPurple,
          inactiveThumbColor: AppColors.typeSecondary,
          inactiveTrackColor: AppColors.dropdownBorder,
          trackOutlineColor: WidgetStateProperty.resolveWith<Color?>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.buttonsPurple;
              }
              return AppColors.dropdownBorder;
            },
          ),
        ),
      ],
    );
  }
}

/// Subtitle styling editor used by the in-player Customize sheet. Stays
/// stateful so dragging the sliders renders smooth previews; persistence
/// is fan-out via [onChanged] so the player can re-apply native style.
class _SubtitleCustomizeSheet extends StatefulWidget {
  const _SubtitleCustomizeSheet({
    required this.initialSize,
    required this.initialColor,
    required this.initialBgOpacity,
    required this.onChanged,
    required this.onBack,
  });

  final int initialSize;
  final String initialColor;
  final double initialBgOpacity;
  final void Function({int? size, String? color, double? bgOpacity}) onChanged;
  final VoidCallback onBack;

  @override
  State<_SubtitleCustomizeSheet> createState() =>
      _SubtitleCustomizeSheetState();
}

class _SubtitleCustomizeSheetState extends State<_SubtitleCustomizeSheet> {
  late int _size = widget.initialSize;
  late String _color = widget.initialColor;
  late double _bgOpacity = widget.initialBgOpacity;
  // Debounce Hive writes triggered by drag gestures so the storage box does
  // not get hammered ~60 times a second when the user drags a slider.
  Timer? _writeDebounce;

  @override
  void dispose() {
    _writeDebounce?.cancel();
    super.dispose();
  }

  void _scheduleWrite({int? size, String? color, double? bgOpacity}) {
    _writeDebounce?.cancel();
    _writeDebounce = Timer(const Duration(milliseconds: 200), () {
      widget.onChanged(size: size, color: color, bgOpacity: bgOpacity);
    });
  }

  static const List<({String hex, String label, Color swatch})> _palette =
      <({String hex, String label, Color swatch})>[
    (hex: '#FFFFFFFF', label: 'White', swatch: Color(0xFFFFFFFF)),
    (hex: '#FFFCEC61', label: 'Yellow', swatch: Color(0xFFFCEC61)),
    (hex: '#FF60D26A', label: 'Green', swatch: Color(0xFF60D26A)),
    (hex: '#FF8288FE', label: 'Purple', swatch: Color(0xFF8288FE)),
    (hex: '#FFF46E6E', label: 'Red', swatch: Color(0xFFF46E6E)),
  ];

  @override
  Widget build(BuildContext context) {
    final double maxH = MediaQuery.sizeOf(context).height * 0.88;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    'Customize subtitles',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.typeEmphasis,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x3),
            // Live preview block. Mirrors the on-screen subtitle render so
            // the slider/color choices feel immediate.
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.blackC50,
                borderRadius: BorderRadius.circular(AppSpacing.x3),
                border: Border.all(color: AppColors.dropdownBorder),
              ),
              child: SizedBox(
                height: 96,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.x3,
                      vertical: AppSpacing.x2,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: _bgOpacity),
                        borderRadius: BorderRadius.circular(AppSpacing.x2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.x2,
                          vertical: AppSpacing.x1,
                        ),
                        child: Text(
                          'Sample subtitle text',
                          style: TextStyle(
                            color: _hexToColor(_color),
                            fontSize: _size.toDouble(),
                            fontWeight: FontWeight.w600,
                            shadows: const <Shadow>[
                              Shadow(
                                color: Colors.black,
                                offset: Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.x4),
          Text('Font size', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            min: 16,
            max: 56,
            divisions: 20,
            value: _size.toDouble(),
            label: '$_size',
            onChanged: (double value) {
              setState(() {
                _size = value.round();
              });
              _scheduleWrite(size: _size);
            },
            onChangeEnd: (double value) {
              widget.onChanged(size: _size);
            },
          ),
          const SizedBox(height: AppSpacing.x2),
          Text('Text color', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.x2),
          Wrap(
            spacing: AppSpacing.x3,
            runSpacing: AppSpacing.x2,
            children: <Widget>[
              for (final ({String hex, String label, Color swatch}) opt
                  in _palette)
                _ColorSwatch(
                  swatch: opt.swatch,
                  selected: _color.toUpperCase() == opt.hex.toUpperCase(),
                  onTap: () {
                    setState(() {
                      _color = opt.hex;
                    });
                    widget.onChanged(color: _color);
                  },
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          Text(
            'Background opacity',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            min: 0,
            max: 1,
            divisions: 10,
            value: _bgOpacity,
            label: '${(_bgOpacity * 100).round()}%',
            onChanged: (double value) {
              setState(() {
                _bgOpacity = value;
              });
              _scheduleWrite(bgOpacity: _bgOpacity);
            },
            onChangeEnd: (double value) {
              widget.onChanged(bgOpacity: _bgOpacity);
            },
          ),
          ],
        ),
      ),
    );
  }

  static Color _hexToColor(String hex) {
    final String clean = hex.startsWith('#') ? hex.substring(1) : hex;
    final int parsed = int.tryParse(clean, radix: 16) ?? 0xFFFFFFFF;
    return Color(parsed);
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.swatch,
    required this.selected,
    required this.onTap,
  });

  final Color swatch;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.x4),
      child: Container(
        width: AppSpacing.x10,
        height: AppSpacing.x10,
        decoration: BoxDecoration(
          color: swatch,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.typeEmphasis : AppColors.dropdownBorder,
            width: selected ? 3 : 1,
          ),
        ),
        child: selected
            ? const Icon(
                Icons.check_rounded,
                color: AppColors.blackC50,
                size: AppSpacing.x5,
              )
            : null,
      ),
    );
  }
}

/// Small floating pill shown when the player is locked. The only affordance
/// while the controls are hidden — tap to restore the full overlay. Kept
/// light (no [BackdropFilter] blur) so it doesn't tax the GPU on top of the
/// active video frame.
class _LockedUnlockPill extends StatelessWidget {
  const _LockedUnlockPill({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onUnlock,
        borderRadius: BorderRadius.circular(AppSpacing.x10),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x3,
            vertical: AppSpacing.x2,
          ),
          decoration: BoxDecoration(
            color: AppColors.blackC50.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppSpacing.x10),
            border: Border.all(
              color: AppColors.videoContextBorder.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.lock_rounded,
                size: AppSpacing.x4,
                color: AppColors.typeEmphasis,
              ),
              const SizedBox(width: AppSpacing.x2),
              Text(
                'Tap to unlock',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.typeEmphasis,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
