import 'package:coalition_app_v2/features/engagement/utils/ids.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../debug/logging.dart';
import '../../../providers/app_providers.dart';
import '../data/comments_repository.dart';
import '../models/comment.dart';

class ActiveCommentsRegistry extends StateNotifier<Set<String>> {
  ActiveCommentsRegistry() : super(<String>{});

  void acquire(String postId) {
    if (postId.isEmpty) {
      return;
    }
    final next = Set<String>.of(state)..add(postId);
    state = next;
  }

  void release(String postId) {
    if (postId.isEmpty || !state.contains(postId)) {
      return;
    }
    final next = Set<String>.of(state)..remove(postId);
    state = next;
  }
}

final activeCommentsRegistryProvider =
    StateNotifierProvider<ActiveCommentsRegistry, Set<String>>(
  (ref) => ActiveCommentsRegistry(),
);

final commentsRepositoryProvider = Provider<CommentsRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CommentsRepository(apiClient: apiClient);
});

class CommentsState {
  CommentsState({
    required this.items,
    this.cursor,
    this.loading = false,
    this.replyingTo,
  });

  final List<Comment> items;
  final String? cursor;
  final bool loading;
  final String? replyingTo;

  CommentsState copyWith({
    List<Comment>? items,
    String? cursor,
    bool? loading,
    String? replyingTo,
    bool clearReplyingTo = false,
  }) {
    return CommentsState(
      items: items ?? this.items,
      cursor: cursor ?? this.cursor,
      loading: loading ?? this.loading,
      replyingTo: clearReplyingTo ? null : (replyingTo ?? this.replyingTo),
    );
  }
}

final commentsControllerProvider =
    StateNotifierProvider.family<CommentsController, CommentsState, String>(
        (ref, postId) {
  final repo = ref.read(commentsRepositoryProvider);
  final normalized = normalizePostId(postId);
  return CommentsController(repo, normalized);
});

class CommentsController extends StateNotifier<CommentsState> {
  CommentsController(this._repo, this.postId)
      : super(CommentsState(items: const []));

  final CommentsRepository _repo;
  final String postId;
  final Map<String, int> _opSeq = <String, int>{};
  final Set<String> _pending = <String>{};
  final Set<String> _hydratedEngagement = <String>{};
  final Set<String> _hydratingEngagement = <String>{};

  bool isPending(String commentId) {
    final trimmed = commentId.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    return _pending.contains(trimmed);
  }

