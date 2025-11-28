import 'dart:convert';

import 'package:coalition_app_v2/utils/cloudflare_stream.dart';
import 'package:coalition_app_v2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:coalition_app_v2/models/edit_manifest.dart';
import 'read_only_overlay_text_layer.dart';

enum FeedMediaType { image, video }

class FeedEntry {
  FeedEntry({
    required this.id,
    required this.type,
    this.description,
    this.imageUrl,
    this.videoUrl,
    this.previewImageUrl,
    this.aspectRatio,
    this.authorName,
    this.authorAvatarUrl,
    this.editTimeline,
    this.editTimelineMap,
    EditManifest? editManifest,
  }) : _editManifest = editManifest;

  factory FeedEntry.fromJson(
    Map<String, dynamic> json, {
    required String fallbackId,
  }) {
    String? _asString(dynamic value) {
      if (value is String && value.isNotEmpty) {
        return value;
      }
      if (value is num) {
        return value.toString();
      }
      return null;
    }

    double? _asPositiveDouble(dynamic value) {
      if (value is num && value > 0) {
        return value.toDouble();
      }
      if (value is Map) {
        final width = value['width'];
        final height = value['height'];
        if (width is num && height is num && width > 0 && height > 0) {
          return width.toDouble() / height.toDouble();
        }
      }
      return null;
    }


    final typeString = _asString(json['type'])?.toLowerCase() ?? '';
    final type =
        typeString == 'video' ? FeedMediaType.video : FeedMediaType.image;

    final id = _asString(json['id']) ??
        _asString(json['postId']) ??
        _asString(json['uuid']) ??
        _asString(json['slug']) ??
        fallbackId;

    final description = _asString(json['description']) ??
        _asString(json['caption']) ??
        _asString(json['text']);

    String? imageUrl = _asString(json['imageUrl']) ??
        _asString(json['croppedImageUrl']) ??
        _asString(json['previewImageUrl']) ??
        _asString(json['thumbnailUrl']) ??
        _asString(json['mediaUrl']) ??
        _asString(json['url']);

    String? previewImageUrl = _asString(json['previewImageUrl']) ??
        _asString(json['thumbnailUrl']) ??
        _asString(json['coverUrl']) ??
        _asString(json['posterUrl']) ??
        imageUrl;

    String? videoUrl = resolveCloudflareHlsUrl(json) ??
        _asString(json['videoUrl']) ??
        _asString(json['streamUrl']) ??
        _asString(json['mediaUrl']) ??
        _asString(json['url']);

    final aspectRatio = _asPositiveDouble(json['aspectRatio']) ??
        _asPositiveDouble(json['ratio']);

    final user = json['user'];
    String? authorName;
    String? avatarUrl;
    if (user is Map<String, dynamic>) {
      authorName = _asString(user['name']) ??
          _asString(user['username']) ??
          _asString(user['displayName']);
      avatarUrl = _asString(user['avatarUrl']) ??
          _asString(user['avatar']) ??
          _asString(user['profileImage']);
    }

    authorName ??= _asString(json['authorName']) ?? _asString(json['username']);
    avatarUrl ??= _asString(json['authorAvatarUrl']);
    final rawEditTimeline = json['editTimeline'] ??
        json['edit_timeline'] ??
        json['editManifest'] ??
        json['edit_manifest'];
    final editTimelineMap = EditManifest.parseTimelineMap(rawEditTimeline);
    final editTimeline = EditManifest.stringifyTimeline(rawEditTimeline) ??
        (editTimelineMap != null ? jsonEncode(editTimelineMap) : null);
    final parsedEditManifest =
        EditManifest.tryParseFromRawTimeline(rawEditTimeline);

    if (type == FeedMediaType.image) {
      if (imageUrl == null) {
        throw const FormatException('Missing image URL for feed item');
      }
      return FeedEntry(
        id: id,
        type: FeedMediaType.image,
        description: description,
        imageUrl: imageUrl,
        previewImageUrl: previewImageUrl,
        aspectRatio: aspectRatio,
        authorName: authorName,
        authorAvatarUrl: avatarUrl,
        editTimeline: editTimeline,
        editTimelineMap: editTimelineMap,
        editManifest: parsedEditManifest,
      );
    } else {
      if (videoUrl == null) {
        throw const FormatException('Missing video URL for feed item');
      }
      return FeedEntry(
        id: id,
        type: FeedMediaType.video,
        description: description,
        videoUrl: videoUrl,
        previewImageUrl: previewImageUrl,
        aspectRatio: aspectRatio,
        authorName: authorName,
        authorAvatarUrl: avatarUrl,
        editTimeline: editTimeline,
        editTimelineMap: editTimelineMap,
        editManifest: parsedEditManifest,
      );
    }
  }

