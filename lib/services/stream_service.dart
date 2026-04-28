import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';

class StreamService {
  const StreamService();

  /// Some reverse proxies / WAFs reject Dart's default `User-Agent`; match a normal client.
  static const Map<String, String> _oracleJsonHeaders = <String, String>{
    'Accept': 'application/json',
    'User-Agent': 'Veil/1.0 (Android; +https://github.com/dikshadamahe/veil-android)',
  };

  Stream<ScrapeEvent> scrapeStream(
    MediaItem mediaItem, {
    int? season,
    int? episode,
    String? seasonTmdbId,
    String? episodeTmdbId,
    String? seasonTitle,
  }) {
    return Stream<ScrapeEvent>.multi((multi) async {
      final http.Client client = http.Client();
      StreamSubscription<String>? subscription;
      /// One deadline for the whole scrape (align with providers-api REQUEST_TIMEOUT_MS).
      /// Do **not** reset on each SSE line — the server may only send [init] then block until
      /// runAll finishes, so a per-chunk 60s idle timeout fires before a valid result.
      Timer? maxWaitTimer;
      bool doneSeen = false;
      bool fallbackTriggered = false;

      void closeResources() {
        maxWaitTimer?.cancel();
        client.close();
      }

      void startMaxWaitTimer() {
        maxWaitTimer?.cancel();
        maxWaitTimer = Timer(const Duration(seconds: 100), () async {
          if (doneSeen) {
            return;
          }
          await subscription?.cancel();
          client.close();
          if (!multi.isClosed) {
            multi.addError(
              TimeoutException(
                'Scrape is taking too long (over 100s). '
                'Check Oracle and network, or try again.',
              ),
            );
            multi.close();
          }
        });
      }

      Future<void> emitBlockingFallback() async {
        if (fallbackTriggered || doneSeen) {
          return;
        }

        fallbackTriggered = true;
        await subscription?.cancel();
        closeResources();
        await _emitBlockingFallback(
          multi,
          mediaItem,
          season: season,
          episode: episode,
          seasonTmdbId: seasonTmdbId,
          episodeTmdbId: episodeTmdbId,
          seasonTitle: seasonTitle,
        );
      }

      try {
        final http.Request request = http.Request(
          'GET',
          _buildUri(
            '/scrape/stream',
            mediaItem,
            season: season,
            episode: episode,
            seasonTmdbId: seasonTmdbId,
            episodeTmdbId: episodeTmdbId,
            seasonTitle: seasonTitle,
          ),
        );
        request.headers.addAll(_oracleJsonHeaders);

        final http.StreamedResponse response = await client
            .send(request)
            .timeout(
              const Duration(seconds: 25),
              onTimeout: () {
                throw TimeoutException(
                  'Timed out connecting to the scrape service.',
                );
              },
            );
        if (response.statusCode != 200) {
          throw _SseConnectionException(
            'SSE connection failed with status ${response.statusCode}.',
          );
        }

        startMaxWaitTimer();

        String? currentEvent;
        final List<String> currentData = <String>[];

        void flushEvent() {
          if (currentEvent == null || currentData.isEmpty) {
            currentEvent = null;
            currentData.clear();
            return;
          }

          final ScrapeEvent event = ScrapeEvent.fromSse(
            event: currentEvent!,
            rawData: currentData.join('\n'),
          );

          multi.add(event);

          if (event.isDone) {
            doneSeen = true;
            maxWaitTimer?.cancel();
          }

          currentEvent = null;
          currentData.clear();
        }

        subscription = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (String line) {
                if (line.isEmpty) {
                  flushEvent();
                  return;
                }

                if (line.startsWith('event:')) {
                  currentEvent = line.substring(6).trim();
                  return;
                }

                if (line.startsWith('data:')) {
                  currentData.add(line.substring(5).trim());
                }
              },
              onDone: () {
                flushEvent();
                closeResources();
                if (!multi.isClosed) {
                  multi.close();
                }
              },
              onError: (Object error, StackTrace stackTrace) async {
                if (error is TimeoutException) {
                  if (!multi.isClosed) {
                    multi.addError(error, stackTrace);
                    multi.close();
                  }
                  return;
                }

                if (error is _SseConnectionException ||
                    error is http.ClientException) {
                  await emitBlockingFallback();
                  return;
                }

                closeResources();
                if (!multi.isClosed) {
                  multi.addError(error, stackTrace);
                  multi.close();
                }
              },
              cancelOnError: false,
            );
      } on TimeoutException {
        await emitBlockingFallback();
      } on _SseConnectionException {
        await emitBlockingFallback();
      } on http.ClientException {
        await emitBlockingFallback();
      } catch (error, stackTrace) {
        closeResources();
        if (!multi.isClosed) {
          multi.addError(error, stackTrace);
          multi.close();
        }
      }
    });
  }

  Future<StreamResult?> scrapeBlocking(
    MediaItem mediaItem, {
    int? season,
    int? episode,
    String? seasonTmdbId,
    String? episodeTmdbId,
    String? seasonTitle,
  }) {
    return _scrapeBlockingRequest(
      mediaItem,
      season: season,
      episode: episode,
      seasonTmdbId: seasonTmdbId,
      episodeTmdbId: episodeTmdbId,
      seasonTitle: seasonTitle,
    );
  }

  Future<StreamResult?> scrapeSingleSource(
    MediaItem mediaItem, {
    required String selectedId,
    required String selectedType,
    String? parentSourceId,
    int? season,
    int? episode,
    String? seasonTmdbId,
    String? episodeTmdbId,
    String? seasonTitle,
  }) {
    return _scrapeBlockingRequest(
      mediaItem,
      season: season,
      episode: episode,
      seasonTmdbId: seasonTmdbId,
      episodeTmdbId: episodeTmdbId,
      seasonTitle: seasonTitle,
      selectedId: selectedId,
      selectedType: selectedType,
      parentSourceId: parentSourceId,
    );
  }

  Future<ScrapeCatalog> fetchCatalog() async {
    final CatalogFetchResult r = await fetchCatalogWithDiagnostics();
    return r.catalog;
  }

  /// Same as [fetchCatalog] plus [failureReason] when the catalog is unusable.
  Future<CatalogFetchResult> fetchCatalogWithDiagnostics() async {
    final Uri uri = _baseUri('/sources');
    if (!uri.hasScheme || uri.host.isEmpty) {
      return CatalogFetchResult(
        catalog: const ScrapeCatalog(),
        failureReason:
            'Invalid ORACLE_URL (need full URL like http://YOUR_IP:3001). Rebuild APK.',
      );
    }

    final http.Client client = http.Client();
    try {
      final http.Response response = await client
          .get(uri, headers: _oracleJsonHeaders)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return CatalogFetchResult(
          catalog: const ScrapeCatalog(),
          failureReason:
              'GET /sources → HTTP ${response.statusCode} from ${uri.host}:${uri.port}. '
              'Compare: curl -sS "$uri"',
        );
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return CatalogFetchResult(
          catalog: const ScrapeCatalog(),
          failureReason:
              'GET /sources returned non-JSON object. First chars: '
              '${_bodyPrefix(response.body)}',
        );
      }

      final Map<String, dynamic> json = Map<String, dynamic>.from(decoded);
      final List<ScrapeSourceDefinition> sources = ((json['sources'] as List?) ??
              const <dynamic>[])
          .map((dynamic entry) => ScrapeSourceDefinition.fromJson(entry))
          .where((ScrapeSourceDefinition s) => s.id.isNotEmpty)
          .toList();
      final List<ScrapeSourceDefinition> embeds = ((json['embeds'] as List?) ??
              const <dynamic>[])
          .map((dynamic entry) => ScrapeSourceDefinition.fromJson(entry))
          .where((ScrapeSourceDefinition s) => s.id.isNotEmpty)
          .toList();

      if (sources.isEmpty) {
        return CatalogFetchResult(
          catalog: ScrapeCatalog(sources: sources, embeds: embeds),
          failureReason:
              'GET /sources HTTP 200 but "sources" is empty after parse. '
              'On Oracle check providers-api and @p-stream/providers listSources(). '
              'Body prefix: ${_bodyPrefix(response.body)}',
        );
      }

      return CatalogFetchResult(
        catalog: ScrapeCatalog(sources: sources, embeds: embeds),
      );
    } on SocketException catch (e) {
      return CatalogFetchResult(
        catalog: const ScrapeCatalog(),
        failureReason:
            'Cannot reach ${uri.host}:${uri.port} from this device ($e). '
            'Oracle security list / Wi‑Fi / VPN?',
      );
    } on TimeoutException {
      return CatalogFetchResult(
        catalog: const ScrapeCatalog(),
        failureReason:
            'Timed out loading /sources from ${uri.host}:${uri.port}.',
      );
    } on FormatException catch (e) {
      return CatalogFetchResult(
        catalog: const ScrapeCatalog(),
        failureReason: 'Bad JSON from /sources: $e',
      );
    } catch (e) {
      return CatalogFetchResult(
        catalog: const ScrapeCatalog(),
        failureReason: 'GET /sources failed: $e',
      );
    } finally {
      client.close();
    }
  }

  static String _bodyPrefix(String body, [int max = 120]) {
    final String t = body.trim();
    if (t.length <= max) {
      return t;
    }
    return '${t.substring(0, max)}…';
  }

  Future<void> _emitBlockingFallback(
    MultiStreamController<ScrapeEvent> multi,
    MediaItem mediaItem, {
    int? season,
    int? episode,
    String? seasonTmdbId,
    String? episodeTmdbId,
    String? seasonTitle,
  }) async {
    final ScrapeCatalog catalog = await fetchCatalog();
    if (catalog.sources.isNotEmpty) {
      multi.add(ScrapeEvent.initWithSources(catalog.sources));
    }

    final StreamResult? result = await scrapeBlocking(
      mediaItem,
      season: season,
      episode: episode,
      seasonTmdbId: seasonTmdbId,
      episodeTmdbId: episodeTmdbId,
      seasonTitle: seasonTitle,
    );

    multi.add(
      result == null
          ? ScrapeEvent.doneWithoutResult()
          : ScrapeEvent.doneWithResult(result),
    );

    if (!multi.isClosed) {
      multi.close();
    }
  }

  Future<StreamResult?> _scrapeBlockingRequest(
    MediaItem mediaItem, {
    int? season,
    int? episode,
    String? seasonTmdbId,
    String? episodeTmdbId,
    String? seasonTitle,
    List<String>? sourceOrder,
    List<String>? embedOrder,
    String? selectedId,
    String? selectedType,
    String? parentSourceId,
  }) async {
    final http.Client client = http.Client();
    final Uri scrapeUri = _buildUri(
      '/scrape',
      mediaItem,
      season: season,
      episode: episode,
      seasonTmdbId: seasonTmdbId,
      episodeTmdbId: episodeTmdbId,
      seasonTitle: seasonTitle,
      sourceOrder: sourceOrder,
      embedOrder: embedOrder,
      selectedId: selectedId,
      selectedType: selectedType,
      parentSourceId: parentSourceId,
    );
    try {
      final http.Response response = await client
          .get(
            scrapeUri,
            headers: _oracleJsonHeaders,
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 404) {
        return null;
      }

      final Map<String, dynamic> json = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );

      if (response.statusCode != 200) {
        throw Exception(json['error'] ?? 'Blocking scrape failed.');
      }

      final dynamic result = json['result'];
      if (result is! Map) {
        return null;
      }

      return StreamResult.fromJson(Map<String, dynamic>.from(result));
    } finally {
      client.close();
    }
  }

  Uri _buildUri(
    String path,
    MediaItem mediaItem, {
    int? season,
    int? episode,
    String? seasonTmdbId,
    String? episodeTmdbId,
    String? seasonTitle,
    List<String>? sourceOrder,
    List<String>? embedOrder,
    String? selectedId,
    String? selectedType,
    String? parentSourceId,
  }) {
    final Uri base = _baseUri(path);
    final List<String>? effectiveOrder =
        sourceOrder ?? AppConfig.scrapeSourceOrderList;
    return base.replace(
      queryParameters: mediaItem.toScrapeQueryParameters(
        season: season,
        episode: episode,
        sourceOrder: effectiveOrder,
        embedOrder: embedOrder,
        selectedId: selectedId,
        selectedType: selectedType,
        parentSourceId: parentSourceId,
        seasonTmdbId: seasonTmdbId,
        episodeTmdbId: episodeTmdbId,
        seasonTitle: seasonTitle,
      ),
    );
  }

  Uri _baseUri(String path) {
    final Uri base = Uri.parse('${AppConfig.proxyBaseUrl}/');
    return base.resolve(path.startsWith('/') ? path.substring(1) : path);
  }
}

class ScrapeCatalog {
  const ScrapeCatalog({
    this.sources = const <ScrapeSourceDefinition>[],
    this.embeds = const <ScrapeSourceDefinition>[],
  });

  final List<ScrapeSourceDefinition> sources;
  final List<ScrapeSourceDefinition> embeds;
}

/// Result of [StreamService.fetchCatalogWithDiagnostics].
class CatalogFetchResult {
  const CatalogFetchResult({
    required this.catalog,
    this.failureReason,
  });

  final ScrapeCatalog catalog;
  /// Set when [catalog.sources] is empty or the request could not complete.
  final String? failureReason;

  bool get hasSources => catalog.sources.isNotEmpty;
}

class _SseConnectionException implements Exception {
  const _SseConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
