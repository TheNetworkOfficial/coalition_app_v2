import 'package:flutter/material.dart';

import '../models/event.dart';

class EventHeaderView extends StatelessWidget {
  const EventHeaderView({
    super.key,
    required this.event,
  });

  final Event event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chips = <Widget>[
      EventInfoChip(
        label: _formatDateRange(context, event.startAt, event.endAt),
        icon: Icons.schedule_outlined,
      ),
      if ((event.locationTown ?? event.locationName)?.isNotEmpty ?? false)
        EventInfoChip(
          label: event.displayTown,
          icon: Icons.place_outlined,
        ),
      if (event.isFree)
        const EventInfoChip(
          label: 'Free',
          icon: Icons.sell_outlined,
        )
      else if (event.costAmount != null)
        EventInfoChip(
          label: '\$${event.costAmount!.toStringAsFixed(2)}',
          icon: Icons.attach_money,
        ),
    ];

    final imageUrl = event.imageUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: hasImage
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined, size: 48),
                      ),
                    ),
                  )
                : Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: Icon(Icons.event, size: 48),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          event.title.isNotEmpty ? event.title : 'Untitled event',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        if (chips.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
        if ((event.hostUsername ?? event.hostDisplayName)?.isNotEmpty ??
            false) ...[
          const SizedBox(height: 8),
          Text(
            'Hosted by ${event.displayHost}',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ],
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

class EventDescriptionView extends StatelessWidget {
  const EventDescriptionView({super.key, required this.description});

  final String? description;

  @override
  Widget build(BuildContext context) {
    final text = description?.trim();
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }
}

class EventTagsView extends StatelessWidget {
  const EventTagsView({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final filtered = tags
        .where((tag) => tag.trim().isNotEmpty)
        .map((tag) => tag.trim())
        .toList(growable: false);
    if (filtered.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final tag in filtered) Chip(label: Text(tag)),
      ],
    );
  }
}

class EventSectionTitle extends StatelessWidget {
  const EventSectionTitle({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
}

class EventInfoChip extends StatelessWidget {
  const EventInfoChip({super.key, required this.label, this.icon, this.large = false});

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
