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
    final mediaChanged =
        widget.post.mediaUrl != oldWidget.post.mediaUrl ||
            widget.post.isVideo != oldWidget.post.isVideo;
    if (mediaChanged) {
      _disposeVideo();
      _updatePlayback();
    }
    if (widget.post.id != oldWidget.post.id) {
      _isActive = widget.initiallyActive;
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
    controller.setVolume(0);

    controller.initialize().then((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
      _updatePlayback();
    }).catchError((_) {});

    _videoController = controller;
  }

  void _updatePlayback() {
    if (!widget.post.isVideo || widget.post.mediaUrl.isEmpty) {
      return;
    }

    final controller = _videoController;
    if (_isActive) {
      if (controller == null) {
        _initializeVideoIfNeeded();
        return;
      }
      if (!controller.value.isInitialized) {
        return;
      }
      controller.play();
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
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(controller),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.2),
            Colors.black.withOpacity(0.05),
            Colors.black.withOpacity(0.4),
            Colors.black.withOpacity(0.8),
          ],
          stops: const [0, 0.4, 0.7, 1],
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
}
