import 'package:flutter/foundation.dart';

@immutable
class PostEngagementState {
  const PostEngagementState({
    required this.postId,
    this.isLiked = false,
    this.likeCount = 0,
    this.commentCount = 0,
    this.loading = false,
    this.loadedOnce = false,
  });

  final String postId;
  final bool isLiked;
  final int likeCount;
  final int commentCount;
  final bool loading;
  final bool loadedOnce;

  PostEngagementState copyWith({
    bool? isLiked,
    int? likeCount,
    int? commentCount,
    bool? loading,
    bool? loadedOnce,
  }) {
    return PostEngagementState(
      postId: postId,
      isLiked: isLiked ?? this.isLiked,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      loading: loading ?? this.loading,
      loadedOnce: loadedOnce ?? this.loadedOnce,
    );
  }
}
