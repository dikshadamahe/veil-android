import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/providers/tmdb_provider.dart';
import 'package:pstream_android/widgets/media_card.dart';

class SearchScreenArgs {
  const SearchScreenArgs({this.initialQuery, this.title});

  final String? initialQuery;
  final String? title;
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery, this.title});

  final String? initialQuery;
  final String? title;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final String initialQuery = widget.initialQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _controller.text = initialQuery;
      _query = initialQuery;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && initialQuery.isEmpty) {
        _focusNode.requestFocus();
      }
    });
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final String query = _controller.text.trim();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _query = query;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasTmdbReadToken) {
      return Scaffold(
        backgroundColor: AppColors.backgroundMain,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.x4),
            children: const <Widget>[
              _SearchMessageState(
                title: 'Search is unavailable.',
                message:
                    'This build is missing TMDB_TOKEN. Rebuild or re-release the app with the TMDB read access token configured in GitHub secrets.',
              ),
            ],
          ),
        ),
      );
    }

    final bool hasQuery = _query.isNotEmpty;
    final AsyncValue<List<MediaItem>> data = hasQuery
        ? ref.watch(searchProvider(_query))
        : ref.watch(trendingMoviesProvider);

    final WindowClass layoutClass = windowClass(context);
    final double horizontal = switch (layoutClass) {
      WindowClass.compact => AppSpacing.x4,
      WindowClass.medium => AppSpacing.x5,
      WindowClass.expanded => AppSpacing.x6,
    };

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                AppSpacing.x4,
                horizontal,
                AppSpacing.x3,
              ),
              child: Material(
                color: AppColors.searchBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppSpacing.x4 + AppSpacing.x1,
                  ),
                  side: const BorderSide(color: AppColors.dropdownBorder),
                ),
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: AppSpacing.x3),
                    Icon(
                      Icons.search_rounded,
                      color: AppColors.searchIcon,
                      size: AppSpacing.x5,
                    ),
                    const SizedBox(width: AppSpacing.x2),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: AppColors.searchText,
                            ),
                        cursorColor: AppColors.typeLink,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Search titles, people, or studios',
                          hintStyle: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: AppColors.searchPlaceholder,
                              ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.x3,
                          ),
                        ),
                      ),
                    ),
                    if (hasQuery)
                      IconButton(
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: () => _controller.clear(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.searchIcon,
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(right: AppSpacing.x2),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.typeSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: data.when(
                data: (List<MediaItem> items) {
                  if (items.isEmpty) {
                    return _SearchMessageState(
                      title: hasQuery
                          ? 'No results found.'
                          : 'Nothing to show yet.',
                      message: hasQuery
                          ? 'Try a different title or keyword.'
                          : 'Trending suggestions came back empty.',
                    );
                  }

                  return _SearchResultsGrid(
                    title: hasQuery
                        ? (widget.title ?? 'Results')
                        : 'Trending suggestions',
                    items: items,
                    isLoading: false,
                    horizontalPadding: horizontal,
                  );
                },
                loading: () => _SearchResultsGrid(
                  title: hasQuery
                      ? (widget.title ?? 'Results')
                      : 'Trending suggestions',
                  items: const <MediaItem>[],
                  isLoading: true,
                  horizontalPadding: horizontal,
                ),
                error: (Object error, StackTrace stackTrace) {
                  return _SearchMessageState(
                    title: 'Could not load search data.',
                    message: _friendlySearchMessage(error),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResultsGrid extends StatelessWidget {
  const _SearchResultsGrid({
    required this.title,
    required this.items,
    required this.isLoading,
    required this.horizontalPadding,
  });

  final String title;
  final List<MediaItem> items;
  final bool isLoading;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final int columns = switch (windowClass(context)) {
      WindowClass.compact => 2,
      WindowClass.medium => 3,
      WindowClass.expanded => 4,
    };

    final int itemCount = isLoading ? columns * 3 : items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            AppSpacing.x2,
            horizontalPadding,
            AppSpacing.x2,
          ),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppColors.typeLogo,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              AppSpacing.x2,
              horizontalPadding,
              AppSpacing.x4,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: AppSpacing.x3,
              mainAxisSpacing: AppSpacing.x4,
              childAspectRatio: 130 / 195,
            ),
            itemCount: itemCount,
            itemBuilder: (BuildContext context, int index) {
              if (isLoading) {
                return const RepaintBoundary(child: MediaCardSkeleton());
              }

              if (items.isEmpty) {
                return const SizedBox.shrink();
              }

              return RepaintBoundary(
                child: MediaCard(mediaItem: items[index], posterSize: 'w185'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchMessageState extends StatelessWidget {
  const _SearchMessageState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.modalBackground,
              borderRadius: BorderRadius.circular(AppSpacing.x5),
              border: Border.all(color: AppColors.dropdownBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.x6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.search_off_rounded,
                    size: AppSpacing.x10,
                    color: AppColors.typeLogo,
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  Text(
                    title,
                    textAlign: TextAlign.center,
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
            ),
          ),
        ),
      ),
    );
  }
}

String _friendlySearchMessage(Object error) {
  final String message = '$error';
  if (message.contains('TMDB authorization failed')) {
    return 'TMDB_TOKEN is invalid or expired in this build. Rebuild the app with the new read access token.';
  }
  if (message.contains('TimeoutException')) {
    return 'TMDB timed out on this network. The app now retries once, but if it still fails, rebuild with the new token and test again on a stable connection.';
  }
  return message;
}
