import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';
import '../models/tag_models.dart';

final eventTagCatalogProvider = FutureProvider<List<TagCategory>>((ref) async {
  final api = ref.read(apiClientProvider);
  final catalog = await api.getEventTagCatalog();
  if (catalog.isEmpty) {
    return const <TagCategory>[];
  }
  final sorted = List<TagCategory>.from(catalog)
    ..sort((a, b) => a.order.compareTo(b.order));
  return List<TagCategory>.unmodifiable(sorted);
});
