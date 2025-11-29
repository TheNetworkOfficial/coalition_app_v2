import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/candidates/ui/candidate_views.dart';
import '../features/events/models/event.dart';
import '../features/events/providers/events_providers.dart';
import '../features/events/services/event_calendar_service.dart';
import '../features/events/services/event_links.dart';
import '../features/events/ui/event_views.dart';

class EventViewerPage extends ConsumerStatefulWidget {
  const EventViewerPage({super.key, required this.eventId});

  final String eventId;

  @override
  ConsumerState<EventViewerPage> createState() => _EventViewerPageState();
}

class _EventViewerPageState extends ConsumerState<EventViewerPage> {
  bool _isToggling = false;

  @override
  Widget build(BuildContext context) {
    final eventAsync = ref.watch(eventDetailProvider(widget.eventId));

    return eventAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Event')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load event: $error'),
          ),
        ),
      ),
      data: (event) {
        if (event == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Event')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Event unavailable.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final theme = Theme.of(context);
        final socials = normalizedCandidateSocials(event.socials);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Event'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _refresh,
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                EventHeaderView(event: event),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    EventInfoChip(
                      label: event.displayHost,
                      icon: Icons.person_outline,
                      large: true,
                    ),
                    EventInfoChip(
                      label: event.displayTown,
                      icon: Icons.place_outlined,
                      large: true,
                    ),
                    EventInfoChip(
                      label: '${event.attendeeCount} attending',
                      icon: Icons.groups_outlined,
                      large: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (event.isFree || event.costAmount != null) ...[
                  const EventSectionTitle(text: 'Cost'),
                  const SizedBox(height: 8),
                  Text(
                    event.isFree
                        ? 'Free'
                        : event.costAmount != null
                            ? '\$${event.costAmount!.toStringAsFixed(2)}'
                            : 'Paid',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 16),
                ],
                if ((event.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const EventSectionTitle(text: 'About'),
                  const SizedBox(height: 8),
                  EventDescriptionView(description: event.description),
                ],
                if (event.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const EventSectionTitle(text: 'Tags'),
                  const SizedBox(height: 8),
                  EventTagsView(tags: event.tags),
                ],
                if ((event.address ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const EventSectionTitle(text: 'Address'),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => openMapsForAddress(context, event.address!),
                    child: Text(
                      event.address!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
                if (socials.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  CandidateSocialsView(
                    socials: socials,
                    title: const EventSectionTitle(text: 'Contact'),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isToggling
                            ? null
                            : () => _toggleAttendance(event),
                        icon: Icon(
                          event.isAttending
                              ? Icons.check
                              : Icons.event_available_outlined,
                        ),
                        label: Text(
                          event.isAttending ? 'Attending' : 'Sign up',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => addEventToCalendar(context, event),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: const Text('Add to calendar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(eventDetailProvider(widget.eventId));
    try {
      await ref.read(eventDetailProvider(widget.eventId).future);
    } catch (_) {}
  }

  Future<void> _toggleAttendance(Event event) async {
    if (_isToggling) {
      return;
    }
    setState(() => _isToggling = true);
    final messenger = ScaffoldMessenger.of(context);
    final desired = !event.isAttending;
    try {
      await ref
          .read(eventsPagerProvider.notifier)
          .optimisticToggleAttendance(event.eventId, desired);
    } catch (error) {
      if (mounted) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('Failed to update attendance: $error')),
          );
      }
    } finally {
      ref.invalidate(eventDetailProvider(event.eventId));
      try {
        await ref.read(eventDetailProvider(event.eventId).future);
      } catch (_) {}
      if (mounted) {
        setState(() => _isToggling = false);
      }
    }
  }
}
