import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncValue, Ref;
import 'package:flutter_riverpod/legacy.dart';

import '../../../providers/app_providers.dart';
import '../data/candidates_repository.dart';
import '../models/candidate.dart';
import '../models/candidates_filter.dart';

class CandidatesPager extends StateNotifier<AsyncValue<List<Candidate>>> {
  CandidatesPager(this._ref) : super(const AsyncValue.loading()) {
    unawaited(_load(reset: true));
  }

  final Ref _ref;
  final List<Candidate> _items = <Candidate>[];
  String? _cursor;
  bool _hasMore = true;
  bool _isLoading = false;
  CandidatesFilter _filter = const CandidatesFilter();

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  CandidatesFilter get filter => _filter;

  Future<void> refresh() => _load(reset: true);

  Future<void> loadMore() => _load(reset: false);

  CandidatesRepository _repositoryForRead() {
    final apiClient = _ref.read(apiClientProvider);
    return CandidatesRepository(apiClient: apiClient);
  }

  Future<void> _load({required bool reset}) async {
    if (_isLoading) {
      return;
    }
    if (!reset && !_hasMore) {
      return;
    }
    _isLoading = true;

    if (reset) {
      _cursor = null;
      _hasMore = true;
      _items.clear();
      state = const AsyncValue.loading();
    }

    final repository = _repositoryForRead();
    try {
      final page = await repository.list(
        limit: 20,
        cursor: _cursor,
        filter: _filter,
      );
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

  Future<void> applyFilter(CandidatesFilter filter) async {
    _filter = filter;
    await _load(reset: true);
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

    final repository = _repositoryForRead();
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
