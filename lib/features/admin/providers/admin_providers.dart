import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';
import '../data/admin_repository.dart';
import '../models/admin_application.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return AdminRepository(apiClient: apiClient);
});

/// AsyncNotifier-based pager for pending applications (endless scroll).
class PendingApplicationsNotifier extends AsyncNotifier<List<AdminApplication>> {
  String? _cursor;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoadingMore;

  @override
  Future<List<AdminApplication>> build() async {
    // Initial load
    final repo = ref.read(adminRepositoryProvider);
    _cursor = null;
    _hasMore = true;
    final page = await repo.listApplications(status: 'pending', limit: 20);
    _cursor = page.nextCursor;
    _hasMore = page.hasMore;
    return page.items;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(adminRepositoryProvider);
      _cursor = null;
      _hasMore = true;
      final page = await repo.listApplications(status: 'pending', limit: 20);
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      return page.items;
    });
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    try {
      final current = state.value ?? const <AdminApplication>[];
      final repo = ref.read(adminRepositoryProvider);
      final page = await repo.listApplications(
        status: 'pending',
        limit: 20,
        cursor: _cursor,
      );
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      state = AsyncData<List<AdminApplication>>(
        List<AdminApplication>.unmodifiable([...current, ...page.items]),
      );
    } catch (err, st) {
      // Keep current items on failure; log in debug
      if (kDebugMode) debugPrint('loadMore failed: $err');
      state = AsyncError(state.error ?? err, st);
    } finally {
      _isLoadingMore = false;
    }
  }
}

final pendingApplicationsProvider =
    AsyncNotifierProvider<PendingApplicationsNotifier, List<AdminApplication>>(
  () => PendingApplicationsNotifier(),
);

final applicationDetailProvider =
    FutureProvider.family<AdminApplication, String>((ref, id) {
  final repo = ref.watch(adminRepositoryProvider);
  return repo.getApplication(id);
});
