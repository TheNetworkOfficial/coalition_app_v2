import 'package:coalition_app_v2/features/engagement/utils/ids.dart';

class RealtimeEvent {
  const RealtimeEvent(this.type, this.payload);

  final String type;
  final Map<String, dynamic> payload;
}

class PostEngagementUpdated {
  PostEngagementUpdated.fromJson(Map<String, dynamic> json)
      : postId = normalizePostId(json['postId']),
        likesCount = (json['likesCount'] as num?)?.toInt(),
        likedByMe = json['likedByMe'] as bool?,
        commentsCount = (json['commentsCount'] as num?)?.toInt();

  final String postId;
  final int? likesCount;
  final bool? likedByMe;
  final int? commentsCount;
}

class CommentCreated {
  CommentCreated.fromJson(Map<String, dynamic> json)
      : postId = normalizePostId(json['postId']),
        commentJson = Map<String, dynamic>.from(
          (json['comment'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{},
        );

  final String postId;
  final Map<String, dynamic> commentJson;
}

class CommentLikesUpdated {
  CommentLikesUpdated.fromJson(Map<String, dynamic> json)
      : commentId = (json['commentId'] ?? '').toString().trim(),
        likeCount = (json['likeCount'] as num?)?.toInt() ?? 0,
        userId = (json['userId'] ?? '').toString().trim(),
        likedByMe = json['likedByMe'] == true;

  final String commentId;
  final int likeCount;
  final String userId;
  final bool likedByMe;
}

class CommentEngagementUser {
  CommentEngagementUser.fromJson(Map<String, dynamic> json)
      : commentId = (json['commentId'] ?? '').toString().trim(),
        userId = (json['userId'] ?? '').toString().trim(),
        likedByMe = json['likedByMe'] == true;

  final String commentId;
  final String userId;
  final bool likedByMe;
}