  final String id;
  final FeedMediaType type;
  final String? description;
  final String? imageUrl;
  final String? videoUrl;
  final String? previewImageUrl;
  final double? aspectRatio;
  final String? authorName;
  final String? authorAvatarUrl;
  final String? editTimeline;
  final Map<String, dynamic>? editTimelineMap;
  final EditManifest? _editManifest;

  EditManifest? get editManifest =>
      _editManifest ??
      EditManifest.tryParseFromRawTimeline(editTimelineMap ?? editTimeline);
}

class FeedItem extends StatefulWidget {
  const FeedItem({super.key, required this.item, required this.isActive});

  final FeedEntry item;
  final bool isActive;

  @override
  State<FeedItem> createState() => _FeedItemState();
}

class _FeedItemState extends State<FeedItem> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  bool _userPaused = false;

  @override
  void initState() {
    super.initState();
    _updatePlayback();
  }

  @override
  void didUpdateWidget(covariant FeedItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.item.type == FeedMediaType.video &&
        oldWidget.item.videoUrl != widget.item.videoUrl) {
      _disposeController();
      _updatePlayback();
    }

    if (widget.isActive != oldWidget.isActive) {
      _updatePlayback();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _maybeInitializeController() {
    if (_controller != null) {
      return;
    }
    if (!widget.isActive) {
      return;
    }
    if (widget.item.type != FeedMediaType.video ||
        widget.item.videoUrl == null) {
      return;
    }

    late Uri uri;
    try {
      uri = Uri.parse(widget.item.videoUrl!);
    } catch (_) {
      return;
    }
    final controller = VideoPlayerController.networkUrl(uri);
    _initializeFuture = controller.initialize().then((_) {
      if (!mounted || _controller != controller) {
        return;
      }
      controller
        ..setLooping(true)
        ..setVolume(1.0);
      setState(() {});
      _updatePlayback();
    });

    _controller = controller;
  }

  void _updatePlayback() {
    if (widget.item.type != FeedMediaType.video) {
      return;
    }

    final controller = _controller;
    debugPrint(
        '[FeedItem] _updatePlayback: isActive=${widget.isActive} controller=${controller != null} userPaused=$_userPaused');
    if (widget.isActive) {
      if (controller == null) {
        _maybeInitializeController();
        return;
      }
      if (!controller.value.isInitialized) {
        return;
      }
      if (_userPaused) {
        debugPrint(
            '[FeedItem] _updatePlayback: honoring _userPaused -> pause()');
        controller.pause();
      } else {
        debugPrint('[FeedItem] _updatePlayback: auto-play -> play()');
        controller.play();
      }
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
    _disposeController();
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _initializeFuture = null;
    _userPaused = false;
    controller?.dispose();
  }

  void _onVideoTap() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    debugPrint(
        '[FeedItem] _onVideoTap: wasPlaying=${controller.value.isPlaying}');
    final wasPlaying = controller.value.isPlaying;
    if (wasPlaying) {
      controller.pause();
      setState(() {
        _userPaused = true;
      });
    } else {
      controller.play();
      setState(() {
        _userPaused = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.authorName != null || item.authorAvatarUrl != null)
            ListTile(
              leading: UserAvatar(
                url: item.authorAvatarUrl,
                size: 40,
              ),
              title: Text(item.authorName ?? 'Unknown'),
            ),
          _MediaContent(
            controller: _controller,
            initializeFuture: _initializeFuture,
            item: item,
            onVideoTap: _onVideoTap,
          ),
          if ((item.description ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                item.description!,
                style: theme.textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaContent extends StatelessWidget {
  const _MediaContent({
    required this.controller,
    required this.initializeFuture,
    required this.item,
    required this.onVideoTap,
  });

  final VideoPlayerController? controller;
  final Future<void>? initializeFuture;
  final FeedEntry item;
  final VoidCallback? onVideoTap;

  @override
  Widget build(BuildContext context) {
    switch (item.type) {
      case FeedMediaType.image:
        return _ImageContent(item: item);
      case FeedMediaType.video:
        return _VideoContent(
          controller: controller,
          initializeFuture: initializeFuture,
          item: item,
          onTap: onVideoTap,
        );
    }
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.item});

  final FeedEntry item;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = item.aspectRatio ?? 4 / 5;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Image.network(
        item.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined, size: 32),
        ),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          return Container(
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        },
      ),
    );
  }
}

class _VideoContent extends StatelessWidget {
  const _VideoContent({
    required this.controller,
    required this.initializeFuture,
    required this.item,
    required this.onTap,
  });

  final VideoPlayerController? controller;
  final Future<void>? initializeFuture;
  final FeedEntry item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final videoController = controller;
    final overlayManifest = item.editManifest;
    final aspectRatio = videoController?.value.isInitialized == true
        ? videoController!.value.aspectRatio
        : (item.aspectRatio ?? 9 / 16);
    Widget mediaContent;

    if (videoController != null) {
      mediaContent = FutureBuilder<void>(
        future: initializeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              videoController.value.isInitialized) {
            return Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(videoController),
                if (overlayManifest != null)
                  IgnorePointer(
                    child: ReadOnlyOverlayTextLayer(
                      videoController: videoController,
                      editManifest: overlayManifest,
                    ),
                  ),
              ],
            );
          }
          return _VideoPlaceholder(item: item);
        },
      );
    } else {
      mediaContent = _VideoPlaceholder(item: item);
    }

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          mediaContent,
          if (onTap != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onTap,
              ),
            ),
          if (videoController != null)
            _VideoControlsOverlay(controller: videoController),
          if (videoController == null ||
              videoController.value.isInitialized == false)
            const _LoadingOverlay(),
          if (videoController != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _VideoProgressBar(controller: videoController),
            ),
        ],
      ),
    );
  }
}

