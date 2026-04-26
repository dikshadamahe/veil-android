import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/config/app_theme.dart';
import 'package:pstream_android/config/breakpoints.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/providers/storage_provider.dart';
import 'package:pstream_android/providers/tmdb_provider.dart';
import 'package:pstream_android/widgets/category_row.dart';
import 'package:pstream_android/widgets/media_card.dart';

enum _HomeCatalogFilter { all, movies, tv }

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  _HomeCatalogFilter _catalogFilter = _HomeCatalogFilter.all;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.hasTmdbReadToken) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundMain,
        body: SafeArea(
          child: _HomeMessageState(
            title: 'App setup is incomplete.',
            message:
                'This build is missing TMDB_TOKEN. Rebuild or re-release the app with the TMDB read access token configured in GitHub secrets.',
          ),
        ),
      );
    }

    final WindowClass layoutClass = windowClass(context);
    final double horizontalPadding = switch (layoutClass) {
      WindowClass.compact => AppSpacing.x4,
      WindowClass.medium => AppSpacing.x5,
      WindowClass.expanded => AppSpacing.x6,
    };
    final double topPadding = switch (layoutClass) {
      WindowClass.compact => AppSpacing.x4,
      WindowClass.medium => AppSpacing.x5,
      WindowClass.expanded => AppSpacing.x6,
    };

    final AsyncValue<List<MediaItem>> trendingMovies = ref.watch(
      trendingMoviesProvider,
    );
    final AsyncValue<List<MediaItem>> trendingTv = ref.watch(
      trendingTVProvider,
    );
    final AsyncValue<List<MediaItem>> popular = ref.watch(
      popularMoviesProvider,
    );
    final List<MediaItem> continueWatching = _filterByCatalog(
      ref.watch(continueWatchingProvider),
    );
    final List<MediaItem> bookmarks = _filterByCatalog(
      ref.watch(bookmarksProvider),
    );
    final Object? error =
        trendingMovies.error ?? trendingTv.error ?? popular.error;

    final bool showMovieRows = _catalogFilter == _HomeCatalogFilter.all ||
        _catalogFilter == _HomeCatalogFilter.movies;
    final bool showTvRows = _catalogFilter == _HomeCatalogFilter.all ||
        _catalogFilter == _HomeCatalogFilter.tv;

    final List<MediaItem> heroCandidates = _heroItems(
      trendingMovies: trendingMovies.value ?? const <MediaItem>[],
      trendingTv: trendingTv.value ?? const <MediaItem>[],
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundMain,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(top: topPadding, bottom: AppSpacing.x6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: _HomeTopBar(layoutClass: layoutClass),
              ),
              SizedBox(
                height: switch (layoutClass) {
                  WindowClass.compact => AppSpacing.x4,
                  _ => AppSpacing.x5,
                },
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: _HomeCategoryChips(
                  selected: _catalogFilter,
                  onSelected: (_HomeCatalogFilter next) {
                    setState(() {
                      _catalogFilter = next;
                    });
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.x4),
              if (error != null)
                _HomeMessageState(
                  title: 'Could not load the home feed.',
                  message: _friendlyMessage(error),
                )
              else if (trendingMovies.isLoading ||
                  trendingTv.isLoading ||
                  popular.isLoading)
                const _HomeLoadingState()
              else ...<Widget>[
                if (heroCandidates.isNotEmpty) ...<Widget>[
                  RepaintBoundary(
                    child: _HomeHeroCarousel(
                      items: heroCandidates,
                      layoutClass: layoutClass,
                      horizontalPadding: horizontalPadding,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                ],
                if (continueWatching.isNotEmpty) ...<Widget>[
                  CategoryRow(
                    title: 'Continue watching',
                    items: continueWatching,
                    useSectionAccent: true,
                    cardBehavior: MediaCardBehavior.continueWatching,
                    onSeeAll: () => context.go('/list'),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                ],
                if (bookmarks.isNotEmpty) ...<Widget>[
                  CategoryRow(
                    title: 'My list',
                    items: bookmarks,
                    useSectionAccent: true,
                    onSeeAll: () => context.go('/list'),
                  ),
                  const SizedBox(height: AppSpacing.x6),
                ],
                if (showMovieRows &&
                    (trendingMovies.value ?? const <MediaItem>[]).isNotEmpty)
                  CategoryRow(
                    title: 'Trending movies',
                    items: trendingMovies.value ?? const <MediaItem>[],
                    useSectionAccent: true,
                    onSeeAll: () => context.go('/search'),
                  ),
                if (showMovieRows &&
                    (trendingMovies.value ?? const <MediaItem>[]).isNotEmpty)
                  const SizedBox(height: AppSpacing.x6),
                if (showTvRows &&
                    (trendingTv.value ?? const <MediaItem>[]).isNotEmpty)
                  CategoryRow(
                    title: 'Trending TV',
                    items: trendingTv.value ?? const <MediaItem>[],
                    useSectionAccent: true,
                    onSeeAll: () => context.go('/search'),
                  ),
                if (showTvRows &&
                    (trendingTv.value ?? const <MediaItem>[]).isNotEmpty)
                  const SizedBox(height: AppSpacing.x6),
                if (showMovieRows &&
                    (popular.value ?? const <MediaItem>[]).isNotEmpty)
                  CategoryRow(
                    title: 'Popular',
                    items: popular.value ?? const <MediaItem>[],
                    useSectionAccent: true,
                    onSeeAll: () => context.go('/search'),
                  ),
                if ((trendingMovies.value ?? const <MediaItem>[]).isEmpty &&
                    (trendingTv.value ?? const <MediaItem>[]).isEmpty &&
                    (popular.value ?? const <MediaItem>[]).isEmpty)
                  const _HomeMessageState(
                    title: 'Nothing to show yet.',
                    message: 'Trending data came back empty.',
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Apply the All / Movies / TV chip to a row of [items]. Keeps order stable.
  List<MediaItem> _filterByCatalog(List<MediaItem> items) {
    switch (_catalogFilter) {
      case _HomeCatalogFilter.all:
        return items;
      case _HomeCatalogFilter.movies:
        return items.where((MediaItem m) => m.isMovie).toList(growable: false);
      case _HomeCatalogFilter.tv:
        return items.where((MediaItem m) => m.isShow).toList(growable: false);
    }
  }

  List<MediaItem> _heroItems({
    required List<MediaItem> trendingMovies,
    required List<MediaItem> trendingTv,
  }) {
    switch (_catalogFilter) {
      case _HomeCatalogFilter.movies:
        return trendingMovies.take(8).toList(growable: false);
      case _HomeCatalogFilter.tv:
        return trendingTv.take(8).toList(growable: false);
      case _HomeCatalogFilter.all:
        final List<MediaItem> merged = <MediaItem>[
          ...trendingMovies.take(5),
          ...trendingTv.take(5),
        ];
        return merged.take(8).toList(growable: false);
    }
  }
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({required this.layoutClass});

  final WindowClass layoutClass;

  @override
  Widget build(BuildContext context) {
    final double brandHeight = switch (layoutClass) {
      WindowClass.compact => 34,
      WindowClass.medium => 38,
      WindowClass.expanded => 40,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: _HomeBrandMark(height: brandHeight),
          ),
        ),
      ],
    );
  }
}

/// Logo asset, or a single purple wordmark — no duplicate “V + Veil” lockup.
class _HomeBrandMark extends StatelessWidget {
  const _HomeBrandMark({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Image.asset(
        'logo.png',
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        filterQuality: FilterQuality.medium,
        errorBuilder: (BuildContext context, Object error, StackTrace? st) {
          return Text(
            'Veil',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.typeLogo,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.75,
                  height: 1,
                ),
          );
        },
      ),
    );
  }
}

class _HomeCategoryChips extends StatelessWidget {
  const _HomeCategoryChips({required this.selected, required this.onSelected});

  final _HomeCatalogFilter selected;
  final ValueChanged<_HomeCatalogFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const List<({String label, _HomeCatalogFilter value})> options =
        <({String label, _HomeCatalogFilter value})>[
      (label: 'All', value: _HomeCatalogFilter.all),
      (label: 'Movies', value: _HomeCatalogFilter.movies),
      (label: 'TV', value: _HomeCatalogFilter.tv),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.x2),
        itemBuilder: (BuildContext context, int index) {
          final ({String label, _HomeCatalogFilter value}) opt = options[index];
          final bool isOn = selected == opt.value;
          return Material(
            color: isOn ? AppColors.purpleC700 : AppColors.transparent,
            borderRadius: BorderRadius.circular(21),
            child: InkWell(
              borderRadius: BorderRadius.circular(21),
              onTap: () => onSelected(opt.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x4,
                  vertical: AppSpacing.x2,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(
                    color: isOn ? AppColors.purpleC400 : AppColors.dropdownBorder,
                  ),
                ),
                child: Center(
                  child: Text(
                    opt.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isOn
                          ? AppColors.typeEmphasis
                          : AppColors.typeSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Hero carousel owns its own [PageController] + page index so swiping
/// between slides only rebuilds this widget — the rest of the home page
/// (category rows, hero candidates, async providers) stays untouched.
class _HomeHeroCarousel extends StatefulWidget {
  const _HomeHeroCarousel({
    required this.items,
    required this.layoutClass,
    required this.horizontalPadding,
  });

  final List<MediaItem> items;
  final WindowClass layoutClass;
  final double horizontalPadding;

  @override
  State<_HomeHeroCarousel> createState() => _HomeHeroCarouselState();
}

class _HomeHeroCarouselState extends State<_HomeHeroCarousel> {
  final PageController _controller = PageController();
  int _pageIndex = 0;

  @override
  void didUpdateWidget(covariant _HomeHeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameItems(oldWidget.items, widget.items)) {
      _pageIndex = 0;
      if (_controller.hasClients) {
        _controller.jumpToPage(0);
      }
    }
  }

  static bool _sameItems(List<MediaItem> a, List<MediaItem> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i].tmdbId != b[i].tmdbId) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double width =
        MediaQuery.sizeOf(context).width - widget.horizontalPadding * 2;
    final double height = switch (widget.layoutClass) {
      WindowClass.compact => width * 0.52,
      WindowClass.medium => width * 0.42,
      WindowClass.expanded => width * 0.36,
    };

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.x5),
            child: SizedBox(
              height: height,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (int i) => setState(() => _pageIndex = i),
                itemCount: widget.items.length,
                itemBuilder: (BuildContext context, int index) {
                  return _HomeHeroSlide(media: widget.items[index]);
                },
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List<Widget>.generate(widget.items.length, (int i) {
              final bool active = i == _pageIndex;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: active ? AppSpacing.x3 : AppSpacing.x2,
                  height: AppSpacing.x2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.x1),
                    color: active ? AppColors.typeLogo : AppColors.ashC600,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _HomeHeroSlide extends StatelessWidget {
  const _HomeHeroSlide({required this.media});

  final MediaItem media;

  @override
  Widget build(BuildContext context) {
    final String? backdrop = media.backdropUrl('w780');
    final String? castName = media.credits.isNotEmpty
        ? media.credits.first.name
        : null;
    final String yearLabel = media.year > 0 ? '${media.year}' : '—';

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ColoredBox(
          color: AppColors.blackC100,
          child: backdrop == null
              ? const Center(
                  child: Icon(
                    Icons.movie_creation_outlined,
                    color: AppColors.typeSecondary,
                    size: 48,
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: backdrop,
                  fit: BoxFit.cover,
                  placeholder: (_, _) =>
                      const ColoredBox(color: AppColors.blackC100),
                  errorWidget: (_, _, _) =>
                      const ColoredBox(color: AppColors.blackC100),
                ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                AppColors.transparent,
                AppColors.transparent,
                AppColors.blackC50,
              ],
              stops: <double>[0, 0.45, 1],
            ),
          ),
        ),
        Positioned(
          left: AppSpacing.x4,
          right: AppSpacing.x4,
          bottom: AppSpacing.x4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Container(
                    width: AppSpacing.x2,
                    height: AppSpacing.x2,
                    decoration: const BoxDecoration(
                      color: AppColors.typeLogo,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Text(
                      media.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.typeEmphasis,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x2),
              if (castName != null)
                _HeroMetaRow(label: 'Cast', value: castName),
              _HeroMetaRow(label: 'Release', value: yearLabel),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroMetaRow extends StatelessWidget {
  const _HeroMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$label ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.typeEmphasis.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.typeEmphasis.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeLoadingState extends StatelessWidget {
  const _HomeLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: <Widget>[
        CategoryRow(
          title: 'Continue watching',
          items: <MediaItem>[],
          isLoading: true,
          useSectionAccent: true,
        ),
        SizedBox(height: AppSpacing.x6),
        CategoryRow(
          title: 'My list',
          items: <MediaItem>[],
          isLoading: true,
          useSectionAccent: true,
        ),
        SizedBox(height: AppSpacing.x6),
        CategoryRow(
          title: 'Trending movies',
          items: <MediaItem>[],
          isLoading: true,
          useSectionAccent: true,
        ),
        SizedBox(height: AppSpacing.x6),
        CategoryRow(
          title: 'Trending TV',
          items: <MediaItem>[],
          isLoading: true,
          useSectionAccent: true,
        ),
        SizedBox(height: AppSpacing.x6),
        CategoryRow(
          title: 'Popular',
          items: <MediaItem>[],
          isLoading: true,
          useSectionAccent: true,
        ),
      ],
    );
  }
}

class _HomeMessageState extends StatelessWidget {
  const _HomeMessageState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.x4),
        decoration: BoxDecoration(
          color: AppColors.modalBackground,
          borderRadius: BorderRadius.circular(AppSpacing.x4),
          border: Border.all(color: AppColors.dropdownBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.x2),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

String _friendlyMessage(Object error) {
  final String message = '$error';
  if (message.contains('TMDB authorization failed')) {
    return 'TMDB_TOKEN is invalid or expired in this build. Rebuild the app with the new read access token.';
  }
  if (message.contains('TimeoutException')) {
    return 'TMDB timed out on this network. The app now retries once, but if it still fails, rebuild with the new token and test again on a stable connection.';
  }
  return message;
}
