import 'package:flutter/foundation.dart';

@immutable
class CandidateUpdate {
  const CandidateUpdate({
    this.displayName,
    this.levelOfOffice,
    this.district,
    this.bio,
    this.priorityTags,
    this.avatarUrl,
    this.socials,
  });

  final String? displayName;
  final String? levelOfOffice;
  final String? district;
  final String? bio;
  final List<String>? priorityTags;
  final String? avatarUrl;
  final Map<String, String?>? socials;

  List<String>? get _sanitizedTags {
    if (priorityTags == null) {
      return null;
    }
    final cleaned = priorityTags!
        .whereType<String>()
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .take(5)
        .toList(growable: false);
    return cleaned.isEmpty ? null : cleaned;
  }

  Map<String, String?>? get _sanitizedSocials {
    if (socials == null) {
      return null;
    }
    final entries = <String, String?>{};
    for (final entry in socials!.entries) {
      final key = entry.key;
      final value = entry.value?.trim();
      if (value != null && value.isNotEmpty) {
        entries[key] = value;
      }
    }
    if (entries.isEmpty) {
      return null;
    }
    return Map<String, String?>.unmodifiable(entries);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (displayName != null && displayName!.trim().isNotEmpty)
        'displayName': displayName!.trim(),
      if (levelOfOffice != null && levelOfOffice!.trim().isNotEmpty)
        'levelOfOffice': levelOfOffice!.trim(),
      if (district != null && district!.trim().isNotEmpty)
        'district': district!.trim(),
      if (bio != null && bio!.trim().isNotEmpty) 'bio': bio!.trim(),
      if (_sanitizedTags != null) 'priorityTags': _sanitizedTags,
      if (avatarUrl != null && avatarUrl!.trim().isNotEmpty)
        'avatarUrl': avatarUrl!.trim(),
      if (_sanitizedSocials != null) 'socials': _sanitizedSocials,
    };
  }
}
