import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';
import '../../candidates/data/focus_tags.dart' as legacy;
import '../models/tag_models.dart';

final tagCatalogProvider = FutureProvider<List<TagCategory>>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final catalog = await api.getTagCatalog();
    if (catalog.isNotEmpty) {
      final sorted = List<TagCategory>.from(catalog)
        ..sort((a, b) => a.order.compareTo(b.order));
      return List<TagCategory>.unmodifiable(sorted);
    }
  } catch (_) {
    // Ignore errors and fall back to legacy constants.
  }

  final categories = <TagCategory>[];
  var index = 0;
  for (final entry in legacy.kFocusAreaTags.entries) {
    final tags = entry.value
        .map(
          (mapping) => TagDefinition(
            tagId: mapping.values.first,
            label: mapping.keys.first,
            value: mapping.values.first,
          ),
        )
        .toList(growable: false);
    categories.add(
      TagCategory(
        categoryId: 'legacy-$index',
        name: entry.key,
        order: index,
        tags: List<TagDefinition>.unmodifiable(tags),
      ),
    );
    index += 1;
  }

  return List<TagCategory>.unmodifiable(categories);
});
