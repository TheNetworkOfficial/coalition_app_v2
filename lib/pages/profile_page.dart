import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

enum UserPostStatus { processing, ready, failed }

class UserPost {
  UserPost({
    required this.id,
    required this.title,
    this.description,
    this.previewImageUrl,
    this.type,
    required this.status,
    this.createdAt,
  });

  factory UserPost.fromJson(
    Map<String, dynamic> json, {
    required String fallbackId,
  }) {
    String? asString(dynamic value) {
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is num) {
        return value.toString();
      }
      return null;
    }

    DateTime? parseDate(String? value) {
      if (value == null) {
        return null;
      }
      try {
        return DateTime.parse(value).toLocal();
      } catch (_) {
        return null;
      }
    }

    UserPostStatus parseStatus(dynamic value) {
      final normalized = asString(value)?.toLowerCase();
      switch (normalized) {
        case 'ready':
        case 'completed':
        case 'complete':
        case 'success':
        case 'published':
          return UserPostStatus.ready;
        case 'failed':
        case 'error':
        case 'errored':
        case 'cancelled':
        case 'canceled':
          return UserPostStatus.failed;
        default:
          return UserPostStatus.processing;
      }
    }

    final id = asString(json['id']) ??
        asString(json['postId']) ??
        asString(json['uuid']) ??
        fallbackId;

    final description = asString(json['description']) ??
        asString(json['caption']) ??
        asString(json['text']);

    final title = asString(json['title']) ??
        asString(json['name']) ??
        description ??
        'Untitled post';

    final previewImageUrl = asString(json['thumbnailUrl']) ??
        asString(json['previewImageUrl']) ??
        asString(json['coverUrl']) ??
        asString(json['posterUrl']) ??
        asString(json['imageUrl']);

    final type = asString(json['type']) ?? asString(json['mediaType']);

    final status = parseStatus(json['status'] ?? json['state']);

    final createdAt = parseDate(
          asString(json['createdAt']) ??
              asString(json['created_at']) ??
              asString(json['createdOn']) ??
              asString(json['created_on']),
        ) ??
        parseDate(asString(json['updatedAt']) ?? asString(json['updated_at']));

    return UserPost(
      id: id,
      title: title,
      description: description,
      previewImageUrl: previewImageUrl,
      type: type,
      status: status,
      createdAt: createdAt,
    );
  }

  final String id;
  final String title;
  final String? description;
  final String? previewImageUrl;
  final String? type;
  final UserPostStatus status;
  final DateTime? createdAt;
}

class _ProfilePageState extends State<ProfilePage> {
  static const _baseUrl = 'http://localhost:54321';
  static const _defaultPageSize = 10;

  final ScrollController _scrollController = ScrollController();
  final List<UserPost> _posts = [];

  bool _isInitialLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _nextPage = 1;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _fetchPosts(reset: true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPosts({bool reset = false}) async {
    if (_isLoadingMore) {
      return;
    }
    if (reset) {
      setState(() {
        _posts.clear();
        _nextPage = 1;
        _hasMore = true;
        _errorMessage = null;
        _isInitialLoading = true;
        _isLoadingMore = true;
      });
    } else {
      if (!_hasMore) {
        return;
      }
      setState(() {
        _errorMessage = null;
        _isLoadingMore = true;
      });
    }

    final pageToLoad = _nextPage;
    try {
      final uri = Uri.parse('$_baseUrl/api/me/posts').replace(
        queryParameters: {'page': '$pageToLoad'},
      );
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Failed to load posts (${response.statusCode})');
      }

      final data = response.body.isEmpty ? null : jsonDecode(response.body);
      final items = _extractPosts(data, pageToLoad);
      final hasMore = _resolveHasMore(data, items.length);

      if (!mounted) {
        return;
      }

      setState(() {
        _posts.addAll(items);
        _nextPage = pageToLoad + 1;
        _hasMore = hasMore;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            error is HttpException ? error.message : 'Failed to load posts';
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingMore = false;
        _isInitialLoading = false;
      });
    }
  }

  List<UserPost> _extractPosts(dynamic data, int page) {
    final result = <UserPost>[];

    Iterable<dynamic>? rawItems;
    if (data is List) {
      rawItems = data;
    } else if (data is Map<String, dynamic>) {
      const candidates = ['posts', 'items', 'data', 'results', 'entries'];
      for (final key in candidates) {
        final value = data[key];
        if (value is List) {
          rawItems = value;
          break;
        }
        if (value is Map<String, dynamic>) {
          final nested = value['items'] ?? value['data'] ?? value['posts'];
          if (nested is List) {
            rawItems = nested;
            break;
          }
        }
      }
      if (rawItems == null && data['data'] is Map<String, dynamic>) {
        final inner = data['data'] as Map<String, dynamic>;
        for (final key in candidates) {
          final value = inner[key];
          if (value is List) {
            rawItems = value;
            break;
          }
        }
      }
    }

    if (rawItems == null) {
      return result;
    }

    var index = 0;
    for (final item in rawItems) {
      if (item is Map<String, dynamic>) {
        try {
          result.add(UserPost.fromJson(item, fallbackId: 'page$page-$index'));
        } catch (_) {
          // Ignore malformed entries.
        }
      }
      index++;
    }

    return result;
  }

