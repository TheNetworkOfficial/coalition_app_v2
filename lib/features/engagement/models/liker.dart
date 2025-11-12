import 'package:flutter/foundation.dart';

class Liker {
  const Liker({
    required this.userId,
    this.displayName,
    this.avatarUrl,
    this.createdAt,
  });

  factory Liker.fromJson(Map<String, dynamic> json) {
    DateTime? parsedCreatedAt;
    final rawCreatedAt = json['createdAt'];
    if (rawCreatedAt is String) {
      parsedCreatedAt = DateTime.tryParse(rawCreatedAt);
    } else if (rawCreatedAt is num) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(
        rawCreatedAt.toInt(),
        isUtc: true,
      );
    }

    String _readString(String key) {
      final value = json[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      return '';
    }

    String? _readOptional(String key) {
      final value = json[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      return null;
    }

    return Liker(
      userId: _readString('userId'),
      displayName: _readOptional('displayName') ??
          _readOptional('name') ??
          _readOptional('username'),
      avatarUrl: _readOptional('avatarUrl') ??
          _readOptional('userAvatarUrl') ??
          _readOptional('profileImageUrl'),
      createdAt: parsedCreatedAt,
    );
  }

  final String userId;
  final String? displayName;
  final String? avatarUrl;
  final DateTime? createdAt;
}

@immutable
class LikersPage {
  const LikersPage({
    required this.items,
    this.nextCursor,
  });

  factory LikersPage.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = <Liker>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map<String, dynamic>) {
          items.add(Liker.fromJson(entry));
        }
      }
    }
    final rawCursor = json['nextCursor'] ?? json['cursor'];
    String? cursor;
    if (rawCursor is String && rawCursor.trim().isNotEmpty) {
      cursor = rawCursor.trim();
    }
    return LikersPage(items: items, nextCursor: cursor);
  }

  final List<Liker> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
