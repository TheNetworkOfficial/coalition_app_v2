import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/tags/models/tag_models.dart';
import '../../features/tags/providers/event_tag_catalog_providers.dart';
import '../../providers/app_providers.dart';

class AdminEventTagsPage extends ConsumerStatefulWidget {
  const AdminEventTagsPage({super.key});

  @override
  ConsumerState<AdminEventTagsPage> createState() => _AdminEventTagsPageState();
}

class _AdminEventTagsPageState extends ConsumerState<AdminEventTagsPage> {
  @override
  Widget build(BuildContext context) {
    final asyncCatalog = ref.watch(eventTagCatalogProvider);
    final categories = asyncCatalog.asData?.value ?? const <TagCategory>[];
    final isLoading = asyncCatalog.isLoading && categories.isEmpty;
    final hasError = asyncCatalog.hasError;

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (hasError && categories.isEmpty) {
      return _AdminTagsError(
        error: asyncCatalog.error,
        onRetry: () async {
          ref.invalidate(eventTagCatalogProvider);
          await ref.read(eventTagCatalogProvider.future);
        },
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(eventTagCatalogProvider);
        await ref.read(eventTagCatalogProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _handleAddCategory(context),
              icon: const Icon(Icons.add),
              label: const Text('Add category'),
            ),
          ),
          if (categories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'No event tag categories yet. Add one to get started.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          for (final category in categories) ...[
            const SizedBox(height: 16),
            _CategoryCard(
              category: category,
              onAddTag: () => _handleAddTag(context, category),
              onEditCategory: () => _handleEditCategory(context, category),
              onDeleteCategory: () => _handleDeleteCategory(context, category),
              onEditTag: (tag) => _handleEditTag(context, category, tag),
              onDeleteTag: (tag) => _handleDeleteTag(context, category, tag),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _handleAddCategory(BuildContext context) async {
    final result = await _showCategoryDialog(context);
    if (result == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    try {
      await api.createEventTagCategory(
        name: result.name,
        order: result.order ?? 0,
      );
      ref.invalidate(eventTagCatalogProvider);
      await ref.read(eventTagCatalogProvider.future);
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Category created')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to create category: $error')),
        );
    }
  }

  Future<void> _handleEditCategory(
    BuildContext context,
    TagCategory category,
  ) async {
    final result = await _showCategoryDialog(
      context,
      initialName: category.name,
      initialOrder: category.order,
    );
    if (result == null) {
      return;
    }
    final payloadName = result.name != category.name ? result.name : null;
    final payloadOrder =
        result.order != category.order ? result.order : null;
    if (payloadName == null && payloadOrder == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    try {
      await api.updateEventTagCategory(
        categoryId: category.categoryId,
        name: payloadName,
        order: payloadOrder,
      );
      ref.invalidate(eventTagCatalogProvider);
      await ref.read(eventTagCatalogProvider.future);
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Category updated')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to update category: $error')),
        );
    }
  }

