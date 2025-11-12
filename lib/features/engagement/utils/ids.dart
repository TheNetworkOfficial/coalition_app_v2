library ids;

const _badPrefixes = <String>[
  'remote-',
  'fallback-',
  'img-',
  'test-image-',
];

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final RegExp _ulid = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');

bool isValidPostId(String? id) {
  if (id == null) return false;
  final s = id.trim();
  if (s.isEmpty) return false;
  for (final prefix in _badPrefixes) {
    if (s.startsWith(prefix)) {
      return false;
    }
  }
  return _uuidV4.hasMatch(s) || _ulid.hasMatch(s);
}

String normalizePostId(String? id) {
  final s = id?.trim() ?? '';
  return isValidPostId(s) ? s : '';
}

/// Utility kept here so call sites only import a single ids helper.
String normalizeUserId(Object? raw) {
  return (raw ?? '').toString().trim();
}
