import 'package:flutter/foundation.dart';

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
    this.candidateAccessStatus = 'none',
    this.totalLikes = 0,
    List<String>? roles,
    this.isAdmin = false,
  }) : roles = _normalizeProfileRoles(roles);

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

    final rawRoles = json['roles'];
    final rawIsAdmin = json['isAdmin'];
    debugPrint(
      '[Profile][TEMP] raw roles type=${rawRoles.runtimeType} value=$rawRoles | isAdmin raw=$rawIsAdmin',
    );
    final parsedRoles = _parseRoles(rawRoles);

    final profile = Profile(
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
      candidateAccessStatus:
          stringValue(json['candidateAccessStatus'])?.toLowerCase() ?? 'none',
      totalLikes: (json['totalLikes'] as num?)?.toInt() ?? 0,
      roles: parsedRoles,
      isAdmin: (rawIsAdmin as bool?) ?? false,
    );

    debugPrint(
      '[Profile][TEMP] normalized roles len=${profile.roles.length} roles=${profile.roles}',
    );

    return profile;
  }

  final String userId;
  final String? displayName;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final bool isFollowing;
  final int followersCount;
  final int followingCount;
  /// 'approved' | 'pending' | 'none' (default)
  final String candidateAccessStatus;
  final int totalLikes;
  /// Normalized roles returned by the server.
  final List<String> roles;
  /// Explicit admin flag from the API response.
  final bool isAdmin;

  bool get hasAdminAccess => isAdmin || roles.contains('admin');

  bool get isEmpty => userId.isEmpty && displayName == null && username == null;

  Profile copyWith({
    String? displayName,
    String? username,
    String? avatarUrl,
    String? bio,
    bool? isFollowing,
    int? followersCount,
    int? followingCount,
    String? candidateAccessStatus,
    int? totalLikes,
    List<String>? roles,
    bool? isAdmin,
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
      candidateAccessStatus:
          candidateAccessStatus ?? this.candidateAccessStatus,
      totalLikes: totalLikes ?? this.totalLikes,
      roles: roles ?? this.roles,
      isAdmin: isAdmin ?? this.isAdmin,
    );
  }
}

List<String> _normalizeProfileRoles(List<String>? roles) {
  if (roles == null || roles.isEmpty) {
    return const <String>[];
  }
  final normalized = <String>{};
  for (final entry in roles) {
    final trimmed = entry.trim();
    if (trimmed.isNotEmpty) {
      normalized.add(trimmed.toLowerCase());
    }
  }
  if (normalized.isEmpty) {
    return const <String>[];
  }
  return List<String>.unmodifiable(normalized);
}

List<String> _parseRoles(dynamic raw) {
  if (raw is List) {
    return _normalizeProfileRoles(raw.whereType<String>().toList());
  }
  if (raw is String) {
    final parts = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return _normalizeProfileRoles(parts);
  }
  return const <String>[];
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
