import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../config/breakpoints.dart';

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
    _AdaptiveNavDestination(label: 'Home', icon: Icons.home_outlined),
    _AdaptiveNavDestination(label: 'Search', icon: Icons.search_rounded),
    _AdaptiveNavDestination(label: 'History', icon: Icons.history_rounded),
    _AdaptiveNavDestination(label: 'Settings', icon: Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final layoutClass = windowClass(context);

    if (layoutClass == WindowClass.compact) {
      return Scaffold(
        backgroundColor: AppColors.backgroundMain,
        body: child,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onDestinationSelected,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.backgroundSecondary,
          selectedItemColor: AppColors.typeEmphasis,
          unselectedItemColor: AppColors.typeSecondary,
          items: _destinations
              .map(
                (destination) => BottomNavigationBarItem(
                  icon: Icon(destination.icon, size: AppSpacing.x6),
                  label: destination.label,
                ),
              )
              .toList(growable: false),
        ),
      );
    }

    final isExpanded = layoutClass == WindowClass.expanded;
    final railIconSize = isExpanded ? AppSpacing.x8 : AppSpacing.x6;

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: Row(
        children: [
          SafeArea(
            child: NavigationRailTheme(
              data: NavigationRailThemeData(
                minWidth: AppSpacing.x16,
                groupAlignment: -1,
                elevation: 0,
              ),
              child: NavigationRail(
                selectedIndex: currentIndex,
                onDestinationSelected: onDestinationSelected,
                extended: false,
                labelType: NavigationRailLabelType.all,
                backgroundColor: AppColors.backgroundSecondary,
                indicatorColor: AppColors.buttonsToggle,
                leading: const SizedBox(height: AppSpacing.x2),
                selectedIconTheme: IconThemeData(
                  color: AppColors.typeEmphasis,
                  size: railIconSize,
                ),
                unselectedIconTheme: IconThemeData(
                  color: AppColors.typeSecondary,
                  size: railIconSize,
                ),
                selectedLabelTextStyle: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(
                      color: AppColors.typeEmphasis,
                      fontWeight: FontWeight.w600,
                    ),
                unselectedLabelTextStyle: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: AppColors.typeSecondary),
                destinations: _destinations
                    .map(
                      (destination) => NavigationRailDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.icon),
                        label: Text(destination.label),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
          const SizedBox(
            width: AppSpacing.x1,
            child: ColoredBox(color: AppColors.utilsDivider),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _AdaptiveNavDestination {
  const _AdaptiveNavDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
