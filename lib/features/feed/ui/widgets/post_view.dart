import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../models/post.dart';
import 'expandable_description.dart';
import 'overlay_actions.dart';

class PostView extends StatefulWidget {
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
  State<PostView> createState() => PostViewState();
}

class PostViewState extends State<PostView>
    with AutomaticKeepAliveClientMixin<PostView> {
  VideoPlayerController? _videoController;
  bool _isFavorite = false;
  bool _isActive = false;
  // --- NEW: user-intent & speed coordination ---
  bool _userPaused = false; // true if user explicitly paused via tap
  double _userSpeed = 1.0; // baseline playback speed user expects
  double? _holdPrevSpeed; // temporary cache used during long-press
  bool _holdWasPaused = false; // whether video was paused before the hold

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _isActive = widget.initiallyActive;
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
      _isActive = widget.initiallyActive;
      _userPaused = false;
      _userSpeed = 1.0;
      _holdPrevSpeed = null;
      _holdWasPaused = false;
      _updatePlayback();
    }
  }

  @override
  void dispose() {
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
    setState(() => _isFavorite = !_isFavorite);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _isFavorite ? 'Liked!' : 'Unliked.',
          ),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                    onCommentsTap: widget.onCommentsTap,
                    onFavoriteTap: _toggleFavorite,
                    onShareTap: _share,
                    isFavorite: _isFavorite,
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
    if (url == null || url.isEmpty) {
      return Container(color: Colors.black);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    // Visual-only overlay; ignore pointer events so taps fall through to
    // the video surface beneath.
    return IgnorePointer(
      ignoring: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.2),
              Colors.black.withValues(alpha: 0.05),
              Colors.black.withValues(alpha: 0.4),
              Colors.black.withValues(alpha: 0.8),
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
}
