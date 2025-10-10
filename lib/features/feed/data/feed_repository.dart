import 'dart:convert';

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
        return _fallbackPostsShuffled();
      }

      final dynamic body;
      try {
        body = response.body.isEmpty ? null : jsonDecode(response.body);
      } on FormatException catch (error) {
        _logFallback('Failed to decode feed response: $error');
        return _fallbackPostsShuffled();
      }

      final rawItems = _extractItems(body);
      final posts = <Post>[];
      for (var i = 0; i < rawItems.length; i++) {
        final raw = rawItems[i];
        if (raw is Map<String, dynamic>) {
          try {
            posts.add(Post.fromJson(raw, fallbackId: 'remote-$i'));
          } catch (error, stackTrace) {
            debugPrint(
              '[FeedRepository] Skipping malformed feed item: $error\n$stackTrace',
            );
          }
        }
      }

      if (posts.isNotEmpty) {
        final shuffled = List<Post>.of(posts)..shuffle();
        return shuffled;
      }

      _logFallback('GET /api/feed returned no usable items');
    } catch (error, stackTrace) {
      _logFallback('Error loading feed: $error', stackTrace);
    }

    return _fallbackPostsShuffled();
  }

  static const bool _fallbackEnabled = bool.fromEnvironment(
    'FEED_REPOSITORY_ENABLE_FALLBACK',
    defaultValue: true,
  );

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

  static List<Post> _fallbackPostsShuffled() {
    if (!_fallbackEnabled) {
      return const [];
    }

    final posts = List<Post>.of(_fallbackPosts);
    posts.shuffle();
    return posts;
  }

  static const List<Post> _fallbackPosts = [
    Post(
      id: 'fallback-1',
      userId: 'creator-1',
      userDisplayName: 'Jordan Miles',
      userAvatarUrl: 'https://i.pravatar.cc/150?img=47',
      description: 'Exploring downtown at night. Lights for days!',
      mediaUrl: 'https://samplelib.com/lib/preview/mp4/sample-5s.mp4',
      thumbUrl:
          'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=800',
      isVideo: true,
      type: 'video',
      status: PostStatus.ready,
    ),
    Post(
      id: 'fallback-2',
      userId: 'creator-2',
      userDisplayName: 'Alexandria N.',
      userAvatarUrl: 'https://i.pravatar.cc/150?img=12',
      description: 'Sunrise hikes are the best motivation.',
      mediaUrl:
          'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1200',
      thumbUrl:
          'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=600',
      isVideo: false,
      type: 'image',
      status: PostStatus.ready,
    ),
    Post(
      id: 'fallback-3',
      userId: 'creator-3',
      userDisplayName: 'Chef W.',
      userAvatarUrl: 'https://i.pravatar.cc/150?img=5',
      description: 'New recipe drop 🍝 What do you think?',
      mediaUrl:
          'https://images.unsplash.com/photo-1528712306091-ed0763094c98?w=1200',
      thumbUrl:
          'https://images.unsplash.com/photo-1528712306091-ed0763094c98?w=600',
      isVideo: false,
      type: 'image',
      status: PostStatus.ready,
    ),
    Post(
      id: 'fallback-4',
      userId: 'creator-4',
      userDisplayName: 'RunWithMe',
      userAvatarUrl: 'https://i.pravatar.cc/150?img=20',
      description: 'Training montage – day 42. Keep pushing!',
      mediaUrl: 'https://samplelib.com/lib/preview/mp4/sample-10s.mp4',
      thumbUrl:
          'https://images.unsplash.com/photo-1517964106626-460c6a3b8964?w=800',
      isVideo: true,
      type: 'video',
      status: PostStatus.ready,
    ),
    Post(
      id: 'fallback-5',
      userId: 'creator-5',
      userDisplayName: 'Aria Bloom',
      userAvatarUrl: 'https://i.pravatar.cc/150?img=31',
      description: 'Studio day. Can’t wait for you to hear this track.',
      mediaUrl:
          'https://images.unsplash.com/photo-1485579149621-3123dd979885?w=1200',
      thumbUrl:
          'https://images.unsplash.com/photo-1485579149621-3123dd979885?w=600',
      isVideo: false,
      type: 'image',
      status: PostStatus.ready,
    ),
  ];
}
