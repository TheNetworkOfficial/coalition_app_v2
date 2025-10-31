import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/candidates_filter.dart';

class CandidatesFilterNotifier extends StateNotifier<CandidatesFilter> {
  CandidatesFilterNotifier() : super(const CandidatesFilter());

  void setQuery(String? query) {
    state = state.copyWith(query: query, clearQuery: query == null || query.isEmpty);
  }

  void setLevel(String? level) {
    state = state.copyWith(level: level, clearLevel: level == null || level.isEmpty);
  }

  void setDistrict(String? district) {
    state = state.copyWith(
      district: district,
      clearDistrict: district == null || district.isEmpty,
    );
  }

  void toggleTag(String tag) {
    final next = Set<String>.from(state.tags);
    if (next.contains(tag)) {
      next.remove(tag);
    } else {
      next.add(tag);
    }
    state = state.copyWith(tags: next);
  }

  void clearTags() {
    state = state.copyWith(clearTags: true);
  }

  void clearAll() {
    state = const CandidatesFilter();
  }

  void setFilter(CandidatesFilter filter) {
    state = filter;
  }
}

final candidatesFilterProvider =
    StateNotifierProvider<CandidatesFilterNotifier, CandidatesFilter>(
  (ref) => CandidatesFilterNotifier(),
);
