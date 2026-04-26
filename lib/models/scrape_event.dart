import 'dart:convert';

import 'package:pstream_android/models/stream_result.dart';

class ScrapeEvent {
  const ScrapeEvent({required this.event, required this.payload});

  final String event;
  final Map<String, dynamic> payload;

  String get type => _normalizeEventName(event);

  bool get isDone => type == 'done';

  bool get ok => payload['ok'] == true;

  String? get sourceId {
    final dynamic value =
        payload['sourceId'] ?? payload['id'] ?? payload['scraperId'];
    return _parseNullableString(value);
  }

  String? get errorMessage {
    return _parseNullableString(payload['error'] ?? payload['message']);
  }

  String? get updateStatus {
    return _parseNullableString(payload['status']);
  }

  double? get progress {
    final dynamic value = payload['percentage'] ?? payload['progress'];
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse('$value');
  }

  StreamResult? get result {
    final dynamic value = payload['result'];
    if (value is Map) {
      return StreamResult.fromJson(Map<String, dynamic>.from(value));
    }

    return null;
  }

  List<ScrapeSourceDefinition> get sources {
    return _readDefinitions(
      payload['sources'],
      fallbackIds: payload['sourceIds'],
    );
  }

  List<ScrapeSourceDefinition> get embeds {
    return _readDefinitions(
      payload['embeds'],
      fallbackIds: payload['embedIds'],
    );
  }

  factory ScrapeEvent.fromSse({
    required String event,
    required String rawData,
  }) {
    final String trimmedData = rawData.trim();
    if (trimmedData.isEmpty) {
      return ScrapeEvent(event: event, payload: const <String, dynamic>{});
    }

    final dynamic decoded = jsonDecode(trimmedData);
    if (decoded is Map<String, dynamic>) {
      return ScrapeEvent(event: event, payload: decoded);
    }

    if (decoded is Map) {
      return ScrapeEvent(
        event: event,
        payload: Map<String, dynamic>.from(decoded),
      );
    }

    return ScrapeEvent(
      event: event,
      payload: <String, dynamic>{'value': decoded},
    );
  }

  factory ScrapeEvent.initWithSources(List<ScrapeSourceDefinition> sources) {
    return ScrapeEvent(
      event: 'init',
      payload: <String, dynamic>{
        'sources': sources.map((ScrapeSourceDefinition source) {
          return source.toJson();
        }).toList(),
      },
    );
  }

  factory ScrapeEvent.doneWithResult(StreamResult result) {
    return ScrapeEvent(
      event: 'done',
      payload: <String, dynamic>{
        'ok': true,
        'result': <String, dynamic>{
          'sourceId': result.sourceId,
          'sourceName': result.sourceName,
          'embedId': result.embedId,
          'embedName': result.embedName,
          'stream': <String, dynamic>{
            'id': result.stream.id,
            'type': result.stream.type,
            'playlist': result.stream.playlist,
            'playbackUrl': result.stream.playbackUrl,
            'playbackType': result.stream.playbackType,
            'selectedQuality': result.stream.selectedQuality,
            'qualities': result.stream.qualities.map(
              (String key, StreamQuality value) => MapEntry(
                key,
                <String, dynamic>{'url': value.url, 'type': value.type},
              ),
            ),
            'headers': result.stream.headers,
            'preferredHeaders': result.stream.preferredHeaders,
            'captions': result.stream.captions
                .map((StreamCaption caption) => caption.raw)
                .toList(),
            'flags': result.stream.flags,
          },
        },
      },
    );
  }

  factory ScrapeEvent.doneWithoutResult([String error = 'No stream found.']) {
    return ScrapeEvent(
      event: 'done',
      payload: <String, dynamic>{'ok': false, 'error': error},
    );
  }

  static String _normalizeEventName(String value) {
    return switch (value) {
      'discoverEmbeds' => 'embeds',
      'startSource' => 'start',
      'updateSource' => 'update',
      _ => value,
    };
  }

  static String? _parseNullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final String parsed = '$value'.trim();
    return parsed.isEmpty ? null : parsed;
  }

  static List<ScrapeSourceDefinition> _readDefinitions(
    dynamic values, {
    dynamic fallbackIds,
  }) {
    if (values is List) {
      return values
          .map((dynamic entry) => ScrapeSourceDefinition.fromJson(entry))
          .toList();
    }

    if (fallbackIds is List) {
      return fallbackIds
          .map(
            (dynamic entry) =>
                ScrapeSourceDefinition(id: '$entry', name: '$entry'),
          )
          .toList();
    }

    return const <ScrapeSourceDefinition>[];
  }
}

class ScrapeSourceDefinition {
  const ScrapeSourceDefinition({
    required this.id,
    required this.name,
    this.embedScraperId,
  });

  final String id;
  final String name;
  final String? embedScraperId;

  factory ScrapeSourceDefinition.fromJson(dynamic json) {
    final Map<String, dynamic> map = Map<String, dynamic>.from(
      json as Map? ?? const <String, dynamic>{},
    );

    final String idRaw =
        '${map['id'] ?? map['sourceId'] ?? map['scraperId'] ?? ''}'.trim();

    return ScrapeSourceDefinition(
      id: idRaw,
      name:
          '${map['name'] ?? map['embedScraperId'] ?? map['id'] ?? map['scraperId'] ?? ''}'
              .trim(),
      embedScraperId: _parseNullableString(map['embedScraperId']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      if (embedScraperId != null) 'embedScraperId': embedScraperId,
    };
  }

  static String? _parseNullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final String parsed = '$value'.trim();
    return parsed.isEmpty ? null : parsed;
  }
}
