import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/services/tmdb_service.dart';
import 'package:pstream_android/widgets/media_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.tmdbService = const TmdbService()});

  final TmdbService tmdbService;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  bool _isLoading = false;
  List<MediaItem> _results = const <MediaItem>[];
  late Future<List<MediaItem>> _suggestionsFuture;

  @override
  void initState() {
    super.initState();
    _suggestionsFuture = widget.tmdbService.getTrending('movie', 'week');
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
    if (query.isEmpty) {
      setState(() {
        _isLoading = false;
        _results = const <MediaItem>[];
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final List<MediaItem> results = await widget.tmdbService.search(query);
      if (!mounted || query != _controller.text.trim()) {
        return;
      }

      setState(() {
        _results = results;
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool hasQuery = _controller.text.trim().isNotEmpty;

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
            hintText: 'Search movies and shows',
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
      body: hasQuery
          ? _SearchResultsGrid(items: _results, isLoading: _isLoading)
          : FutureBuilder<List<MediaItem>>(
              future: _suggestionsFuture,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<List<MediaItem>> snapshot,
                  ) {
                    return _SearchResultsGrid(
                      title: 'Trending Suggestions',
                      items: snapshot.data ?? const <MediaItem>[],
                      isLoading:
                          snapshot.connectionState != ConnectionState.done,
                    );
                  },
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
      WindowClass.expanded => 3,
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
