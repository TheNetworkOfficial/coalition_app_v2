import 'dart:io';
import 'dart:math';

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
  final Random _random = Random();
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
    if (!mounted) {
      return;
    }
    setState(() {
      if (showLoader) {
        _isLoading = true;
      }
    });

    final apiClient = ref.read(apiClientProvider);
    try {
      final profile = await _fetchOrCreateProfile(apiClient);
      final posts = await apiClient.getMyPosts();
      if (!mounted) {
        return;
      }
      setState(() {
        _profile = profile;
        _posts = posts;
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
      if (error.statusCode != HttpStatus.notFound) {
        _showProfileErrorSnackBar(
          error.message.isNotEmpty
              ? error.message
              : 'Failed to load profile: ${error.statusCode}',
        );
      }
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showProfileErrorSnackBar('Failed to load profile: $error');
      setState(() {
        _isLoading = false;
        _hasLoaded = true;
      });
    }
  }

  Future<void> _refreshProfile() async {
    await _loadProfile(showLoader: false);
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
              _loadProfile();
            },
              ),
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final posts = _posts;
    final profile = _profile;
    final isInitialLoading = _isLoading && !_hasLoaded;
    final usernameValue = profile?.username?.trim().isNotEmpty == true
        ? profile!.username!.trim()
        : (authState.user?.username ?? '').trim();
    final usernameLabel =
        usernameValue.isNotEmpty ? '@$usernameValue' : 'Username pending';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshProfile,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: _ProfileDetailsSection(
                    profile: profile,
                    isLoading: _isLoading,
                    onEditProfile: _handleEditProfile,
                    onSignOut: _signOut,
                    usernameLabel: usernameLabel,
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
                          post: post,
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

  void _openPost(Post post) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _PostViewerPage(post: post),
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
  });

  final Profile? profile;
  final bool isLoading;
  final VoidCallback onEditProfile;
  final VoidCallback onSignOut;
  final String usernameLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = profile?.displayName?.trim();
    final avatarUrl = profile?.avatarUrl;
    final bio = profile?.bio;

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
              child: avatarUrl == null ? const Icon(Icons.person, size: 36) : null,
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
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: isLoading ? null : onEditProfile,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit profile'),
                  ),
                ],
              ),
            ),
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
          bio?.isNotEmpty == true
              ? bio!
              : 'Tell the community more about you.',
          style: theme.textTheme.bodyMedium,
        ),
      ],
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
  const _PostGridTile({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = post.duration;
    final hasThumb = post.thumbUrl != null && post.thumbUrl!.isNotEmpty;
    final canUseMedia = !post.isVideo && post.mediaUrl.isNotEmpty;
    final thumbnailUrl = hasThumb
        ? post.thumbUrl!
        : (canUseMedia ? post.mediaUrl : null);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => const _ShimmerTile(),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey.shade300,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              )
            else
              Container(
                color: Colors.grey.shade300,
                alignment: Alignment.center,
                child: Icon(
                  post.isVideo ? Icons.videocam_outlined : Icons.image_outlined,
                  color: Colors.grey.shade600,
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
                          Colors.grey.shade200.withAlpha(0),
                          Colors.grey.shade100.withAlpha(179), // ~0.7 * 255
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
