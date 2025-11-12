import 'package:coalition_app_v2/features/engagement/utils/ids.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:flutter_riverpod/legacy.dart';

import '../../../providers/app_providers.dart';
import '../data/engagement_repository.dart';
import '../models/liker.dart';
import '../models/post_engagement.dart';

final engagementRepositoryProvider = Provider<EngagementRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return EngagementRepository(apiClient: api);
});

class PostEngagementController extends StateNotifier<PostEngagementState> {
  PostEngagementController({
    required EngagementRepository repo,
    required String postId,
  })  : _repo = repo,
        super(PostEngagementState(postId: postId));

  final EngagementRepository _repo;
  bool _loadingNetwork = false;

  /// Idempotent: seeds from UI if provided, then (optionally) fetches server truth.
  Future<void> ensureLoaded({
    bool? isLikedSeed,
    int? likeCountSeed,
    int? commentCountSeed,
  }) async {
    if (!state.loadedOnce) {
      final capturedPostId = state.postId;
      // Schedule after current build; this avoids provider-mutation-during-build
      Future(() {
        if (!mounted) {
          return;
        }
        // verify the key didn't change while deferred
        if (state.postId != capturedPostId) {
          return;
        }
        applyServerSummary(
          likeCount: likeCountSeed,
          likedByMe: isLikedSeed,
          commentCount: commentCountSeed,
        );
      });
    }
    if (_loadingNetwork) {
      return;
    }
    // Skip invalid/synthetic IDs to avoid hitting 400s.
    if (!isValidPostId(state.postId)) {
      return;
    }
    _loadingNetwork = true;
    final capturedPostId = state.postId;
    try {
      final summary = await _repo.fetchSummary(capturedPostId);
      if (!mounted || state.postId != capturedPostId) {
        return;
      }
      if (summary != null) {
        final serverLiked = summary['likedByMe'] == true;
        final serverCount =
            (summary['likesCount'] as num?)?.toInt() ?? state.likeCount;
        final serverComments =
            (summary['commentsCount'] as num?)?.toInt() ?? state.commentCount;
        applyServerSummary(
          likeCount: serverCount,
          likedByMe: serverLiked,
          commentCount: serverComments,
        );
      }
    } catch (_) {
      // swallow; optimistic seed still applied
    } finally {
      _loadingNetwork = false;
    }
  }

  Future<void> toggleLike() async {
    if (!isValidPostId(state.postId)) {
      return;
    }
    final capturedPostId = state.postId;
    final previous = state;
    final target = !state.isLiked;
    final optimisticCount = _nextCount(previous.likeCount, previous.isLiked, target);
    state = state.copyWith(
      isLiked: target,
      likeCount: optimisticCount,
      loadedOnce: true,
    );

    try {
      final result = target
          ? await _repo.like(capturedPostId)
          : await _repo.unlike(capturedPostId);
      if (!mounted || state.postId != capturedPostId) {
        return;
      }
      applyServerSummary(
        likeCount: result.likesCount,
        likedByMe: result.liked,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[PostEngagementController] toggleLike failed: $error\n$stackTrace',
      );
      if (!mounted || state.postId != capturedPostId) {
        return;
      }
      state = previous;
    }
  }

  void applyServerSummary({
    int? likeCount,
    bool? likedByMe,
    int? commentCount,
    bool overrideLikedStatus = true,
  }) {
    if (!mounted) {
      return;
    }
    state = state.copyWith(
      likeCount: likeCount ?? state.likeCount,
      isLiked: overrideLikedStatus ? (likedByMe ?? state.isLiked) : state.isLiked,
      commentCount: commentCount ?? state.commentCount,
      loadedOnce: true,
    );
  }

  int _nextCount(int currentCount, bool currentLiked, bool targetLiked) {
    if (currentLiked == targetLiked) {
      return currentCount;
    }
    final delta = targetLiked ? 1 : -1;
    final next = currentCount + delta;
    return next < 0 ? 0 : next;
  }
}

final postEngagementProvider = StateNotifierProvider.family<
    PostEngagementController, PostEngagementState, String>((ref, postId) {
  final repo = ref.watch(engagementRepositoryProvider);
  final normalized = normalizePostId(postId);
  return PostEngagementController(repo: repo, postId: normalized);
});

@immutable
class LikersState {
  const LikersState({
    required this.items,
    this.cursor,
    this.loading = false,
    this.error,
  });

  final List<Liker> items;
  final String? cursor;
  final bool loading;
  final String? error;

  LikersState copyWith({
    List<Liker>? items,
    String? cursor,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return LikersState(
      items: items ?? this.items,
      cursor: cursor ?? this.cursor,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class LikersController extends StateNotifier<LikersState> {
  LikersController({required EngagementRepository repo, required String postId})
      : _repo = repo,
        _postId = normalizePostId(postId),
        super(const LikersState(items: <Liker>[]));

  final EngagementRepository _repo;
  final String _postId;

  Future<void> loadInitial() async {
    if (_postId.isEmpty || state.loading) {
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _repo.fetchLikers(_postId);
      if (!mounted) {
        return;
      }
      state = LikersState(
        items: page.items,
        cursor: page.nextCursor,
        loading: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to load likers: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  Future<void> loadMore() async {
    if (_postId.isEmpty || state.loading || state.cursor == null) {
      return;
    }
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _repo.fetchLikers(
        _postId,
        cursor: state.cursor,
      );
      if (!mounted) {
        return;
      }
      state = LikersState(
        items: [...state.items, ...page.items],
        cursor: page.nextCursor,
        loading: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to load more likers: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      state = state.copyWith(loading: false, error: error.toString());
    }
  }
}

final postLikersProvider = StateNotifierProvider.family<
    LikersController, LikersState, String>((ref, postId) {
  final repo = ref.watch(engagementRepositoryProvider);
  return LikersController(repo: repo, postId: postId);
});
