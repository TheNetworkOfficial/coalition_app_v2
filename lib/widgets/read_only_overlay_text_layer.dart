import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/edit_manifest.dart';

/// Read-only layer that paints text overlays from an [EditManifest] on top of a
/// [VideoPlayer]. Coordinates are normalized (0-1) and mapped to alignment.
class ReadOnlyOverlayTextLayer extends StatelessWidget {
  const ReadOnlyOverlayTextLayer({
    super.key,
    required this.videoController,
    required this.editManifest,
  });

  final VideoPlayerController videoController;
  final EditManifest editManifest;

  @override
  Widget build(BuildContext context) {
    if (editManifest.overlayTextOps.isEmpty) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: videoController,
      builder: (context, _) {
        if (!videoController.value.isInitialized) {
          return const SizedBox.shrink();
        }

        final positionMs = videoController.value.position.inMilliseconds;
        final overlays = editManifest.overlayTextOps
            .where((op) => _isVisible(op, positionMs))
            .toList();
        if (overlays.isEmpty) {
          return const SizedBox.shrink();
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.biggest.isEmpty) {
              return const SizedBox.shrink();
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                for (final op in overlays) _buildOverlay(context, op),
              ],
            );
          },
        );
      },
    );
  }

  bool _isVisible(OverlayTextOp op, int positionMs) {
    final start = op.startMs ?? 0;
    final end = op.endMs;
    if (end != null && end >= start) {
      return positionMs >= start && positionMs <= end;
    }
    return positionMs >= start;
  }

  Widget _buildOverlay(BuildContext context, OverlayTextOp op) {
    final alignment = Alignment(
      _normalizedAlignment(op.x),
      _normalizedAlignment(op.y),
    );
    final radians = op.rotationDeg * math.pi / 180;
    final scale = _normalizedScale(op.scale);
    final Color textColor = _parseColorHex(op.color) ?? Colors.white;
    final Color? bgColor =
        op.backgroundColorHex != null ? _parseColorHex(op.backgroundColorHex!) : null;

    final text = Text(
      op.text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: textColor,
            fontFamily: op.fontFamily,
          ) ??
          TextStyle(
            color: textColor,
            fontFamily: op.fontFamily,
          ),
    );

    final overlay = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: bgColor != null
          ? BoxDecoration(
              color: bgColor.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            )
          : null,
      child: text,
    );

    return Align(
      alignment: alignment,
      child: Transform.rotate(
        angle: radians,
        child: Transform.scale(
          scale: scale,
          child: overlay,
        ),
      ),
    );
  }

  double _normalizedScale(double raw) {
    if (!raw.isFinite || raw <= 0) {
      return 1.0;
    }
    return raw.clamp(0.5, 3.0).toDouble();
  }

  double _normalizedAlignment(double value) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    return (clamped * 2) - 1;
  }

  Color? _parseColorHex(String? hex) {
    if (hex == null) {
      return null;
    }
    var value = hex.trim();
    if (value.isEmpty) {
      return null;
    }
    if (value.startsWith('#')) {
      value = value.substring(1);
    }
    if (value.startsWith('0x')) {
      value = value.substring(2);
    }
    if (value.length == 6) {
      value = 'FF$value';
    }
    if (value.length != 8) {
      return null;
    }
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) {
      return null;
    }
    return Color(parsed);
  }
}
