import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pstream_android/models/live_channel.dart';
import 'package:pstream_android/services/live_service.dart';

final liveServiceProvider = Provider<LiveService>((_) => const LiveService());

final liveChannelsProvider = FutureProvider<List<LiveChannel>>((ref) async {
  return ref.read(liveServiceProvider).fetchChannels();
});

final liveEpgProvider =
    FutureProvider<Map<String, List<LiveProgram>>>((ref) async {
  return ref.read(liveServiceProvider).fetchEpg();
});
