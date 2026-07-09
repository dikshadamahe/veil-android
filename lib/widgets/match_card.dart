import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/models/sports_match.dart';

/// Grid tile for a single sports match.
///
/// Shows the event poster (or a team-badge fallback), a sport chip, a `● LIVE`
/// badge when the match is live, the title, and the kickoff time / status.
class MatchCard extends StatelessWidget {
  const MatchCard({
    super.key,
    required this.match,
    required this.isLive,
    required this.onTap,
  });

  final SportsMatch match;
  final bool isLive;
  final VoidCallback onTap;

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
                    fit: StackFit.expand,
                    children: <Widget>[
                      _MatchArtwork(match: match),
                      Positioned(
                        left: AppSpacing.x2,
                        top: AppSpacing.x2,
                        child: isLive
                            ? const _LiveBadge()
                            : _SportChip(category: match.category),
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
                        match.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.typeEmphasis,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.x1),
                      _StatusLine(match: match, isLive: isLive),
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

class _MatchArtwork extends StatelessWidget {
  const _MatchArtwork({required this.match});

  final SportsMatch match;

  @override
  Widget build(BuildContext context) {
    final String? poster = match.posterUrl;
    if (poster == null) {
      return _TeamsFallback(match: match);
    }
    return CachedNetworkImage(
      imageUrl: poster,
      fit: BoxFit.cover,
      placeholder: (BuildContext context, String url) =>
          const ColoredBox(color: AppColors.mediaCardHoverBackground),
      errorWidget: (BuildContext context, String url, Object error) =>
          _TeamsFallback(match: match),
    );
  }
}

class _TeamsFallback extends StatelessWidget {
  const _TeamsFallback({required this.match});

  final SportsMatch match;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.blackC125, AppColors.purpleC800],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Flexible(child: _TeamBadge(team: match.home)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
              child: Text(
                'vs',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.typeSecondary,
                    ),
              ),
            ),
            Flexible(child: _TeamBadge(team: match.away)),
          ],
        ),
      ),
    );
  }
}

class _TeamBadge extends StatelessWidget {
  const _TeamBadge({required this.team});

  final MatchTeam? team;

  @override
  Widget build(BuildContext context) {
    final MatchTeam? t = team;
    final String? badge = t?.badgeUrl;
    final Widget image = (badge == null)
        ? const Icon(
            Icons.sports_soccer_rounded,
            color: AppColors.typeSecondary,
            size: AppSpacing.x8,
          )
        : CachedNetworkImage(
            imageUrl: badge,
            width: AppSpacing.x10,
            height: AppSpacing.x10,
            fit: BoxFit.contain,
            placeholder: (BuildContext context, String url) =>
                const SizedBox(width: AppSpacing.x10, height: AppSpacing.x10),
            errorWidget: (BuildContext context, String url, Object error) =>
                const Icon(
              Icons.shield_outlined,
              color: AppColors.typeSecondary,
              size: AppSpacing.x8,
            ),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        image,
        if (t != null && t.name.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.x1),
          Text(
            t.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.typeText,
                ),
          ),
        ],
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.match, required this.isLive});

  final SportsMatch match;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    if (isLive) {
      return Row(
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
          Text(
            'LIVE NOW',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.semanticRedC200,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      );
    }

    final DateTime? date = match.date;
    final String text = date != null
        ? _formatKickoff(date.toLocal())
        : (match.hasStarted ? 'In progress' : 'Scheduled');
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context)
          .textTheme
          .labelSmall
          ?.copyWith(color: AppColors.typeSecondary),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.semanticRedC200,
        borderRadius: BorderRadius.circular(AppSpacing.x4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: AppSpacing.x2,
              height: AppSpacing.x2,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.white,
              ),
            ),
            const SizedBox(width: AppSpacing.x1),
            Text(
              'LIVE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SportChip extends StatelessWidget {
  const _SportChip({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    if (category.isEmpty) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.blackC50.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: AppSpacing.x1,
        ),
        child: Text(
          _prettySport(category),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.typeText,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }
}

/// Turns a sport id (`american-football`) into a display label
/// (`American Football`).
String _prettySport(String id) {
  return id
      .split('-')
      .where((String p) => p.isNotEmpty)
      .map((String p) => '${p[0].toUpperCase()}${p.substring(1)}')
      .join(' ');
}

const List<String> _monthAbbr = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatKickoff(DateTime dt) {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime day = DateTime(dt.year, dt.month, dt.day);
  final int diffDays = day.difference(today).inDays;
  final String hhmm =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  if (diffDays == 0) {
    return 'Today $hhmm';
  }
  if (diffDays == 1) {
    return 'Tomorrow $hhmm';
  }
  if (diffDays == -1) {
    return 'Yesterday $hhmm';
  }
  return '${dt.day} ${_monthAbbr[dt.month - 1]} $hhmm';
}
