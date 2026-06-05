import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/services/stream_service.dart';

/// Single StreamService instance for the app. The constructor reads
/// `ORACLE_URL` from `AppConfig.oracleUrl` and calls
/// `GET /v1/movies/{id}` / `GET /v1/tv/{id}/seasons/{s}/episodes/{e}`.
final streamServiceProvider = Provider<StreamService>((Ref ref) {
  return const StreamService();
});
