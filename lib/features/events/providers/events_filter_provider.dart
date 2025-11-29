import 'package:flutter_riverpod/legacy.dart';

import '../models/event_filter.dart';

class EventFilterNotifier extends StateNotifier<EventFilter> {
  EventFilterNotifier() : super(const EventFilter());

  void setQuery(String? query) {
    state = state.copyWith(query: query, clearQuery: query == null || query.isEmpty);
  }

  void setTown(String? town) {
    state = state.copyWith(town: town, clearTown: town == null || town.isEmpty);
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

  void setAfter(DateTime? after) {
    state = state.copyWith(after: after, clearAfter: after == null);
  }

  void clearAll() {
    state = const EventFilter();
  }

  void setFilter(EventFilter filter) {
    state = filter;
  }
}

final eventFilterProvider =
    StateNotifierProvider<EventFilterNotifier, EventFilter>(
  (ref) => EventFilterNotifier(),
);
