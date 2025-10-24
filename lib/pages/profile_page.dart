import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../features/auth/providers/auth_state.dart';
import '../models/posts_page.dart';
import '../models/profile.dart';
import '../providers/app_providers.dart';
import '../providers/upload_manager.dart';
import '../services/api_client.dart';
import 'edit_profile_page.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key, this.targetUserId});

  final String? targetUserId;

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  Profile? _profile;
  List<PostItem> _items = const [];
  String? _cursor;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isInitialLoading = true;
  final Random _random = Random();
  ProviderSubscription<UploadManager>? _uploadSubscription;
  late final ScrollController _scrollController;

  String? get _resolvedTargetUserId {
    final raw = widget.targetUserId;
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get _isViewingSelf => _resolvedTargetUserId == null;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _uploadSubscription = ref.listenManual<UploadManager>(
      uploadManagerProvider,
      (previous, next) {
        final previousStatus = previous?.status;
        final nextStatus = next.status;
        if (previousStatus != nextStatus && nextStatus?.isFinalState == true) {
          _refreshContent();
        }
      },
      fireImmediately: false,
    );
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _uploadSubscription?.close();
    super.dispose();
  }

  Future<void> _loadInitialData({
    bool resetState = true,
    bool showLoader = true,
  }) async {
    if (!mounted) {
      return;
    }
    setState(() {
      if (resetState) {
        _items = const [];
        _cursor = null;
        _hasMore = true;
      }
      _isLoading = true;
      if (resetState || showLoader) {
        _isInitialLoading = true;
      }
    });

    final apiClient = ref.read(apiClientProvider);
    final targetUserId = _resolvedTargetUserId;
    try {
      if (_isViewingSelf) {
        final profile = await _fetchOrCreateProfile(apiClient);
        final page = await apiClient.getMyPosts(limit: 30);
        if (!mounted) {
          return;
        }
        debugPrint(
          '[ProfilePage] Initial load items=${page.items.length} nextCursor=${page.nextCursor ?? 'null'}',
        );
        ref.read(uploadManagerProvider).removePendingPostsByIds(
              page.items.map((item) => item.id),
            );
        setState(() {
          _profile = profile;
          _items = page.items;
          _cursor = page.nextCursor;
          _hasMore = page.hasMore;
          _isLoading = false;
          _isInitialLoading = false;
        });
        return;
      }

      if (targetUserId == null) {
        return;
      }

      final profile = await apiClient.getProfile(targetUserId);
      final page = await apiClient.getUserPosts(targetUserId, limit: 30);
      if (!mounted) {
        return;
      }
      debugPrint(
        '[ProfilePage] Initial load (user=$targetUserId) items=${page.items.length} nextCursor=${page.nextCursor ?? 'null'}',
      );
      setState(() {
        _profile = profile;
        _items = page.items;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _isLoading = false;
        _isInitialLoading = false;
      });
    } on ApiException catch (error) {
      await _handleApiException(error);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showProfileErrorSnackBar('Failed to load profile: $error');
      setState(() {
        _isLoading = false;
        _isInitialLoading = false;
      });
    }
  }

  Future<void> _refreshContent() async {
    await _loadInitialData(resetState: true, showLoader: false);
  }

  Future<void> _loadMorePosts() async {
    if (!mounted || _isLoading || !_hasMore || (_cursor ?? '').isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final apiClient = ref.read(apiClientProvider);
    final targetUserId = _resolvedTargetUserId;
    try {
      final page = _isViewingSelf
          ? await apiClient.getMyPosts(limit: 30, cursor: _cursor)
          : await apiClient.getUserPosts(targetUserId!, limit: 30, cursor: _cursor);
      if (!mounted) {
        return;
      }
      debugPrint(
        '[ProfilePage] Load more received ${page.items.length} items nextCursor=${page.nextCursor ?? 'null'}',
      );
      if (_isViewingSelf) {
        ref.read(uploadManagerProvider).removePendingPostsByIds(
              page.items.map((item) => item.id),
            );
      }
      setState(() {
        final updated = List<PostItem>.of(_items)..addAll(page.items);
        _items = updated;
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      await _handleApiException(error, isLoadMore: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showProfileErrorSnackBar('Failed to load posts: $error');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> onToggleFollow(String targetUserId, bool next) async {
    if (_isViewingSelf) {
      return;
    }
    final trimmedId = targetUserId.trim();
    if (trimmedId.isEmpty) {
      return;
    }
    final profile = _profile;
    if (profile == null) {
      return;
    }

    final previousFollowersCount = profile.followersCount;
    final previousIsFollowing = profile.isFollowing;

    setState(() {
      final delta = next ? 1 : -1;
      final updatedCount = max(0, previousFollowersCount + delta);
      _profile = profile.copyWith(
        isFollowing: next,
        followersCount: updatedCount,
      );
    });

    final apiClient = ref.read(apiClientProvider);
    try {
      await apiClient.toggleFollow(trimmedId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        final current = _profile ?? profile;
        if (current == null) {
          return;
        }
        _profile = current.copyWith(
          isFollowing: previousIsFollowing,
          followersCount: previousFollowersCount,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update follow: $error')),
      );
    }
  }

  Future<void> _handleApiException(
    ApiException error, {
    bool isLoadMore = false,
  }) async {
    if (error.statusCode == HttpStatus.unauthorized) {
      await ref.read(authStateProvider.notifier).signOut();
      if (!mounted) {
        return;
      }
      context.go('/auth');
      return;
    }
    if (!mounted) {
      return;
    }
    if (error.statusCode != HttpStatus.notFound) {
      final message = error.message.isNotEmpty
          ? error.message
          : 'Failed to load posts: ${error.statusCode}';
      _showProfileErrorSnackBar(message);
    }
    setState(() {
      _isLoading = false;
      if (!isLoadMore) {
        _isInitialLoading = false;
      }
    });
  }

  Future<Profile> _fetchOrCreateProfile(ApiClient apiClient) async {
    try {
      return await apiClient.getMyProfile();
    } on ApiException catch (error) {
      if (error.statusCode == HttpStatus.notFound) {
        final defaultDisplayName = _generateDefaultDisplayName();
        final authState = ref.read(authStateProvider);
        final username = authState.user?.username;
        final update = ProfileUpdate(
          displayName: defaultDisplayName,
          username:
              (username != null && username.isNotEmpty) ? username : null,
        );
        final upserted = await apiClient.upsertMyProfile(update);
        try {
          return await apiClient.getMyProfile();
        } on ApiException catch (retryError) {
          if (retryError.statusCode == HttpStatus.notFound) {
            return upserted;
          }
          rethrow;
        }
      }
      rethrow;
    }
  }

  String _generateDefaultDisplayName() {
    final number = _random.nextInt(900000) + 100000;
    return 'user$number';
  }

  void _showProfileErrorSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () {
              _loadInitialData();
            },
          ),
        ),
      );
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasPixels || position.maxScrollExtent <= 0) {
      return;
    }
    final threshold = position.maxScrollExtent * 0.8;
    if (position.pixels >= threshold) {
      _loadMorePosts();
    }
  }

  Future<void> _onRefresh() async {
    await _loadInitialData(resetState: true, showLoader: false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final uploadManager = ref.watch(uploadManagerProvider);
    final pendingPosts = _isViewingSelf ? uploadManager.pendingPosts : const <PostItem>[];
    final seenIds = <String>{};
    final combinedPosts = <PostItem>[];
    for (final pending in pendingPosts) {
      if (seenIds.add(pending.id)) {
        combinedPosts.add(pending);
      }
    }
    for (final item in _items) {
      if (seenIds.add(item.id)) {
        combinedPosts.add(item);
      }
    }
    final posts = combinedPosts;
    final profile = _profile;
    final isInitialLoading = _isInitialLoading;
    final isLoadMoreInProgress = !isInitialLoading && _isLoading;
    final profileIsLoading = profile == null && isInitialLoading;
    final usernameValue = profile?.username?.trim().isNotEmpty == true
        ? profile!.username!.trim()
        : (_isViewingSelf ? (authState.user?.username ?? '').trim() : '');
    final usernameLabel =
        usernameValue.isNotEmpty ? '@$usernameValue' : 'Username pending';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            controller: _scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: _ProfileDetailsSection(
                    profile: profile,
                    isLoading: profileIsLoading,
                    onEditProfile: _handleEditProfile,
                    onSignOut: _signOut,
                    usernameLabel: usernameLabel,
                    showActions: _isViewingSelf,
                    onToggleFollow: onToggleFollow,
                  ),
                ),
              ),
              if (isInitialLoading)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => const _ShimmerTile(),
                      childCount: 9,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 1,
                    ),
                  ),
                )
              else if (posts.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _NoPostsView(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final post = posts[index];
                        return _PostGridTile(
                          item: post,
                          onTap: () => _openPost(post),
                        );
                      },
                      childCount: posts.length,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                      childAspectRatio: 1,
                    ),
                  ),
                ),
              if (isLoadMoreInProgress && posts.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        height: 32,
                        width: 32,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleEditProfile() async {
    final currentProfile = _profile;
    final result = await Navigator.of(context).push<Profile>(
      MaterialPageRoute(
        builder: (context) => EditProfilePage(initialProfile: currentProfile),
      ),
    );
    if (result != null) {
      setState(() => _profile = result);
    }
  }

  Future<void> _signOut() async {
    await ref.read(authStateProvider.notifier).signOut();
    if (!mounted) {
      return;
    }
    context.go('/auth');
  }

  void _openPost(PostItem item) {
    final playbackUrl = item.playbackUrl?.trim();
    if (playbackUrl != null && playbackUrl.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => _ProfilePostPlaybackPage(item: item),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _ProfilePostViewerPage(item: item),
      ),
    );
  }
}

