import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:coalition_app_v2/features/engagement/models/liker.dart';
import 'package:coalition_app_v2/core/ids.dart'
    show isValidPostId, normalizePostId;

import '../../../services/api_client.dart';

class LikeActionResult {
  const LikeActionResult({
    required this.liked,
    required this.likesCount,
  });

  final bool liked;
  final int likesCount;
}

class EngagementRepository {
  EngagementRepository({required ApiClient apiClient}) : _api = apiClient;

  final ApiClient _api;

  Future<Map<String, dynamic>?> fetchSummary(String postId) async {
    if (!isValidPostId(postId)) {
      return null; // don't hit /engagement for invalid ids
    }
    final encoded = _encodePostId(postId, allowEmpty: true);
    if (encoded == null) {
      return null;
    }

    final response = await _api.get('/api/posts/$encoded/engagement');
    if (response.statusCode == HttpStatus.notFound) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[EngagementRepository] fetchSummary failed '
        '(${response.statusCode}) body=${response.body}',
      );
      return null;
    }
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (body is Map<String, dynamic>) {
      return body;
    }
    return null;
  }

  Future<LikeActionResult> like(String postId) async {
    final encoded = _encodePostId(postId);
    final response = await _api.postJson(
      '/api/posts/$encoded/like',
      body: const <String, dynamic>{},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to like post: ${response.statusCode}');
    }
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      return const LikeActionResult(liked: true, likesCount: 0);
    }
    return _parseLikeActionResult(body);
  }

  Future<LikeActionResult> unlike(String postId) async {
    final encoded = _encodePostId(postId);
    final response = await _api.deleteJson('/api/posts/$encoded/like');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to unlike post: ${response.statusCode}');
    }
    final body = response.body.isEmpty ? null : jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      return const LikeActionResult(liked: false, likesCount: 0);
    }
    return _parseLikeActionResult(body);
  }

  Future<LikersPage> fetchLikers(
    String postId, {
    int limit = 50,
    String? cursor,
  }) {
    return _api.getPostLikers(postId, limit: limit, cursor: cursor);
  }

  String? _encodePostId(String postId, {bool allowEmpty = false}) {
    final normalized = normalizePostId(postId);
    if (normalized.isEmpty) {
      if (allowEmpty) {
        return null;
      }
      throw ArgumentError('postId must not be empty');
    }
    return Uri.encodeComponent(normalized);
  }

  LikeActionResult _parseLikeActionResult(Map<String, dynamic> body) {
    final liked = body['liked'] == true;
    final likesCount = (body['likesCount'] as num?)?.toInt();
    final safeCount = likesCount != null && likesCount >= 0 ? likesCount : 0;
    return LikeActionResult(liked: liked, likesCount: safeCount);
  }
}
