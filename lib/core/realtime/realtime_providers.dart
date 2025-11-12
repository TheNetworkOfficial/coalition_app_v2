import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/engagement/providers/engagement_providers.dart'
    show engagementRepositoryProvider;
import 'realtime_service.dart';

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final repo = ref.watch(engagementRepositoryProvider);
  final service = PollingRealtimeService(
    fetchSummary: (postId) => repo.fetchSummary(postId),
  );
  ref.onDispose(service.dispose);
  return service;
});

final realtimeReducerProvider = Provider<RealtimeReducer>((ref) {
  final service = ref.watch(realtimeServiceProvider);
  final reducer = RealtimeReducer(ref, service.stream);
  ref.onDispose(reducer.dispose);
  return reducer;
});
