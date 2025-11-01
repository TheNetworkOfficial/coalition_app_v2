import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/focus_tags.dart';
import '../models/candidates_filter.dart';
import '../providers/candidates_filter_provider.dart';
import '../providers/candidates_providers.dart';
import '../../tags/models/tag_models.dart';
import '../../tags/providers/tag_catalog_providers.dart';

/// Opens the reusable Candidates filter/search sheet.
Future<void> showCandidatesFilterSheet(BuildContext context, WidgetRef ref) async {
  final current = ref.read(candidatesFilterProvider);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _FilterSheet(initial: current),
  );
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final CandidatesFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late final TextEditingController _queryController;
  late String? _level;
  late Set<String> _tags;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initial.query ?? '');
    _level = widget.initial.level;
    _tags = Set<String>.from(widget.initial.tags);
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).viewInsets.bottom + 24.0;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final asyncCatalog = ref.watch(tagCatalogProvider);
    final categories =
        asyncCatalog.asData?.value ?? const <TagCategory>[];
    final loadingCatalog = asyncCatalog.isLoading && categories.isEmpty;
    final catalogError = asyncCatalog.hasError;

    final tagSections = <Widget>[];
    if (loadingCatalog) {
      tagSections.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    } else if (categories.isEmpty) {
      final message = catalogError
          ? 'Failed to load tags. Try again later.'
          : 'No tags available yet.';
      tagSections.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    } else {
      for (var index = 0; index < categories.length; index += 1) {
        final category = categories[index];
        tagSections.add(
          ExpansionTile(
            initiallyExpanded: index == 0,
            title: Text(category.name),
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: category.tags.map((tag) {
                    final selected = _tags.contains(tag.value);
                    return FilterChip(
                      label: Text(tag.label),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          selected
                              ? _tags.remove(tag.value)
                              : _tags.add(tag.value);
                        });
                      },
                    );
                  }).toList(growable: false),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, pad),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          children: [
            if (isIOS)
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            TextField(
              controller: _queryController,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search by name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _levelDisplayNullable(_level),
              decoration: const InputDecoration(
                labelText: 'Government level',
                border: OutlineInputBorder(),
              ),
              items: kGovernmentLevels
                  .map(
                    (level) => DropdownMenuItem<String>(
                      value: level,
                      child: Text(level),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                setState(() {
                  _level = _levelFromDisplay(value);
                });
              },
            ),
            const SizedBox(height: 12),
            ...tagSections,
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _tags.clear();
                    });
                  },
                  child: const Text('Clear tags'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () {
                    final next = CandidatesFilter(
                      query: _queryController.text.trim().isEmpty
                          ? null
                          : _queryController.text.trim(),
                      level: _level,
                      district: widget.initial.district,
                      tags: _tags,
                    );
                    ref.read(candidatesFilterProvider.notifier).setFilter(next);
                    unawaited(
                      ref.read(candidatesPagerProvider.notifier).applyFilter(next),
                    );
                    Navigator.of(context).pop();
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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

String _levelDisplayNullable(String? value) {
  if (value == null || value.isEmpty) {
    return kGovernmentLevels.first;
  }
  return _levelDisplay(value);
}

String? _levelFromDisplay(String? display) {
  if (display == null || display == kGovernmentLevels.first) {
    return null;
  }
  switch (display) {
    case 'Federal':
      return 'federal';
    case 'State':
      return 'state';
    case 'County':
      return 'county';
    case 'City/Township':
      return 'city';
  }
  return display.toLowerCase();
}