bool _overlayVisible(VideoPlayerValue value, bool isReady) =>
    isReady && !value.isPlaying;

class _VideoControlsOverlay extends StatelessWidget {
  const _VideoControlsOverlay({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final isReady = value.isInitialized;
        final isVisible = _overlayVisible(value, isReady);
        // Do not block pointer events from reaching the underlying
        // GestureDetector. The overlay is purely visual; taps should
        // always be handled by the video tap handler so the user can
        // toggle playback even when the overlay is visible.
        return IgnorePointer(
          // Always ignore pointers here so the overlay never intercepts
          // hit testing. This lets the Positioned.fill GestureDetector
          // receive taps reliably.
          ignoring: true,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: isVisible ? 1.0 : 0.0,
            child: Container(
              color: Colors.black38,
              alignment: Alignment.center,
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 56,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VideoProgressBar extends StatelessWidget {
  const _VideoProgressBar({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        if (!value.isInitialized || value.duration == Duration.zero) {
          return const SizedBox.shrink();
        }
        final progress =
            value.position.inMilliseconds / value.duration.inMilliseconds;
        final clampedProgress = progress.clamp(0.0, 1.0).toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clampedProgress,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.white.withValues(alpha: 0.9)),
              minHeight: 3,
            ),
          ),
        );
      },
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({required this.item});

  final FeedEntry item;

  @override
  Widget build(BuildContext context) {
    if (item.previewImageUrl != null) {
      return Image.network(
        item.previewImageUrl!,
        fit: BoxFit.cover,
      );
    }
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Icon(Icons.play_arrow, color: Colors.white, size: 48),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black26,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 36,
        height: 36,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}
