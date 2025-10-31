class TagDefinition {
  final String tagId;
  final String label;
  final String value;

  TagDefinition({
    required this.tagId,
    required this.label,
    required this.value,
  });

  factory TagDefinition.fromJson(Map<String, dynamic> json) => TagDefinition(
        tagId: (json['tagId'] as String).trim(),
        label: (json['label'] as String).trim(),
        value: (json['value'] as String).trim(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'tagId': tagId,
        'label': label,
        'value': value,
      };
}

class TagCategory {
  final String categoryId;
  final String name;
  final int order;
  final List<TagDefinition> tags;

  TagCategory({
    required this.categoryId,
    required this.name,
    required this.order,
    required this.tags,
  });

  factory TagCategory.fromJson(Map<String, dynamic> json) => TagCategory(
        categoryId: (json['categoryId'] as String).trim(),
        name: (json['name'] as String).trim(),
        order: (json['order'] as num?)?.toInt() ?? 0,
        tags: ((json['tags'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TagDefinition.fromJson)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'categoryId': categoryId,
        'name': name,
        'order': order,
        'tags': tags.map((tag) => tag.toJson()).toList(growable: false),
      };
}
