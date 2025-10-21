import 'package:flutter/foundation.dart';

import 'package:coalition_app_v2/utils/cloudflare_stream.dart';

@immutable
class PostItem {
  const PostItem({
    required this.id,
    required this.createdAt,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.thumbUrl,
    required this.status,
    this.playbackUrl,
  });

  factory PostItem.fromJson(Map<String, dynamic> json) {
    String _requireString(String key) {
      final value = json[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      throw FormatException('Missing required string: $key');
    }

    int _readInt(Map<String, dynamic> source, String key,
        {int defaultValue = 0}) {
      final value = source[key];
      if (value is int) {
        return value;
      }
      if (value is double) {
        return value.round();
      }
      if (value is num) {
        return value.round();
      }
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          final parsed = int.tryParse(trimmed);
          if (parsed != null) {
            return parsed;
          }
        }
      }
      return defaultValue;
    }

    DateTime _parseCreatedAt(String raw) {
      try {
        return DateTime.parse(raw).toUtc();
      } catch (_) {
        throw FormatException('Invalid createdAt format');
      }
    }

    final id = _requireString('id');
    final createdAt = _parseCreatedAt(_requireString('createdAt'));
    final durationMs = _readInt(json, 'durationMs', defaultValue: 0);
    final width = _readInt(json, 'width', defaultValue: 0);
    final height = _readInt(json, 'height', defaultValue: 0);
    String _normalizeStatus(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      return 'UNKNOWN';
    }
    String? _sanitizeThumb(dynamic value) {
      if (value is! String) {
        return null;
      }
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final lower = trimmed.toLowerCase();
      final base = lower.split('?').first;
      if (base.endsWith('.m3u8')) {
        return null;
      }
      return trimmed;
    }

    final thumbUrl =
        _sanitizeThumb(json['thumbUrl']) ?? _sanitizeThumb(json['previewUrl']);
    String? _readString(Map<String, dynamic> source, String key) {
      final value = source[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      return null;
    }

    final playbackUrl = resolveCloudflareHlsUrl(json) ??
        _readString(json, 'playbackUrl') ??
        _readString(json, 'playback_url');
    final status = _normalizeStatus(json['status']);

    return PostItem(
      id: id,
      createdAt: createdAt,
      durationMs: durationMs,
      width: width <= 0 ? 1 : width,
      height: height <= 0 ? 1 : height,
      thumbUrl: thumbUrl,
      status: status,
      playbackUrl: playbackUrl,
    );
  }

  final String id;
  final DateTime createdAt;
  final int durationMs;
  final int width;
  final int height;
  final String? thumbUrl;
  final String status;
  final String? playbackUrl;

  Duration get duration => Duration(milliseconds: durationMs);

  double get aspectRatio => height <= 0 ? 1 : width / height;

  bool get isReady => status.toUpperCase() == 'READY';
  bool get isPending => status.toUpperCase() == 'PENDING';
}

@immutable
class PostsPage {
  PostsPage({
    required List<PostItem> items,
    required this.nextCursor,
  }) : items = List<PostItem>.unmodifiable(items);

  factory PostsPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw FormatException('PostsPage requires a list of items');
    }
    final items = <PostItem>[];
    for (final entry in rawItems) {
      if (entry is Map<String, dynamic>) {
        items.add(PostItem.fromJson(entry));
      }
    }
    final rawCursor = json['nextCursor'];
    String? cursor;
    if (rawCursor is String && rawCursor.trim().isNotEmpty) {
      cursor = rawCursor;
    }
    return PostsPage(
      items: items,
      nextCursor: cursor,
    );
  }

  final List<PostItem> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
