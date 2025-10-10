import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/providers/auth_state.dart';
import '../features/feed/models/post.dart';
import '../features/feed/ui/widgets/post_view.dart';
import '../models/profile.dart';
import '../providers/app_providers.dart';
import '../providers/upload_manager.dart';
import '../services/api_client.dart';
import 'edit_profile_page.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  Profile? _profile;
  List<Post> _posts = const [];
  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _hasPending = false;
  String? _error;
  ProviderSubscription<UploadManager>? _uploadSubscription;

  @override
  void initState() {
    super.initState();
    _uploadSubscription = ref.listenManual<UploadManager>(
      uploadManagerProvider,
      (previous, next) {
        final previousStatus = previous?.status;
        final nextStatus = next.status;
        if (previousStatus != nextStatus && nextStatus?.isFinalState == true) {
          _refreshProfile();
        }
      },
      fireImmediately: false,
    );
    _loadProfile();
  }

  @override
  void dispose() {
    _uploadSubscription?.close();
    super.dispose();
  }

  Future<void> _loadProfile({bool showLoader = true}) async {
    setState(() {
      if (showLoader) {
        _isLoading = true;
      }
      _error = null;
    });

    final apiClient = ref.read(apiClientProvider);
    try {
      final profile = await apiClient.getMyProfile();
      final posts = await apiClient.getMyPosts(includePending: true);
      final readyPosts = posts
          .where((post) => post.isVideo && post.status == PostStatus.ready)
          .toList();
      final hasPending = posts.any((post) => post.status != PostStatus.ready);
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _posts = readyPosts;
        _hasPending = hasPending;
        _isLoading = false;
        _hasLoaded = true;
      });
    } on ApiException catch (error) {
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
      setState(() {
        _error = error.message;
        _isLoading = false;
        _hasLoaded = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _isLoading = false;
        _hasLoaded = true;
      });
    }
  }

  Future<void> _refreshProfile() async {
    await _loadProfile(showLoader: false);
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    final profile = _profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          PopupMenuButton<String>(
            onSelected: _handleMenuSelected,
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'edit',
                child: Text('Edit profile'),
              ),
              const PopupMenuItem<String>(
                value: 'signout',
                child: Text('Sign out'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _ProfileHeader(
                profile: profile,
                isLoading: _isLoading,
                hasError: _error != null,
                onEditTap: _handleEditProfile,
              ),
            ),
            if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ProfileErrorView(
                  message: _error!,
                  onRetry: () => _loadProfile(),
                ),
              )
            else if (_isLoading && !_hasLoaded)
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const _ShimmerTile(),
                    childCount: 6,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 1,
                  ),
                ),
              )
            else if (posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _ProfileEmptyState(
                  hasPending: _hasPending,
                  onRefresh: _refreshProfile,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final post = posts[index];
                      return _PostGridTile(
                        post: post,
                        onTap: () => _openPost(post),
                      );
                    },
                    childCount: posts.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 1,
                  ),
                ),
              ),
          ],
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

  void _handleMenuSelected(String value) {
    switch (value) {
      case 'edit':
        _handleEditProfile();
        break;
      case 'signout':
        _signOut();
        break;
    }
  }

  Future<void> _signOut() async {
    await ref.read(authStateProvider.notifier).signOut();
    if (!mounted) {
      return;
    }
    context.go('/auth');
  }

  void _openPost(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _PostViewerPage(post: post),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.isLoading,
    required this.hasError,
    required this.onEditTap,
  });

  final Profile? profile;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onEditTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = profile?.displayName ?? 'Set your name';
    final username = profile?.username != null
        ? '@${profile!.username}'
        : 'Add a username';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage: profile?.avatarUrl != null
                    ? NetworkImage(profile!.avatarUrl!)
                    : null,
                child: profile?.avatarUrl == null
                    ? const Icon(Icons.person, size: 36)
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      username,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLoading && !hasError)
                TextButton.icon(
                  onPressed: onEditTap,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            profile?.bio?.isNotEmpty == true
                ? profile!.bio!
                : 'Tell the community more about you.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ProfileErrorView extends StatelessWidget {
  const _ProfileErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'We couldn\'t load your profile.',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileEmptyState extends StatelessWidget {
  const _ProfileEmptyState({required this.hasPending, required this.onRefresh});

  final bool hasPending;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasPending ? Icons.hourglass_empty : Icons.video_library_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              hasPending
                  ? 'Your video is processing—check back in a minute.'
                  : 'You haven\'t uploaded any videos yet.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: hasPending
                  ? () => onRefresh()
                  : () => GoRouter.of(context).go('/create'),
              child: Text(hasPending ? 'Refresh' : 'Upload a video'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostGridTile extends StatelessWidget {
  const _PostGridTile({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = post.duration;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: post.thumbUrl ?? post.mediaUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => const _ShimmerTile(),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey.shade300,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
            if (duration != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatDuration(duration),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
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
                final dx = (width + shimmerWidth) * _controller.value - shimmerWidth;
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: Container(
                    width: shimmerWidth,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.grey.shade200.withOpacity(0.0),
                          Colors.grey.shade100.withOpacity(0.7),
                          Colors.grey.shade200.withOpacity(0.0),
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

class _PostViewerPage extends StatefulWidget {
  const _PostViewerPage({required this.post});

  final Post post;

  @override
  State<_PostViewerPage> createState() => _PostViewerPageState();
}

class _PostViewerPageState extends State<_PostViewerPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PostView(
              post: widget.post,
              onProfileTap: () {},
              onCommentsTap: () {},
              initiallyActive: true,
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                color: Colors.white,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
