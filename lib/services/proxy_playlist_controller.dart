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

typedef PlaylistEditorBuilder = VideoEditorController Function(
    PlaylistSegment segment);

class ProxyPlaylistController {
  ProxyPlaylistController({
    required this.jobId,
    Stream<dynamic>? events,
    PlaylistEditorBuilder? editorBuilder,
  })  : _editorBuilder = editorBuilder ?? _defaultEditorBuilder {
    final source = events ?? VideoProxyService().nativeEventsFor(jobId);
    _eventsSub = source.listen(_handleEvent);
  }

  final String jobId;
  final List<PlaylistSegment> segments = [];

  VideoEditorController? _editorController;
  int _currentIndex = 0;
  StreamSubscription? _eventsSub;
  final PlaylistEditorBuilder _editorBuilder;
  final Map<int, VideoEditorController> _preparedControllers = {};
  VoidCallback? onReady;
  VoidCallback? onBuffering;
  VoidCallback? onSegmentAppended;
  bool _awaitingFallbackSegments = false;

  bool get isReady =>
      _editorController != null && _editorController!.video.value.isInitialized;

  Future<void> dispose() async {
    await _eventsSub?.cancel();
    final ctrl = _editorController;
    if (ctrl != null) {
      ctrl.removeListener(_onEditorUpdate);
      await ctrl.dispose();
    }
    _editorController = null;
    await _disposePreparedControllers();
  }

  Future<void> _handleEvent(dynamic raw) async {
    final event = _ProxyPlaylistEvent.fromDynamic(raw);
    if (event == null) return;

    if (event.fallbackTriggered && !_awaitingFallbackSegments) {
      _awaitingFallbackSegments = true;
      await _handleFallbackTriggered();
    }

    if (event.type == 'segment_ready') {
      _awaitingFallbackSegments = false;
      final path = event.path;
      if (path == null) return;
      final idx = event.segmentIndex ?? 0;
      final durationMs = event.durationMs ?? 0;
      final width = event.width ?? 0;
      final height = event.height ?? 0;
      if (segments.any((s) => s.index == idx)) return; // dedupe
      final seg = PlaylistSegment(
        index: idx,
        path: path,
        durationMs: durationMs,
        width: width,
        height: height,
      );
      segments.add(seg);
      segments.sort((a, b) => a.index.compareTo(b.index));

      if (_editorController == null && segments.isNotEmpty) {
        await _initEditorForSegment(segments.first);
        onReady?.call();
      } else if (_editorController != null) {
        await _prefetchNextSegment();
      }

      onSegmentAppended?.call();
    }
  }

  Future<void> _initEditorForSegment(PlaylistSegment seg) async {
    final index = segments.indexOf(seg);
    if (index < 0) return;
    final controller = await _acquireControllerForIndex(index,
        failureLabel: 'first segment');
    if (controller == null) return;
    controller.addListener(_onEditorUpdate);
    _editorController = controller;
    _currentIndex = index;

    // Autoplay
    if (controller.video.value.isInitialized) {
      controller.video.play();
    }
    await _prefetchNextSegment();
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

    final controller = await _acquireControllerForIndex(nextIndex,
        failureLabel: 'segment ${nextSeg.index}');
    if (controller == null) {
      return;
    }
    controller.addListener(_onEditorUpdate);
    _editorController = controller;
    _currentIndex = nextIndex;
    controller.video.play();
    await _prefetchNextSegment();
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
    final controller = await _acquireControllerForIndex(index,
        failureLabel: 'segment ${seg.index}');
    if (controller == null) return;
    controller.addListener(_onEditorUpdate);
    _editorController = controller;
    _currentIndex = index;
    await controller.video.seekTo(Duration(milliseconds: seekMs));
    controller.video.play();
    await _prefetchNextSegment();
  }

  Future<void> _handleFallbackTriggered() async {
    final old = _editorController;
    _editorController = null;
    if (old != null) {
      old.removeListener(_onEditorUpdate);
      await old.dispose();
    }
    await _disposePreparedControllers();
    segments.clear();
    _currentIndex = 0;
    onBuffering?.call();
  }

