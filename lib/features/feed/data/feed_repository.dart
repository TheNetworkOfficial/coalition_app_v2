import 'dart:convert';

import 'package:coalition_app_v2/core/ids.dart' show isValidPostId;
import 'package:flutter/foundation.dart';

import '../../../services/api_client.dart';
import '../models/post.dart';

class FeedRepository {
  FeedRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<List<Post>> getFeed() async {
    try {
      final response = await _apiClient.get('/api/feed');
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logFallback(
          'GET /api/feed failed with status ${response.statusCode}',
        );
        return const [];
      }

      final dynamic body;
      try {
        body = response.body.isEmpty ? null : jsonDecode(response.body);
      } on FormatException catch (error) {
        _logFallback('Failed to decode feed response: $error');
        return const [];
      }

      final rawItems = _extractItems(body);
      final posts = <Post>[];
      for (var i = 0; i < rawItems.length; i++) {
        final raw = rawItems[i];
        if (raw is Map<String, dynamic>) {
          try {
            final post = Post.fromJson(raw);
            posts.add(post);
          } catch (error, stackTrace) {
            debugPrint(
              '[FeedRepository] Skipping malformed feed item: $error\n$stackTrace',
            );
          }
        }
      }

      final items = posts.where((post) => isValidPostId(post.id)).toList();
      if (items.isEmpty) {
        _logFallback('GET /api/feed returned no usable items');
      }
      return items;
    } catch (error, stackTrace) {
      _logFallback('Error loading feed: $error', stackTrace);
    }

    return const [];
  }

  static bool _hasLoggedFallback = false;

  static void _logFallback(String message, [StackTrace? stackTrace]) {
    if (_hasLoggedFallback) {
      return;
    }
    _hasLoggedFallback = true;

    final buffer = StringBuffer('[FeedRepository] $message');
    if (stackTrace != null) {
      buffer
        ..write('\n')
        ..write(stackTrace);
    }
    debugPrint(buffer.toString());
  }

  static List<dynamic> _extractItems(dynamic body) {
    if (body is List) {
      return body;
    }
    if (body is Map<String, dynamic>) {
      final possibleKeys = ['items', 'data', 'results', 'posts', 'feed'];
      for (final key in possibleKeys) {
        final value = body[key];
        if (value is List) {
          return value;
        }
      }
    }
    return const [];
  }
}
