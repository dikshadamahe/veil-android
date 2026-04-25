import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/providers/storage_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const String _releasesUrl =
      'https://github.com/dikshadamahe/veil-android/releases';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<MediaStat> stats = <MediaStat>[
      MediaStat(
        label: 'Continue watching',
        value: ref.watch(continueWatchingProvider).length,
      ),
      MediaStat(
        label: 'Bookmarks',
        value: ref.watch(bookmarksProvider).length,
      ),
      MediaStat(
        label: 'History',
        value: ref.watch(historyProvider).length,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x4,
            AppSpacing.x4,
            AppSpacing.x6,
          ),
          children: <Widget>[
            Row(
              children: <Widget>[
                _RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: AppSpacing.x3),
                Expanded(
                  child: Text(
                    'Settings',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.x4),
            _SettingsHeroCard(stats: stats),
            const SizedBox(height: AppSpacing.x4),
            _SettingsSection(
              title: 'Library',
              subtitle: 'Manage local watch data stored on this device.',
              child: Column(
                children: <Widget>[
                  _SettingsActionTile(
                    icon: Icons.history_rounded,
                    title: 'Clear watch history',
                    subtitle: 'Removes history entries and saved progress.',
                    actionLabel: 'Clear',
                    destructive: true,
                    onTap: () => _confirmAndRun(
                      context,
                      title: 'Clear watch history?',
                      message:
                          'This will remove watch history and resume progress for all titles on this device.',
                      onConfirm: () async {
                        await ref.read(storageControllerProvider).clearHistory();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Watch history cleared'),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  _SettingsActionTile(
                    icon: Icons.bookmark_remove_rounded,
                    title: 'Clear bookmarks',
                    subtitle: 'Removes all saved bookmarks from this device.',
                    actionLabel: 'Clear',
                    destructive: true,
                    onTap: () => _confirmAndRun(
                      context,
                      title: 'Clear bookmarks?',
                      message:
                          'This will remove all bookmarked titles from local storage.',
                      onConfirm: () async {
                        await ref
                            .read(storageControllerProvider)
                            .clearBookmarks();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Bookmarks cleared'),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x4),
            _SettingsSection(
              title: 'Environment',
              subtitle: 'Build and release information.',
              child: Column(
                children: <Widget>[
                  const _SettingsInfoTile(
                    title: 'App version',
                    value: '1.0.0+1',
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  const _SettingsInfoTile(
                    title: 'GitHub releases',
                    value: _releasesUrl,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndRun(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    final bool? shouldContinue = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (shouldContinue == true) {
      await onConfirm();
    }
  }
}

class MediaStat {
  const MediaStat({required this.label, required this.value});

  final String label;
  final int value;
}

class _SettingsHeroCard extends StatelessWidget {
  const _SettingsHeroCard({required this.stats});

  final List<MediaStat> stats;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.x5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            AppColors.blackC125,
            AppColors.blackC100,
            AppColors.purpleC900.withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(color: AppColors.settingsCardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Device and playback preferences',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'A cleaner settings surface for local data, runtime info, and playback-related housekeeping.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.x4),
            Wrap(
              spacing: AppSpacing.x3,
              runSpacing: AppSpacing.x3,
              children: stats
                  .map((MediaStat stat) => _SettingsStatCard(stat: stat))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsStatCard extends StatelessWidget {
  const _SettingsStatCard({required this.stat});

  final MediaStat stat;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.settingsCardBackground,
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          border: Border.all(color: AppColors.dropdownBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${stat.value}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: AppColors.typeEmphasis,
                    ),
              ),
              const SizedBox(height: AppSpacing.x1),
              Text(
                stat.label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.settingsCardBackground,
        borderRadius: BorderRadius.circular(AppSpacing.x5),
        border: Border.all(color: AppColors.settingsCardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.x1),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.x4),
            child,
          ],
        ),
      ),
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color accentColor =
        destructive ? AppColors.typeDanger : AppColors.typeLink;

    return Material(
      color: AppColors.blackC100,
      borderRadius: BorderRadius.circular(AppSpacing.x4),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.x4),
          child: Row(
            children: <Widget>[
              Container(
                width: AppSpacing.x12,
                height: AppSpacing.x12,
                decoration: BoxDecoration(
                  color: AppColors.blackC150,
                  borderRadius: BorderRadius.circular(AppSpacing.x4),
                ),
                child: Icon(icon, color: accentColor),
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Text(
                actionLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: accentColor,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsInfoTile extends StatelessWidget {
  const _SettingsInfoTile({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.blackC100,
        borderRadius: BorderRadius.circular(AppSpacing.x4),
        border: Border.all(color: AppColors.dropdownBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.x2),
            SelectableText(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.typeText,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blackC100,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}
