import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/providers/storage_provider.dart';
import 'package:pstream_android/storage/local_storage.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<MediaStat> stats = <MediaStat>[
      MediaStat(
        label: 'Continue watching',
        value: ref.watch(continueWatchingProvider).length,
      ),
      MediaStat(label: 'Bookmarks', value: ref.watch(bookmarksProvider).length),
      MediaStat(label: 'History', value: ref.watch(historyProvider).length),
    ];

    final double horizontal = switch (windowClass(context)) {
      WindowClass.compact => AppSpacing.x4,
      WindowClass.medium => AppSpacing.x5,
      WindowClass.expanded => AppSpacing.x6,
    };

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            AppSpacing.x4,
            horizontal,
            AppSpacing.x6,
          ),
          children: <Widget>[
            _SettingsProfileHeader(
              statsLine:
                  '${stats[0].value} in progress · ${stats[1].value} saved · ${stats[2].value} in history',
            ),
            const SizedBox(height: AppSpacing.x5),
            _SettingsHeroCard(stats: stats),
            const SizedBox(height: AppSpacing.x4),
            _SettingsSection(
              title: 'Library',
              subtitle: 'Manage local watch data stored on this device.',
              child: Column(
                children: <Widget>[
                  _SettingsNavTile(
                    icon: Icons.video_library_outlined,
                    title: 'Watch history',
                    subtitle: 'Open your full watch history grid.',
                    onTap: () => context.push('/history'),
                  ),
                  const SizedBox(height: AppSpacing.x3),
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
                        await ref
                            .read(storageControllerProvider)
                            .clearHistory();
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
                            const SnackBar(content: Text('Bookmarks cleared')),
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
              title: 'Playback',
              subtitle:
                  'Defaults applied when starting a new stream. Saved to this device.',
              child: Column(
                children: <Widget>[
                  _QualityCapTile(
                    value: ref.watch(qualityCapPrefProvider),
                    onPick: (String picked) async {
                      await ref
                          .read(storageControllerProvider)
                          .setQualityCap(picked);
                    },
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  _SubtitleDefaultTile(
                    value: ref.watch(subtitlesDefaultOnPrefProvider),
                    onChanged: (bool next) async {
                      await ref
                          .read(storageControllerProvider)
                          .setSubtitlesDefaultOn(next);
                    },
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  _DoubleTapSeekTile(
                    value: ref.watch(doubleTapSeekSecsPrefProvider),
                    onPick: (int picked) async {
                      await ref
                          .read(storageControllerProvider)
                          .setDoubleTapSeekSecs(picked);
                    },
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  _SettingsNavTile(
                    icon: Icons.insights_rounded,
                    title: 'Watch statistics',
                    subtitle: 'Finished titles, in-progress, total time.',
                    onTap: () => context.push('/watch-stats'),
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

class _SettingsProfileHeader extends StatelessWidget {
  const _SettingsProfileHeader({required this.statsLine});

  final String statsLine;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 26,
          backgroundColor: AppColors.blackC150,
          child: Icon(
            Icons.person_rounded,
            size: AppSpacing.x8,
            color: AppColors.typeLogo,
          ),
        ),
        const SizedBox(width: AppSpacing.x4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.x2),
              Text(statsLine, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
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
              'This device',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.x2),
            Text(
              'Playback preferences and library summaries below are scoped to local storage on this phone.',
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
              Text(stat.label, style: Theme.of(context).textTheme.labelMedium),
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppColors.typeLogo,
                fontWeight: FontWeight.w700,
              ),
            ),
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

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blackC150,
      borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x3,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, color: AppColors.typeLink),
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
              Icon(Icons.chevron_right_rounded, color: AppColors.typeSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the saved [LocalStorage.getQualityCap] value and opens a
/// radio-list bottom sheet so the user can pick a new cap. Persists via
/// [StorageController.setQualityCap].
class _QualityCapTile extends StatelessWidget {
  const _QualityCapTile({required this.value, required this.onPick});

  final String value;
  final ValueChanged<String> onPick;

  static String _label(String value) {
    return switch (value) {
      LocalStorage.qualityCap720 => '720p cap',
      LocalStorage.qualityCap1080 => '1080p cap',
      _ => 'Auto',
    };
  }

  Future<void> _open(BuildContext context) async {
    final String? picked = await showModalBottomSheet<String>(
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
                  'Default stream quality',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  'Picks the highest available quality at or below this cap when a stream first opens.',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.x3),
                // Flutter 3.32+ deprecates per-tile `groupValue` / `onChanged`
                // on [RadioListTile]; the group is now driven by an ancestor
                // [RadioGroup] that owns the selected value and handler.
                RadioGroup<String>(
                  groupValue: value,
                  onChanged: (String? next) {
                    if (next != null) {
                      Navigator.of(sheetContext).pop(next);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final ({String id, String label, String hint}) opt
                          in const <({String id, String label, String hint})>[
                        (
                          id: LocalStorage.qualityCapAuto,
                          label: 'Auto',
                          hint: 'Use the source default',
                        ),
                        (
                          id: LocalStorage.qualityCap720,
                          label: '720p cap',
                          hint: 'Save data on cellular',
                        ),
                        (
                          id: LocalStorage.qualityCap1080,
                          label: '1080p cap',
                          hint: 'Best quality on Wi-Fi',
                        ),
                      ])
                        RadioListTile<String>(
                          value: opt.id,
                          title: Text(opt.label),
                          subtitle: Text(opt.hint),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null && picked != value) {
      onPick(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blackC150,
      borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x4,
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.high_quality_rounded,
                color: AppColors.typeLink,
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Default stream quality',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      _label(value),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.typeLink,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
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

/// Picker tile for the player double-tap skip interval. Reads/writes via
/// [storageControllerProvider]. Mirrors [_QualityCapTile] styling so the
/// Playback section stays consistent.
class _DoubleTapSeekTile extends StatelessWidget {
  const _DoubleTapSeekTile({required this.value, required this.onPick});

  final int value;
  final ValueChanged<int> onPick;

  Future<void> _open(BuildContext context) async {
    final int? picked = await showModalBottomSheet<int>(
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
                  'Double-tap seek',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.x1),
                Text(
                  'Distance to skip when you double-tap the player. Tap left side seeks back, right side seeks forward.',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.x3),
                RadioGroup<int>(
                  groupValue: value,
                  onChanged: (int? next) {
                    if (next != null) {
                      Navigator.of(sheetContext).pop(next);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (final int secs
                          in LocalStorage.doubleTapSeekChoicesSecs)
                        RadioListTile<int>(
                          value: secs,
                          title: Text('$secs seconds'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null && picked != value) {
      onPick(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blackC150,
      borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x4,
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.touch_app_rounded,
                color: AppColors.typeLink,
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Double-tap seek',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      '$value seconds per double-tap',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.typeLink,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
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

/// Inline switch row: persist whether subtitles auto-enable when a stream
/// has caption tracks. Reads/writes via [storageControllerProvider].
class _SubtitleDefaultTile extends StatelessWidget {
  const _SubtitleDefaultTile({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.blackC150,
      borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.x4 + AppSpacing.x1),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.x4,
            vertical: AppSpacing.x3,
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.closed_caption_rounded,
                color: AppColors.typeLink,
              ),
              const SizedBox(width: AppSpacing.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Subtitles on by default',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.x1),
                    Text(
                      'Auto-enable subtitles when the stream has caption tracks.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                // Default Material 3 styling renders a purple thumb in the
                // off position on dark backgrounds. Pin off-state colors so
                // off looks neutral grey, on looks purple.
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
          ),
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
    final Color accentColor = destructive
        ? AppColors.typeDanger
        : AppColors.typeLink;

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
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: accentColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
