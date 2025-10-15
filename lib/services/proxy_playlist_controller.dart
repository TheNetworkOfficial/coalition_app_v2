import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:video_editor_2/video_editor.dart';

import 'video_proxy_service.dart';

class PlaylistSegment {
  PlaylistSegment({
    required this.index,
    required this.path,
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final int index;
  final String path;
  final int durationMs;
  final int width;
  final int height;
}

class ProxyPlaylistController {
  ProxyPlaylistController({required this.jobId, Stream<dynamic>? events}) {
    final source = events ?? VideoProxyService().nativeEventsFor(jobId);
    _eventsSub = source.listen(_handleEvent);
  }

  final String jobId;
  final List<PlaylistSegment> segments = [];

  VideoEditorController? _editorController;
  int _currentIndex = 0;
  StreamSubscription? _eventsSub;
  VoidCallback? onReady;
  VoidCallback? onBuffering;
  VoidCallback? onSegmentAppended;

  bool get isReady =>
      _editorController != null && _editorController!.video.value.isInitialized;

  Future<void> dispose() async {
    await _eventsSub?.cancel();
    final ctrl = _editorController;
    if (ctrl != null) {
      ctrl.removeListener(_onEditorUpdate);
      await ctrl.dispose();
    }
  }

  Future<void> _handleEvent(dynamic raw) async {
    if (raw is! Map) return;
    final event = raw;
    final type = event['type']?.toString();
    if (type == 'segment_ready') {
      final idx = (event['segmentIndex'] as num?)?.toInt() ?? 0;
      final path = event['path']?.toString();
      final durationMs = (event['durationMs'] as num?)?.toInt() ?? 0;
      final width = (event['width'] as num?)?.toInt() ?? 0;
      final height = (event['height'] as num?)?.toInt() ?? 0;
      if (path == null) return;
      final seg = PlaylistSegment(
          index: idx,
          path: path,
          durationMs: durationMs,
          width: width,
          height: height);
      if (segments.any((s) => s.index == idx)) return; // dedupe
      segments.add(seg);
      segments.sort((a, b) => a.index.compareTo(b.index));

      // If first segment, init player
      if (_editorController == null && segments.isNotEmpty) {
        await _initEditorForSegment(segments.first);
        onReady?.call();
      }

      onSegmentAppended?.call();
    }
  }

  Future<void> _initEditorForSegment(PlaylistSegment seg) async {
    final controller = VideoEditorController.file(XFile(seg.path),
        maxDuration: Duration(days: 1), minDuration: Duration.zero);
    try {
      await controller.initialize();
    } catch (e) {
      debugPrint(
          '[ProxyPlaylistController] Failed to init editor for first segment: $e');
      return;
    }
    controller.addListener(_onEditorUpdate);
    _editorController = controller;
    _currentIndex = 0;

    // Autoplay
    if (controller.video.value.isInitialized) {
      controller.video.play();
    }
  }

  void _onEditorUpdate() {
    final ctrl = _editorController;
    if (ctrl == null) return;
    final video = ctrl.video;
    if (!video.value.isInitialized) return;

    if (video.value.position >= video.value.duration) {
      _advanceToNextSegment();
    }
  }

  Future<void> _advanceToNextSegment() async {
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= segments.length) {
      // no next segment yet, pause and notify buffering
      _editorController?.video.pause();
      onBuffering?.call();
      return;
    }

    final nextSeg = segments[nextIndex];
    final old = _editorController;
    if (old != null) {
      old.removeListener(_onEditorUpdate);
      await old.dispose();
    }

    final controller = VideoEditorController.file(XFile(nextSeg.path),
        maxDuration: Duration(days: 1), minDuration: Duration.zero);
    try {
      await controller.initialize();
    } catch (e) {
      debugPrint(
          '[ProxyPlaylistController] Failed to init editor for segment $nextIndex: $e');
      return;
    }
    controller.addListener(_onEditorUpdate);
    _editorController = controller;
    _currentIndex = nextIndex;
    controller.video.play();
  }

  VideoEditorController? get editor => _editorController;

  Future<void> seekTo(Duration position) async {
    var ms = position.inMilliseconds;
    var acc = 0;
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (ms < acc + s.durationMs) {
        final inSeg = ms - acc;
        if (_currentIndex != i) {
          await _switchToSegmentIndex(i, seekMs: inSeg);
        } else {
          await editor?.video.seekTo(Duration(milliseconds: inSeg));
        }
        return;
      }
      acc += s.durationMs;
    }
    final last = segments.isNotEmpty ? segments.last : null;
    if (last != null) {
      await _switchToSegmentIndex(segments.length - 1,
          seekMs: last.durationMs - 1);
    }
  }

  Future<void> _switchToSegmentIndex(int index, {required int seekMs}) async {
    if (index >= segments.length) return;
    final seg = segments[index];
    final old = _editorController;
    if (old != null) {
      old.removeListener(_onEditorUpdate);
      await old.dispose();
    }
    final controller = VideoEditorController.file(XFile(seg.path),
        maxDuration: Duration(days: 1), minDuration: Duration.zero);
    try {
      await controller.initialize();
    } catch (e) {
      debugPrint(
          '[ProxyPlaylistController] Failed to init editor for segment $index: $e');
      return;
    }
    controller.addListener(_onEditorUpdate);
    _editorController = controller;
    _currentIndex = index;
    await controller.video.seekTo(Duration(milliseconds: seekMs));
    controller.video.play();
  }
}
