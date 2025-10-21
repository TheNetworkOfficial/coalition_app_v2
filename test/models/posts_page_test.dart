import 'package:flutter_test/flutter_test.dart';

import 'package:coalition_app_v2/models/posts_page.dart';

void main() {
  group('PostItem', () {
    test('parses optional duration and coerces numeric strings', () {
      final json = <String, dynamic>{
        'id': 'post_1',
        'createdAt': '2024-05-01T12:00:00Z',
        'durationMs': null,
        'width': '1080',
        'height': '0',
        'thumbUrl': 'https://example.com/thumb.jpg',
      };

      final item = PostItem.fromJson(json);

      expect(item.id, 'post_1');
      expect(item.durationMs, 0);
      expect(item.width, 1080);
      expect(item.height, 1); // coerced minimum
    });
  });

  group('PostsPage', () {
    test('parses list of PostItem and optional next cursor', () {
      final json = <String, dynamic>{
        'items': [
          {
            'id': 'post_1',
            'createdAt': '2024-05-01T12:00:00Z',
            'durationMs': 0,
            'width': 1080,
            'height': 1920,
            'thumbUrl': 'https://example.com/thumb.jpg',
          },
        ],
        'nextCursor': null,
      };

      final page = PostsPage.fromJson(json);

      expect(page.items, hasLength(1));
      expect(page.nextCursor, isNull);
    });
  });
}
