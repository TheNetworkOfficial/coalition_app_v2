import 'package:equatable/equatable.dart';

class Candidate extends Equatable {
  final String candidateId;
  final String name;
  final String? headshotUrl;
  final String? level;
  final String? district;
  final String? description;
  final List<String> tags;
  final int followersCount;
  final bool isFollowing;

  const Candidate({
    required this.candidateId,
    required this.name,
    this.headshotUrl,
    this.level,
    this.district,
    this.description,
    this.tags = const [],
    this.followersCount = 0,
    this.isFollowing = false,
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

    return Candidate(
      candidateId: readString(json['candidateId']).trim(),
      name: readString(json['name']).trim(),
      headshotUrl: (json['headshotUrl'] as String?)?.trim(),
      level: (json['level'] as String?)?.trim(),
      district: (json['district'] as String?)?.trim(),
      description: (json['description'] as String?)?.trim(),
      tags: resolveTags(json['tags']),
      followersCount: readInt(json['followersCount']),
      isFollowing: json['isFollowing'] == true,
    );
  }

  Candidate copyWith({
    String? name,
    String? headshotUrl,
    String? level,
    String? district,
    String? description,
    List<String>? tags,
    int? followersCount,
    bool? isFollowing,
  }) {
    return Candidate(
      candidateId: candidateId,
      name: name ?? this.name,
      headshotUrl: headshotUrl ?? this.headshotUrl,
      level: level ?? this.level,
      district: district ?? this.district,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      followersCount: followersCount ?? this.followersCount,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        candidateId,
        name,
        headshotUrl,
        level,
        district,
        description,
        tags,
        followersCount,
        isFollowing,
      ];
}
