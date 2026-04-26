import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/external_subtitle_offer.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/episode.dart';
import 'package:pstream_android/models/season.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';
import 'package:pstream_android/providers/storage_provider.dart';
import 'package:pstream_android/providers/stream_provider.dart';
import 'package:pstream_android/screens/scraping_screen.dart';
import 'package:pstream_android/services/external_subtitle_service.dart';
import 'package:pstream_android/services/stream_service.dart';
import 'package:pstream_android/storage/local_storage.dart';
import 'package:pstream_android/utils/player_native_tune.dart';
import 'package:pstream_android/widgets/player_controls.dart';
import 'package:screen_brightness/screen_brightness.dart';

enum _PlayerEdgeSwipe { none, brightness, volume }

class PlayerScreenArgs {
  const PlayerScreenArgs({
    required this.mediaItem,
    required this.streamResult,
    this.season,
    this.episode,
    this.seasonTmdbId,
    this.episodeTmdbId,
    this.seasonTitle,
    this.resumeFrom,
  });

  final MediaItem mediaItem;
  final StreamResult streamResult;
  final int? season;
  final int? episode;
  final String? seasonTmdbId;
  final String? episodeTmdbId;
  final String? seasonTitle;
  final int? resumeFrom;
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args});

  final PlayerScreenArgs args;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player = Player(
    configuration: const PlayerConfiguration(
      title: 'Veil',
      bufferSize: 64 * 1024 * 1024,
    ),
  );
  late final VideoController _videoController = VideoController(_player);

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  Timer? _controlsHideTimer;
  Timer? _progressTimer;
  String? _subtitleToast;
  Timer? _subtitleToastTimer;
  Timer? _gestureHintTimer;

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
  bool _hasPlaybackError = false;
  bool _sourceSwitching = false;
  bool _wasBackgrounded = false;
  String? _playbackError;
  int? _resumeFromOverride;
  String? _selectedQualityKey;
  String? _selectedQualityUrl;
  StreamCaption? _selectedCaption;
  late final StorageController _storageController;
  late final StreamService _streamService;

  /// When true, player only allows landscape orientations (auto-flips between
  /// left/right). When false, follows the device — phones can stay portrait.
  /// Toggled by the rotate button in [PlayerControls].
  bool _landscapeLocked = true;

  /// When true, all player controls are hidden and gestures (tap to show /
  /// edge-swipe brightness/volume) are ignored. A small unlock pill in the
  /// top-right is the only affordance until the user taps it.
  bool _controlsLocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storageController = ref.read(storageControllerProvider);
    _streamService = ref.read(streamServiceProvider);
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
  void dispose() {
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
    for (final StreamSubscription<dynamic> subscription in _subscriptions) {
      subscription.cancel();
    }
    _controlsHideTimer?.cancel();
    _progressTimer?.cancel();
    _subtitleToastTimer?.cancel();
    _gestureHintTimer?.cancel();
    unawaited(_restoreScreenBrightness());
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    unawaited(_player.dispose());
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
  /// Pick the most reliable language code from a group of captions. The
  /// first non-empty value wins so flags follow the dominant track.
  static String? _languageCodeFor(List<StreamCaption> captions) {
    for (final StreamCaption caption in captions) {
      final String? code = caption.language;
      if (code != null && code.trim().isNotEmpty) {
        return code;
      }
    }
    return null;
  }

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

  /// Push the user's saved subtitle style (size / text color / background
  /// opacity) into the native libmpv player. Called both right after a
  /// stream opens and again whenever the Customize sheet writes a new pref.
  ///
  /// We also push the same style to Flutter's [SubtitleView] via
  /// [_buildSubtitleViewConfiguration] so the on-screen subtitle render is
  /// guaranteed correct even when libmpv's hardware decoder bypasses the
  /// `sub-*` properties.
  Future<void> _applyNativeSubtitleStyleFromPrefs() async {
    await applyNativeSubtitleStyle(
      _player,
      size: LocalStorage.getSubtitleSize(),
      colorHex: LocalStorage.getSubtitleColor(),
      bgOpacity: LocalStorage.getSubtitleBgOpacity(),
    );
  }

  /// Build a [SubtitleViewConfiguration] using live Hive prefs. Watching
  /// the Riverpod providers in [build] makes the [Video] widget rebuild
  /// the moment the user nudges a slider in the Customize sheet.
  SubtitleViewConfiguration _buildSubtitleViewConfiguration(WidgetRef ref) {
    final int size = ref.watch(subtitleSizePrefProvider);
    final String colorHex = ref.watch(subtitleColorPrefProvider);
    final double bgOpacity = ref.watch(subtitleBgOpacityPrefProvider);
    final Color textColor = _hexToColorPlayer(colorHex);
    return SubtitleViewConfiguration(
      style: TextStyle(
        color: textColor,
        fontSize: size.toDouble(),
        fontWeight: FontWeight.w600,
        height: 1.3,
        letterSpacing: 0,
        backgroundColor: Colors.black.withValues(alpha: bgOpacity),
        shadows: const <Shadow>[
          Shadow(color: Colors.black, blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      textAlign: TextAlign.center,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x4,
        vertical: AppSpacing.x6,
      ),
    );
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
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _wasBackgrounded = true;
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
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      _player.stream.position.listen((Duration value) {
        if (!mounted) {
          return;
        }
        // libmpv emits position ~4×/s. Skip the [setState] (and the entire
        // controls-overlay rebuild) while the chrome is hidden — the value
        // is still cached for the next time controls are shown / progress
        // is persisted.
        if (!_controlsVisible) {
          _position = value;
          return;
        }
        setState(() {
          _position = value;
        });
      }),
      _player.stream.duration.listen((Duration value) {
        if (!mounted) {
          return;
        }
        setState(() {
          _duration = value;
        });
        // Resume needs the source's duration to be known — seeking before
        // libmpv reports duration is silently ignored. The earlier hook on
        // `playing == true` fired too soon for HLS/DASH streams, so do the
        // first seek here too as soon as a positive duration arrives.
        if (value.inMilliseconds > 0 && !_resumeApplied) {
          unawaited(_seekToResumePositionIfNeeded());
        }
      }),
      _player.stream.buffer.listen((Duration value) {
        if (!mounted) {
          return;
        }
        if (!_controlsVisible) {
          _buffer = value;
          return;
        }
        setState(() {
          _buffer = value;
        });
      }),
      _player.stream.playing.listen((bool value) {
        if (!mounted) {
          return;
        }
        setState(() {
          _playing = value;
        });
        if (value) {
          _seekToResumePositionIfNeeded();
        }
      }),
      _player.stream.buffering.listen((bool value) {
        if (!mounted) {
          return;
        }
        setState(() {
          _buffering = value;
        });
      }),
    ]);
  }

  Future<void> _openStream({int? resumeFrom}) async {
    final StreamPlayback playback = widget.args.streamResult.stream;
    final String? url = _selectedQualityUrl ?? _resolvePlayableUrl(playback);
    final Map<String, String> headers = playback.preferredHeaders.isNotEmpty
        ? playback.preferredHeaders
        : playback.headers;

    if (url == null || url.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hasPlaybackError = true;
        _playerReady = false;
        _buffering = false;
        _playbackError = 'No playable stream URL was provided.';
      });
      return;
    }

    try {
      if (resumeFrom != null && resumeFrom > 0) {
        _resumeFromOverride = resumeFrom;
      }
      _resumeApplied = false;
      final int? resumeStartSec = _resolvedResumeFrom;
      await _player.open(
        Media(
          url,
          httpHeaders: headers,
          start: resumeStartSec != null && resumeStartSec > 0
              ? Duration(seconds: resumeStartSec)
              : null,
        ),
      );
      await applyNativePlaybackTune(_player);
      await _applyNativeSubtitleStyleFromPrefs();
      await _player.setVolume(_softwareVolume);
      await _applySelectedSubtitleTrack();
      if (!mounted) {
        return;
      }
      setState(() {
        _playerReady = true;
        _hasPlaybackError = false;
        _playbackError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hasPlaybackError = true;
        _playerReady = false;
        _buffering = false;
        _playbackError = '$error';
      });
    }
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
    await _player.seek(Duration(seconds: targetSec));
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
    await _applyPlayerChrome();
    if (!_wasBackgrounded || !mounted) {
      return;
    }

    _wasBackgrounded = false;
    _resumeApplied = false;
    await _openStream(resumeFrom: _position.inSeconds);
    if (mounted) {
      setState(() {});
    }
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
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    _showControls();
  }

  Future<void> _seekRelative(int seconds) async {
    final int targetMs =
        ((_position.inMilliseconds + (seconds * 1000)).clamp(
                  0,
                  _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 0,
                )
                as num)
            .toInt();
    await _player.seek(Duration(milliseconds: targetMs));
    _showControls();
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
    await _player.seek(Duration(milliseconds: targetMs));
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
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  Future<T?> _showPlayerSheet<T>({required WidgetBuilder builder}) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
      barrierColor: AppColors.blackC50.withValues(alpha: 0.82),
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
              child: _PlayerSettingsHomeSheet(
                qualityLabel: _currentQualityLabel,
                sourceLabel: widget.args.streamResult.sourceName,
                subtitleLabel: _currentSubtitleLabel,
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
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSourceSheet() async {
    _showControls();
    final String? selectedSourceId = await _showPlayerSheet<String>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: FutureBuilder<ScrapeCatalog>(
            future: _streamService.fetchCatalog(),
            builder:
                (BuildContext context, AsyncSnapshot<ScrapeCatalog> snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.x6),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final List<ScrapeSourceDefinition> sources =
                      snapshot.data?.sources ??
                      const <ScrapeSourceDefinition>[];

                  return _PlayerOptionSheet(
                    title: 'Sources',
                    trailingText: 'Find next source',
                    onBack: () => Navigator.of(context).pop(),
                    onTrailingTap: () async {
                      final NavigatorState modalNavigator = Navigator.of(
                        context,
                      );
                      final NavigatorState screenNavigator = Navigator.of(
                        this.context,
                      );
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
                          ),
                        ),
                      );
                    },
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: sources.length,
                      itemBuilder: (BuildContext context, int index) {
                        final ScrapeSourceDefinition source = sources[index];
                        final bool isCurrent =
                            source.id == widget.args.streamResult.sourceId;

                        return _PlayerOptionRow(
                          title: source.name,
                          selected: isCurrent,
                          onTap: () => Navigator.of(context).pop(source.id),
                        );
                      },
                    ),
                  );
                },
          ),
        );
      },
    );

    if (selectedSourceId == null ||
        selectedSourceId == widget.args.streamResult.sourceId) {
      return;
    }

    await _switchSource(selectedSourceId);
  }

  Future<void> _openQualitySheet() async {
    _showControls();
    final List<MapEntry<String, StreamQuality>> qualities = _availableQualities;
    final bool hasQualities = qualities.isNotEmpty;

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
                footer: hasQualities
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
                                  widget.args.streamResult.stream
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
                          'This source did not expose multiple stream qualities. '
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

  Future<void> _openSubtitlesSheet() async {
    _showControls();

    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        // Sheet stays open across selections — picking Off / Auto / a
        // language only flips the tick; "leaf" actions (file, paste,
        // transcript, online search, customize) layer sub-sheets on top so
        // back returns here.
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final Map<String, List<StreamCaption>> groupedCaptions =
                _groupedCaptionsByLanguage;
            return _PlayerSheetScaffold(
              child: _PlayerOptionSheet(
                title: 'Subtitles',
                trailingText: 'Customize',
                onBack: () => Navigator.of(context).pop(),
                onTrailingTap: () async {
                  await _openCustomizeSubtitlesSheet();
                  setSheetState(() {});
                },
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    _PlayerOptionRow(
                      title: 'Off',
                      selected: !_subtitlesEnabled,
                      onTap: () {
                        _disableSubtitles();
                        setSheetState(() {});
                      },
                    ),
                    _PlayerOptionRow(
                      title: 'Auto select',
                      subtitle:
                          'Tap again to auto select a different subtitle',
                      selected: _subtitlesEnabled && _selectedCaption == null,
                      onTap: () {
                        _enableAutoSubtitles();
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
                    _PlayerOptionRow(
                      title: 'Transcript',
                      subtitle: _selectedCaption != null
                          ? 'Read the active track as text'
                          : 'Pick a subtitle first to read its transcript',
                      showChevron: true,
                      onTap: () async {
                        if (_selectedCaption?.url?.isNotEmpty == true) {
                          await _openTranscriptSheet(_selectedCaption!);
                        } else {
                          _setSubtitleState(
                            enabled: _subtitlesEnabled,
                            message:
                                'Pick a subtitle track first to read transcript.',
                          );
                        }
                        setSheetState(() {});
                      },
                    ),
                    if (AppConfig.hasWyzieApiKey ||
                        AppConfig.hasOpensubtitlesApiKey)
                      _PlayerOptionRow(
                        title: 'Search online…',
                        subtitle: 'Wyzie & OpenSubtitles',
                        showChevron: true,
                        onTap: () async {
                          await _openOnlineSubtitlesPicker();
                          setSheetState(() {});
                        },
                      ),
                    for (final MapEntry<String, List<StreamCaption>> entry
                        in groupedCaptions.entries)
                      _PlayerLanguageRow(
                        flag: _flagForLanguage(_languageCodeFor(entry.value)),
                        name: entry.key,
                        count: entry.value.length,
                        selected: _selectedCaption != null &&
                            entry.value.contains(_selectedCaption),
                        onTap: () async {
                          await _openSubtitleLanguageSheet(
                            entry.key,
                            entry.value,
                          );
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSubtitleLanguageSheet(
    String language,
    List<StreamCaption> captions,
  ) async {
    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
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
                  itemCount: captions.length,
                  itemBuilder: (BuildContext context, int index) {
                    final StreamCaption caption = captions[index];
                    final bool isSelected = caption == _selectedCaption;

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
      _subtitlesEnabled = true;
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          'file://$resolvedPath',
          title: single.name,
          language: 'local',
        ),
      );
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
    _subtitlesEnabled = true;
    try {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          'file://$path',
          title: 'Pasted',
          language: 'local',
        ),
      );
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

  /// Read-only transcript viewer. Fetches the selected track, parses cue
  /// lines, and renders them as a scrollable list with timestamps. Stream
  /// preferred headers are forwarded so providers that gate captions
  /// behind referrer/origin checks still serve the file.
  Future<void> _openTranscriptSheet(StreamCaption caption) async {
    final StreamPlayback playback = widget.args.streamResult.stream;
    final Map<String, String> headers = playback.preferredHeaders.isNotEmpty
        ? playback.preferredHeaders
        : playback.headers;
    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: _TranscriptSheet(
            caption: caption,
            headers: headers,
            onBack: () => Navigator.of(context).pop(),
          ),
        );
      },
    );
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

  Future<void> _openOnlineSubtitlesPicker() async {
    _showControls();
    if (!AppConfig.hasWyzieApiKey && !AppConfig.hasOpensubtitlesApiKey) {
      _setSubtitleState(
        enabled: _subtitlesEnabled,
        message: 'Add WYZIE_API_KEY or OPENSUBTITLES_API_KEY to your build',
      );
      return;
    }

    if (widget.args.mediaItem.isShow &&
        (widget.args.season == null || widget.args.episode == null)) {
      _setSubtitleState(
        enabled: _subtitlesEnabled,
        message: 'Episode context required for online subtitles',
      );
      return;
    }

    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: _OnlineSubtitleSearchSheet(
            mediaItem: widget.args.mediaItem,
            season: widget.args.season,
            episode: widget.args.episode,
            onBack: () => Navigator.of(context).pop(),
            onPick: (ExternalSubtitleOffer offer) async {
              Navigator.of(context).pop();
              await _applyExternalSubtitleOffer(offer);
            },
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
      String? url = offer.directUrl;
      if (offer.opensubtitlesFileId != null) {
        const ExternalSubtitleService service = ExternalSubtitleService();
        url ??= await service.resolveOpensubtitlesDownloadUrl(
          offer.opensubtitlesFileId!,
        );
      }

      if (url == null || url.isEmpty) {
        if (!mounted) {
          return;
        }
        _setSubtitleState(
          enabled: _subtitlesEnabled,
          message:
              'Could not open subtitle (try OPENSUBTITLES_USERNAME/PASSWORD for OpenSubtitles)',
        );
        return;
      }

      if (!mounted) {
        return;
      }

      _selectedCaption = null;
      _subtitlesEnabled = true;
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          url,
          title: offer.title,
          language: offer.languageLabel,
        ),
      );
      _setSubtitleState(enabled: true, message: offer.providerLabel);
      _showControls();
    } catch (_) {
      if (mounted) {
        _setSubtitleState(
          enabled: _subtitlesEnabled,
          message: 'Subtitle failed',
        );
      }
    }
  }

  Future<void> _switchSource(String sourceId) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _sourceSwitching = true;
      _buffering = true;
    });

    try {
      await _persistProgress();
      final StreamResult? result = await _streamService.scrapeSingleSource(
        widget.args.mediaItem,
        sourceId: sourceId,
        season: widget.args.season,
        episode: widget.args.episode,
        seasonTmdbId: widget.args.seasonTmdbId,
        episodeTmdbId: widget.args.episodeTmdbId,
        seasonTitle: widget.args.seasonTitle,
      );

      if (!mounted) {
        return;
      }

      if (result == null) {
        setState(() {
          _sourceSwitching = false;
          _buffering = false;
        });
        _setSubtitleState(
          enabled: _subtitlesEnabled,
          message: 'Source did not return a playable stream',
        );
        return;
      }

      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            args: PlayerScreenArgs(
              mediaItem: widget.args.mediaItem,
              streamResult: result,
              season: widget.args.season,
              episode: widget.args.episode,
              seasonTmdbId: widget.args.seasonTmdbId,
              episodeTmdbId: widget.args.episodeTmdbId,
              seasonTitle: widget.args.seasonTitle,
              resumeFrom: _position.inSeconds,
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sourceSwitching = false;
        _buffering = false;
      });
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
      unawaited(_seekRelative(-seekSecs));
      _flashGestureHint(
        icon: _doubleTapSeekIcon(-seekSecs),
        label: '-${seekSecs}s',
      );
    } else if (x > thirdRight) {
      unawaited(_seekRelative(seekSecs));
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
    if (_controlsLocked) {
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
      await _player.setVolume(_softwareVolume);
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
                        await _player.setVolume(_softwareVolume);
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
                          unawaited(_player.setVolume(_softwareVolume));
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
                    child: _playerReady
                        ? Video(
                            controller: _videoController,
                            controls: NoVideoControls,
                            fit: BoxFit.contain,
                            fill: AppColors.blackC50,
                            // Flutter-side subtitle render. media_kit pushes
                            // the active text track to `_player.stream.subtitle`
                            // and SubtitleView paints it with the
                            // [TextStyle] below — guaranteed independent of
                            // libmpv's hardware decode path. Style is read
                            // live from Hive prefs so the Customize sheet
                            // updates immediately.
                            subtitleViewConfiguration:
                                _buildSubtitleViewConfiguration(ref),
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
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const CircularProgressIndicator(),
                            const SizedBox(height: AppSpacing.x3),
                            Text(
                              'Switching source...',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: AppColors.typeEmphasis),
                            ),
                          ],
                        )
                      : !_playerReady
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.play_circle_fill_rounded,
                              color: AppColors.typeEmphasis.withValues(
                                alpha: 0.18,
                              ),
                              size:
                                  MediaQuery.sizeOf(context).shortestSide *
                                  0.24,
                            ),
                            const SizedBox(height: AppSpacing.x3),
                            Text(
                              _playerReady ? 'Streaming' : 'Loading stream...',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: AppColors.typeEmphasis),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                if (_buffering && !_hasPlaybackError)
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
                  sourceLabel:
                      widget.args.streamResult.embedName ??
                      widget.args.streamResult.sourceName,
                  isPlaying: _playing,
                  position: _position,
                  duration: _duration,
                  buffered: _buffer,
                  showNextEpisode: _shouldShowNextEpisode,
                  nextEpisodeLabel: _nextEpisodeTarget?.label,
                  onBack: () async {
                    final NavigatorState navigator = Navigator.of(context);
                    await _persistProgress();
                    if (!mounted) {
                      return;
                    }
                    await navigator.maybePop();
                  },
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
    return widget.args.streamResult.stream.captions
        .where((StreamCaption caption) => caption.url?.isNotEmpty == true)
        .toList(growable: false);
  }

  List<MapEntry<String, StreamQuality>> get _availableQualities {
    return widget.args.streamResult.stream.qualities.entries
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

  String get _currentQualityLabel {
    return _selectedQualityKey ??
        widget.args.streamResult.stream.selectedQuality ??
        (_availableQualities.isNotEmpty
            ? _availableQualities.first.key
            : 'Auto');
  }

  String get _currentSubtitleLabel {
    if (!_subtitlesEnabled) {
      return 'Off';
    }
    return _selectedCaption?.label ??
        _selectedCaption?.language ??
        (_availableCaptions.isNotEmpty ? 'Auto' : 'Embedded');
  }

  Future<void> _applySelectedSubtitleTrack() async {
    if (!_subtitlesEnabled) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      return;
    }

    if (_selectedCaption?.url?.isNotEmpty == true) {
      final StreamCaption caption = _selectedCaption!;
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          caption.url!,
          title: caption.label ?? caption.language ?? 'Subtitles',
          language: caption.language ?? 'unknown',
        ),
      );
      return;
    }

    if (_player.state.tracks.subtitle.isNotEmpty) {
      await _player.setSubtitleTrack(SubtitleTrack.auto());
      return;
    }

    if (_availableCaptions.isNotEmpty) {
      final StreamCaption caption = _availableCaptions.first;
      _selectedCaption = caption;
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          caption.url!,
          title: caption.label ?? caption.language ?? 'Subtitles',
          language: caption.language ?? 'unknown',
        ),
      );
      return;
    }

    _subtitlesEnabled = false;
  }

  Future<void> _selectQuality(String? qualityKey) async {
    final int resumeFrom = _position.inSeconds;
    final String? qualityUrl = qualityKey == null
        ? null
        : widget.args.streamResult.stream.qualities[qualityKey]?.url;

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
    await _player.setSubtitleTrack(SubtitleTrack.no());
    _setSubtitleState(enabled: false, message: 'Subtitles off');
    _showControls();
  }

  Future<void> _enableAutoSubtitles() async {
    _selectedCaption = null;

    if (_availableCaptions.isEmpty && _player.state.tracks.subtitle.isEmpty) {
      _setSubtitleState(enabled: false, message: 'No subtitles available');
      _showControls();
      return;
    }

    _subtitlesEnabled = true;
    await _applySelectedSubtitleTrack();
    _setSubtitleState(enabled: true, message: 'Subtitles auto');
    _showControls();
  }

  Future<void> _selectCaption(StreamCaption caption) async {
    if (caption.url?.isEmpty != false) {
      _setSubtitleState(enabled: false, message: 'Subtitle track unavailable');
      return;
    }

    _selectedCaption = caption;
    await _player.setSubtitleTrack(
      SubtitleTrack.uri(
        caption.url!,
        title: caption.label ?? caption.language ?? 'Subtitles',
        language: caption.language ?? 'unknown',
      ),
    );
    _setSubtitleState(
      enabled: true,
      message: caption.label ?? caption.language ?? 'Subtitles on',
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
    if (playback.proxiedPlaylist?.isNotEmpty == true) {
      return playback.proxiedPlaylist;
    }
    if (playback.playlist?.isNotEmpty == true) {
      return playback.playlist;
    }
    if (playback.playbackUrl?.isNotEmpty == true) {
      return playback.playbackUrl;
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

class _PlayerSheetScaffold extends StatelessWidget {
  const _PlayerSheetScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.x3,
          AppSpacing.x3,
          AppSpacing.x3,
          AppSpacing.x4,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.blackC50.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(AppSpacing.x5),
            border: Border.all(color: AppColors.videoContextBorder),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.x5),
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
    required this.onQualityTap,
    required this.onSourceTap,
    required this.onSubtitlesTap,
  });

  final String qualityLabel;
  final String sourceLabel;
  final String subtitleLabel;
  final VoidCallback onQualityTap;
  final VoidCallback onSourceTap;
  final VoidCallback onSubtitlesTap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        // [stretch] so the lone Subtitles card fills the full sheet width.
        // Row children already fill internally, coming-soon tiles too.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Two cards side-by-side: Quality + Source.
          Row(
            children: <Widget>[
              Expanded(
                child: _PlayerSettingsCard(
                  title: 'Quality',
                  subtitle: qualityLabel,
                  onTap: onQualityTap,
                ),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: _PlayerSettingsCard(
                  title: 'Source',
                  subtitle: sourceLabel,
                  onTap: onSourceTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          // Subtitles spans full width — replaces the old 2x2 layout that
          // also held a non-clickable "Audio" tile (always HLS).
          _PlayerSettingsCard(
            title: 'Subtitles',
            subtitle: subtitleLabel,
            onTap: onSubtitlesTap,
          ),
          const SizedBox(height: AppSpacing.x4),
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
          const SizedBox(height: AppSpacing.x3),
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
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Now used inside Row+Expanded for a true 2x2 grid; the card simply
    // fills its column. Fixed inner height keeps the four cards aligned
    // even when subtitle/source labels wrap to two lines.
    return SizedBox(
      height: AppSpacing.x20,
      child: Material(
        color: AppColors.blackC125,
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.x4,
              vertical: AppSpacing.x4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.typeEmphasis,
                      ),
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  subtitle,
                  maxLines: 1,
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
    this.trailingIcon,
    this.onTrailingTap,
  });

  final String title;
  final Widget child;
  final VoidCallback onBack;
  final Widget? footer;
  final String? trailingText;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.typeEmphasis,
                  ),
                ),
              ),
              if (trailingText != null)
                TextButton(
                  onPressed: onTrailingTap,
                  child: Text(trailingText!),
                ),
              if (trailingIcon != null)
                IconButton(onPressed: onTrailingTap, icon: Icon(trailingIcon)),
            ],
          ),
          const SizedBox(height: AppSpacing.x3),
          const Divider(color: AppColors.utilsDivider, height: AppSpacing.x0),
          const SizedBox(height: AppSpacing.x3),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.46,
            child: child,
          ),
          if (footer != null) ...<Widget>[
            const SizedBox(height: AppSpacing.x3),
            const Divider(color: AppColors.utilsDivider, height: AppSpacing.x0),
            const SizedBox(height: AppSpacing.x3),
            footer!,
          ],
        ],
      ),
    );
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
    );
  }
}

