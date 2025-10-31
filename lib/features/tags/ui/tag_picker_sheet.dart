import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tag_models.dart';
import '../providers/tag_catalog_providers.dart';

class TagPickerSheet extends ConsumerStatefulWidget {
  const TagPickerSheet({
    super.key,
    required this.initiallySelected,
    this.maxSelection = 5,
  });

  final List<String> initiallySelected;
  final int maxSelection;

  @override
  ConsumerState<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<TagPickerSheet> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initiallySelected
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final asyncCatalog = ref.watch(tagCatalogProvider);
    final categories = asyncCatalog.asData?.value ?? const <TagCategory>[];
    final isLoading = asyncCatalog.isLoading && categories.isEmpty;
    final hasError = asyncCatalog.hasError;
    final size = MediaQuery.of(context).size;
    final maxHeight = (size.height * 0.8).clamp(320.0, 720.0);

    final knownValues = <String>{};
    for (final category in categories) {
      for (final tag in category.tags) {
        knownValues.add(tag.value);
      }
    }
    final unknownSelected = _selected
        .where((value) => !knownValues.contains(value))
        .toList(growable: false);

    Widget body;
    if (isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (hasError && categories.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Failed to load tags. Showing any existing selections.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (unknownSelected.isNotEmpty)
            _LegacySelectionSection(
              values: unknownSelected,
              onToggle: _handleToggle,
              maxReached: _maxReached,
            ),
          for (final category in categories)
            ExpansionTile(
              initiallyExpanded:
                  categories.indexOf(category) == 0 && unknownSelected.isEmpty,
              title: Text(category.name),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in category.tags)
                        FilterChip(
                          label: Text(tag.label),
                          selected: _selected.contains(tag.value),
                          onSelected: (isSelected) =>
                              _handleChipToggle(tag.value, isSelected),
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      );
    }

    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Select up to ${widget.maxSelection} tags',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(child: body),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text('${_selected.length}/${widget.maxSelection} selected'),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pop<List<String>>(null),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context)
                        .pop<List<String>>(_selected.toList(growable: false)),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _maxReached =>
      _selected.length >= widget.maxSelection && widget.maxSelection > 0;

  void _handleChipToggle(String value, bool isSelected) {
    setState(() {
      if (isSelected) {
        if (!_selected.contains(value) && !_maxReached) {
          _selected.add(value);
        }
      } else {
        _selected.remove(value);
      }
    });
  }

  void _handleToggle(String value) {
    final isSelected = _selected.contains(value);
    _handleChipToggle(value, !isSelected);
  }
}

class _LegacySelectionSection extends StatelessWidget {
  const _LegacySelectionSection({
    required this.values,
    required this.onToggle,
    required this.maxReached,
  });

  final List<String> values;
  final ValueChanged<String> onToggle;
  final bool maxReached;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      initiallyExpanded: true,
      title: const Text('Existing selections'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values
                .map(
                  (value) => FilterChip(
                    label: Text(value),
                    selected: true,
                    onSelected: (_) => onToggle(value),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        if (maxReached)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Unselect a tag to add new ones.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
