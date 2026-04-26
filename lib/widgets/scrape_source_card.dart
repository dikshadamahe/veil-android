import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:pstream_android/config/app_theme.dart';

enum ScrapeStatus { waiting, pending, success, failure, notfound }

/// A single source row used by [ScrapingScreen]. Visually flat (no card
/// chrome) to match the web `ScrapingPart.tsx` layout: status circle on
/// the left, provider name + optional subline on the right.
class ScrapeSourceCard extends StatelessWidget {
  const ScrapeSourceCard({
    super.key,
    required this.sourceName,
    required this.status,
    this.embeds = const <ScrapeEmbedItem>[],
    this.subline,
  });

  final String sourceName;
  final ScrapeStatus status;
  final List<ScrapeEmbedItem> embeds;

  /// Shown under [sourceName] when set (e.g. "Checking for videos…" while pending).
  final String? subline;

  static const double estimatedHeight = AppSpacing.x12 + AppSpacing.x6;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = status == ScrapeStatus.pending;
    final bool dimmed =
        status == ScrapeStatus.waiting && embeds.isEmpty && subline == null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.x2,
        vertical: AppSpacing.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              StatusCircle(status: status),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      sourceName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: dimmed
                            ? AppColors.typeSecondary
                            : AppColors.typeEmphasis,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (subline != null && subline!.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: AppSpacing.x1),
                      Text(
                        subline!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.typeSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (embeds.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.x2),
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.x10),
              child: Column(
                children: List<Widget>.generate(embeds.length, (int index) {
                  final ScrapeEmbedItem embed = embeds[index];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index == embeds.length - 1
                          ? AppSpacing.x0
                          : AppSpacing.x2,
                    ),
                    child: Row(
                      children: <Widget>[
                        StatusCircle(
                          status: embed.status,
                          size: AppSpacing.x4,
                          strokeWidth: 1.4,
                        ),
                        const SizedBox(width: AppSpacing.x2),
                        Expanded(
                          child: Text(
                            embed.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.typeText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ScrapeEmbedItem {
  const ScrapeEmbedItem({required this.name, required this.status});

  final String name;
  final ScrapeStatus status;
}

/// Web-parity status badge: hollow purple ring while waiting, animated
/// rotating arc while pending, filled purple + check on success, filled
/// red + cross on failure / notfound.
class StatusCircle extends StatelessWidget {
  const StatusCircle({
    super.key,
    required this.status,
    this.size = AppSpacing.x6,
    this.strokeWidth = 2,
  });

  final ScrapeStatus status;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final Widget body = SizedBox.square(
      dimension: size,
      child: switch (status) {
        ScrapeStatus.waiting => _RingCircle(
            size: size,
            strokeWidth: strokeWidth,
            color: AppColors.dropdownBorder,
          ),
        ScrapeStatus.pending => _PendingCircle(
            size: size,
            strokeWidth: strokeWidth,
          ),
        ScrapeStatus.success => _FilledCircle(
            size: size,
            color: AppColors.videoScrapingSuccess,
            child: Icon(
              Icons.check_rounded,
              size: size * 0.66,
              color: AppColors.typeEmphasis,
            ),
          ),
        ScrapeStatus.failure || ScrapeStatus.notfound => _FilledCircle(
            size: size,
            color: AppColors.videoScrapingError,
            child: Icon(
              Icons.close_rounded,
              size: size * 0.66,
              color: AppColors.typeEmphasis,
            ),
          ),
      },
    );

    return RepaintBoundary(child: body);
  }
}

class _RingCircle extends StatelessWidget {
  const _RingCircle({
    required this.size,
    required this.strokeWidth,
    required this.color,
  });

  final double size;
  final double strokeWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: strokeWidth),
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

class _FilledCircle extends StatelessWidget {
  const _FilledCircle({
    required this.size,
    required this.color,
    required this.child,
  });

  final double size;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      child: SizedBox.square(
        dimension: size,
        child: Center(child: child),
      ),
    );
  }
}

/// Active "checking" badge: solid purple disc + a thin lighter ring that
/// rotates continuously, mirroring the web `StatusCircle.tsx` pulse.
class _PendingCircle extends StatelessWidget {
  const _PendingCircle({required this.size, required this.strokeWidth});

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.videoScrapingLoading,
          ),
          child: SizedBox.square(dimension: size),
        ),
        SizedBox.square(
          dimension: size + strokeWidth * 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: <Color>[
                  AppColors.purpleC50.withValues(alpha: 0.0),
                  AppColors.purpleC50.withValues(alpha: 0.85),
                  AppColors.purpleC50.withValues(alpha: 0.0),
                ],
                stops: const <double>[0, 0.6, 1],
              ),
            ),
          ),
        )
            .animate(
              onPlay: (AnimationController controller) => controller.repeat(),
            )
            .rotate(duration: 1100.ms, curve: Curves.linear),
      ],
    );
  }
}