  Future<VideoEditorController?> _acquireControllerForIndex(int index,
      {required String failureLabel}) async {
    if (index < 0 || index >= segments.length) return null;
    final cached = _preparedControllers.remove(index);
    if (cached != null) {
      return cached;
    }
    return _createControllerForIndex(index, failureLabel: failureLabel);
  }

  Future<void> _prefetchNextSegment() async {
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= segments.length) return;
    await _prefetchControllerForIndex(nextIndex);
  }

  Future<void> _prefetchControllerForIndex(int index) async {
    if (index < 0 || index >= segments.length) return;
    if (_preparedControllers.containsKey(index)) return;
    final seg = segments[index];
    final controller = await _createControllerForIndex(index,
        failureLabel: 'segment ${seg.index}');
    if (controller != null) {
      if (index < segments.length && identical(segments[index], seg)) {
        _preparedControllers[index] = controller;
      } else {
        try {
          await controller.dispose();
        } catch (_) {}
      }
    }
  }

  Future<void> _disposePreparedControllers() async {
    if (_preparedControllers.isEmpty) return;
    final controllers = _preparedControllers.values.toList();
    _preparedControllers.clear();
    for (final controller in controllers) {
      try {
        await controller.dispose();
      } catch (_) {}
    }
  }

  Future<VideoEditorController?> _createControllerForIndex(int index,
      {required String failureLabel}) async {
    if (index < 0 || index >= segments.length) return null;
    final seg = segments[index];
    final controller = _editorBuilder(seg);
    try {
      await controller.initialize();
      return controller;
    } catch (e) {
      debugPrint(
          '[ProxyPlaylistController] Failed to init editor for $failureLabel: $e');
      try {
        await controller.dispose();
      } catch (_) {}
      return null;
    }
  }

  static VideoEditorController _defaultEditorBuilder(PlaylistSegment seg) {
    return VideoEditorController.file(
      XFile(seg.path),
      maxDuration: const Duration(days: 1),
      minDuration: Duration.zero,
    );
  }
}

class _ProxyPlaylistEvent {
  _ProxyPlaylistEvent({
    required this.type,
    this.segmentIndex,
    this.path,
    this.durationMs,
    this.width,
    this.height,
    this.progress,
    this.fallbackTriggered = false,
  });

  final String type;
  final int? segmentIndex;
  final String? path;
  final int? durationMs;
  final int? width;
  final int? height;
  final double? progress;
  final bool fallbackTriggered;

  static _ProxyPlaylistEvent? fromDynamic(dynamic raw) {
    if (raw == null) return null;

    dynamic read(String key) {
      if (raw is Map) return raw[key];
      try {
        switch (key) {
          case 'type':
            return raw.type;
          case 'segmentIndex':
            return raw.segmentIndex;
          case 'path':
            return raw.path;
          case 'durationMs':
            return raw.durationMs;
          case 'width':
            return raw.width;
          case 'height':
            return raw.height;
          case 'progress':
            return raw.progress;
          case 'fallbackTriggered':
            return raw.fallbackTriggered;
        }
      } catch (_) {
        return null;
      }
      return null;
    }

    final typeValue = read('type')?.toString();
    if (typeValue == null) {
      return null;
    }

    final segmentIndexValue = read('segmentIndex');
    final pathValue = read('path');
    final durationValue = read('durationMs');
    final widthValue = read('width');
    final heightValue = read('height');
    final progressValue = read('progress');
    final fallbackValue = read('fallbackTriggered');

    return _ProxyPlaylistEvent(
      type: typeValue,
      segmentIndex: (segmentIndexValue as num?)?.toInt(),
      path: pathValue?.toString(),
      durationMs: (durationValue as num?)?.toInt(),
      width: (widthValue as num?)?.toInt(),
      height: (heightValue as num?)?.toInt(),
      progress: (progressValue as num?)?.toDouble(),
      fallbackTriggered: fallbackValue == true,
    );
  }
}
