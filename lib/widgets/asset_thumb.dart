import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Lightweight thumbnail renderer that relies on MediaStore cached thumbs
/// instead of decoding full video frames on-device.
class AssetThumb extends StatefulWidget {
  const AssetThumb({
    super.key,
    required this.asset,
    this.size = const ThumbnailSize(200, 200),
    this.quality = 80,
  });

  final AssetEntity asset;
  final ThumbnailSize size;
  final int quality;

  @override
  State<AssetThumb> createState() => _AssetThumbState();
}

class _AssetThumbState extends State<AssetThumb> {
  late Future<Uint8List?> _thumbFuture;

  @override
  void initState() {
    super.initState();
    _thumbFuture = _loadThumb();
  }

  @override
  void didUpdateWidget(covariant AssetThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id ||
        oldWidget.size != widget.size ||
        oldWidget.quality != widget.quality) {
      _thumbFuture = _loadThumb();
    }
  }

  Future<Uint8List?> _loadThumb() async {
    try {
      final quality = widget.quality.clamp(1, 100);
      return await widget.asset.thumbnailDataWithOption(
        ThumbnailOption(
          size: widget.size,
          format: ThumbnailFormat.jpeg,
          quality: quality.toInt(),
        ),
      );
    } catch (error) {
      debugPrint('Asset thumb load failed for ${widget.asset.id}: $error');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _thumbFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const ColoredBox(color: Colors.black12);
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
            if (widget.asset.type == AssetType.video)
              Positioned(
                right: 6,
                bottom: 6,
                child: _DurationBadge(duration: widget.asset.videoDuration),
              ),
          ],
        );
      },
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (duration == Duration.zero) {
      return const SizedBox.shrink();
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final text = duration.inHours > 0
        ? '${two(duration.inHours)}:${two(duration.inMinutes % 60)}:${two(duration.inSeconds % 60)}'
        : '${two(duration.inMinutes)}:${two(duration.inSeconds % 60)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
