import 'package:coalition_app_v2/core/ids.dart' show normalizePostId;
import 'package:coalition_app_v2/utils/cloudflare_stream.dart';

enum PostStatus { processing, ready, failed }

class Post {
  const Post({
    required this.id,
    required this.mediaUrl,
    required this.isVideo,
    this.userId,
    this.userDisplayName = 'Unknown',
    this.userAvatarUrl,
    this.description,
    this.thumbUrl,
    this.type,
    this.status = PostStatus.ready,
    this.playbackId,
    this.duration,
    this.likeCount,
    this.isLiked,
    this.commentCount,
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    String? _asString(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      } else if (value is num) {
        return value.toString();
      }
      return null;
    }

    bool _asBool(dynamic value) {
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') {
          return true;
        }
        if (normalized == 'false' || normalized == '0') {
          return false;
        }
      }
      return false;
    }

    PostStatus _parseStatus(dynamic value) {
      final normalized = _asString(value)?.toLowerCase();
      switch (normalized) {
        case 'ready':
        case 'completed':
        case 'published':
        case 'success':
          return PostStatus.ready;
        case 'failed':
        case 'error':
        case 'errored':
        case 'cancelled':
        case 'canceled':
          return PostStatus.failed;
        default:
          return PostStatus.processing;
      }
    }

    Duration? _parseDuration(dynamic value) {
      if (value is Duration) {
        return value;
      }
      if (value is num) {
        final seconds = value.toDouble();
        if (seconds > 0) {
          return Duration(milliseconds: (seconds * 1000).round());
        }
      }
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) {
          return null;
        }
        final parsed = double.tryParse(trimmed);
        if (parsed != null) {
          return Duration(milliseconds: (parsed * 1000).round());
        }
      }
      return null;
    }

    final id = normalizePostId(_asString(json['postId']) ?? '');
    final userMap = json['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(json['user'] as Map<String, dynamic>)
        : null;
    final rawUserId = (json['userId'] ??
            json['user_id'] ??
            json['ownerId'] ??
            json['owner_id'] ??
            userMap?['userId'] ??
            userMap?['id'] ??
            '')
        .toString()
        .trim();
    final userId = rawUserId.isNotEmpty ? rawUserId : null;

    final displayNameTop = _asString(json['displayName']) ??
        _asString(json['userDisplayName']) ??
        _asString(json['user_display_name']);
    final usernameTop =
        _asString(json['username']) ?? _asString(json['userName']);
    final avatarTop = _asString(json['avatarUrl']) ??
        _asString(json['userAvatarUrl']) ??
        _asString(json['profileImage']) ??
        _asString(json['userAvatar']);

    final displayNameNested = _asString(userMap?['displayName']) ??
        _asString(userMap?['name']) ??
        _asString(userMap?['userDisplayName']) ??
        _asString(userMap?['user_display_name']) ??
        _asString(userMap?['username']) ??
        _asString(userMap?['userName']);
    final usernameNested =
        _asString(userMap?['username']) ?? _asString(userMap?['userName']);
    final avatarNested = _asString(userMap?['avatarUrl']) ??
        _asString(userMap?['userAvatarUrl']) ??
        _asString(userMap?['profileImage']);

    final displayName = displayNameTop ??
        displayNameNested ??
        usernameTop ??
        usernameNested ??
        'Unknown';
    final avatar = avatarTop ?? avatarNested;
    final description = _asString(json['description']) ??
        _asString(json['caption']) ??
        _asString(json['text']);
    final type = _asString(json['type']) ?? _asString(json['mediaType']);
    final isVideo = json.containsKey('isVideo')
        ? _asBool(json['isVideo'])
        : (type?.toLowerCase() == 'video');
    final fallbackMediaUrl = _asString(json['mediaUrl']) ??
        _asString(json['videoUrl']) ??
        _asString(json['imageUrl']) ??
        '';
    final resolvedHlsUrl = resolveCloudflareHlsUrl(json);
    final mediaUrl =
        isVideo ? (resolvedHlsUrl ?? fallbackMediaUrl) : fallbackMediaUrl;
    final thumbUrl = _asString(json['thumbUrl']) ??
        _asString(json['thumbnailUrl']) ??
        _asString(json['previewImageUrl']);
    final playbackId = _asString(json['playbackId']);
    final status = _parseStatus(json['status'] ?? json['state']);
    final duration = _parseDuration(
      json['durationSeconds'] ??
          json['duration'] ??
          json['videoDurationSeconds'] ??
          json['videoDuration'],
    );
    final likeCount = (json['likesCount'] as num?)?.toInt() ??
        (json['likeCount'] as num?)?.toInt();
    final isLiked = (json['likedByMe'] as bool?) ??
        (json['liked'] as bool?) ??
        (json['isLiked'] as bool?);
    final commentCount = (json['commentsCount'] as num?)?.toInt();

    return Post(
      id: id,
      userId: userId,
      userDisplayName: displayName,
      userAvatarUrl: avatar,
      description: description,
      mediaUrl: mediaUrl,
      thumbUrl: thumbUrl,
      isVideo: isVideo,
      type: type,
      status: status,
      playbackId: playbackId,
      duration: duration,
      likeCount: likeCount,
      isLiked: isLiked,
      commentCount: commentCount,
    );
  }

  final String id;
  final String? userId;
  final String userDisplayName;
  final String? userAvatarUrl;
  final String? description;
  final String mediaUrl;
  final String? thumbUrl;
  final bool isVideo;
  final String? type;
  final PostStatus status;
  final String? playbackId;
  final Duration? duration;
  final int? likeCount;
  final bool? isLiked;
  final int? commentCount;
}
