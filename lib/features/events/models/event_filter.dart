import 'package:equatable/equatable.dart';

class EventFilter extends Equatable {
  const EventFilter({
    this.query,
    this.town,
    Set<String>? tags,
    this.after,
  }) : tags = tags ?? const {};

  final String? query;
  final String? town;
  final Set<String> tags;
  final DateTime? after;

  EventFilter copyWith({
    String? query,
    String? town,
    Set<String>? tags,
    DateTime? after,
    bool clearQuery = false,
    bool clearTown = false,
    bool clearTags = false,
    bool clearAfter = false,
  }) {
    return EventFilter(
      query: clearQuery ? null : (query ?? this.query),
      town: clearTown ? null : (town ?? this.town),
      tags: clearTags
          ? {}
          : (tags != null
              ? Set<String>.from(tags)
              : Set<String>.from(this.tags)),
      after: clearAfter ? null : (after ?? this.after),
    );
  }

  bool get isEmpty =>
      (query == null || query!.isEmpty) &&
      (town == null || town!.isEmpty) &&
      tags.isEmpty &&
      after == null;

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (query != null && query!.trim().isNotEmpty) {
      params['q'] = query!.trim();
    }
    if (town != null && town!.trim().isNotEmpty) {
      params['town'] = town!.trim();
    }
    if (tags.isNotEmpty) {
      params['tags'] = tags.join(',');
    }
    if (after != null) {
      params['after'] = after!.toUtc().toIso8601String();
    }
    return params;
  }

  @override
  List<Object?> get props => <Object?>[query, town, tags, after];
}
