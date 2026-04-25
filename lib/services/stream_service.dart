import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pstream_android/config/app_config.dart';
import 'package:pstream_android/models/media_item.dart';
import 'package:pstream_android/models/scrape_event.dart';
import 'package:pstream_android/models/stream_result.dart';

class StreamService {
  const StreamService();

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
      Timer? timeoutTimer;
      bool doneSeen = false;
      bool fallbackTriggered = false;

      void closeResources() {
        timeoutTimer?.cancel();
        client.close();
      }

      void armTimeout() {
        timeoutTimer?.cancel();
        timeoutTimer = Timer(const Duration(seconds: 60), () async {
          if (doneSeen) {
            return;
          }

          await subscription?.cancel();
          closeResources();
          multi.addError(
            TimeoutException(
              'Scrape did not emit a done event within 60 seconds.',
            ),
          );
          multi.close();
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

        armTimeout();

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
            timeoutTimer?.cancel();
          } else {
            armTimeout();
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
    required String sourceId,
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
      sourceOrder: <String>[sourceId],
    );
  }

  Future<ScrapeCatalog> fetchCatalog() async {
    final http.Client client = http.Client();
    try {
      final http.Response response = await client
          .get(_baseUri('/sources'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return const ScrapeCatalog();
      }

      final Map<String, dynamic> json =
          Map<String, dynamic>.from(jsonDecode(response.body) as Map);

      return ScrapeCatalog(
        sources: ((json['sources'] as List?) ?? const <dynamic>[])
            .map((entry) => ScrapeSourceDefinition.fromJson(entry))
            .toList(),
        embeds: ((json['embeds'] as List?) ?? const <dynamic>[])
            .map((entry) => ScrapeSourceDefinition.fromJson(entry))
            .toList(),
      );
    } finally {
      client.close();
    }
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
  }) async {
    final http.Client client = http.Client();
    try {
      final http.Response response = await client
          .get(
            _buildUri(
              '/scrape',
              mediaItem,
              season: season,
              episode: episode,
              seasonTmdbId: seasonTmdbId,
              episodeTmdbId: episodeTmdbId,
              seasonTitle: seasonTitle,
              sourceOrder: sourceOrder,
            ),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 404) {
        return null;
      }

      final Map<String, dynamic> json =
          Map<String, dynamic>.from(jsonDecode(response.body) as Map);

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
  }) {
    final Uri base = _baseUri(path);
    final List<String>? effectiveOrder =
        sourceOrder ?? AppConfig.scrapeSourceOrderList;
    return base.replace(
      queryParameters: mediaItem.toScrapeQueryParameters(
        season: season,
        episode: episode,
        sourceOrder: effectiveOrder,
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

class _SseConnectionException implements Exception {
  const _SseConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}