class _ProfileDetailsSection extends StatelessWidget {
  const _ProfileDetailsSection({
    required this.profile,
    required this.isLoading,
    required this.onEditProfile,
    required this.onSignOut,
    required this.usernameLabel,
    this.showActions = true,
    this.onToggleFollow,
  });

  final Profile? profile;
  final bool isLoading;
  final VoidCallback onEditProfile;
  final VoidCallback onSignOut;
  final String usernameLabel;
  final bool showActions;
  final Future<void> Function(String targetUserId, bool next)? onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = profile?.displayName?.trim();
    final avatarUrl = profile?.avatarUrl;
    final bio = profile?.bio;
    final profileData = profile;
    final toggleFollow = onToggleFollow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundImage:
                  avatarUrl != null ? NetworkImage(avatarUrl) : null,
              child:
                  avatarUrl == null ? const Icon(Icons.person, size: 36) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName != null && displayName.isNotEmpty
                        ? displayName
                        : 'Set your display name',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    usernameLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (showActions) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: isLoading ? null : onEditProfile,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit profile'),
                    ),
                  ],
                  if (!showActions && profileData != null && toggleFollow != null)
                    ...[
                      const SizedBox(height: 12),
                      _FollowButton(
                        targetUserId: profileData.userId,
                        isFollowing: profileData.isFollowing,
                        onToggle: toggleFollow,
                      ),
                    ],
                ],
              ),
            ),
            if (showActions)
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEditProfile();
                      break;
                    case 'signout':
                      onSignOut();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text('Edit profile'),
                  ),
                  PopupMenuItem<String>(
                    value: 'signout',
                    child: Text('Sign out'),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          bio?.isNotEmpty == true ? bio! : 'Tell the community more about you.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({
    required this.targetUserId,
    required this.isFollowing,
    required this.onToggle,
  });

  final String targetUserId;
  final bool isFollowing;
  final Future<void> Function(String targetUserId, bool next) onToggle;

  @override
  Widget build(BuildContext context) {
    final next = !isFollowing;
    return ElevatedButton(
      onPressed: () => onToggle(targetUserId, next),
      child: Text(isFollowing ? 'Following' : 'Follow'),
    );
  }
}

