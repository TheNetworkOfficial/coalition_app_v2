import 'package:coalition_app_v2/features/events/models/event.dart';
import 'package:coalition_app_v2/features/events/models/event_filter.dart';
import 'package:coalition_app_v2/services/api_client.dart';

class EventsRepository {
  const EventsRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<({List<Event> items, String? cursor})> list({
    int limit = 20,
    String? cursor,
    EventFilter? filter,
  }) {
    return apiClient.getEvents(
      limit: limit,
      cursor: cursor,
      tags: filter?.tags.isEmpty ?? true ? null : filter?.tags.join(','),
      town: filter?.town,
      after: filter?.after,
      query: filter?.query,
    );
  }

  Future<Event> getEvent(String id) {
    return apiClient.getEvent(id);
  }

  Future<({bool isAttending, int attendeeCount, Event? event})> signup(
    String id,
  ) {
    return apiClient.signupForEvent(id);
  }

  Future<({bool isAttending, int attendeeCount, Event? event})> cancelSignup(
    String id,
  ) {
    return apiClient.cancelEventSignup(id);
  }
}
