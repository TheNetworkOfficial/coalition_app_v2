class Comment {
  Comment({
    required this.commentId,
    required this.postId,
    required this.userId,
    required this.text,
    required this.createdAt,
    required this.likeCount,
    this.replyTo,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.likedByMe = false,
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    return Comment(
      commentId: json['commentId'] as String,
      postId: json['postId'] as String,
      userId: json['userId'] as String,
      text: json['text'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      replyTo: json['replyTo'] as String?,
      displayName: (json['displayName'] ?? json['userDisplayName']) as String?,
      username: json['username'] as String?,
      avatarUrl: (json['avatarUrl'] ?? json['userAvatarUrl']) as String?,
      likedByMe: (json['likedByMe'] as bool?) ?? false,
    );
  }

  Comment copyWith({
    int? likeCount,
    bool? likedByMe,
  }) {
    return Comment(
      commentId: commentId,
      postId: postId,
      userId: userId,
      text: text,
      createdAt: createdAt,
      likeCount: likeCount ?? this.likeCount,
      replyTo: replyTo,
      displayName: displayName,
      username: username,
      avatarUrl: avatarUrl,
      likedByMe: likedByMe ?? this.likedByMe,
    );
  }

  final String commentId;
  final String postId;
  final String userId;
  final String text;
  final int createdAt;
  final int likeCount;
  final String? replyTo;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final bool likedByMe;
}
