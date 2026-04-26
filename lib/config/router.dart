import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/screens/detail_screen.dart';
import 'package:pstream_android/screens/history_screen.dart';
import 'package:pstream_android/screens/home_screen.dart';
import 'package:pstream_android/screens/my_list_screen.dart';
import 'package:pstream_android/screens/player_screen.dart';
import 'package:pstream_android/screens/scraping_screen.dart';
import 'package:pstream_android/screens/search_screen.dart';
import 'package:pstream_android/screens/settings_screen.dart';
import 'package:pstream_android/screens/splash_screen.dart';
import 'package:pstream_android/screens/watch_stats_screen.dart';
import 'package:pstream_android/widgets/adaptive_nav.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/splash',
  routes: <RouteBase>[
    GoRoute(
      path: '/splash',
      builder: (BuildContext context, GoRouterState state) {
        return const SplashScreen();
      },
    ),
    StatefulShellRoute.indexedStack(
      builder:
          (
            BuildContext context,
            GoRouterState state,
            StatefulNavigationShell navigationShell,
          ) {
            return PopScope(
              // System back at any tab root → switch to Home instead of exiting.
              // When [navigationShell.currentIndex] is already 0, allow OS exit.
              canPop: navigationShell.currentIndex == 0,
              onPopInvokedWithResult: (bool didPop, Object? result) {
                if (didPop) {
                  return;
                }
                if (navigationShell.currentIndex != 0) {
                  navigationShell.goBranch(0, initialLocation: false);
                }
              },
              child: AdaptiveNav(
                currentIndex: navigationShell.currentIndex,
                onDestinationSelected: (int index) {
                  // [goBranch] preserves each tab's nested location and scroll
                  // state so switching tabs no longer rebuilds from scratch.
                  // [initialLocation: false] keeps the last visited sub-route
                  // when revisiting a branch.
                  navigationShell.goBranch(
                    index,
                    initialLocation: index == navigationShell.currentIndex,
                  );
                },
                child: navigationShell,
              ),
            );
          },
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (BuildContext context, GoRouterState state) {
                return const HomeScreen();
              },
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/search',
              builder: (BuildContext context, GoRouterState state) {
                final SearchScreenArgs? args = state.extra as SearchScreenArgs?;
                return SearchScreen(
                  initialQuery: args?.initialQuery,
                  title: args?.title,
                );
              },
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/list',
              builder: (BuildContext context, GoRouterState state) {
                return const MyListScreen();
              },
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/settings',
              builder: (BuildContext context, GoRouterState state) {
                return const SettingsScreen();
              },
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/history',
      builder: (BuildContext context, GoRouterState state) {
        return const HistoryScreen();
      },
    ),
    GoRoute(
      path: '/watch-stats',
      builder: (BuildContext context, GoRouterState state) {
        return const WatchStatsScreen();
      },
    ),
    GoRoute(
      path: '/detail/:id',
      builder: (BuildContext context, GoRouterState state) {
        final MediaItem mediaItem = state.extra! as MediaItem;
        return DetailScreen(mediaItem: mediaItem);
      },
    ),
    GoRoute(
      path: '/scraping',
      builder: (BuildContext context, GoRouterState state) {
        final ScrapingScreenArgs args = state.extra! as ScrapingScreenArgs;
        return ScrapingScreen(
          mediaItem: args.mediaItem,
          season: args.season,
          episode: args.episode,
          seasonTmdbId: args.seasonTmdbId,
          episodeTmdbId: args.episodeTmdbId,
          seasonTitle: args.seasonTitle,
          resumeFrom: args.resumeFrom,
        );
      },
    ),
    GoRoute(
      path: '/player',
      builder: (BuildContext context, GoRouterState state) {
        final PlayerScreenArgs args = state.extra! as PlayerScreenArgs;
        return PlayerScreen(args: args);
      },
    ),
  ],
);
