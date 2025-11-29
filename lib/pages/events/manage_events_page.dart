import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/events/models/event.dart';
import '../../features/events/providers/events_providers.dart';
import '../../providers/app_providers.dart';
import '../../services/api_client.dart';

class ManageEventsPage extends ConsumerStatefulWidget {
  const ManageEventsPage({super.key});

  @override
  ConsumerState<ManageEventsPage> createState() => _ManageEventsPageState();
}

class _ManageEventsPageState extends ConsumerState<ManageEventsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage events'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'Previous'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          MyEventsTab(status: MyEventsStatus.active),
          MyEventsTab(status: MyEventsStatus.previous),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          if (_tabController.index != 0) {
            return const SizedBox.shrink();
          }
          return child ?? const SizedBox.shrink();
        },
        child: FloatingActionButton(
          onPressed: () => context.goNamed('event_create'),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class MyEventsTab extends ConsumerWidget {
  const MyEventsTab({super.key, required this.status});

  final MyEventsStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEvents = ref.watch(myEventsProvider(status));
    Future<void> refresh() =>
        ref.refresh(myEventsProvider(status).future).then((_) {});

    return asyncEvents.when(
      data: (events) {
        if (events.isEmpty) {
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No events.')),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final event = events[index];
              return ManageEventCard(
                event: event,
                onEdit: () => _onEditEvent(context, event),
                onDelete: () => _onDeleteEvent(context, ref, event),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load events: $error'),
        ),
      ),
    );
  }

  void _onEditEvent(BuildContext context, Event event) {
    final id = event.eventId.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot edit event: missing id')),
      );
      return;
    }
    context.pushNamed(
      'event_edit',
      pathParameters: {'id': id},
      extra: event,
    );
  }

  Future<void> _onDeleteEvent(
    BuildContext context,
    WidgetRef ref,
    Event event,
  ) async {
    final id = event.eventId.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete event: missing id')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete event?'),
            content: const Text('This will permanently remove the event.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final api = ref.read(apiClientProvider);
      await api.deleteEvent(id);
      ref.invalidate(eventsPagerProvider);
      ref.invalidate(myEventsProvider(MyEventsStatus.active));
      ref.invalidate(myEventsProvider(MyEventsStatus.previous));
      ref.invalidate(eventDetailProvider(id));
      messenger.showSnackBar(
        const SnackBar(content: Text('Event deleted')),
      );
    } on ApiException catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete event: $error')),
      );
    }
  }
}

class ManageEventCard extends StatelessWidget {
  const ManageEventCard({
    super.key,
    required this.event,
    required this.onEdit,
    required this.onDelete,
  });

  final Event event;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = event.title.isEmpty ? 'Untitled event' : event.title;
    final desc = event.description;
    final tags = event.tags.take(5).toList();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: (event.imageUrl != null &&
                          event.imageUrl!.trim().isNotEmpty)
                      ? NetworkImage(event.imageUrl!)
                      : null,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: (event.imageUrl != null &&
                          event.imageUrl!.trim().isNotEmpty)
                      ? null
                      : const Icon(Icons.event),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _ManageInfoChip(
                            label: _formatDateRange(
                              context,
                              event.startAt,
                              event.endAt,
                            ),
                            large: true,
                          ),
                          if ((event.locationTown ?? event.locationName)
                                  ?.isNotEmpty ??
                              false)
                            _ManageInfoChip(
                              label: event.displayTown,
                              large: true,
                            ),
                          if (event.isFree)
                            const _ManageInfoChip(
                              icon: Icons.sell_outlined,
                              label: 'Free',
                              large: true,
                            )
                          else if (event.costAmount != null)
                            _ManageInfoChip(
                              icon: Icons.attach_money,
                              label: '\$${event.costAmount!.toStringAsFixed(2)}',
                              large: true,
                            ),
                          _ManageInfoChip(
                            icon: Icons.people_alt_outlined,
                            label: '${event.attendeeCount}',
                            large: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (desc != null && desc.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                desc.trim(),
                style: theme.textTheme.bodyLarge,
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    tags.map((t) => _ManageTagChip(label: t, large: true)).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onEdit,
                  child: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onDelete,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDateRange(
  BuildContext context,
  DateTime start,
  DateTime? end,
) {
  final localizations = MaterialLocalizations.of(context);
  final startDate = localizations.formatShortDate(start);
  final startTime = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(start),
    alwaysUse24HourFormat: false,
  );
  if (end == null) {
    return '$startDate · $startTime';
  }
  final endDate = localizations.formatShortDate(end);
  final endTime = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(end),
    alwaysUse24HourFormat: false,
  );
  final sameDay = start.year == end.year &&
      start.month == end.month &&
      start.day == end.day;
  if (sameDay) {
    return '$startDate · $startTime–$endTime';
  }
  return '$startDate $startTime – $endDate $endTime';
}

class _ManageInfoChip extends StatelessWidget {
  const _ManageInfoChip({required this.label, this.icon, this.large = false});
  final String label;
  final IconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = (large
            ? Theme.of(context).textTheme.labelLarge
            : Theme.of(context).textTheme.labelMedium)
        ?.copyWith(fontWeight: FontWeight.w600);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 10,
        vertical: large ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: large ? 18 : 16),
            const SizedBox(width: 6),
          ],
          Text(label, style: style),
        ],
      ),
    );
  }
}

class _ManageTagChip extends StatelessWidget {
  const _ManageTagChip({required this.label, this.large = false});
  final String label;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = large
        ? Theme.of(context).textTheme.labelLarge
        : Theme.of(context).textTheme.labelMedium;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 10,
        vertical: large ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(label, style: style),
    );
  }
}