  Future<void> loadInitial() async {
    if (state.loading) return;
    state = state.copyWith(loading: true);
    try {
      final result = await _repo.listComments(postId);
      if (!mounted) {
        return;
      }
      state = CommentsState(
        items: result.items,
        cursor: result.cursor,
        loading: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to load comments: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      state = state.copyWith(loading: false);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.cursor == null) return;
    state = state.copyWith(loading: true);
    try {
      final result = await _repo.listComments(postId, cursor: state.cursor);
      if (!mounted) {
        return;
      }
      state = state.copyWith(
        items: [...state.items, ...result.items],
        cursor: result.cursor,
        loading: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to load more comments: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      state = state.copyWith(loading: false);
    }
  }

  Future<void> addComment(String text, {String? replyTo}) async {
    logDebug(
      'COMMENTS',
      'addComment start',
      extra: <String, Object?>{
        'postId': postId,
        'textLength': text.length,
        if (replyTo != null && replyTo.isNotEmpty) 'replyTo': replyTo,
      },
    );
    try {
      final created = await _repo.createComment(
        postId,
        text: text,
        replyTo: replyTo,
      );
      if (!mounted) {
        return;
      }
      final current = [...state.items];
      if (created.replyTo == null || created.replyTo!.isEmpty) {
        state = state.copyWith(items: [created, ...current]);
      } else {
        final parentId = created.replyTo!;
        final parentIndex = current.indexWhere((c) => c.commentId == parentId);
        if (parentIndex == -1) {
          state = state.copyWith(items: [created, ...current]);
        } else {
          var insertAt = parentIndex + 1;
          while (insertAt < current.length &&
              current[insertAt].replyTo == parentId) {
            insertAt++;
          }
          current.insert(insertAt, created);
          state = state.copyWith(items: current);
        }
      }
      logDebug(
        'COMMENTS',
        'addComment success',
        extra: <String, Object?>{'commentId': created.commentId},
      );
    } catch (error, stackTrace) {
      logDebug(
        'COMMENTS',
        'addComment failed: $error',
        extra: stackTrace.toString(),
      );
      rethrow;
    }
  }

  Future<void> toggleLike(String commentId) async {
    final trimmedId = commentId.trim();
    if (trimmedId.isEmpty) {
      return;
    }
    final idx = state.items.indexWhere((c) => c.commentId == trimmedId);
    if (idx < 0) {
      return;
    }

    if (_pending.contains(trimmedId)) {
      return;
    }
    _pending.add(trimmedId);

    final base = state.items[idx];
    final target = !base.likedByMe;
    final seq = (_opSeq[trimmedId] ?? 0) + 1;
    _opSeq[trimmedId] = seq;

    final optimistic = base.copyWith(
      likedByMe: target,
      likeCount:
          (base.likeCount + (target ? 1 : -1)).clamp(0, 1 << 31).toInt(),
    );
    final optimisticItems = [...state.items]..[idx] = optimistic;
    state = state.copyWith(items: optimisticItems);

    try {
      final result = await _repo.setLike(trimmedId, target);
      if (!mounted) {
        return;
      }
      if (_opSeq[trimmedId] != seq) {
        return;
      }
      final curIdx =
          state.items.indexWhere((item) => item.commentId == trimmedId);
      if (curIdx >= 0) {
        final next = state.items[curIdx].copyWith(
          likedByMe: result.liked,
          likeCount: result.likeCount,
        );
        final nextItems = [...state.items]..[curIdx] = next;
        state = state.copyWith(items: nextItems);
        _hydratedEngagement.add(trimmedId);
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to set like: $error\n$stackTrace');
      if (!mounted) {
        return;
      }
      if (_opSeq[trimmedId] == seq) {
        final curIdx =
            state.items.indexWhere((item) => item.commentId == trimmedId);
        if (curIdx >= 0) {
          final rollbackItems = [...state.items]..[curIdx] = base;
          state = state.copyWith(items: rollbackItems);
        }
      }
    } finally {
      if (_opSeq[trimmedId] == seq) {
        _pending.remove(trimmedId);
      }
    }
  }

  void setReplyingTo(String? commentId) {
    state = state.copyWith(
      replyingTo: commentId,
      clearReplyingTo: commentId == null,
    );
  }

  void insertFromServer(Map<String, dynamic> json) {
    try {
      final incoming = Comment.fromJson(json);
      final alreadyExists =
          state.items.any((c) => c.commentId == incoming.commentId);
      if (alreadyExists) {
        return;
      }
      final current = [...state.items];
      if (incoming.replyTo == null || incoming.replyTo!.isEmpty) {
        state = state.copyWith(items: [incoming, ...current]);
        return;
      }
      final parentId = incoming.replyTo!;
      final parentIndex = current.indexWhere((c) => c.commentId == parentId);
      if (parentIndex == -1) {
        state = state.copyWith(items: [incoming, ...current]);
        return;
      }
      var insertAt = parentIndex + 1;
      while (insertAt < current.length &&
          current[insertAt].replyTo == parentId) {
        insertAt++;
      }
      current.insert(insertAt, incoming);
      state = state.copyWith(items: current);
    } catch (error, stackTrace) {
      debugPrint('Failed to merge comment from server: $error\n$stackTrace');
    }
  }

  void applyServerLikeCount(String commentId, int likeCount) {
    final trimmed = commentId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final idx = state.items.indexWhere((c) => c.commentId == trimmed);
    if (idx < 0) {
      return;
    }
    final cur = state.items[idx];
    final safeCount =
        likeCount.clamp(0, 1 << 31).toInt();
    final next = cur.copyWith(likeCount: safeCount);
    final items = [...state.items]..[idx] = next;
    state = state.copyWith(items: items);
  }

  void applyUserLikedStatus(String commentId, bool likedByMe) {
    final trimmed = commentId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final idx = state.items.indexWhere((c) => c.commentId == trimmed);
    if (idx < 0) {
      return;
    }
    final cur = state.items[idx];
    final next = cur.copyWith(likedByMe: likedByMe);
    final items = [...state.items]..[idx] = next;
    state = state.copyWith(items: items);
    _hydratedEngagement.add(trimmed);
  }

  Future<void> ensureEngagementLoaded(String commentId) async {
    final trimmedId = commentId.trim();
    if (trimmedId.isEmpty) {
      return;
    }
    if (_hydratedEngagement.contains(trimmedId) ||
        _hydratingEngagement.contains(trimmedId)) {
      return;
    }
    final idx = state.items.indexWhere((c) => c.commentId == trimmedId);
    if (idx < 0) {
      return;
    }
    final item = state.items[idx];
    if (item.likedByMe) {
      _hydratedEngagement.add(trimmedId);
      return;
    }

    _hydratingEngagement.add(trimmedId);
    try {
      final body = await _repo.fetchEngagement(trimmedId);
      if (!mounted) {
        return;
      }
      if (body == null) {
        return;
      }
      final likedByMe = body['likedByMe'] == true;
      final likesCount = (body['likesCount'] as num?)?.toInt();
      applyUserLikedStatus(trimmedId, likedByMe);
      if (likesCount != null) {
        applyServerLikeCount(trimmedId, likesCount);
      }
      _hydratedEngagement.add(trimmedId);
    } catch (error, stackTrace) {
      debugPrint('Failed to load comment engagement: $error\n$stackTrace');
    } finally {
      _hydratingEngagement.remove(trimmedId);
    }
  }
}
