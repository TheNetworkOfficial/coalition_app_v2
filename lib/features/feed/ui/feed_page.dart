import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  @override
  void initState() {
    super.initState();
    _feedSubscription = ref.listenManual<AsyncValue<List<Post>>>(
      feedItemsProvider,
      _handleFeedUpdate,
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _feedSubscription?.close();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final postsAsync = ref.watch(feedItemsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
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
    if (posts.isEmpty) {
      return _FeedEmptyView(onRetry: _refreshFeed);
    }

    _currentPosts = posts;
    _cleanupKeys(posts);
    _scheduleActivationSync();

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          allowImplicitScrolling: false,
          padEnds: false,
          pageSnapping: true,
          itemCount: posts.length,
          onPageChanged: _handlePageChanged,
          itemBuilder: (context, index) {
            final post = posts[index];
            final key = _postKeys.putIfAbsent(
              post.id,
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
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
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
    final target = post.userId;
    if (target == null || target.isEmpty) {
      return;
    }
    context.push('/profile', extra: target);
  }

  void _handleCommentsTap(Post post) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => CommentsSheet(
        postId: post.id,
        onProfileTap: (userId) {
          if (userId.isEmpty) {
            return;
          }
          context.push('/profile', extra: userId);
        },
      ),
    );
  }

  void _cleanupKeys(List<Post> posts) {
    final validIds = posts.map((post) => post.id).toSet();
    final staleIds = _postKeys.keys.where((id) => !validIds.contains(id)).toList();
    for (final id in staleIds) {
      _postKeys.remove(id);
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
        final key = _postKeys[post.id];
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

      _currentPosts = posts;
      _cleanupKeys(posts);

      int targetIndex = _activeIndex;
      if (posts.isEmpty) {
        targetIndex = 0;
      } else if (_activeIndex >= posts.length) {
        targetIndex = posts.length - 1;
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
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            'Something went wrong',
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '$error',
                textAlign: TextAlign.center,
                style:
                    theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'No posts yet',
            style: TextStyle(color: Colors.white70),
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
