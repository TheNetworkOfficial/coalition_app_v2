import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/events/models/event.dart';
import '../features/events/providers/events_providers.dart';
import '../features/events/ui/events_filter_sheet.dart';

class EventsPage extends ConsumerWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncEvents = ref.watch(eventsPagerProvider);
    final pager = ref.watch(eventsPagerProvider.notifier);

    final Widget mainChild = asyncEvents.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load events: $error'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => pager.refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 48, bottom: 24),
              children: const [
                Center(child: Text('No events yet.')),
              ],
            ),
          );
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.maxScrollExtent == double.infinity) {
              return false;
            }
            final double threshold =
                (metrics.viewportDimension * 1.2).clamp(300.0, 800.0).toDouble();
            final remaining = metrics.extentAfter;
            final bool atVirtualEnd =
                metrics.maxScrollExtent == 0 &&
                    notification is OverscrollNotification &&
                    notification.overscroll > 0;
            final bool nearEnd = metrics.pixels > 0 && remaining <= threshold;
            if ((atVirtualEnd || nearEnd) &&
                pager.hasMore &&
                !pager.isLoading) {
              unawaited(pager.loadMore());
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () => pager.refresh(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                var viewportHeight = constraints.maxHeight;
                if (!viewportHeight.isFinite || viewportHeight <= 0) {
                  final media = MediaQuery.of(context);
                  viewportHeight = media.size.height -
                      media.padding.top -
                      media.padding.bottom;
                }

                final showLoader = pager.isLoading && pager.hasMore;
                final itemCount = items.length + (showLoader ? 1 : 0);

                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    if (index >= items.length) {
                      return SizedBox(
                        height: viewportHeight,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final event = items[index];
                    return SizedBox(
                      height: viewportHeight,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: EventListCard(
                          event: event,
                          fillHeight: true,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );

    return Scaffold(
      body: SafeArea(
        top: true,
        child: Stack(
          children: [
            Positioned.fill(child: mainChild),
            Positioned(
              top: 8,
              right: 12,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.search),
                tooltip: 'Browse by focus area',
                onPressed: () => showEventsFilterSheet(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EventListCard extends StatelessWidget {
  const EventListCard({
    super.key,
    required this.event,
    this.fillHeight = false,
  });

  final Event event;
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return _EventListCard(
      event: event,
      onOpen: () {
        final id = event.eventId.trim();
        if (id.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Event unavailable: missing event id',
              ),
            ),
          );
          return;
        }
        assert(() {
          debugPrint('Open event → $id');
          return true;
        }());
        context.pushNamed(
          'event_view',
          pathParameters: {'id': id},
        );
      },
      fullHeight: fillHeight,
    );
  }
}

class _EventListCard extends StatelessWidget {
  const _EventListCard({
    required this.event,
    required this.onOpen,
    this.fullHeight = false,
  });

  final Event event;
  final VoidCallback onOpen;
  final bool fullHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = event.title.isEmpty ? 'Untitled event' : event.title;
    final desc = event.description;
    final tags = event.tags.take(5).toList();

    final actionButton = FilledButton.icon(
      onPressed: onOpen,
      icon: const Icon(Icons.open_in_new),
      label: const Text('Learn more'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: theme.textTheme.labelLarge,
      ),
    );

    final children = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundImage: (event.imageUrl != null &&
                    event.imageUrl!.trim().isNotEmpty)
                ? NetworkImage(event.imageUrl!)
                : null,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
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
                    _InfoChip(
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
                      _InfoChip(
                        label: event.displayTown,
                        large: true,
                      ),
                    if (event.isFree)
                      const _InfoChip(
                        icon: Icons.sell_outlined,
                        label: 'Free',
                        large: true,
                      )
                    else if (event.costAmount != null)
                      _InfoChip(
                        icon: Icons.attach_money,
                        label: '\$${event.costAmount!.toStringAsFixed(2)}',
                        large: true,
                      ),
                    _InfoChip(
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
              tags.map((t) => _TagChip(label: t, large: true)).toList(),
        ),
      ],
      fullHeight ? const Spacer() : const SizedBox(height: 16),
      actionButton,
    ];

    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fullHeight ? MainAxisSize.max : MainAxisSize.min,
        children: children,
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: fullHeight ? SizedBox.expand(child: content) : content,
    );
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
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, this.icon, this.large = false});
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

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.large = false});
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
