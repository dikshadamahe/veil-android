import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/live_channel.dart';

/// Grid tile for a single Live TV channel.
///
/// Shows the channel logo, a category chip, the channel name, and — when EPG
/// data is available — a `● LIVE` badge with the current program title.
class ChannelCard extends StatelessWidget {
  const ChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.currentProgram,
  });

  final LiveChannel channel;
  final VoidCallback onTap;

  /// Current EPG program title; null when no EPG data is available.
  final String? currentProgram;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Material(
        color: AppColors.glassSheet,
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.x4),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.x4),
                          child: _ChannelLogo(channel: channel),
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.x2,
                        bottom: AppSpacing.x2,
                        child: _CategoryChip(category: channel.cat),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.x3,
                    AppSpacing.x2,
                    AppSpacing.x3,
                    AppSpacing.x3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.typeEmphasis,
                            ),
                      ),
                      if (currentProgram != null &&
                          currentProgram!.isNotEmpty) ...<Widget>[
                        const SizedBox(height: AppSpacing.x1),
                        Row(
                          children: <Widget>[
                            Container(
                              width: AppSpacing.x2,
                              height: AppSpacing.x2,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.semanticRedC200,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.x1),
                            Expanded(
                              child: Text(
                                currentProgram!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: AppColors.typeSecondary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
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

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel});

  final LiveChannel channel;

  @override
  Widget build(BuildContext context) {
    if (channel.logo.isEmpty) {
      return _LogoFallback(channel: channel);
    }
    return CachedNetworkImage(
      imageUrl: channel.logo,
      fit: BoxFit.contain,
      placeholder: (BuildContext context, String url) =>
          const SizedBox.shrink(),
      errorWidget: (BuildContext context, String url, Object error) =>
          _LogoFallback(channel: channel),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback({required this.channel});

  final LiveChannel channel;

  @override
  Widget build(BuildContext context) {
    final String initial =
        channel.name.isNotEmpty ? channel.name.characters.first.toUpperCase() : '?';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(
            Icons.live_tv_rounded,
            color: AppColors.typeSecondary,
            size: AppSpacing.x10,
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            initial,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.typeEmphasis,
                ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    if (category.isEmpty) {
      return const SizedBox.shrink();
    }
    final Color color = _categoryColor(category);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.blackC50.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        child: Text(
          category,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }

  static Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'sports':
        return AppColors.purpleC200;
      case 'news':
        return AppColors.semanticRedC200;
      case 'entertainment':
        return AppColors.semanticYellowC200;
      case 'kids':
        return AppColors.semanticGreenC100;
      case 'movies':
        return AppColors.blueC200;
      case 'music':
        return AppColors.semanticRoseC100;
      case 'docs':
        return AppColors.semanticSilverC300;
      default:
        return AppColors.typeSecondary;
    }
  }
}
