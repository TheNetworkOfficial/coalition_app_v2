import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/posts_page.dart';

String? validPostThumbUrl(String? url) {
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

class PostGridTile extends StatelessWidget {
  const PostGridTile({
    super.key,
    required this.item,
    required this.onTap,
  });

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
        final hasThumbnail = validPostThumbUrl(item.thumbUrl) != null;
        final isFailed = item.status.toUpperCase() == 'FAILED';
        final showSpinner = !hasThumbnail;
        final showDuration = item.durationMs > 0 && hasThumbnail;

        final colorScheme = Theme.of(context).colorScheme;
        final onSurface = colorScheme.onSurface;

        return GestureDetector(
          onTap: (!isFailed && hasThumbnail) ? onTap : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Hero(
                  tag: 'profile_post_${item.id}',
                  child: _buildThumbnail(
                    context,
                    memCacheWidth,
                    memCacheHeight,
                  ),
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
                        color: colorScheme.scrim.withValues(alpha: 0.87),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatDuration(item.duration),
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                if (showSpinner && !isFailed)
                  Container(
                    color: colorScheme.scrim.withValues(alpha: 0.26),
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
                    color: colorScheme.scrim.withValues(alpha: 0.54),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: onSurface,
                          size: 28,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Video processing failed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: onSurface,
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

  Widget _buildThumbnail(
    BuildContext context,
    int memCacheWidth,
    int memCacheHeight,
  ) {
    final safeThumb = validPostThumbUrl(item.thumbUrl);
    if (safeThumb == null) {
      return _placeholderTile(context);
    }
    return CachedNetworkImage(
      imageUrl: safeThumb,
      fit: BoxFit.cover,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      placeholder: (context, url) => const PostGridShimmer(),
      errorWidget: (context, url, error) => _placeholderTile(context),
    );
  }

  Widget _placeholderTile(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Align(
        child: Icon(
          Icons.videocam_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
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

class PostGridShimmer extends StatelessWidget {
  const PostGridShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.5);
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

typedef PostGridShimmerTile = PostGridShimmer;
