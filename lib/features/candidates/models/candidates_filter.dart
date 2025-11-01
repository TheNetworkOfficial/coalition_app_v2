import 'package:equatable/equatable.dart';

class CandidatesFilter extends Equatable {
  const CandidatesFilter({
    this.query,
    this.level,
    this.district,
    Set<String>? tags,
  }) : tags = tags ?? const {};

  final String? query;
  final String? level;
  final String? district;
  final Set<String> tags;

  CandidatesFilter copyWith({
    String? query,
    String? level,
    String? district,
    Set<String>? tags,
    bool clearQuery = false,
    bool clearLevel = false,
    bool clearDistrict = false,
    bool clearTags = false,
  }) {
    return CandidatesFilter(
      query: clearQuery ? null : (query ?? this.query),
      level: clearLevel ? null : (level ?? this.level),
      district: clearDistrict ? null : (district ?? this.district),
      tags: clearTags
          ? {}
          : (tags != null
              ? Set<String>.from(tags)
              : Set<String>.from(this.tags)),
    );
  }

  bool get isEmpty =>
      (query == null || query!.isEmpty) &&
      (level == null || level!.isEmpty) &&
      (district == null || district!.isEmpty) &&
      tags.isEmpty;

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (query != null && query!.trim().isNotEmpty) {
      params['q'] = query!.trim();
    }
    if (level != null && level!.trim().isNotEmpty) {
      params['level'] = level!.trim();
    }
    if (district != null && district!.trim().isNotEmpty) {
      params['district'] = district!.trim();
    }
    if (tags.isNotEmpty) {
      params['tags'] = tags.join(',');
    }
    return params;
  }

  @override
  List<Object?> get props => <Object?>[query, level, district, tags];
}
