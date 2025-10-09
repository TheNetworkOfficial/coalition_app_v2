import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../env.dart';
import '../providers/upload_manager.dart';
import '../widgets/feed_item.dart';

class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  static const _pageSize = 10;

  late final PagingController<int, FeedEntry> _pagingController;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey<_FeedListItemContainerState>> _itemKeys = {};

  int? _activeVideoIndex;
  bool _visibilityUpdateScheduled = false;
  int? _nextPageKey = 1;
  int? _lastRequestedPageKey;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _pagingController = PagingController<int, FeedEntry>(
      getNextPageKey: _getNextPageKey,
      fetchPage: _fetchPage,
    );
  }

  @override
  void dispose() {
    _pagingController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<FeedEntry>> _fetchPage(int pageKey) async {
    try {
      final uri = resolveApiUri('/api/feed').replace(
        queryParameters: {
          'page': '$pageKey',
        },
      );
      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Failed to load feed: ${response.statusCode}');
      }

      final body = response.body.isEmpty ? null : jsonDecode(response.body);
      final rawItems = _extractItems(body);

      final items = <FeedEntry>[];
      for (var i = 0; i < rawItems.length; i++) {
        final raw = rawItems[i];
        if (raw is Map<String, dynamic>) {
          try {
            items.add(
              FeedEntry.fromJson(
                raw,
                fallbackId: 'page$pageKey-$i',
              ),
            );
          } catch (_) {
            // Ignore malformed entries.
          }
        }
      }

      final nextPageKey = _resolveNextPageKey(body, pageKey, items.length);
      _hasMore = nextPageKey != null;
      _nextPageKey = nextPageKey;
      _pagingController.value = _pagingController.value.copyWith(
        hasNextPage: _hasMore,
        error: null,
      );

      _scheduleVisibilityUpdate();
      return items;
    } catch (error) {
      _nextPageKey = _lastRequestedPageKey ?? pageKey;
      rethrow;
    }
  }

  int? _getNextPageKey(PagingState<int, FeedEntry> state) {
    if (!_hasMore) {
      return null;
    }

    int? key = _nextPageKey;
    if (key == null) {
      final existingKeys = state.keys;
      if (existingKeys != null && existingKeys.isNotEmpty) {
        key = existingKeys.last + 1;
      } else {
        key = 1;
      }
    }

    _lastRequestedPageKey = key;
    _nextPageKey = null;
    return key;
  }

  Future<void> _handleRefresh() {
    final completer = Completer<void>();
    void listener() {
      if (_pagingController.status != PagingStatus.loadingFirstPage) {
        _pagingController.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    }

    _pagingController.addListener(listener);

    setState(() {
      _activeVideoIndex = null;
      _itemKeys.clear();
    });

    _hasMore = true;
    _nextPageKey = 1;
    _lastRequestedPageKey = null;

    _pagingController.refresh();
    _scheduleVisibilityUpdate();

    return completer.future;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification ||
        notification is OverscrollNotification) {
      _scheduleVisibilityUpdate();
    }
    return false;
  }

  void _scheduleVisibilityUpdate() {
    if (_visibilityUpdateScheduled) {
      return;
    }
    _visibilityUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _visibilityUpdateScheduled = false;
      _updateActiveVideo();
    });
  }

  void _updateActiveVideo() {
    if (!_scrollController.hasClients) {
      return;
    }

    final items = _pagingController.items;
    if (items == null || items.isEmpty) {
      if (_activeVideoIndex != null) {
        setState(() => _activeVideoIndex = null);
      }
      return;
    }

    final position = _scrollController.position;
    final viewportStart = position.pixels;
    final viewportEnd = viewportStart + position.viewportDimension;

    int? bestIndex;
    double bestFraction = 0;

    _itemKeys.forEach((index, key) {
      if (index < 0 || index >= items.length) {
        return;
      }
      final entry = items[index];
      if (entry.type != FeedMediaType.video) {
        return;
      }

      final context = key.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox) {
        return;
      }
      final viewport = RenderAbstractViewport.of(renderObject);

      final metricsTop = viewport.getOffsetToReveal(renderObject, 0).offset;
      final metricsBottom =
          viewport.getOffsetToReveal(renderObject, 1).offset;

      final itemExtent = metricsBottom - metricsTop;
      if (itemExtent <= 0) {
        return;
      }

      final visibleStart = math.max(metricsTop, viewportStart);
      final visibleEnd = math.min(metricsBottom, viewportEnd);
      final visibleExtent = visibleEnd - visibleStart;
      final fraction = (visibleExtent <= 0)
          ? 0.0
          : math.min(1.0, math.max(0.0, visibleExtent / itemExtent));

      if (fraction > bestFraction) {
        bestFraction = fraction;
        bestIndex = index;
      }
    });

    if (bestFraction == 0) {
      bestIndex = null;
    }

    if (_activeVideoIndex != bestIndex) {
      setState(() {
        _activeVideoIndex = bestIndex;
      });
    }
  }

  void _handleItemRemoved(int index) {
    _itemKeys.remove(index);
    if (_activeVideoIndex == index) {
      _activeVideoIndex = null;
    }
    _scheduleVisibilityUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final uploadManager = ref.watch(uploadManagerProvider);
    final showUploadBar = uploadManager.hasActiveUpload;
    double? indicatorValue;
    final progress = uploadManager.progress;
    if (progress != null) {
      final clamped = progress.clamp(0.0, 1.0);
      if (clamped > 0 && clamped < 1) {
        indicatorValue = clamped;
      } else if (clamped >= 1) {
        indicatorValue = 1.0;
      } else {
        indicatorValue = null;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Feed'),
      ),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: showUploadBar
                ? SizedBox(
                    key: const ValueKey('upload-progress'),
                    height: 4,
                    child: LinearProgressIndicator(
                      value: indicatorValue,
                    ),
                  )
                : const SizedBox(
                    key: ValueKey('upload-progress-empty'),
                    height: 0,
                  ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                child: ValueListenableBuilder<PagingState<int, FeedEntry>>(
                  valueListenable: _pagingController,
                  builder: (context, state, _) {
                    return PagedListView<int, FeedEntry>.separated(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                      state: state,
                      fetchNextPage: _pagingController.fetchNextPage,
                      scrollController: _scrollController,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      builderDelegate: PagedChildBuilderDelegate<FeedEntry>(
                        itemBuilder: (context, item, index) {
                          final key = _itemKeys[index] ??
                              GlobalKey<_FeedListItemContainerState>();
                          _itemKeys[index] = key;

                          _scheduleVisibilityUpdate();

                          return _FeedListItemContainer(
                            key: key,
                            index: index,
                            onRemoved: _handleItemRemoved,
                            onMetricsChanged: _scheduleVisibilityUpdate,
                            child: FeedItem(
                              item: item,
                              isActive: _activeVideoIndex == index,
                            ),
                          );
                        },
                        firstPageProgressIndicatorBuilder: (context) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        newPageProgressIndicatorBuilder: (context) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                        firstPageErrorIndicatorBuilder: (context) => _FeedErrorIndicator(
                          onRetry: _pagingController.refresh,
                          error: _pagingController.error,
                        ),
                        newPageErrorIndicatorBuilder: (context) => _FeedErrorIndicator(
                          onRetry: _pagingController.fetchNextPage,
                          error: _pagingController.error,
                        ),
                        noItemsFoundIndicatorBuilder: (context) => const _FeedEmptyIndicator(),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static List<dynamic> _extractItems(dynamic body) {
    if (body is List) {
      return body;
    }
    if (body is Map<String, dynamic>) {
      for (final key in const ['items', 'data', 'results', 'posts', 'feed']) {
        final value = body[key];
        if (value is List) {
          return value;
        }
      }
    }
    return const [];
  }

  int? _resolveNextPageKey(dynamic body, int currentPage, int itemCount) {
    if (body is Map<String, dynamic>) {
      final dynamic nextPageRaw = body['nextPage'] ?? body['next_page'];
      if (nextPageRaw is int) {
        return nextPageRaw;
      }
      if (nextPageRaw is String) {
        final parsed = int.tryParse(nextPageRaw);
        if (parsed != null) {
          return parsed;
        }
      }

      final dynamic hasMoreRaw = body['hasMore'] ?? body['has_more'];
      if (hasMoreRaw is bool) {
        return hasMoreRaw ? currentPage + 1 : null;
      }
      if (hasMoreRaw is String) {
        final normalized = hasMoreRaw.toLowerCase();
        if (normalized == 'true') {
          return currentPage + 1;
        }
        if (normalized == 'false') {
          return null;
        }
      }

      final dynamic totalPagesRaw = body['totalPages'] ?? body['total_pages'];
      if (totalPagesRaw is int && totalPagesRaw > 0) {
        return currentPage < totalPagesRaw ? currentPage + 1 : null;
      }
      if (totalPagesRaw is String) {
        final parsed = int.tryParse(totalPagesRaw);
        if (parsed != null && parsed > 0) {
          return currentPage < parsed ? currentPage + 1 : null;
        }
      }
    }

    if (itemCount < _pageSize) {
      return null;
    }
    return currentPage + 1;
  }
}

class _FeedListItemContainer extends StatefulWidget {
  const _FeedListItemContainer({
    required super.key,
    required this.index,
    required this.child,
    required this.onRemoved,
    required this.onMetricsChanged,
  });

  final int index;
  final Widget child;
  final ValueChanged<int> onRemoved;
  final VoidCallback onMetricsChanged;

  @override
  State<_FeedListItemContainer> createState() => _FeedListItemContainerState();
}

class _FeedListItemContainerState extends State<_FeedListItemContainer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onMetricsChanged());
  }

  @override
  void didUpdateWidget(covariant _FeedListItemContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => widget.onMetricsChanged());
  }

  @override
  void dispose() {
    widget.onRemoved(widget.index);
    widget.onMetricsChanged();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _FeedErrorIndicator extends StatelessWidget {
  const _FeedErrorIndicator({required this.onRetry, this.error});

  final VoidCallback onRetry;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.error,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Something went wrong',
            style: theme.textTheme.titleMedium,
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _FeedEmptyIndicator extends StatelessWidget {
  const _FeedEmptyIndicator();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inbox, size: 48),
          SizedBox(height: 12),
          Text('No feed items yet'),
        ],
      ),
    );
  }
}

class HttpException implements Exception {
  HttpException(this.message);
  final String message;

  @override
  String toString() => message;
}
