import 'package:equatable/equatable.dart';

class Candidate extends Equatable {
  final String candidateId;
  final String name;
  final String? headshotUrl;
  final String? avatarUrl;
  final String? level;
  final String? district;
  final String? description;
  final List<String> tags;
  final int followersCount;
  final bool isFollowing;
  final Map<String, String?>? socials;

  const Candidate({
    required this.candidateId,
    required this.name,
    this.headshotUrl,
    this.avatarUrl,
    this.level,
    this.district,
    this.description,
    this.tags = const [],
    this.followersCount = 0,
    this.isFollowing = false,
    this.socials,
  });

  factory Candidate.fromJson(Map<String, dynamic> json) {
    List<String> resolveTags(dynamic value) {
      if (value is List) {
        return value
            .whereType<String>()
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toList(growable: false);
      }
      return const [];
    }

    String readString(dynamic value) => value == null ? '' : value.toString();

    int readInt(dynamic value) {
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          final parsed = int.tryParse(trimmed);
          if (parsed != null) {
            return parsed;
          }
        }
      }
      return 0;
    }

    final rawId =
        (json['candidateId'] ?? json['id'] ?? json['candidate_id'] ?? '')
            .toString();

    final resolvedName = () {
      final primary = readString(json['name']).trim();
      if (primary.isNotEmpty) {
        return primary;
      }
      final fallback = readString(json['displayName']).trim();
      if (fallback.isNotEmpty) {
        return fallback;
      }
      return 'Unnamed candidate';
    }();

    String? readNullable(dynamic value) {
      final text = readString(value).trim();
      return text.isEmpty ? null : text;
    }

    final resolvedLevel =
        readNullable(json['level'] ?? json['levelOfOffice']);
    final resolvedDistrict = readNullable(json['district']);
    final resolvedDescription =
        readNullable(json['description'] ?? json['bio']);

    return Candidate(
      candidateId: rawId.trim(),
      name: resolvedName,
      headshotUrl: (json['headshotUrl'] as String?)?.trim(),
      avatarUrl: (json['avatarUrl'] as String?)?.trim(),
      level: resolvedLevel,
      district: resolvedDistrict,
      description: resolvedDescription,
      tags: resolveTags(json['tags']),
      followersCount: readInt(json['followersCount']),
      isFollowing: json['isFollowing'] == true,
      socials: _readSocials(json['socials']),
    );
  }

  Candidate copyWith({
    String? name,
    String? headshotUrl,
    String? avatarUrl,
    String? level,
    String? district,
    String? description,
    List<String>? tags,
    int? followersCount,
    bool? isFollowing,
    Map<String, String?>? socials,
  }) {
    return Candidate(
      candidateId: candidateId,
      name: name ?? this.name,
      headshotUrl: headshotUrl ?? this.headshotUrl,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      level: level ?? this.level,
      district: district ?? this.district,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      followersCount: followersCount ?? this.followersCount,
      isFollowing: isFollowing ?? this.isFollowing,
      socials: socials ?? this.socials,
    );
  }

  Map<String, dynamic> toJson() {
    final sanitizedSocials = socials == null
        ? null
        : Map<String, String?>.fromEntries(
            socials!.entries.where((entry) => entry.value != null),
          );
    return <String, dynamic>{
      'candidateId': candidateId,
      'name': name,
      if (headshotUrl != null) 'headshotUrl': headshotUrl,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (level != null) 'level': level,
      if (district != null) 'district': district,
      if (description != null) 'description': description,
      if (tags.isNotEmpty) 'tags': List<String>.from(tags),
      'followersCount': followersCount,
      'isFollowing': isFollowing,
      if (sanitizedSocials != null && sanitizedSocials.isNotEmpty)
        'socials': sanitizedSocials,
    };
  }

  @override
  List<Object?> get props => <Object?>[
        candidateId,
        name,
        headshotUrl,
        avatarUrl,
        level,
        district,
        description,
        tags,
        followersCount,
        isFollowing,
        socials,
      ];

  static Map<String, String?>? _readSocials(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final normalized = <String, String?>{};
    raw.forEach((key, value) {
      if (key is! String) {
        return;
      }
      final normalizedKey = key.trim().toLowerCase();
      if (normalizedKey.isEmpty) {
        return;
      }
      final textValue = value is String ? value.trim() : null;
      if (textValue == null || textValue.isEmpty) {
        return;
      }
      normalized[normalizedKey] = textValue;
    });

    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.containsKey('twitter') &&
        !normalized.containsKey('x') &&
        (normalized['twitter']?.isNotEmpty ?? false)) {
      normalized['x'] = normalized['twitter'];
    }

    return Map<String, String?>.unmodifiable(normalized);
  }
}
