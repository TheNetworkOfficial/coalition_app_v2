import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncValue, FutureProvider, Provider, Ref;
import 'package:flutter_riverpod/legacy.dart';

import '../../../providers/app_providers.dart';
import '../../../services/api_client.dart';
import '../data/candidates_repository.dart';
import '../models/candidate.dart';
import '../models/candidate_update.dart';
import '../../../models/posts_page.dart';

final candidatesRepositoryProvider = Provider<CandidatesRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CandidatesRepository(apiClient: apiClient);
});

final candidateDetailProvider =
    FutureProvider.family<Candidate?, String>((ref, id) async {
  final apiClient = ref.watch(apiClientProvider);
  final trimmed = id.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    final response = await apiClient.getCandidate(trimmed);
    return response.candidate;
  } on ApiException catch (error) {
    if (error.statusCode == HttpStatus.notFound) {
      return null;
    }
    rethrow;
  }
});

final candidatePostsProvider =
    FutureProvider.family<PostsPage, String>((ref, id) {
  final repository = ref.watch(candidatesRepositoryProvider);
  return repository.getCandidatePosts(id);
});

final candidateUpdateControllerProvider =
    Provider<Future<Candidate> Function(String, CandidateUpdate)>((ref) {
  final repository = ref.watch(candidatesRepositoryProvider);
  return (String id, CandidateUpdate update) async {
    final updated = await repository.updateCandidate(id, update);
    ref.invalidate(candidateDetailProvider(id));
    ref.invalidate(candidatePostsProvider(id));
    ref.invalidate(candidatesPagerProvider);
    return updated;
  };
});

class CandidatesPager extends StateNotifier<AsyncValue<List<Candidate>>> {
  CandidatesPager(this._ref) : super(const AsyncValue.loading()) {
    unawaited(_load(reset: true));
  }

  final Ref _ref;
  final List<Candidate> _items = <Candidate>[];
  String? _cursor;
  bool _hasMore = true;
  bool _isLoading = false;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  Future<void> refresh() => _load(reset: true);

  Future<void> loadMore() => _load(reset: false);

  Future<void> _load({required bool reset}) async {
    if (_isLoading) {
      return;
    }
    _isLoading = true;

    if (reset) {
      _cursor = null;
      _hasMore = true;
      _items.clear();
      state = const AsyncValue.loading();
    }

    final repository = _ref.read(candidatesRepositoryProvider);
    try {
      final page = await repository.list(limit: 20, cursor: _cursor);
      if (reset) {
        _items
          ..clear()
          ..addAll(page.items);
      } else {
        _items.addAll(page.items);
      }
      _cursor = page.cursor;
      _hasMore = _cursor != null && _cursor!.isNotEmpty;
      state = AsyncValue.data(List<Candidate>.unmodifiable(_items));
    } catch (error, stackTrace) {
      if (reset && _items.isEmpty) {
        state = AsyncValue.error(error, stackTrace);
      } else {
        if (kDebugMode) {
          debugPrint('Failed to load candidates: $error');
        }
        state = AsyncValue.data(List<Candidate>.unmodifiable(_items));
      }
      return;
    } finally {
      _isLoading = false;
    }
  }

  Future<void> optimisticToggle(String id, bool next) async {
    final index = _items.indexWhere((candidate) => candidate.candidateId == id);
    if (index < 0) {
      return;
    }
    final previous = _items[index];
    final delta = next ? 1 : -1;
    final updatedCount = max(0, previous.followersCount + delta);
    _items[index] = previous.copyWith(
      isFollowing: next,
      followersCount: updatedCount,
    );
    state = AsyncValue.data(List<Candidate>.unmodifiable(_items));

    final repository = _ref.read(candidatesRepositoryProvider);
    try {
      await repository.toggleFollow(id);
    } catch (error, stackTrace) {
      _items[index] = previous;
      state = AsyncValue.data(List<Candidate>.unmodifiable(_items));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final candidatesPagerProvider =
    StateNotifierProvider<CandidatesPager, AsyncValue<List<Candidate>>>(
  (ref) => CandidatesPager(ref),
);
