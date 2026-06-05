import 'dart:ui';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/breakpoints.dart';

/// Shell navigation: **always** bottom dock (no side rail), inspired by streaming
/// app layouts — placement only; colors follow Veil dark + purple tokens.
class AdaptiveNav extends StatelessWidget {
  const AdaptiveNav({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.child,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;

  static const List<_AdaptiveNavDestination> _destinations = [
    _AdaptiveNavDestination(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _AdaptiveNavDestination(label: 'Search', icon: Icons.search_rounded),
    _AdaptiveNavDestination(
      label: 'My list',
      icon: Icons.bookmark_outline_rounded,
      selectedIcon: Icons.bookmark_rounded,
    ),
    _AdaptiveNavDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final WindowClass layoutClass = windowClass(context);
    final double dockHorizontal = switch (layoutClass) {
      WindowClass.compact => AppSpacing.x4,
      WindowClass.medium => AppSpacing.x8,
      WindowClass.expanded => AppSpacing.x10,
    };

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: child,
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            dockHorizontal,
            AppSpacing.x2,
            dockHorizontal,
            AppSpacing.x3,
          ),
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.x8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.glassSheet,
                    borderRadius: BorderRadius.circular(AppSpacing.x8),
                    border: Border.all(
                      color: AppColors.glassBorder,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.blackC50.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: NavigationBar(
                    height: 64,
                    backgroundColor: AppColors.transparent,
                    surfaceTintColor: AppColors.transparent,
                    indicatorColor: AppColors.purpleC600.withValues(alpha: 0.35),
                    selectedIndex: currentIndex,
                    onDestinationSelected: onDestinationSelected,
                    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    destinations: _destinations.asMap().entries.map(
                      (MapEntry<int, _AdaptiveNavDestination> e) {
                        final bool selected = currentIndex == e.key;
                        return NavigationDestination(
                          icon: Icon(e.value.icon),
                          selectedIcon: Icon(e.value.resolvedIcon(selected)),
                          label: e.value.label,
                        );
                      },
                    ).toList(growable: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdaptiveNavDestination {
  const _AdaptiveNavDestination({
    required this.label,
    required this.icon,
    this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData? selectedIcon;

  IconData resolvedIcon(bool selected) {
    if (selected && selectedIcon != null) {
      return selectedIcon!;
    }
    return icon;
  }
}
