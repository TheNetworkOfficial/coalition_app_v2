class Profile {
  Profile({
    required this.userId,
    this.displayName,
    this.username,
    this.avatarUrl,
    this.bio,
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
    );
  }

  final String userId;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? bio;

  bool get isEmpty => userId.isEmpty && displayName == null && username == null;

  Profile copyWith({
    String? displayName,
    String? username,
    String? avatarUrl,
    String? bio,
  }) {
    return Profile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
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
