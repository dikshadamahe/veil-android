import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
    unawaited(_persistProgress(refresh: false));
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

  /// Push the user's saved subtitle style (size / text color / background
  /// opacity) into the native libmpv player. Called both right after a
  /// stream opens and again whenever the Customize sheet writes a new pref.
  Future<void> _applyNativeSubtitleStyleFromPrefs() async {
    await applyNativeSubtitleStyle(
      _player,
      size: LocalStorage.getSubtitleSize(),
      colorHex: LocalStorage.getSubtitleColor(),
      bgOpacity: LocalStorage.getSubtitleBgOpacity(),
    );
  }

  Future<void> _applyPlayerChrome() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
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
      }),
      _player.stream.buffer.listen((Duration value) {
        if (!mounted) {
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
      await _player.open(Media(url, httpHeaders: headers));
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

    _resumeApplied = true;
    await _player.seek(Duration(seconds: resumeFrom));
  }

  int? get _resolvedResumeFrom {
    if (_resumeFromOverride != null && _resumeFromOverride! > 0) {
      return _resumeFromOverride;
    }
    if (widget.args.resumeFrom != null) {
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
    if (!_playerReady || _duration.inSeconds <= 0) {
      return;
    }

    await _storageController.saveProgress(
      widget.args.mediaItem,
      positionSecs: _position.inSeconds,
      durationSecs: _duration.inSeconds,
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
    final bool subtitlesAvailable =
        _availableCaptions.isNotEmpty ||
        _player.state.tracks.subtitle.isNotEmpty;

    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: _PlayerSettingsHomeSheet(
            qualityLabel: _currentQualityLabel,
            sourceLabel: widget.args.streamResult.sourceName,
            subtitleLabel: _currentSubtitleLabel,
            audioLabel: _currentAudioLabel,
            subtitlesEnabled: _subtitlesEnabled,
            subtitlesAvailable: subtitlesAvailable,
            onQualityTap: () {
              Navigator.of(context).pop();
              _openQualitySheet();
            },
            onSourceTap: () {
              Navigator.of(context).pop();
              _openSourceSheet();
            },
            onSubtitlesTap: () {
              Navigator.of(context).pop();
              _openSubtitlesSheet();
            },
            onSubtitleToggle: (bool value) {
              Navigator.of(context).pop();
              if (value) {
                _enableAutoSubtitles();
              } else {
                _disableSubtitles();
              }
            },
          ),
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

    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: _PlayerOptionSheet(
            title: 'Quality',
            onBack: () => Navigator.of(context).pop(),
            footer: _PlayerToggleRow(
              title: 'Automatic quality',
              subtitle:
                  'Use the source default unless you explicitly select a stream quality.',
              value: _selectedQualityKey == null,
              onChanged: (bool value) {
                Navigator.of(context).pop();
                if (value) {
                  _selectQuality(null);
                }
              },
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: qualities.length,
              itemBuilder: (BuildContext context, int index) {
                final MapEntry<String, StreamQuality> quality =
                    qualities[index];
                final bool isSelected =
                    _selectedQualityKey == quality.key ||
                    (_selectedQualityKey == null &&
                        widget.args.streamResult.stream.selectedQuality ==
                            quality.key);

                return _PlayerOptionRow(
                  title: quality.key,
                  subtitle: quality.value.type,
                  selected: isSelected,
                  onTap: () {
                    Navigator.of(context).pop();
                    _selectQuality(quality.key);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSubtitlesSheet() async {
    _showControls();
    final Map<String, List<StreamCaption>> groupedCaptions =
        _groupedCaptionsByLanguage;

    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: _PlayerOptionSheet(
            title: 'Subtitles',
            trailingText: 'Customize',
            onBack: () => Navigator.of(context).pop(),
            onTrailingTap: () {
              Navigator.of(context).pop();
              unawaited(_openCustomizeSubtitlesSheet());
            },
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                _PlayerOptionRow(
                  title: 'Off',
                  selected: !_subtitlesEnabled,
                  onTap: () {
                    Navigator.of(context).pop();
                    _disableSubtitles();
                  },
                ),
                _PlayerOptionRow(
                  title: 'Auto select',
                  subtitle: 'Tap again to auto select a different subtitle',
                  selected: _subtitlesEnabled && _selectedCaption == null,
                  onTap: () {
                    Navigator.of(context).pop();
                    _enableAutoSubtitles();
                  },
                ),
                _PlayerOptionRow(
                  title: 'Drop or upload file',
                  subtitle: '.srt or .vtt from this device',
                  showChevron: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_pickSubtitleFile());
                  },
                ),
                _PlayerOptionRow(
                  title: 'Paste subtitle data',
                  subtitle: 'Paste raw VTT or SRT text',
                  showChevron: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_openPasteSubtitleSheet());
                  },
                ),
                _PlayerOptionRow(
                  title: 'Transcript',
                  subtitle: _selectedCaption != null
                      ? 'Read the active track as text'
                      : 'Pick a subtitle first to read its transcript',
                  showChevron: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    if (_selectedCaption?.url?.isNotEmpty == true) {
                      unawaited(_openTranscriptSheet(_selectedCaption!));
                    } else {
                      _setSubtitleState(
                        enabled: _subtitlesEnabled,
                        message:
                            'Pick a subtitle track first to read transcript.',
                      );
                    }
                  },
                ),
                if (AppConfig.hasWyzieApiKey ||
                    AppConfig.hasOpensubtitlesApiKey)
                  _PlayerOptionRow(
                    title: 'Search online…',
                    subtitle: 'Wyzie & OpenSubtitles',
                    showChevron: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_openOnlineSubtitlesPicker());
                    },
                  ),
                for (final MapEntry<String, List<StreamCaption>> entry
                    in groupedCaptions.entries)
                  _PlayerOptionRow(
                    title: entry.key,
                    subtitle:
                        '${entry.value.length} track${entry.value.length == 1 ? '' : 's'}',
                    selected:
                        _selectedCaption != null &&
                        entry.value.contains(_selectedCaption),
                    showChevron: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      _openSubtitleLanguageSheet(entry.key, entry.value);
                    },
                  ),
              ],
            ),
          ),
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
        return _PlayerSheetScaffold(
          child: _PlayerOptionSheet(
            title: language,
            trailingText: 'Customize',
            onBack: () => Navigator.of(context).pop(),
            onTrailingTap: () {
              Navigator.of(context).pop();
              unawaited(_openCustomizeSubtitlesSheet());
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
                  onTap: () {
                    Navigator.of(context).pop();
                    _selectCaption(caption);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// Picks a local subtitle file via the system file picker, then loads it
  /// as the active track. Honors `.srt` / `.vtt` extensions.
  Future<void> _pickSubtitleFile() async {
    try {
      // file_picker 11.x replaced `FilePicker.platform.pickFiles` with a
      // static method on the [FilePicker] class itself.
      final FilePickerResult? picked = await FilePicker.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: const <String>['srt', 'vtt'],
      );
      if (picked == null || picked.files.isEmpty) {
        return;
      }
      final String? path = picked.files.single.path;
      if (path == null || path.isEmpty) {
        return;
      }
      if (!mounted) {
        return;
      }
      _selectedCaption = null;
      _subtitlesEnabled = true;
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          'file://$path',
          title: picked.files.single.name,
          language: 'local',
        ),
      );
      _setSubtitleState(enabled: true, message: 'Loaded ${picked.files.single.name}');
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
    final String mime = isVtt ? 'text/vtt' : 'application/x-subrip';
    final String dataUri =
        'data:$mime;base64,${base64Encode(utf8.encode(trimmed))}';
    if (!mounted) {
      return;
    }
    _selectedCaption = null;
    _subtitlesEnabled = true;
    try {
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          dataUri,
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
  /// lines, and renders them as a scrollable list with timestamps.
  Future<void> _openTranscriptSheet(StreamCaption caption) async {
    await _showPlayerSheet<void>(
      builder: (BuildContext context) {
        return _PlayerSheetScaffold(
          child: _TranscriptSheet(
            caption: caption,
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
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _armControlsHideTimer();
    } else {
      _controlsHideTimer?.cancel();
    }
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
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) {
          unawaited(_persistProgress());
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.blackC50,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleScreenTap,
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
                  visible: _controlsVisible,
                  mediaTitle: title,
                  sourceLabel:
                      widget.args.streamResult.embedName ??
                      widget.args.streamResult.sourceName,
                  qualityLabel: _currentQualityLabel,
                  subtitleLabel: _currentSubtitleLabel,
                  volumeLabel: '${_softwareVolume.round()}',
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
                  onFullscreen: _applyPlayerChrome,
                  onNextEpisode: _playNextEpisode,
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

  String get _currentAudioLabel {
    return widget.args.streamResult.stream.playbackType ??
        widget.args.streamResult.embedName ??
        'Default';
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
    required this.audioLabel,
    required this.subtitlesEnabled,
    required this.subtitlesAvailable,
    required this.onQualityTap,
    required this.onSourceTap,
    required this.onSubtitlesTap,
    required this.onSubtitleToggle,
  });

  final String qualityLabel;
  final String sourceLabel;
  final String subtitleLabel;
  final String audioLabel;
  final bool subtitlesEnabled;
  final bool subtitlesAvailable;
  final VoidCallback onQualityTap;
  final VoidCallback onSourceTap;
  final VoidCallback onSubtitlesTap;
  final ValueChanged<bool> onSubtitleToggle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: AppSpacing.x3,
            runSpacing: AppSpacing.x3,
            children: <Widget>[
              _PlayerSettingsCard(
                title: 'Quality',
                subtitle: qualityLabel,
                onTap: onQualityTap,
              ),
              _PlayerSettingsCard(
                title: 'Source',
                subtitle: sourceLabel,
                onTap: onSourceTap,
              ),
              _PlayerSettingsCard(
                title: 'Subtitles',
                subtitle: subtitleLabel,
                onTap: onSubtitlesTap,
              ),
              _PlayerSettingsCard(title: 'Audio', subtitle: audioLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.x4),
          // Web-parity rows (Download / Watch Party). Surfaced as
          // coming-soon entries so visual parity is preserved without
          // shipping a half-baked feature inside this aggregator-only
          // build.
          const _PlayerComingSoonTile(
            icon: Icons.download_rounded,
            title: 'Download',
          ),
          const SizedBox(height: AppSpacing.x2),
          const _PlayerComingSoonTile(
            icon: Icons.podcasts_rounded,
            title: 'Watch Party',
          ),
          const SizedBox(height: AppSpacing.x4),
          const Divider(color: AppColors.utilsDivider, height: AppSpacing.x0),
          const SizedBox(height: AppSpacing.x4),
          _PlayerToggleRow(
            title: 'Enable subtitles',
            subtitle: subtitlesAvailable
                ? 'Use auto select or choose a language-specific track.'
                : 'No subtitle tracks are available for this stream.',
            value: subtitlesEnabled,
            enabled: subtitlesAvailable,
            onChanged: onSubtitleToggle,
          ),
          const SizedBox(height: AppSpacing.x3),
          const _PlayerInlineInfoRow(
            title: 'Playback settings',
            subtitle:
                'Quality, source, subtitles, and stream-specific options.',
          ),
          const SizedBox(height: AppSpacing.x3),
          const _PlayerComingSoonTile(
            icon: Icons.skip_next_rounded,
            title: 'Skip Segments',
            inlineChevron: true,
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
  const _PlayerComingSoonTile({
    required this.icon,
    required this.title,
    this.inlineChevron = false,
  });

  final IconData icon;
  final String title;
  final bool inlineChevron;

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
          if (inlineChevron)
            const Padding(
              padding: EdgeInsets.only(left: AppSpacing.x2),
              child: Icon(
                Icons.chevron_right_rounded,
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
    final double width =
        (MediaQuery.sizeOf(context).width - AppSpacing.x12) / 2;
    return SizedBox(
      width: width.clamp(140, 220).toDouble(),
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
              children: <Widget>[
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.typeEmphasis,
                  ),
                ),
                const SizedBox(height: AppSpacing.x2),
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

class _PlayerCaptionRow extends StatelessWidget {
  const _PlayerCaptionRow({
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  final StreamCaption caption;
  final bool selected;
  final VoidCallback onTap;

  String _languageBadge(String? value) {
    final String normalized = (value == null || value.trim().isEmpty)
        ? '??'
        : value.trim().toUpperCase();
    return normalized.length >= 2 ? normalized.substring(0, 2) : normalized;
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
                  _languageBadge(caption.language),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.typeEmphasis,
                  ),
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
                    if (badges.isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.x2),
                      Wrap(
                        spacing: AppSpacing.x2,
                        runSpacing: AppSpacing.x2,
                        children: badges
                            .map(
                              (String badge) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.x2,
                                  vertical: AppSpacing.x1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.blackC125,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.x2,
                                  ),
                                ),
                                child: Text(
                                  badge.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(color: AppColors.typeEmphasis),
                                ),
                              ),
                            )
                            .toList(growable: false),
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

class _PlayerToggleRow extends StatelessWidget {
  const _PlayerToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

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
        Switch(value: value, onChanged: enabled ? onChanged : null),
      ],
    );
  }
}

class _PlayerInlineInfoRow extends StatelessWidget {
  const _PlayerInlineInfoRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.x1),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.typeSecondary),
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
  const _TranscriptSheet({required this.caption, required this.onBack});

  final StreamCaption caption;
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
        .get(Uri.parse(url))
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