  bool _resolveHasMore(dynamic data, int itemCount) {
    if (data is Map<String, dynamic>) {
      bool? hasMore;
      final meta = data['meta'] ?? data['pagination'] ?? data['pageInfo'];
      if (meta is Map) {
        hasMore ??= _boolFromMap(meta, ['hasMore', 'has_next', 'hasNext', 'hasNextPage']);
        final nextPage = _valueFromMap(meta, ['nextPage', 'next_page', 'next']);
        if (nextPage != null && nextPage != false) {
          return true;
        }
        final totalPages = _intFromMap(meta, ['totalPages', 'total_pages']);
        final currentPage =
            _intFromMap(meta, ['currentPage', 'page', 'pageNumber']);
        if (totalPages != null && currentPage != null) {
          return currentPage < totalPages;
        }
      }
      hasMore ??= _boolFromMap(data, ['hasMore', 'has_next', 'hasNextPage']);
      if (hasMore != null) {
        return hasMore;
      }
      final next = _valueFromMap(data, ['nextPage', 'next_page', 'next']);
      if (next != null && next != false) {
        return true;
      }
    }

    if (itemCount == 0) {
      return false;
    }
    return itemCount >= _defaultPageSize;
  }

  bool? _boolFromMap(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        final lower = value.toLowerCase();
        if (lower == 'true' || lower == 'yes' || lower == '1') {
          return true;
        }
        if (lower == 'false' || lower == 'no' || lower == '0') {
          return false;
        }
      }
    }
    return null;
  }

  int? _intFromMap(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  dynamic _valueFromMap(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  Future<void> _handleRefresh() {
    return _fetchPosts(reset: true);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasPixels || !position.hasContentDimensions) {
      return;
    }
    const threshold = 200.0;
    final remaining = position.maxScrollExtent - position.pixels;
    if (remaining <= threshold) {
      _fetchPosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_posts.isEmpty) {
      if (_isInitialLoading) {
        return _buildPlaceholder(
          const SizedBox(
            height: 48,
            width: 48,
            child: CircularProgressIndicator(),
          ),
        );
      }
      if (_errorMessage != null) {
        return _buildPlaceholder(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                'Unable to load your posts.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _fetchPosts(reset: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      return _buildPlaceholder(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No posts yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Posts you create will show up here once they are ready.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final itemCount = _posts.length +
        ((_isLoadingMore || (_errorMessage != null)) ? 1 : 0);

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemBuilder: (context, index) {
          if (index >= _posts.length) {
            return _buildFooter();
          }
          final post = _posts[index];
          return _buildPostTile(post);
        },
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemCount: itemCount,
      ),
    );
  }

  Widget _buildPlaceholder(Widget child) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
        children: [
          Center(child: child),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            height: 32,
            width: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Something went wrong while loading more posts.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _fetchPosts(),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildPostTile(UserPost post) {
    final theme = Theme.of(context);
    final subtitleWidgets = <Widget>[];
    if (post.description != null && post.description!.isNotEmpty) {
      subtitleWidgets.add(
        Text(
          post.description!,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    if (post.createdAt != null) {
      subtitleWidgets.add(
        Text(
          'Created ${_formatTimestamp(post.createdAt!)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildThumbnail(post),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          post.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(status: post.status),
                    ],
                  ),
                  if (subtitleWidgets.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < subtitleWidgets.length; i++) ...[
                          if (i > 0) const SizedBox(height: 4),
                          subtitleWidgets[i],
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(UserPost post) {
    final borderRadius = BorderRadius.circular(12);
    final type = post.type?.toLowerCase();
    final icon = type == 'video'
        ? Icons.videocam_outlined
        : type == 'audio'
            ? Icons.audiotrack
            : Icons.image_outlined;

    Widget fallbackIcon(ColorScheme colorScheme) {
      return Container(
        color: colorScheme.surfaceVariant,
        child: Icon(
          icon,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return SizedBox(
      height: 64,
      width: 64,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Builder(
          builder: (context) {
            final previewUrl = post.previewImageUrl;
            if (previewUrl == null || previewUrl.isEmpty) {
              return fallbackIcon(Theme.of(context).colorScheme);
            }
            return Image.network(
              previewUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return fallbackIcon(Theme.of(context).colorScheme);
              },
            );
          },
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime value) {
    final date = value.toLocal();
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final datePart =
        '${date.year}-${twoDigits(date.month)}-${twoDigits(date.day)}';
    final timePart = '${twoDigits(date.hour)}:${twoDigits(date.minute)}';
    return '$datePart · $timePart';
  }
}

extension UserPostStatusX on UserPostStatus {
  String get label {
    switch (this) {
      case UserPostStatus.ready:
        return 'Ready';
      case UserPostStatus.failed:
        return 'Failed';
      case UserPostStatus.processing:
        return 'Processing';
    }
  }
}

class _StatusChipStyle {
  const _StatusChipStyle({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

_StatusChipStyle _statusChipStyle(UserPostStatus status) {
  switch (status) {
    case UserPostStatus.ready:
      return _StatusChipStyle(
        background: Colors.green.shade50,
        foreground: Colors.green.shade900,
      );
    case UserPostStatus.failed:
      return _StatusChipStyle(
        background: Colors.red.shade50,
        foreground: Colors.red.shade900,
      );
    case UserPostStatus.processing:
      return _StatusChipStyle(
        background: Colors.amber.shade50,
        foreground: Colors.amber.shade900,
      );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final UserPostStatus status;

  @override
  Widget build(BuildContext context) {
    final style = _statusChipStyle(status);
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: style.foreground,
          fontWeight: FontWeight.w600,
        );
    return Container(
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Text(status.label, style: textStyle),
    );
  }
}
