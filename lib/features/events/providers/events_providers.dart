import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../providers/app_providers.dart';
import '../../../services/api_client.dart';
import '../data/events_repository.dart';
import '../models/event.dart';
import '../models/event_filter.dart';
import 'events_filter_provider.dart';

enum MyEventsStatus { active, previous }

class EventsPager extends StateNotifier<AsyncValue<List<Event>>> {
  EventsPager(this._ref) : super(const AsyncValue.loading()) {
    _filter = _ref.read(eventFilterProvider);
    unawaited(_load(reset: true));
  }

  final Ref _ref;
  final List<Event> _items = <Event>[];
  String? _cursor;
  bool _hasMore = true;
  bool _isLoading = false;
  late EventFilter _filter;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;

  EventsRepository _repositoryForRead() {
    final apiClient = _ref.read(apiClientProvider);
    return EventsRepository(apiClient: apiClient);
  }

  Future<void> refresh() => _load(reset: true);

  Future<void> loadMore() => _load(reset: false);

  Future<void> _load({required bool reset}) async {
    if (_isLoading) {
      return;
    }
    if (!reset && !_hasMore) {
      return;
    }
    _isLoading = true;

    if (reset) {
      _cursor = null;
      _hasMore = true;
      _items.clear();
      state = const AsyncValue.loading();
    }

    final repository = _repositoryForRead();
    try {
      final page = await repository.list(
        limit: 20,
        cursor: _cursor,
        filter: _filter,
      );
      _mergeItems(page.items, reset: reset);
      _cursor = page.cursor;
      _hasMore = _cursor != null && _cursor!.isNotEmpty;
      state = AsyncValue.data(List<Event>.unmodifiable(_items));
    } catch (error, stackTrace) {
      if (reset && _items.isEmpty) {
        state = AsyncValue.error(error, stackTrace);
      } else {
        if (kDebugMode) {
          debugPrint('Failed to load events: $error');
        }
        state = AsyncValue.data(List<Event>.unmodifiable(_items));
      }
      return;
    } finally {
      _isLoading = false;
    }
  }

  Future<void> optimisticToggleAttendance(String id, bool attend) async {
    final index = _items.indexWhere((event) => event.eventId == id);
    if (index < 0) {
      final repository = _repositoryForRead();
      if (attend) {
        await repository.signup(id);
      } else {
        await repository.cancelSignup(id);
      }
      return;
    }
    final previous = _items[index];
    final delta = attend ? 1 : -1;
    final updatedCount = max(0, previous.attendeeCount + delta);
    _items[index] = previous.copyWith(
      isAttending: attend,
      attendeeCount: updatedCount,
    );
    state = AsyncValue.data(List<Event>.unmodifiable(_items));

    final repository = _repositoryForRead();
    try {
      final response =
          attend ? await repository.signup(id) : await repository.cancelSignup(id);
      final latest = response.event ??
          previous.copyWith(
            isAttending: response.isAttending,
            attendeeCount: response.attendeeCount,
          );
      _items[index] = latest;
      state = AsyncValue.data(List<Event>.unmodifiable(_items));
    } catch (error, stackTrace) {
      _items[index] = previous;
      state = AsyncValue.data(List<Event>.unmodifiable(_items));
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> applyFilter(EventFilter filter) async {
    _filter = filter;
    await _load(reset: true);
  }

  void _mergeItems(List<Event> newItems, {required bool reset}) {
    final merged = reset ? <Event>[] : List<Event>.from(_items);
    final seenIndex = <String, int>{};

    for (var i = 0; i < merged.length; i++) {
      final id = merged[i].eventId.trim();
      if (id.isNotEmpty) {
        seenIndex[id] = i;
      }
    }

    for (final item in newItems) {
      final id = item.eventId.trim();
      if (id.isEmpty) {
        merged.add(item);
        continue;
      }
      final existingIndex = seenIndex[id];
      if (existingIndex != null) {
        merged[existingIndex] = item;
      } else {
        seenIndex[id] = merged.length;
        merged.add(item);
      }
    }

    _items
      ..clear()
      ..addAll(merged);
  }
}

final eventsRepositoryProvider = Provider<EventsRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return EventsRepository(apiClient: apiClient);
});

final eventsPagerProvider =
    StateNotifierProvider<EventsPager, AsyncValue<List<Event>>>(
  (ref) => EventsPager(ref),
);

final myEventsProvider =
    FutureProvider.family<List<Event>, MyEventsStatus>((ref, status) async {
  final api = ref.watch(apiClientProvider);
  final result = await api.getMyEvents(
    status: switch (status) {
      MyEventsStatus.active => 'active',
      MyEventsStatus.previous => 'previous',
    },
  );
  return result.items;
});

final eventDetailProvider = FutureProvider.family<Event?, String>((ref, id) async {
  final apiClient = ref.watch(apiClientProvider);
  final trimmed = id.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    final event = await apiClient.getEvent(trimmed);
    return event;
  } on ApiException catch (error) {
    if (error.statusCode == HttpStatus.notFound) {
      return null;
    }
    rethrow;
  }
});
