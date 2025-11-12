import 'package:coalition_app_v2/core/ids.dart' show normalizePostId;
import 'package:coalition_app_v2/core/realtime/realtime_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../models/post.dart';
import '../../../engagement/models/post_engagement.dart';
import '../../../engagement/providers/engagement_providers.dart';
import '../../../engagement/ui/likers_sheet.dart';
import 'expandable_description.dart';
import 'overlay_actions.dart';

class PostView extends ConsumerStatefulWidget {
  const PostView({
    super.key,
    required this.post,
    required this.onProfileTap,
    required this.onCommentsTap,
    this.initiallyActive = false,
  });

  final Post post;
  final VoidCallback onProfileTap;
  final VoidCallback onCommentsTap;
  final bool initiallyActive;

  @override
  ConsumerState<PostView> createState() => PostViewState();
}

class PostViewState extends ConsumerState<PostView>
    with AutomaticKeepAliveClientMixin<PostView> {
  VideoPlayerController? _videoController;
  bool _isActive = false;
  // --- NEW: user-intent & speed coordination ---
  bool _userPaused = false; // true if user explicitly paused via tap
  double _userSpeed = 1.0; // baseline playback speed user expects
  double? _holdPrevSpeed; // temporary cache used during long-press
  bool _holdWasPaused = false; // whether video was paused before the hold
  late String _postId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _postId = normalizePostId(widget.post.id);
    assert(() {
      debugPrint('[PostView] postId=$_postId');
      return true;
    }());
    _isActive = widget.initiallyActive;
    ref.read(realtimeReducerProvider);
    if (_postId.isNotEmpty) {
      ref.read(realtimeServiceProvider).subscribePost(_postId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _seedEngagement();
      });
    }
    _updatePlayback();
  }

  @override
  void didUpdateWidget(covariant PostView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final mediaChanged = widget.post.mediaUrl != oldWidget.post.mediaUrl ||
        widget.post.isVideo != oldWidget.post.isVideo;
    if (mediaChanged) {
      _disposeVideo();
      _userPaused = false;
      _userSpeed = 1.0;
      _holdPrevSpeed = null;
      _holdWasPaused = false;
      _updatePlayback();
    }
    if (widget.post.id != oldWidget.post.id) {
      final previousId = _postId;
      if (previousId.isNotEmpty) {
        ref.read(realtimeServiceProvider).unsubscribePost(previousId);
      }
      _postId = normalizePostId(widget.post.id);
      assert(() {
        debugPrint('[PostView] postId=$_postId');
        return true;
      }());
      if (_postId.isNotEmpty) {
        ref.read(realtimeServiceProvider).subscribePost(_postId);
      }
      _isActive = widget.initiallyActive;
      _userPaused = false;
      _userSpeed = 1.0;
      _holdPrevSpeed = null;
      _holdWasPaused = false;
      if (_postId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _seedEngagement();
        });
      }
      _updatePlayback();
    }
  }

  @override
  void dispose() {
    if (_postId.isNotEmpty) {
      ref.read(realtimeServiceProvider).unsubscribePost(_postId);
    }
    _disposeVideo();
    super.dispose();
  }

  void _initializeVideoIfNeeded() {
    if (!_isActive) {
      return;
    }
    if (_videoController != null) {
      return;
    }
    if (!widget.post.isVideo || widget.post.mediaUrl.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(widget.post.mediaUrl);
    if (uri == null) {
      return;
    }

    final controller = VideoPlayerController.networkUrl(uri);
    controller.setLooping(true);
    // Always start audible; device hardware buttons control loudness.
    // Do not set volume to 0 on feed.

    controller.initialize().then((_) {
      if (!mounted || _videoController != controller) {
        return;
      }
      // Ensure audible after init (some platforms default to 1.0, this is explicit).
      _ensureAudible(controller);
      setState(() {});
      _updatePlayback();
    }).catchError((_) {});

    _videoController = controller;
  }

  void _ensureAudible(VideoPlayerController c) {
    try {
      final value = c.value;
      if (!value.isInitialized || value.volume == 0.0) {
        c.setVolume(1.0);
      }
    } catch (_) {
      try {
        c.setVolume(1.0);
      } catch (_) {}
    }
  }

  void _updatePlayback() {
    if (!widget.post.isVideo || widget.post.mediaUrl.isEmpty) {
      return;
    }

    final controller = _videoController;
    debugPrint(
        '[PostView] _updatePlayback: isActive=$_isActive controller=${controller != null} userPaused=$_userPaused');
    if (_isActive) {
      if (controller == null) {
        _initializeVideoIfNeeded();
        return;
      }
      if (!controller.value.isInitialized) {
        return;
      }
      // Respect user intent: don't auto-play if user explicitly paused.
      if (_userPaused) {
        debugPrint(
            '[PostView] _updatePlayback: honoring _userPaused -> pause()');
        controller.pause();
        return;
      }
      // Auto-play when active, applying user's chosen baseline speed.
      debugPrint(
          '[PostView] _updatePlayback: auto-play -> play() at speed=$_userSpeed');
      // Safety: if some earlier code or recycled state zeroed volume, restore it.
      _ensureAudible(controller);
      controller
        ..play()
        ..setPlaybackSpeed(_userSpeed);
      return;
    }

    if (controller == null) {
      return;
    }

    if (controller.value.isInitialized) {
      controller
        ..pause()
        ..seekTo(Duration.zero);
    }
    // Clear transient hold-only state when deactivating
    _holdPrevSpeed = null;
    _holdWasPaused = false;
    _disposeVideo();
  }

  void _disposeVideo() {
    final controller = _videoController;
    _videoController = null;
    controller?.dispose();
  }

  void _toggleFavorite() {
    if (_postId.isEmpty) {
      _showEngagementUnavailable();
      return;
    }
    final notifier =
        ref.read(postEngagementProvider(_postId).notifier);
    final current = ref.read(postEngagementProvider(_postId));
    final target = !current.isLiked;
    notifier.toggleLike();
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(target ? 'Liked!' : 'Unliked.'),
        ),
      );
  }

  void _share() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Share coming soon'),
        ),
      );
  }

  void _showEngagementUnavailable() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Engagement unavailable for this post.'),
        ),
      );
  }

  void _showLikers() {
    if (_postId.isEmpty) {
      _showEngagementUnavailable();
      return;
    }
    showLikersSheet(context, _postId);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final bool engagementEnabled = _postId.isNotEmpty;
    final PostEngagementState engagement = engagementEnabled
        ? ref.watch(postEngagementProvider(_postId))
        : PostEngagementState(
            postId: '',
            isLiked: widget.post.isLiked ?? false,
            likeCount: widget.post.likeCount ?? 0,
            commentCount: widget.post.commentCount ?? 0,
            loadedOnce: true,
          );
    debugPrint(
      '[PostView] bind onProfileTap | postId=${widget.post.id} userId=${widget.post.userId ?? '<null>'}',
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildMedia(),
        _buildGradientOverlay(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: OverlayActions(
                    avatarUrl: widget.post.userAvatarUrl,
                    onProfileTap: widget.onProfileTap,
                    onCommentsTap: engagementEnabled
                        ? widget.onCommentsTap
                        : _showEngagementUnavailable,
                    onFavoriteTap: engagementEnabled
                        ? _toggleFavorite
                        : _showEngagementUnavailable,
                    onFavoriteLongPress:
                        engagementEnabled ? _showLikers : null,
                    onLikersTap: engagementEnabled
                        ? _showLikers
                        : _showEngagementUnavailable,
                    onShareTap: _share,
                    isFavorite: engagement.isLiked,
                    likeCount: engagement.likeCount,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    child: ExpandableDescription(
                      displayName: widget.post.userDisplayName,
                      description: widget.post.description,
                      onDisplayNameTap: widget.onProfileTap,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMedia() {
    if (widget.post.isVideo) {
      return _buildVideo();
    }
    return _buildImage(widget.post.mediaUrl);
  }

  Widget _buildVideo() {
    final controller = _videoController;
    if (controller != null && controller.value.isInitialized) {
      final size = controller.value.size;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onSurfaceTapTogglePlayPause,
        onLongPressStart: (_) => _onSurfaceHoldStart(),
        onLongPressEnd: (_) => _onSurfaceHoldEnd(),
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildImage(widget.post.thumbUrl ?? widget.post.mediaUrl),
        const Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      ],
    );
  }

  Widget _buildImage(String? url) {
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface;
    if (url == null || url.isEmpty) {
      return ColoredBox(color: surfaceColor);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return ColoredBox(
          color: surfaceColor,
          child: const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => ColoredBox(
        color: surfaceColor,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: colorScheme.onSurface.withValues(alpha: 0.54),
          ),
        ),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    // Visual-only overlay; ignore pointer events so taps fall through to
    // the video surface beneath.
    final colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.scrim.withValues(alpha: 0.20),
              colorScheme.scrim.withValues(alpha: 0.05),
              colorScheme.scrim.withValues(alpha: 0.40),
              colorScheme.scrim.withValues(alpha: 0.80),
            ],
            stops: const [0, 0.4, 0.7, 1],
          ),
        ),
      ),
    );
  }

  void onActiveChanged(bool isActive) {
    if (_isActive != isActive) {
      _isActive = isActive;
    }
    _updatePlayback();
  }

  void _onSurfaceTapTogglePlayPause() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    debugPrint(
        '[PostView] _onSurfaceTapTogglePlayPause: wasPlaying=${c.value.isPlaying}');
    // Toggle play/pause and set user intent flag
    if (c.value.isPlaying) {
      _userPaused = true;
      c.pause();
    } else {
      _userPaused = false;
      c
        ..play()
        ..setPlaybackSpeed(_userSpeed);
    }
    setState(() {});
  }

  void _onSurfaceHoldStart() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    _holdPrevSpeed ??= c.value.playbackSpeed;
    _holdWasPaused = !c.value.isPlaying;
    // During hold: ensure playing at 2.0x regardless of prior speed
    c.play();
    c.setPlaybackSpeed(2.0);
    // Do NOT change _userPaused here; this is a transient hold state
    setState(() {});
  }

  void _onSurfaceHoldEnd() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) {
      return;
    }
    // Restore user's baseline speed and prior pause/play state
    final targetSpeed = _holdPrevSpeed ?? _userSpeed;
    c.setPlaybackSpeed(targetSpeed);
    if (_holdWasPaused) {
      c.pause();
    } else {
      if (!_userPaused) {
        c.play();
      } else {
        c.pause();
      }
    }
    // Clear transient hold flags
    _holdPrevSpeed = null;
    _holdWasPaused = false;
    setState(() {});
  }

  void _seedEngagement() {
    if (_postId.isEmpty) {
      return;
    }
    ref
        .read(postEngagementProvider(_postId).notifier)
        .ensureLoaded(
          isLikedSeed: widget.post.isLiked,
          likeCountSeed: widget.post.likeCount,
          commentCountSeed: widget.post.commentCount,
        );
  }
}