class _OnlineSubtitleSearchSheet extends StatefulWidget {
  const _OnlineSubtitleSearchSheet({
    required this.mediaItem,
    required this.season,
    required this.episode,
    required this.onBack,
    required this.onPick,
  });

  final MediaItem mediaItem;
  final int? season;
  final int? episode;
  final VoidCallback onBack;
  final Future<void> Function(ExternalSubtitleOffer offer) onPick;

  @override
  State<_OnlineSubtitleSearchSheet> createState() =>
      _OnlineSubtitleSearchSheetState();
}

class _OnlineSubtitleSearchSheetState
    extends State<_OnlineSubtitleSearchSheet> {
  late Future<List<ExternalSubtitleOffer>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadOffers();
  }

  Future<List<ExternalSubtitleOffer>> _loadOffers() {
    return const ExternalSubtitleService().searchOnline(
      media: widget.mediaItem,
      season: widget.season,
      episode: widget.episode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PlayerOptionSheet(
      title: 'Online subtitles',
      trailingIcon: Icons.sync_alt_rounded,
      onBack: widget.onBack,
      onTrailingTap: () {
        setState(() {
          _future = _loadOffers();
        });
      },
      child: FutureBuilder<List<ExternalSubtitleOffer>>(
        future: _future,
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<ExternalSubtitleOffer>> snapshot,
            ) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.x8),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.x5),
                  child: Text(
                    '${snapshot.error}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.typeText),
                  ),
                );
              }
              final List<ExternalSubtitleOffer> offers =
                  snapshot.data ?? const <ExternalSubtitleOffer>[];
              if (offers.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(AppSpacing.x5),
                  child: Text(
                    'No online subtitles found. Check keys or try another episode.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.typeText),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: AppSpacing.x4),
                itemCount: offers.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(height: AppSpacing.x2),
                itemBuilder: (BuildContext context, int index) {
                  final ExternalSubtitleOffer offer = offers[index];
                  return Material(
                    color: AppColors.dropdownAltBackground,
                    borderRadius: BorderRadius.circular(AppSpacing.x4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppSpacing.x4),
                      onTap: () => widget.onPick(offer),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.x4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              offer.title,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    color: AppColors.typeEmphasis,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.x2),
                            Text(
                              '${offer.languageLabel} · ${offer.providerLabel}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.typeSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
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
    return Padding(
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

/// Read-only transcript reader. Streams the chosen caption track over
/// HTTP, runs a tolerant VTT/SRT parser, and renders cues with timestamps.
class _TranscriptSheet extends StatefulWidget {
  const _TranscriptSheet({
    required this.caption,
    required this.onBack,
    this.headers = const <String, String>{},
  });

  final StreamCaption caption;
  final Map<String, String> headers;
  final VoidCallback onBack;

  @override
  State<_TranscriptSheet> createState() => _TranscriptSheetState();
}

class _TranscriptSheetState extends State<_TranscriptSheet> {
  late Future<List<_TranscriptCue>> _future = _load();

  Future<List<_TranscriptCue>> _load() async {
    final String? url = widget.caption.url;
    if (url == null || url.isEmpty) {
      return const <_TranscriptCue>[];
    }
    final http.Response response = await http
        .get(Uri.parse(url), headers: widget.headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Could not load transcript (${response.statusCode})');
    }
    return _parseCues(response.body);
  }

  static List<_TranscriptCue> _parseCues(String raw) {
    final List<_TranscriptCue> out = <_TranscriptCue>[];
    // Tolerant block split — VTT and SRT both separate cues with a blank
    // line. Timestamps are matched with `-->` and trimmed of trailing
    // styling info (`align:`, `position:` etc.).
    final RegExp tsRe = RegExp(
      r'(\d{1,2}:\d{2}(?::\d{2})?[,.]\d{1,3})\s*-->\s*(\d{1,2}:\d{2}(?::\d{2})?[,.]\d{1,3})',
    );
    for (final String block in raw.split(RegExp(r'\r?\n\r?\n'))) {
      final List<String> lines = block.split(RegExp(r'\r?\n'));
      if (lines.isEmpty) {
        continue;
      }
      String? start;
      final List<String> textLines = <String>[];
      for (final String line in lines) {
        final RegExpMatch? m = tsRe.firstMatch(line);
        if (m != null) {
          start = m.group(1);
          continue;
        }
        if (line.trim().isEmpty) {
          continue;
        }
        if (start == null) {
          // Skip cue numbers ("1", "2") and metadata ("WEBVTT").
          if (line.trim().toUpperCase() == 'WEBVTT' ||
              int.tryParse(line.trim()) != null) {
            continue;
          }
          continue;
        }
        textLines.add(line);
      }
      if (start != null && textLines.isNotEmpty) {
        out.add(
          _TranscriptCue(
            timestamp: start,
            text: textLines.join('\n').replaceAll(RegExp(r'<[^>]+>'), ''),
          ),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                  'Transcript',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColors.typeEmphasis,
                      ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _future = _load();
                  });
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: FutureBuilder<List<_TranscriptCue>>(
              future: _future,
              builder: (
                BuildContext context,
                AsyncSnapshot<List<_TranscriptCue>> snapshot,
              ) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4),
                    child: Text(
                      '${snapshot.error}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                final List<_TranscriptCue> cues =
                    snapshot.data ?? const <_TranscriptCue>[];
                if (cues.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(AppSpacing.x4),
                    child: Text(
                      'Transcript is empty for the selected track.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: cues.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.x2),
                  itemBuilder: (BuildContext context, int index) {
                    final _TranscriptCue cue = cues[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.x2,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            cue.timestamp,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AppColors.typeLink),
                          ),
                          const SizedBox(height: AppSpacing.x1),
                          Text(
                            cue.text,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptCue {
  const _TranscriptCue({required this.timestamp, required this.text});

  final String timestamp;
  final String text;
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
