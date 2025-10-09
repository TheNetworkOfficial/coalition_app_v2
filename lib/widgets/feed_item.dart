import 'package:coalition_app_v2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
  });

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
    final type = typeString == 'video' ? FeedMediaType.video : FeedMediaType.image;

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

    String? videoUrl = _asString(json['videoUrl']) ??
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

  @override
  void initState() {
    super.initState();
    _maybeInitializeController();
  }

  @override
  void didUpdateWidget(covariant FeedItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.item.type == FeedMediaType.video &&
        oldWidget.item.videoUrl != widget.item.videoUrl) {
      _disposeController();
      _maybeInitializeController();
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
    if (widget.item.type != FeedMediaType.video || widget.item.videoUrl == null) {
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
      controller
        ..setLooping(true)
        ..setVolume(0);
      if (!mounted) {
        return;
      }
      setState(() {});
      _updatePlayback();
    });

    _controller = controller;
  }

  void _updatePlayback() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (!controller.value.isInitialized) {
      return;
    }
    if (widget.isActive) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    _initializeFuture = null;
    controller?.dispose();
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
  });

  final VideoPlayerController? controller;
  final Future<void>? initializeFuture;
  final FeedEntry item;

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
  });

  final VideoPlayerController? controller;
  final Future<void>? initializeFuture;
  final FeedEntry item;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = controller?.value.isInitialized == true
        ? controller!.value.aspectRatio
        : (item.aspectRatio ?? 9 / 16);

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            FutureBuilder<void>(
              future: initializeFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done &&
                    controller!.value.isInitialized) {
                  return VideoPlayer(controller!);
                }
                return _VideoPlaceholder(item: item);
              },
            )
          else
            _VideoPlaceholder(item: item),
          if (controller == null || controller!.value.isInitialized == false)
            const _LoadingOverlay(),
        ],
      ),
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