class _NoPostsView extends StatelessWidget {
  const _NoPostsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        'No posts yet.',
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _PostGridTile extends StatelessWidget {
  const _PostGridTile({required this.item, required this.onTap});

  final PostItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
        final width = (constraints.maxWidth * devicePixelRatio).round();
        final height = (constraints.maxHeight * devicePixelRatio).round();
        final memCacheWidth = width > 0 ? width : 1;
        final memCacheHeight = height > 0 ? height : 1;
        final hasThumbnail = _validThumbUrl(item.thumbUrl) != null;
        final isFailed = item.status.toUpperCase() == 'FAILED';
        final showSpinner = !hasThumbnail;
        final showDuration = item.durationMs > 0 && hasThumbnail;

        return GestureDetector(
          onTap: (!isFailed && hasThumbnail) ? onTap : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'profile_post_${item.id}',
                  child:
                      _buildThumbnail(memCacheWidth, memCacheHeight),
                ),
                if (showDuration)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(item.duration),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                if (showSpinner && !isFailed)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                if (isFailed)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.error_outline, color: Colors.white, size: 28),
                        SizedBox(height: 8),
                        Text(
                          'Video processing failed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(int memCacheWidth, int memCacheHeight) {
    final safeThumb = _validThumbUrl(item.thumbUrl);
    if (safeThumb == null) {
      return _placeholderTile();
    }
    return CachedNetworkImage(
      imageUrl: safeThumb,
      fit: BoxFit.cover,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      placeholder: (context, url) => const _ShimmerTile(),
      errorWidget: (context, url, error) => _placeholderTile(),
    );
  }

  Widget _placeholderTile() {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: const Icon(Icons.videocam_outlined, color: Colors.black38),
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final minutesStr = minutes.toString().padLeft(2, '0');
    final secondsStr = seconds.toString().padLeft(2, '0');
    return '$minutesStr:$secondsStr';
  }
}

class _ShimmerTile extends StatefulWidget {
  const _ShimmerTile();

  @override
  State<_ShimmerTile> createState() => _ShimmerTileState();
}

