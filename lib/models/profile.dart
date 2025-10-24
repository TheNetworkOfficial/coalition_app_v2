class Profile {
  Profile({
    required this.userId,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.bio,
    this.isFollowing = false,
    this.followersCount = 0,
    this.followingCount = 0,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    String? stringValue(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      if (value is num) {
        return value.toString();
      }
      return null;
    }

    return Profile(
      userId: stringValue(json['userId']) ??
          stringValue(json['id']) ??
          stringValue(json['sub']) ??
          '',
      displayName: stringValue(json['displayName']) ??
          stringValue(json['name']) ??
          stringValue(json['fullName']),
      username: stringValue(json['username']) ??
          stringValue(json['handle']) ??
          stringValue(json['preferredUsername']),
      avatarUrl: stringValue(json['avatarUrl']) ??
          stringValue(json['profileImageUrl']) ??
          stringValue(json['avatar']),
      bio: stringValue(json['bio']) ?? stringValue(json['about']),
      isFollowing: (json['isFollowing'] as bool?) ?? false,
      followersCount: (json['followersCount'] as num?)?.toInt() ?? 0,
      followingCount: (json['followingCount'] as num?)?.toInt() ?? 0,
    );
  }

  final String userId;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final bool isFollowing;
  final int followersCount;
  final int followingCount;

  bool get isEmpty => userId.isEmpty && displayName == null && username == null;

  Profile copyWith({
    String? displayName,
    String? username,
    String? avatarUrl,
    String? bio,
    bool? isFollowing,
    int? followersCount,
    int? followingCount,
  }) {
    return Profile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      isFollowing: isFollowing ?? this.isFollowing,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
    );
  }
}

class ProfileUpdate {
  ProfileUpdate({this.displayName, this.username, this.avatarUrl, this.bio});

  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? bio;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (displayName != null) 'displayName': displayName,
      if (username != null) 'username': username,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (bio != null) 'bio': bio,
    };
  }
}
