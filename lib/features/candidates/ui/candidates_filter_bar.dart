import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/focus_tags.dart';
import '../models/candidates_filter.dart';
import '../providers/candidates_filter_provider.dart';
import '../providers/candidates_providers.dart';
import 'candidates_filter_sheet.dart';

class CandidatesFilterBar extends ConsumerWidget {
  const CandidatesFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(candidatesFilterProvider);
    final hasActiveFilters = !filter.isEmpty;

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, hasActiveFilters ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              readOnly: true,
              showCursor: false,
              onTap: () => showCandidatesFilterSheet(context, ref),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Browse by focus area',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if ((filter.level ?? '').isNotEmpty)
                    FilterChip(
                      label: Text(_levelDisplay(filter.level!)),
                      selected: true,
                      onSelected: (_) =>
                          _applyFilter(ref, filter.copyWith(clearLevel: true)),
                    ),
                  if ((filter.query ?? '').isNotEmpty)
                    FilterChip(
                      label: Text('“${filter.query}”'),
                      selected: true,
                      onSelected: (_) =>
                          _applyFilter(ref, filter.copyWith(clearQuery: true)),
                    ),
                  for (final tag in filter.tags)
                    FilterChip(
                      label: Text(_tagLabel(tag)),
                      selected: true,
                      onSelected: (_) => _applyFilter(
                        ref,
                        filter.copyWith(
                          tags: Set<String>.from(filter.tags)..remove(tag),
                        ),
                      ),
                    ),
                  if (filter.tags.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          _applyFilter(ref, filter.copyWith(clearTags: true)),
                      child: const Text('Clear tags'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _applyFilter(WidgetRef ref, CandidatesFilter filter) {
    ref.read(candidatesFilterProvider.notifier).setFilter(filter);
    unawaited(ref.read(candidatesPagerProvider.notifier).applyFilter(filter));
  }
}
String _tagLabel(String canonical) {
  for (final section in kFocusAreaTags.values) {
    for (final mapping in section) {
      final label = mapping.keys.first;
      final value = mapping.values.first;
      if (value == canonical) {
        return label;
      }
    }
  }
  return canonical;
}

String _levelDisplay(String raw) {
  switch (raw.toLowerCase()) {
    case 'federal':
      return 'Federal';
    case 'state':
      return 'State';
    case 'county':
      return 'County';
    case 'city':
      return 'City/Township';
    default:
      return raw;
  }
}
