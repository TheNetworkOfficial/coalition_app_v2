import 'package:coalition_app_v2/utils/cloudflare_stream.dart';

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
  });

  factory Post.fromJson(
    Map<String, dynamic> json, {
    required String fallbackId,
  }) {
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

    final id = _asString(json['id']) ?? fallbackId;
    final userId = _asString(json['userId']) ??
        _asString(json['user_id']) ??
        _asString(json['ownerId']);
    final displayName = _asString(json['userDisplayName']) ??
        _asString(json['displayName']) ??
        _asString(json['userName']) ??
        _asString(json['user_display_name']) ??
        'Unknown';
    final avatar = _asString(json['userAvatarUrl']) ??
        _asString(json['avatarUrl']) ??
        _asString(json['profileImage']) ??
        _asString(json['userAvatar']);
    final description = _asString(json['description']) ??
        _asString(json['caption']) ??
        _asString(json['text']);
    final isVideo = json.containsKey('isVideo')
        ? _asBool(json['isVideo'])
        : _asBool(json['type'] == 'video');
    final fallbackMediaUrl = _asString(json['mediaUrl']) ??
        _asString(json['videoUrl']) ??
        _asString(json['imageUrl']) ??
        '';
    final resolvedHlsUrl = resolveCloudflareHlsUrl(json);
    final mediaUrl = isVideo
        ? (resolvedHlsUrl ?? fallbackMediaUrl)
        : fallbackMediaUrl;
    final thumbUrl = _asString(json['thumbUrl']) ??
        _asString(json['thumbnailUrl']) ??
        _asString(json['previewImageUrl']);

    return Post(
      id: id,
      userId: userId,
      userDisplayName: displayName,
      userAvatarUrl: avatar,
      description: description,
      mediaUrl: mediaUrl,
      thumbUrl: thumbUrl,
      isVideo: isVideo,
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
}
