import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/api_client.dart';
import '../data/feed_repository.dart';
import '../models/post.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return FeedRepository(apiClient: apiClient);
});

final feedItemsProvider = FutureProvider<List<Post>>((ref) async {
  final repository = ref.watch(feedRepositoryProvider);
  return repository.getFeed();
});
