import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:flutter_riverpod/legacy.dart';

import '../../../debug/logging.dart';
import '../../../providers/app_providers.dart';
import '../data/comments_repository.dart';
import '../models/comment.dart';

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

final commentsControllerProvider = StateNotifierProvider.family<
    CommentsController, CommentsState, String>((ref, postId) {
  final repo = ref.read(commentsRepositoryProvider);
  return CommentsController(repo, postId);
});

class CommentsController extends StateNotifier<CommentsState> {
  CommentsController(this._repo, this.postId)
      : super(CommentsState(items: const []));

  final CommentsRepository _repo;
  final String postId;

  Future<void> loadInitial() async {
    if (state.loading) return;
    state = state.copyWith(loading: true);
    try {
      final result = await _repo.listComments(postId);
      state = CommentsState(
        items: result.items,
        cursor: result.cursor,
        loading: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to load comments: $error\n$stackTrace');
      state = state.copyWith(loading: false);
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.cursor == null) return;
    state = state.copyWith(loading: true);
    try {
      final result = await _repo.listComments(postId, cursor: state.cursor);
      state = state.copyWith(
        items: [...state.items, ...result.items],
        cursor: result.cursor,
        loading: false,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to load more comments: $error\n$stackTrace');
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
    final index = state.items.indexWhere((c) => c.commentId == commentId);
    if (index < 0) return;

    final current = state.items[index];
    final optimistic = current.copyWith(
      likedByMe: !current.likedByMe,
      likeCount: current.likeCount + (current.likedByMe ? -1 : 1),
    );
    final optimisticItems = [...state.items]..[index] = optimistic;
    state = state.copyWith(items: optimisticItems);

    try {
      final liked = await _repo.toggleLike(commentId);
      final targetIndex =
          state.items.indexWhere((item) => item.commentId == commentId);
      if (targetIndex >= 0) {
        final reconciled = state.items[targetIndex].copyWith(
          likedByMe: liked,
          likeCount: optimistic.likeCount,
        );
        final reconciledItems = [...state.items]..[targetIndex] = reconciled;
        state = state.copyWith(items: reconciledItems);
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to toggle like: $error\n$stackTrace');
      final targetIndex =
          state.items.indexWhere((item) => item.commentId == commentId);
      if (targetIndex >= 0) {
        final revertedItems = [...state.items]..[targetIndex] = current;
        state = state.copyWith(items: revertedItems);
      }
    }
  }

  void setReplyingTo(String? commentId) {
    state = state.copyWith(
      replyingTo: commentId,
      clearReplyingTo: commentId == null,
    );
  }
}