  Future<void> _handleDeleteCategory(
    BuildContext context,
    TagCategory category,
  ) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Delete category',
      message:
          'Delete "${category.name}" and its ${category.tags.length} tag(s)?',
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    try {
      await api.deleteEventTagCategory(category.categoryId);
      ref.invalidate(eventTagCatalogProvider);
      await ref.read(eventTagCatalogProvider.future);
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Category deleted')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to delete category: $error')),
        );
    }
  }

  Future<void> _handleAddTag(
    BuildContext context,
    TagCategory category,
  ) async {
    final result = await _showTagDialog(context);
    if (result == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    try {
      final trimmedValue = result.value?.trim();
      await api.addEventTagToCategory(
        categoryId: category.categoryId,
        label: result.label,
        value: trimmedValue != null && trimmedValue.isNotEmpty
            ? trimmedValue
            : null,
      );
      ref.invalidate(eventTagCatalogProvider);
      await ref.read(eventTagCatalogProvider.future);
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Tag added')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to add tag: $error')),
        );
    }
  }

  Future<void> _handleEditTag(
    BuildContext context,
    TagCategory category,
    TagDefinition tag,
  ) async {
    final result = await _showTagDialog(
      context,
      initialLabel: tag.label,
      initialValue: tag.value,
    );
    if (result == null) {
      return;
    }
    final updatedLabel = result.label != tag.label ? result.label : null;
    final updatedValue = result.value != tag.value ? result.value : null;
    if (updatedLabel == null && updatedValue == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    try {
      await api.updateEventTagInCategory(
        categoryId: category.categoryId,
        tagId: tag.tagId,
        label: updatedLabel,
        value: updatedValue,
      );
      ref.invalidate(eventTagCatalogProvider);
      await ref.read(eventTagCatalogProvider.future);
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Tag updated')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to update tag: $error')),
        );
    }
  }

  Future<void> _handleDeleteTag(
    BuildContext context,
    TagCategory category,
    TagDefinition tag,
  ) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Delete tag',
      message: 'Delete "${tag.label}" from "${category.name}"?',
    );
    if (confirmed != true) {
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(apiClientProvider);
    try {
      await api.deleteEventTagInCategory(
        categoryId: category.categoryId,
        tagId: tag.tagId,
      );
      ref.invalidate(eventTagCatalogProvider);
      await ref.read(eventTagCatalogProvider.future);
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Tag deleted')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to delete tag: $error')),
        );
    }
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.onAddTag,
    required this.onEditCategory,
    required this.onDeleteCategory,
    required this.onEditTag,
    required this.onDeleteTag,
  });

  final TagCategory category;
  final VoidCallback onAddTag;
  final VoidCallback onEditCategory;
  final VoidCallback onDeleteCategory;
  final ValueChanged<TagDefinition> onEditTag;
  final ValueChanged<TagDefinition> onDeleteTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text('Order: ${category.order}'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: category.tags.isEmpty
                  ? [
                      Text(
                        'No tags yet.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.hintColor),
                      ),
                    ]
                  : category.tags
                      .map(
                        (tag) => InputChip(
                          label: Text('${tag.label} (${tag.value})'),
                          onPressed: () => onEditTag(tag),
                          onDeleted: () => onDeleteTag(tag),
                        ),
                      )
                      .toList(growable: false),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onAddTag,
                  icon: const Icon(Icons.add),
                  label: const Text('Add tag'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onEditCategory,
                  child: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onDeleteCategory,
                  child: Text(
                    'Delete',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminTagsError extends StatelessWidget {
  const _AdminTagsError({
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Failed to load event tag catalog: $error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDialogResult {
  const _CategoryDialogResult({required this.name, this.order});

  final String name;
  final int? order;
}

class _TagDialogResult {
  const _TagDialogResult({required this.label, this.value});

  final String label;
  final String? value;
}

Future<_CategoryDialogResult?> _showCategoryDialog(
  BuildContext context, {
  String? initialName,
  int? initialOrder,
}) {
  final nameController = TextEditingController(text: initialName ?? '');
  final orderController =
      TextEditingController(text: initialOrder?.toString() ?? '');
  final formKey = GlobalKey<FormState>();

  return showDialog<_CategoryDialogResult>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initialName == null ? 'Add category' : 'Edit category'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: orderController,
              decoration: const InputDecoration(
                labelText: 'Order (optional)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                final trimmed = value?.trim();
                if (trimmed == null || trimmed.isEmpty) {
                  return null;
                }
                return int.tryParse(trimmed) == null
                    ? 'Enter a whole number'
                    : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) {
              return;
            }
            final name = nameController.text.trim();
            final orderText = orderController.text.trim();
            Navigator.of(context).pop(
              _CategoryDialogResult(
                name: name,
                order: orderText.isEmpty ? null : int.tryParse(orderText),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<_TagDialogResult?> _showTagDialog(
  BuildContext context, {
  String? initialLabel,
  String? initialValue,
}) {
  final labelController = TextEditingController(text: initialLabel ?? '');
  final valueController = TextEditingController(text: initialValue ?? '');
  final formKey = GlobalKey<FormState>();

  return showDialog<_TagDialogResult>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initialLabel == null ? 'Add tag' : 'Edit tag'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Label',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Label is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: valueController,
              decoration: const InputDecoration(
                labelText: 'Value (optional)',
                border: OutlineInputBorder(),
                helperText: 'Defaults to label if left blank',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) {
              return;
            }
            final label = labelController.text.trim();
            final value = valueController.text.trim();
            Navigator.of(context).pop(
              _TagDialogResult(
                label: label,
                value: value.isEmpty ? null : value,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<bool?> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}
