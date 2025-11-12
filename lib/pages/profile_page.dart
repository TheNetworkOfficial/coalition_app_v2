import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:coalition_app_v2/features/auth/providers/auth_state.dart';
import 'package:coalition_app_v2/features/auth/providers/current_user_roles_provider.dart';
import 'package:coalition_app_v2/features/candidates/ui/inline_editable.dart';
import 'package:coalition_app_v2/features/feed/models/post.dart';
import 'package:coalition_app_v2/models/posts_page.dart';
import 'package:coalition_app_v2/models/profile.dart';
import 'package:coalition_app_v2/providers/app_providers.dart';
import 'package:coalition_app_v2/providers/upload_manager.dart';
import 'package:coalition_app_v2/router/app_router.dart' show rootNavigatorKey;
import 'package:coalition_app_v2/services/api_client.dart';
import 'package:coalition_app_v2/widgets/post_grid_tile.dart';
import 'package:coalition_app_v2/widgets/user_avatar.dart';
import 'package:coalition_app_v2/shared/media/image_uploader.dart';
import 'package:coalition_app_v2/features/engagement/utils/ids.dart';

import 'settings_page.dart';

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
          : await apiClient.getUserPosts(targetUserId!,
              limit: 30, cursor: _cursor);
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
          username: (username != null && username.isNotEmpty) ? username : null,
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
    final rolesAsync = ref.watch(currentUserRolesProvider);
    final hasAdminAccess = ref.watch(hasAdminAccessProvider);
    final rolesState = rolesAsync.isLoading
        ? 'loading'
        : rolesAsync.hasError
            ? 'error'
            : 'data';
    final rolesValueForLog = rolesAsync.maybeWhen<List<String>?>(
      data: (roles) => roles,
      orElse: () => null,
    );
    debugPrint(
      '[ProfilePage][TEMP] rolesAsync state=$rolesState roles=$rolesValueForLog hasAdminAccess=$hasAdminAccess',
    );
    final uploadManager = ref.watch(uploadManagerProvider);
    final pendingPosts =
        _isViewingSelf ? uploadManager.pendingPosts : const <PostItem>[];
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
    final showAdminDashboardMenu = _isViewingSelf && hasAdminAccess;
    final adminMenuEnabled = !rolesAsync.isLoading && !rolesAsync.hasError;
    final candidateStatus =
        (profile?.candidateAccessStatus ?? 'none').trim();
    final openAdminDashboardCallback =
        showAdminDashboardMenu ? _openAdminDashboard : null;
    debugPrint(
      '[ProfilePage][TEMP] overflow gating isViewingSelf=$_isViewingSelf showAdminDashboardMenu=$showAdminDashboardMenu adminMenuEnabled=$adminMenuEnabled',
    );
    final profileTitle = profile?.displayName?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          profileTitle?.isNotEmpty == true ? profileTitle! : 'Profile',
        ),
        actions: [
          if (_isViewingSelf)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () {
                final args = SettingsArgs(
                  onEditProfile: _handleEditProfile,
                  onSignOut: _signOut,
                  onOpenAdminDashboard: openAdminDashboardCallback,
                  showCandidateAccess: candidateStatus != 'approved',
                  showAdminDashboard: showAdminDashboardMenu,
                  adminDashboardEnabled: adminMenuEnabled,
                );
                context.push('/settings', extra: args);
              },
            ),
        ],
      ),
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
                    usernameLabel: usernameLabel,
                    onSaveProfile: _saveProfile,
                    onEditCandidatePage: _handleEditCandidatePage,
                    onToggleFollow: onToggleFollow,
                    showActions: _isViewingSelf,
                  ),
                ),
              ),
              if (isInitialLoading)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => const PostGridShimmer(),
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
                        return PostGridTile(
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
    final navigator = rootNavigatorKey.currentState;
    if (navigator?.canPop() ?? false) {
      navigator?.pop();
    }
  }

  Future<void> _saveProfile(ProfileUpdate update) async {
    final apiClient = ref.read(apiClientProvider);
    final updated = await apiClient.upsertMyProfile(update);
    if (!mounted) {
      return;
    }
    setState(() => _profile = updated);
  }

  void _handleEditCandidatePage() {
    if (!mounted) {
      return;
    }
    context.pushNamed('candidate_edit');
  }

  void _openAdminDashboard() {
    final targetContext = rootNavigatorKey.currentContext ?? context;
    GoRouter.of(targetContext).push('/admin');
  }

  Future<void> _signOut() async {
    await ref.read(authStateProvider.notifier).signOut();
    if (!mounted) {
      return;
    }
    context.go('/auth');
  }

  void _openPost(PostItem item) {
    final postId = normalizePostId(item.id);
    if (postId.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Post unavailable.')),
        );
      return;
    }
    final post = _mapPostItemToPost(item, postId: postId);
    if (post == null) {
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Post unavailable.')),
        );
      return;
    }
    context.pushNamed('post_view', extra: post);
  }

  Post? _mapPostItemToPost(PostItem item, {required String postId}) {
    final playbackUrl = (item.playbackUrl ?? '').trim();
    if (playbackUrl.isEmpty) {
      return null;
    }

    String? ownerId = _profile?.userId;
    if (ownerId != null) {
      ownerId = normalizeUserId(ownerId);
      if (ownerId.isEmpty) {
        ownerId = null;
      }
    }

    final ownerDisplayName = _profile?.displayName ??
        _profile?.username ??
        (_isViewingSelf ? 'You' : 'Unknown');

    PostStatus _resolveStatus() {
      final normalizedStatus = item.status.toUpperCase();
      if (normalizedStatus == 'FAILED') {
        return PostStatus.failed;
      }
      if (item.isReady) {
        return PostStatus.ready;
      }
      return PostStatus.processing;
    }

    return Post(
      id: postId,
      mediaUrl: playbackUrl,
      isVideo: true,
      userId: ownerId,
      userDisplayName: ownerDisplayName,
      userAvatarUrl: _profile?.avatarUrl,
      description: item.caption ?? item.description,
      thumbUrl: item.thumbUrl,
      status: _resolveStatus(),
      type: 'video',
      duration: item.duration,
      likeCount: item.likesCount,
      isLiked: item.likedByMe,
      commentCount: null,
    );
  }
}

