import 'package:coalition_app_v2/features/engagement/utils/ids.dart';
import 'package:coalition_app_v2/router/app_router.dart' show rootNavigatorKey;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../playback/feed_activity_provider.dart';
import '../models/post.dart';
import '../providers/feed_providers.dart';
import 'widgets/post_view.dart';
import 'widgets/comments_sheet.dart';

class FeedPage extends ConsumerStatefulWidget {
  const FeedPage({super.key});

  @override
  ConsumerState<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends ConsumerState<FeedPage> {
  final PageController _pageController = PageController(viewportFraction: 1.0);
  int _activeIndex = 0;
  final Map<String, GlobalKey<PostViewState>> _postKeys = {};
  List<Post> _currentPosts = const [];
  bool _activationScheduled = false;
  ProviderSubscription<AsyncValue<List<Post>>>? _feedSubscription;
  ProviderSubscription<bool>? _feedActivitySub;

  @override
  void initState() {
    super.initState();
    _feedSubscription = ref.listenManual<AsyncValue<List<Post>>>(
      feedItemsProvider,
      _handleFeedUpdate,
      fireImmediately: true,
    );
    _feedActivitySub = ref.listenManual<bool>(
      feedActiveProvider,
      (previous, next) {
        if (next == false) {
          _deactivateAllVisiblePosts();
          return;
        }
        _scheduleActivationSync();
      },
    );
    _feedActivitySub?.read();
  }

  @override
  void dispose() {
    _feedSubscription?.close();
    _feedActivitySub?.close();
    _feedActivitySub = null;
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(feedItemsProvider);

    return Scaffold(
      body: postsAsync.when(
        data: (posts) => _buildFeed(posts),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _FeedErrorView(
          error: error,
          onRetry: _refreshFeed,
        ),
      ),
    );
  }

  void _refreshFeed() {
    ref.invalidate(feedItemsProvider);
  }

  Widget _buildFeed(List<Post> posts) {
    final canonicalPosts = _canonicalizePosts(posts);
    if (canonicalPosts.isEmpty) {
      return _FeedEmptyView(onRetry: _refreshFeed);
    }

    _currentPosts = canonicalPosts;
    _cleanupKeys(canonicalPosts);
    _scheduleActivationSync();

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          allowImplicitScrolling: false,
          padEnds: false,
          pageSnapping: true,
          itemCount: canonicalPosts.length,
          onPageChanged: _handlePageChanged,
          itemBuilder: (context, index) {
            final post = canonicalPosts[index];
            final postId = normalizePostId(post.id);
            if (postId.isEmpty) {
              return const SizedBox.shrink();
            }
            final key = _postKeys.putIfAbsent(
              postId,
              () => GlobalKey<PostViewState>(),
            );
            return PostView(
              key: key,
              post: post,
              initiallyActive: index == _activeIndex,
              onProfileTap: () => _handleProfileTap(post),
              onCommentsTap: () => _handleCommentsTap(post),
            );
          },
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, right: 16),
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .scrim
                    .withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  tooltip: 'Refresh feed',
                  onPressed: _refreshFeed,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handlePageChanged(int index) {
    if (_activeIndex == index) {
      return;
    }
    setState(() => _activeIndex = index);
    _scheduleActivationSync();
  }

  void _handleProfileTap(Post post) {
    final rawUserId = post.userId;
    final targetUserId = (rawUserId ?? '').trim();
    debugPrint(
      '[NAV] profile tap received | postId=${post.id} userId=${rawUserId ?? '<null>'} resolved=$targetUserId',
    );
    if (targetUserId.isEmpty) {
      if (kDebugMode) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Missing user id for profile')),
        );
      }
      return;
    }
    _pushProfile(targetUserId);
  }

  void _handleCommentsTap(Post post) {
    final postId = normalizePostId(post.id);
    if (postId.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Comments unavailable for this post.')),
        );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      // Opaque backdrop: no transparency
      barrierColor: Theme.of(context).colorScheme.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => CommentsSheet(
        postId: postId,
        onProfileTap: (userId) {
          final resolvedUserId = userId.trim();
          if (resolvedUserId.isEmpty) {
            return;
          }
          _pushProfile(resolvedUserId);
        },
      ),
    );
  }

  void _pushProfile(String userId) {
    final rootContext = rootNavigatorKey.currentContext;
    if (rootContext == null) {
      debugPrint(
          '[NAV][ERROR] rootNavigatorKey.currentContext is null; aborting profile navigation');
      return;
    }
    debugPrint(
        '[NAV] pushing profile route | userId=$userId via root navigator');
    GoRouter.of(rootContext).pushNamed('profile', extra: userId);
  }

  void _cleanupKeys(List<Post> posts) {
    final validIds = posts
        .map((post) => normalizePostId(post.id))
        .where((id) => id.isNotEmpty)
        .toSet();
    final staleIds =
        _postKeys.keys.where((id) => !validIds.contains(id)).toList();
    for (final id in staleIds) {
      _postKeys.remove(id);
    }
  }

  void _deactivateAllVisiblePosts() {
    for (final key in _postKeys.values) {
      key.currentState?.onActiveChanged(false);
    }
  }

  void _scheduleActivationSync() {
    if (_activationScheduled) {
      return;
    }
    _activationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activationScheduled = false;
      if (!mounted) {
        return;
      }
      if (_currentPosts.isEmpty) {
        return;
      }
      for (var i = 0; i < _currentPosts.length; i++) {
        final post = _currentPosts[i];
        final postId = normalizePostId(post.id);
        if (postId.isEmpty) {
          continue;
        }
        final key = _postKeys[postId];
        key?.currentState?.onActiveChanged(i == _activeIndex);
      }
    });
  }

  void _handleFeedUpdate(
    AsyncValue<List<Post>>? previous,
    AsyncValue<List<Post>> next,
  ) {
    next.whenData((posts) {
      if (!mounted) {
        return;
      }

      final canonicalPosts = _canonicalizePosts(posts);
      _currentPosts = canonicalPosts;
      _cleanupKeys(canonicalPosts);

      int targetIndex = _activeIndex;
      if (canonicalPosts.isEmpty) {
        targetIndex = 0;
      } else if (_activeIndex >= canonicalPosts.length) {
        targetIndex = canonicalPosts.length - 1;
      }

      if (targetIndex != _activeIndex) {
        setState(() => _activeIndex = targetIndex);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(targetIndex);
        }
      }

      _scheduleActivationSync();
    });
  }

  List<Post> _canonicalizePosts(List<Post> posts) {
    return posts
        .where((post) => normalizePostId(post.id).isNotEmpty)
        .toList(growable: false);
  }
}

class _FeedErrorView extends StatelessWidget {
  const _FeedErrorView({required this.onRetry, this.error});

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
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface
                      .withValues(alpha: 0.70),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _FeedEmptyView extends StatelessWidget {
  const _FeedEmptyView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No posts yet',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: onSurface.withValues(alpha: 0.70),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Reload'),
          ),
        ],
      ),
    );
  }
}