class _ShimmerTileState extends State<_ShimmerTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.grey.shade300),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final shimmerWidth = width * 0.6;
                final dx =
                    (width + shimmerWidth) * _controller.value - shimmerWidth;
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: Container(
                    width: shimmerWidth,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.grey.shade200.withAlpha(0),
                          Colors.grey.shade100.withAlpha(179),
                          Colors.grey.shade200.withAlpha(0),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _ProfilePostPlaybackPage extends StatefulWidget {
  const _ProfilePostPlaybackPage({required this.item});

  final PostItem item;

  @override
  State<_ProfilePostPlaybackPage> createState() => _ProfilePostPlaybackPageState();
}

class _ProfilePostPlaybackPageState extends State<_ProfilePostPlaybackPage> {
  VideoPlayerController? _controller;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _initializePlayback();
  }

  void _initializePlayback() {
    final playbackUrl = widget.item.playbackUrl?.trim();
    if (playbackUrl == null || playbackUrl.isEmpty) {
      setState(() {
        _loadError = ArgumentError('Missing playback URL');
      });
      return;
    }
    final uri = Uri.tryParse(playbackUrl);
    if (uri == null) {
      setState(() {
        _loadError = ArgumentError('Invalid playback URL');
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    _controller = controller;
    controller.setLooping(true);
    controller.initialize().then((_) {
      if (!mounted || _controller != controller) {
        return;
      }
      setState(() {});
      controller.play();
    }).catchError((Object error) {
      if (!mounted || _controller != controller) {
        return;
      }
      setState(() {
        _loadError = error;
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final hasError = _loadError != null;
    final isInitialized = controller != null && controller.value.isInitialized;
    final safeThumb = _validThumbUrl(widget.item.thumbUrl);

    Widget child;

    if (hasError) {
      child = _buildFallback(safeThumb);
    } else if (isInitialized && controller != null) {
      var aspectRatio = controller.value.aspectRatio;
      if (!aspectRatio.isFinite || aspectRatio <= 0) {
        aspectRatio = widget.item.aspectRatio;
      }
      if (!aspectRatio.isFinite || aspectRatio <= 0) {
        aspectRatio = 1;
      }
      child = GestureDetector(
        onTap: _togglePlayback,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: VideoPlayer(controller),
            ),
            if (!controller.value.isPlaying)
              const Center(
                child: Icon(
                  Icons.play_arrow,
                  color: Colors.white70,
                  size: 64,
                ),
              ),
          ],
        ),
      );
    } else {
      child = Stack(
        fit: StackFit.expand,
        children: [
          if (safeThumb != null)
            CachedNetworkImage(
              imageUrl: safeThumb,
              fit: BoxFit.contain,
              placeholder: (context, url) => const _ShimmerTile(),
              errorWidget: (context, url, error) =>
                  _profileFullScreenPlaceholder(),
            )
          else
            _profileFullScreenPlaceholder(),
          const Center(
            child: SizedBox(
              height: 48,
              width: 48,
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Hero(
          tag: 'profile_post_${widget.item.id}',
          child: child,
        ),
      ),
    );
  }

  Widget _buildFallback(String? safeThumb) {
    if (safeThumb != null) {
      return CachedNetworkImage(
        imageUrl: safeThumb,
        fit: BoxFit.contain,
        placeholder: (context, url) => const _ShimmerTile(),
        errorWidget: (context, url, error) => _profileFullScreenPlaceholder(),
      );
    }
    return _profileFullScreenPlaceholder();
  }
}

class _ProfilePostViewerPage extends StatelessWidget {
  const _ProfilePostViewerPage({required this.item});

  final PostItem item;

  @override
  Widget build(BuildContext context) {
    final safeThumb = _validThumbUrl(item.thumbUrl);
    final Widget heroChild = safeThumb != null
        ? CachedNetworkImage(
            imageUrl: safeThumb,
            fit: BoxFit.contain,
            placeholder: (context, url) => const _ShimmerTile(),
            errorWidget: (context, url, error) => _profileFullScreenPlaceholder(),
          )
        : _profileFullScreenPlaceholder();

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Hero(
          tag: 'profile_post_${item.id}',
          child: heroChild,
        ),
      ),
    );
  }
}

String? _validThumbUrl(String? url) {
  if (url == null) {
    return null;
  }
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final base = trimmed.toLowerCase().split('?').first;
  if (base.endsWith('.m3u8')) {
    return null;
  }
  return trimmed;
}

Widget _profileFullScreenPlaceholder() {
  return Container(
    color: Colors.black,
    alignment: Alignment.center,
    child: const Icon(
      Icons.broken_image_outlined,
      color: Colors.white70,
      size: 48,
    ),
  );
}