class _ProfileDetailsSection extends ConsumerStatefulWidget {
  const _ProfileDetailsSection({
    required this.profile,
    required this.isLoading,
    required this.usernameLabel,
    required this.onSaveProfile,
    this.onEditCandidatePage,
    this.onToggleFollow,
    this.showActions = true,
  });

  final Profile? profile;
  final bool isLoading;
  final String usernameLabel;
  final Future<void> Function(ProfileUpdate update) onSaveProfile;
  final VoidCallback? onEditCandidatePage;
  final bool showActions;
  final Future<void> Function(String targetUserId, bool next)? onToggleFollow;

  @override
  ConsumerState<_ProfileDetailsSection> createState() =>
      _ProfileDetailsSectionState();
}

class _ProfileDetailsSectionState
    extends ConsumerState<_ProfileDetailsSection> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _bioController;
  ImageProvider? _avatarPreview;
  bool _avatarUploading = false;
  bool _savingProfile = false;
  bool _isEditingProfile = false; // page-level edit gate

  @override
  void initState() {
    super.initState();
    _displayNameController =
        TextEditingController(text: widget.profile?.displayName ?? '');
    _bioController = TextEditingController(text: widget.profile?.bio ?? '');
  }

  @override
  void didUpdateWidget(covariant _ProfileDetailsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newDisplayName = widget.profile?.displayName ?? '';
    if (newDisplayName != oldWidget.profile?.displayName &&
        newDisplayName != _displayNameController.text) {
      _displayNameController.value = TextEditingValue(
        text: newDisplayName,
        selection: TextSelection.collapsed(offset: newDisplayName.length),
      );
    }

    final newBio = widget.profile?.bio ?? '';
    if (newBio != oldWidget.profile?.bio &&
        newBio != _bioController.text) {
      _bioController.value = TextEditingValue(
        text: newBio,
        selection: TextSelection.collapsed(offset: newBio.length),
      );
    }

    if (widget.profile?.avatarUrl != oldWidget.profile?.avatarUrl) {
      _avatarPreview = null;
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _enterEditMode() {
    if (!_isEditingProfile) {
      setState(() => _isEditingProfile = true);
    }
  }

  Future<void> _saveAllEdits() async {
    if (_savingProfile) return;

    final original = widget.profile;
    final name = _displayNameController.text.trim();
    final bio = _bioController.text.trim();

    // Require non-empty name (match prior UX)
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name is required')),
      );
      return;
    }

    // Only send changed fields
    final update = ProfileUpdate(
      displayName: name != (original?.displayName ?? '') ? name : null,
      bio: bio != (original?.bio ?? '') ? bio : null,
    );

    // If nothing changed, just exit edit mode
    if (update.displayName == null && update.bio == null) {
      setState(() => _isEditingProfile = false);
      FocusScope.of(context).unfocus();
      return;
    }

    setState(() => _savingProfile = true);
    try {
      await widget.onSaveProfile(update);
      if (!mounted) return;
      setState(() => _isEditingProfile = false);
      FocusScope.of(context).unfocus();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.profile;
    final displayName = (profile?.displayName ?? '').trim();
    final hasDisplayName = displayName.isNotEmpty;
    final displayText = hasDisplayName ? displayName : 'Set your display name';
    final bio = profile?.bio;
    final avatarUrl = profile?.avatarUrl;
    final toggleFollow = widget.onToggleFollow;
    final candidateStatus = (profile?.candidateAccessStatus ?? 'none').trim();
    final candidateEditHandler = widget.onEditCandidatePage;
    final bool showCandidateEditButton = widget.showActions &&
        candidateStatus == 'approved' &&
        candidateEditHandler != null;
    final bool canEdit =
        widget.showActions && !widget.isLoading && profile != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AvatarEditor(
              avatarUrl: avatarUrl,
              preview: _avatarPreview,
              isEnabled: canEdit && !_avatarUploading,
              isUploading: _avatarUploading,
              onTap: _handleAvatarTap,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: InlineEditable(
                          key: ValueKey(_isEditingProfile), // force mode refresh
                          readOnly:
                              !(widget.showActions && _isEditingProfile),
                          startInEdit:
                              widget.showActions && _isEditingProfile,
                          readOnlyHint: 'Tap Edit to make changes',
                          view: _DisplayNameView(
                            text: displayText,
                            isPlaceholder: !hasDisplayName,
                            // Hide decorative icon; we render a real button at the row end
                            showEditIcon: false,
                          ),
                          edit: TextField(
                            controller: _displayNameController,
                            autofocus: true, // focus when edit mode turns on
                            enabled: widget.showActions && !_savingProfile,
                            maxLength: 120,
                            style: theme.textTheme.titleLarge,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              counterText: '',
                            ),
                          ),
                        ),
                      ),
                      if (widget.showActions)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _EditSaveButton(
                            isEditing: _isEditingProfile,
                            isSaving: _savingProfile,
                            onEdit: _enterEditMode,
                            onSave: _saveAllEdits,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.usernameLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ProfileStatsRow(profile: profile),
                  if (showCandidateEditButton) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.isLoading ? null : candidateEditHandler,
                      icon: const Icon(Icons.campaign_outlined),
                      label: const Text('Edit candidate page'),
                    ),
                  ],
                  if (!widget.showActions &&
                      profile != null &&
                      toggleFollow != null) ...[
                    const SizedBox(height: 12),
                    _FollowButton(
                      targetUserId: profile.userId,
                      isFollowing: profile.isFollowing,
                      onToggle: toggleFollow,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        InlineEditable(
          key: ValueKey('bio_${_isEditingProfile ? 'edit' : 'view'}'),
          readOnly: !(widget.showActions && _isEditingProfile),
          startInEdit: widget.showActions && _isEditingProfile,
          readOnlyHint: 'Tap Edit to make changes',
          view: Text(
            bio?.isNotEmpty == true
                ? bio!
                : 'Tell the community more about you.',
            style: theme.textTheme.bodyMedium,
          ),
          edit: TextField(
            controller: _bioController,
            autofocus: false, // display name grabs focus
            enabled: widget.showActions && !_savingProfile,
            maxLines: 4,
            maxLength: 150,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              counterText: '',
            ),
          ),
        ),
        if (_savingProfile)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Future<void> _handleAvatarTap() async {
    if (!widget.showActions || widget.isLoading || _avatarUploading) {
      return;
    }
    setState(() => _avatarUploading = true);
    try {
      final result = await pickAndUploadProfileImage(
        context: context,
        ref: ref,
      );
      if (result == null) {
        setState(() => _avatarUploading = false);
        return;
      }
      if (result.preview != null) {
        setState(() {
          _avatarPreview = result.preview;
        });
      }
      await widget.onSaveProfile(
        ProfileUpdate(avatarUrl: result.remoteUrl),
      );
      if (mounted) {
        setState(() {
          _avatarPreview = null;
        });
      }
    } on ApiException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('Failed to update avatar. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _avatarUploading = false);
      }
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EditSaveButton extends StatelessWidget {
  const _EditSaveButton({
    required this.isEditing,
    required this.isSaving,
    required this.onEdit,
    required this.onSave,
  });

  final bool isEditing;
  final bool isSaving;
  final VoidCallback onEdit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    if (isEditing) {
      if (isSaving) {
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      }
      return IconButton(
        tooltip: 'Save',
        icon: const Icon(Icons.check),
        onPressed: onSave,
      );
    }
    return IconButton(
      tooltip: 'Edit profile',
      icon: const Icon(Icons.edit_outlined),
      onPressed: onEdit,
    );
  }
}

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.avatarUrl,
    required this.preview,
    required this.isEnabled,
    required this.isUploading,
    required this.onTap,
  });

  final String? avatarUrl;
  final ImageProvider? preview;
  final bool isEnabled;
  final bool isUploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: isEnabled ? onTap : null,
          child: SizedBox(
            width: 72,
            height: 72,
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  UserAvatar(
                    url: avatarUrl,
                    size: 72,
                  ),
                  if (preview != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: true,
                        child: Image(
                          image: preview!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  if (!isEnabled)
                    Container(
                      color: theme.colorScheme.surface.withValues(alpha: 0.12),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (isEnabled && !isUploading)
          Positioned(
            bottom: -2,
            right: -2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        if (isUploading)
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DisplayNameView extends StatelessWidget {
  const _DisplayNameView({
    required this.text,
    required this.isPlaceholder,
    required this.showEditIcon,
  });

  final String text;
  final bool isPlaceholder;
  final bool showEditIcon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.titleLarge?.copyWith(
      color: isPlaceholder
          ? theme.colorScheme.onSurfaceVariant
          : theme.textTheme.titleLarge?.color,
    );
    final iconColor = theme.colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            text,
            style: textStyle,
          ),
        ),
        if (showEditIcon)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Icon(
              Icons.edit_outlined,
              size: 18,
              color: iconColor,
            ),
          ),
      ],
    );
  }
}

class _ProfileStatsRow extends StatelessWidget {
  const _ProfileStatsRow({required this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final followers = profile?.followersCount ?? 0;
    final following = profile?.followingCount ?? 0;
    final likes = profile?.totalLikes ?? 0;

    Widget stat(String label, int value) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              value.toString(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        stat('Followers', followers),
        stat('Following', following),
        stat('Likes', likes),
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
