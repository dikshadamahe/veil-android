import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/providers/tmdb_provider.dart';
import 'package:pstream_android/widgets/media_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
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
    final bool hasQuery = _query.isNotEmpty;
    final AsyncValue<List<MediaItem>> data = hasQuery
        ? ref.watch(searchProvider(_query))
        : ref.watch(trendingMoviesProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      appBar: AppBar(
        titleSpacing: AppSpacing.x4,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.searchText),
          decoration: InputDecoration(
            hintText: 'Search titles, actors, or directors',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: hasQuery
                ? IconButton(
                    onPressed: () {
                      _controller.clear();
                    },
                    icon: const Icon(Icons.close_rounded),
                  )
                : null,
          ),
        ),
      ),
      body: SafeArea(
        child: data.when(
          data: (List<MediaItem> items) {
            if (items.isEmpty) {
              return _SearchMessageState(
                title: hasQuery ? 'No results found.' : 'Nothing to show yet.',
                message: hasQuery
                    ? 'Try a different title or keyword.'
                    : 'Trending suggestions came back empty.',
              );
            }

            return _SearchResultsGrid(
              title: hasQuery ? null : 'Trending Suggestions',
              items: items,
              isLoading: false,
            );
          },
          loading: () => _SearchResultsGrid(
            title: hasQuery ? null : 'Trending Suggestions',
            items: const <MediaItem>[],
            isLoading: true,
          ),
          error: (Object error, StackTrace stackTrace) {
            return _SearchMessageState(
              title: 'Could not load search data.',
              message: _friendlySearchMessage(error),
            );
          },
        ),
      ),
    );
  }
}

class _SearchResultsGrid extends StatelessWidget {
  const _SearchResultsGrid({
    this.title,
    required this.items,
    required this.isLoading,
  });

  final String? title;
  final List<MediaItem> items;
  final bool isLoading;

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
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.x4,
              AppSpacing.x4,
              AppSpacing.x4,
              AppSpacing.x2,
            ),
            child: Text(
              title!,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(color: AppColors.typeEmphasis),
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.x4),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: AppSpacing.x3,
              mainAxisSpacing: AppSpacing.x4,
              childAspectRatio: 130 / 195,
            ),
            itemCount: itemCount,
            itemBuilder: (BuildContext context, int index) {
              if (isLoading) {
                return const MediaCardSkeleton();
              }

              if (items.isEmpty) {
                return const SizedBox.shrink();
              }

              return MediaCard(mediaItem: items[index]);
            },
          ),
        ),
      ],
    );
  }
}

class _SearchMessageState extends StatelessWidget {
  const _SearchMessageState({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
