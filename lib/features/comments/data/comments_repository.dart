import 'dart:convert';

import '../../../services/api_client.dart';
import '../models/comment.dart';

class CommentsRepository {
  CommentsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<({List<Comment> items, String? cursor})> listComments(
    String postId, {
    String? cursor,
    int limit = 50,
  }) async {
    final trimmedId = postId.trim();
    if (trimmedId.isEmpty) {
      return (items: const <Comment>[], cursor: null);
    }

    final response = await _apiClient.get(
      '/api/posts/${Uri.encodeComponent(trimmedId)}/comments',
      queryParameters: {
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load comments: ${response.statusCode}');
    }

    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      return (items: const <Comment>[], cursor: null);
    }

    final rawItems = body['items'];
    final items = <Comment>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map<String, dynamic>) {
          items.add(Comment.fromJson(entry));
        }
      }
    }

    final nextCursor = body['cursor'];
    return (
      items: items,
      cursor: nextCursor is String && nextCursor.isNotEmpty ? nextCursor : null,
    );
  }

  Future<Comment> createComment(
    String postId, {
    required String text,
    String? replyTo,
  }) async {
    final trimmedId = postId.trim();
    if (trimmedId.isEmpty) {
      throw Exception('postId is required');
    }

    final payload = <String, dynamic>{'text': text};
    if (replyTo != null && replyTo.isNotEmpty) {
      payload['replyTo'] = replyTo;
    }

    final response = await _apiClient.postJson(
      '/api/posts/${Uri.encodeComponent(trimmedId)}/comments',
      body: payload,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to create comment: ${response.statusCode}');
    }

    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('Malformed create comment response');
    }

    final item = body['item'];
    if (item is! Map<String, dynamic>) {
      throw Exception('Missing comment payload');
    }

    return Comment.fromJson(item);
  }

  Future<bool> toggleLike(String commentId) async {
    final trimmedId = commentId.trim();
    if (trimmedId.isEmpty) {
      throw Exception('commentId is required');
    }

    final response = await _apiClient.postJson(
      '/api/comments/${Uri.encodeComponent(trimmedId)}/like',
      body: const <String, dynamic>{},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to toggle like: ${response.statusCode}');
    }

    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      return false;
    }

    final liked = body['liked'];
    return liked is bool ? liked : false;
  }
}
