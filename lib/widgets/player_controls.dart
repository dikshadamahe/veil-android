import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/config/app_theme.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.visible,
    required this.mediaTitle,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.showNextEpisode,
    required this.onBack,
    required this.onPlayPause,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onSeek,
    required this.onOpenSettings,
    required this.onOpenBrightness,
    required this.onOpenVolume,
    required this.autoRotate,
    required this.onToggleAutoRotate,
    required this.onLock,
    required this.onNextEpisode,
    this.nextEpisodeLabel,
  });

  final bool visible;
  final String mediaTitle;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final bool showNextEpisode;
  final VoidCallback onBack;
  final Future<void> Function() onPlayPause;
  final Future<void> Function() onSeekBack;
  final Future<void> Function() onSeekForward;
  final Future<void> Function(double fraction) onSeek;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenBrightness;
  final Future<void> Function() onOpenVolume;
  /// True when player allows free auto-rotate; false when locked to landscape.
  final bool autoRotate;
  final Future<void> Function() onToggleAutoRotate;
  /// Hide all controls and ignore taps until the user taps the unlock pill.
  final VoidCallback onLock;
  final Future<void> Function() onNextEpisode;
  final String? nextEpisodeLabel;

  @override
  Widget build(BuildContext context) {
    final _PlayerControlMetrics metrics = _PlayerControlMetrics.of(context);

    return IgnorePointer(
      ignoring: !visible,
      child: RepaintBoundary(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned(
                left: metrics.edgeInset,
                right: metrics.edgeInset,
                top: metrics.edgeInset,
                child: _GlassContainer(
                  padding: metrics.barPadding,
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: onBack,
                        visualDensity: VisualDensity.compact,
                        constraints: metrics.iconConstraints,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      SizedBox(width: metrics.compactGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              mediaTitle,
                              maxLines: metrics.titleMaxLines,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontSize: metrics.titleSize),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Center(
                child: RepaintBoundary(
                  child: _GlassContainer(
                    borderRadius: BorderRadius.circular(metrics.centerRadius),
                    padding: metrics.centerPadding,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          onPressed: () {
                            onSeekBack();
                          },
                          visualDensity: VisualDensity.compact,
                          constraints: metrics.iconConstraints,
                          iconSize: metrics.seekIconSize,
                          icon: const Icon(Icons.replay_10_rounded),
                        ),
                        SizedBox(width: metrics.compactGap),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const CircleBorder(),
                            padding: EdgeInsets.all(metrics.playButtonPadding),
                            backgroundColor: AppColors.buttonsPurple,
                            minimumSize: Size.square(metrics.playButtonSize),
                          ),
                          onPressed: () {
                            onPlayPause();
                          },
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: metrics.playIconSize,
                          ),
                        ),
                        SizedBox(width: metrics.compactGap),
                        IconButton(
                          onPressed: () {
                            onSeekForward();
                          },
                          visualDensity: VisualDensity.compact,
                          constraints: metrics.iconConstraints,
                          iconSize: metrics.seekIconSize,
                          icon: const Icon(Icons.forward_10_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: metrics.edgeInset,
                right: metrics.edgeInset,
                bottom: metrics.edgeInset,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (showNextEpisode)
                      Padding(
                        padding: EdgeInsets.only(bottom: metrics.compactGap),
                        child: RepaintBoundary(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _GlassActionButton(
                              icon: Icons.skip_next_rounded,
                              label: nextEpisodeLabel == null
                                  ? 'Next Episode'
                                  : 'Next Episode - $nextEpisodeLabel',
                              onPressed: onNextEpisode,
                            ),
                          ),
                        ),
                      ),
                    _GlassContainer(
                      padding: metrics.barPadding,
                      child: Column(
                        children: <Widget>[
                          _SeekBar(
                            position: position,
                            duration: duration,
                            buffered: buffered,
                            onSeek: onSeek,
                          ),
                          SizedBox(height: metrics.compactGap),
                          Row(
                            children: <Widget>[
                              Text(
                                _formatDuration(position),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(fontSize: metrics.timeTextSize),
                              ),
                              SizedBox(width: metrics.compactGap),
                              Text(
                                '/ ${_formatDuration(duration)}',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(fontSize: metrics.timeTextSize),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () {
                                  unawaited(onOpenBrightness());
                                },
                                visualDensity: VisualDensity.compact,
                                constraints: metrics.iconConstraints,
                                icon: const Icon(Icons.brightness_6_rounded),
                                tooltip: 'Brightness',
                              ),
                              IconButton(
                                onPressed: () {
                                  unawaited(onOpenVolume());
                                },
                                visualDensity: VisualDensity.compact,
                                constraints: metrics.iconConstraints,
                                icon: const Icon(Icons.volume_up_rounded),
                                tooltip: 'Volume',
                              ),
                              IconButton(
                                onPressed: () {
                                  onOpenSettings();
                                },
                                visualDensity: VisualDensity.compact,
                                constraints: metrics.iconConstraints,
                                icon: const Icon(Icons.settings_outlined),
                                tooltip: 'Settings',
                              ),
                              IconButton(
                                onPressed: () {
                                  onToggleAutoRotate();
                                },
                                visualDensity: VisualDensity.compact,
                                constraints: metrics.iconConstraints,
                                icon: Icon(
                                  autoRotate
                                      ? Icons.screen_rotation_rounded
                                      : Icons.screen_lock_rotation_rounded,
                                ),
                                tooltip: autoRotate
                                    ? 'Lock landscape'
                                    : 'Auto-rotate',
                              ),
                              IconButton(
                                onPressed: onLock,
                                visualDensity: VisualDensity.compact,
                                constraints: metrics.iconConstraints,
                                icon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                tooltip: 'Lock controls',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration value) {
    final int totalSeconds = value.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class PlayerInfoPill extends StatelessWidget {
  const PlayerInfoPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return _GlassContainer(
      borderRadius: BorderRadius.circular(AppSpacing.x10),
      child: Text(label, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final Future<void> Function(double fraction) onSeek;

  @override
  Widget build(BuildContext context) {
    final _PlayerControlMetrics metrics = _PlayerControlMetrics.of(context);
    final double totalMs = duration.inMilliseconds.toDouble();
    final double bufferedFraction = totalMs <= 0
        ? 0
        : (buffered.inMilliseconds / totalMs).clamp(0, 1).toDouble();
    final double playedFraction = totalMs <= 0
        ? 0
        : (position.inMilliseconds / totalMs).clamp(0, 1).toDouble();

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (TapDownDetails details) {
              final double fraction =
                  (details.localPosition.dx / constraints.maxWidth)
                      .clamp(0, 1)
                      .toDouble();
              onSeek(fraction);
            },
            onHorizontalDragUpdate: (DragUpdateDetails details) {
              final double fraction =
                  (details.localPosition.dx / constraints.maxWidth)
                      .clamp(0, 1)
                      .toDouble();
              onSeek(fraction);
            },
            child: SizedBox(
              height: metrics.seekBarHeight,
              child: Center(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Container(
                      height: metrics.seekTrackHeight,
                      decoration: BoxDecoration(
                        color: AppColors.progressBackground.withValues(
                          alpha: 0.35,
                        ),
                        borderRadius: BorderRadius.circular(metrics.trackRadius),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: bufferedFraction,
                      child: Container(
                        height: metrics.seekTrackHeight,
                        decoration: BoxDecoration(
                          color: AppColors.semanticSilverC400,
                          borderRadius: BorderRadius.circular(metrics.trackRadius),
                        ),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: playedFraction,
                      child: Container(
                        height: metrics.seekTrackHeight,
                        decoration: BoxDecoration(
                          color: AppColors.progressFilled,
                          borderRadius: BorderRadius.circular(metrics.trackRadius),
                        ),
                      ),
                    ),
                    Positioned(
                      left:
                          (constraints.maxWidth * playedFraction) -
                          metrics.thumbRadius,
                      top: -metrics.thumbRadius,
                      child: Container(
                        width: metrics.thumbSize,
                        height: metrics.thumbSize,
                        decoration: const BoxDecoration(
                          color: AppColors.progressFilled,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  const _GlassActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    final _PlayerControlMetrics metrics = _PlayerControlMetrics.of(context);
    return _GlassContainer(
      borderRadius: BorderRadius.circular(metrics.pillRadius),
      child: TextButton.icon(
        onPressed: () {
          onPressed();
        },
        icon: Icon(icon, color: AppColors.typeEmphasis),
        label: Text(label),
      ),
    );
  }
}

class _GlassContainer extends StatelessWidget {
  const _GlassContainer({
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.x4,
      vertical: AppSpacing.x3,
    ),
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final BorderRadius effectiveRadius =
        borderRadius ?? BorderRadius.circular(AppSpacing.x4);

    // [BackdropFilter] re-blurs every frame in its parent layer. Wrapping in
    // [RepaintBoundary] turns the glass into its own layer so the blurred
    // content is cached and only repainted when this glass's children change
    // — large win when controls are visible while the video frame ticks.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: BackdropFilter(
          filter:
              ImageFilter.blur(sigmaX: AppSpacing.x5, sigmaY: AppSpacing.x5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.videoContextBackground.withValues(alpha: 0.62),
              borderRadius: effectiveRadius,
              border: Border.all(
                color: AppColors.videoContextBorder.withValues(alpha: 0.7),
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class _PlayerControlMetrics {
  const _PlayerControlMetrics({
    required this.edgeInset,
    required this.compactGap,
    required this.barPadding,
    required this.centerPadding,
    required this.iconConstraints,
    required this.seekIconSize,
    required this.playIconSize,
    required this.playButtonPadding,
    required this.playButtonSize,
    required this.centerRadius,
    required this.titleSize,
    required this.titleMaxLines,
    required this.timeTextSize,
    required this.seekBarHeight,
    required this.seekTrackHeight,
    required this.trackRadius,
    required this.thumbSize,
    required this.thumbRadius,
    required this.pillRadius,
  });

  final double edgeInset;
  final double compactGap;
  final EdgeInsetsGeometry barPadding;
  final EdgeInsetsGeometry centerPadding;
  final BoxConstraints iconConstraints;
  final double seekIconSize;
  final double playIconSize;
  final double playButtonPadding;
  final double playButtonSize;
  final double centerRadius;
  final double titleSize;
  final int titleMaxLines;
  final double timeTextSize;
  final double seekBarHeight;
  final double seekTrackHeight;
  final double trackRadius;
  final double thumbSize;
  final double thumbRadius;
  final double pillRadius;

  static _PlayerControlMetrics of(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final HandsetDensity density = handsetDensity(context);
    final bool small = density == HandsetDensity.small;
    final bool regular = density == HandsetDensity.regular;
    final bool shortLandscape = size.height < 420;

    return _PlayerControlMetrics(
      edgeInset: small ? AppSpacing.x2 : AppSpacing.x4,
      compactGap: small ? AppSpacing.x1 : AppSpacing.x2,
      barPadding: EdgeInsets.symmetric(
        horizontal: small ? AppSpacing.x3 : AppSpacing.x4,
        vertical: small ? AppSpacing.x2 : AppSpacing.x3,
      ),
      centerPadding: EdgeInsets.symmetric(
        horizontal: small ? AppSpacing.x3 : AppSpacing.x4,
        vertical: small ? AppSpacing.x2 : AppSpacing.x3,
      ),
      iconConstraints: BoxConstraints.tightFor(
        width: small ? 40 : 44,
        height: small ? 40 : 44,
      ),
      seekIconSize: small ? AppSpacing.x6 : AppSpacing.x8,
      playIconSize: small ? AppSpacing.x8 : AppSpacing.x10,
      playButtonPadding: small ? AppSpacing.x3 : AppSpacing.x4,
      playButtonSize: small ? 44 : 52,
      centerRadius: small ? AppSpacing.x12 : AppSpacing.x16,
      titleSize: small ? 16 : 20,
      titleMaxLines: shortLandscape ? 1 : 2,
      timeTextSize: small ? 11 : 13,
      seekBarHeight: small ? AppSpacing.x8 : AppSpacing.x12,
      seekTrackHeight: small ? 3 : AppSpacing.x1,
      trackRadius: small ? AppSpacing.x1 : AppSpacing.x2,
      thumbSize: small ? AppSpacing.x3 : AppSpacing.x4,
      thumbRadius: small ? 6 : AppSpacing.x2,
      pillRadius: regular ? AppSpacing.x8 : AppSpacing.x10,
    );
  }
}
