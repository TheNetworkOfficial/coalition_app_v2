import 'dart:async';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:video_editor_2/video_editor.dart';

import '../models/video_proxy.dart';
import 'video_proxy_service.dart';

class PlaylistSegment {
  PlaylistSegment({
    required this.index,
    required this.path,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.quality,
  });

  final int index;
  final String path;
  final int durationMs;
  final int width;
  final int height;
  final ProxyQuality quality;
}

typedef PlaylistEditorBuilder = VideoEditorController Function(
    PlaylistSegment segment);

class ProxyPlaylistController {
  ProxyPlaylistController({
    required String jobId,
    VideoProxySession? session,
    ProxyPreview? initialPreview,
    Stream<dynamic>? events,
    PlaylistEditorBuilder? editorBuilder,
    Duration prefetchWindow = const Duration(seconds: 6),
  })  : jobId = session?.jobId ?? jobId,
        _session = session,
        _prefetchWindowMs = prefetchWindow.inMilliseconds.abs(),
        _editorBuilder = editorBuilder ?? _defaultEditorBuilder {
    final source = events ?? VideoProxyService().nativeEventsFor(this.jobId);
    _eventsSub = source.listen(_handleEvent);
    if (initialPreview != null) {
      final estimatedDuration = initialPreview.metadata.durationMs > 0
          ? initialPreview.metadata.durationMs
          : (_session?.manifest?.segmentDurationMs ??
              initialPreview.metadata.durationMs);
      final initialSegment = PlaylistSegment(
        index: initialPreview.segmentIndex ?? 0,
        path: initialPreview.filePath,
        durationMs: math.max(1, estimatedDuration),
        width: initialPreview.metadata.width,
        height: initialPreview.metadata.height,
        quality: initialPreview.quality,
      );
      unawaited(_applySegmentUpdate(initialSegment, isUpgrade: false).then((_) {
        onSegmentAppended?.call();
      }));
    }
  }

  final String jobId;
  final VideoProxySession? _session;
  final int _prefetchWindowMs;
  final List<PlaylistSegment> segments = [];

  VideoEditorController? _editorController;
  int _currentIndex = 0;
  StreamSubscription? _eventsSub;
  final PlaylistEditorBuilder _editorBuilder;
  final Map<int, VideoEditorController> _preparedControllers = {};
  Future<void>? _initializingEditor;
  bool _pendingPrefetchAfterInit = false;
  VoidCallback? onReady;
  VoidCallback? onBuffering;
  VoidCallback? onSegmentAppended;
  ValueChanged<PlaylistSegment>? onSegmentUpgraded;
  bool _awaitingFallbackSegments = false;
  int? _globalStartMs;
  int? _globalEndMs;
  final Set<_SegmentEnsureKey> _pendingEnsures = <_SegmentEnsureKey>{};
  int? _lastEnsureCenterMs;

  bool get isReady =>
      _editorController != null && _editorController!.video.value.isInitialized;

  int get totalDurationMs =>
      segments.fold<int>(0, (sum, segment) => sum + segment.durationMs);

  ProxySegment? manifestSegmentForTimestamp(int timestampMs) {
    return VideoProxyService().manifestSegmentFor(jobId, timestampMs);
  }

  List<ProxyKeyframe> manifestKeyframesInRange(int startMs, int endMs) {
    return VideoProxyService().manifestKeyframesFor(jobId, startMs, endMs);
  }

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

    if (event.type == 'segment_ready' || event.type == 'segment_upgraded') {
      _awaitingFallbackSegments = false;
      final path = event.path;
      if (path == null) return;
      final idx = event.segmentIndex ?? 0;
      final durationMs = event.durationMs ?? 0;
      final width = event.width ?? 0;
      final height = event.height ?? 0;
      final quality = event.quality ?? ProxyQuality.preview;

      final seg = PlaylistSegment(
        index: idx,
        path: path,
        durationMs: durationMs,
        width: width,
        height: height,
        quality: quality,
      );

      await _applySegmentUpdate(
        seg,
        isUpgrade: event.type == 'segment_upgraded',
      );

      if (event.type == 'segment_upgraded') {
        onSegmentUpgraded?.call(seg);
      } else {
        onSegmentAppended?.call();
      }
    }
  }

  Future<void> _applySegmentUpdate(
    PlaylistSegment segment, {
    required bool isUpgrade,
  }) async {
    segments.removeWhere((existing) => existing.index == segment.index);
    segments.add(segment);
    segments.sort((a, b) => a.index.compareTo(b.index));
    _pendingEnsures.removeWhere((key) => key.segmentIndex == segment.index);

    if (_editorController == null && segments.isNotEmpty) {
      if (_initializingEditor != null) {
        _pendingPrefetchAfterInit = true;
        await _initializingEditor;
      } else {
        final future = _initEditorForSegment(segments.first);
        _initializingEditor = future;
        try {
          await future;
          onReady?.call();
        } finally {
          _initializingEditor = null;
          if (_pendingPrefetchAfterInit) {
            _pendingPrefetchAfterInit = false;
            if (_editorController != null) {
              await _prefetchNextSegment();
            }
          }
        }
      }
    } else if (_editorController != null) {
      if (_initializingEditor != null) {
        _pendingPrefetchAfterInit = true;
        await _initializingEditor;
      } else {
        final listIndex = segments.indexOf(segment);
        if (isUpgrade && listIndex == _currentIndex) {
          await _reloadCurrentSegment();
        } else if (isUpgrade) {
          final cached = _preparedControllers.remove(listIndex);
          if (cached != null) {
            try {
              await cached.dispose();
            } catch (_) {}
          }
          await _prefetchControllerForIndex(listIndex);
        } else {
          await _prefetchNextSegment();
        }
      }
    }

    _scheduleEnsureForCurrentPosition();
  }

  Future<void> _initEditorForSegment(PlaylistSegment seg) async {
    final index = segments.indexOf(seg);
    if (index < 0) return;
    final controller =
        await _acquireControllerForIndex(index, failureLabel: 'first segment');
    if (controller == null) return;
    controller.addListener(_onEditorUpdate);
    _editorController = controller;
    _currentIndex = index;
    await _applyTrimToController(index, controller, shouldSeek: true);

    // Autoplay
    if (controller.video.value.isInitialized) {
      controller.video.play();
    }
    await _prefetchNextSegment();
    _scheduleEnsureForCurrentPosition();
  }

  void _onEditorUpdate() {
    final ctrl = _editorController;
    if (ctrl == null) return;
    final video = ctrl.video;
    if (!video.value.isInitialized) return;

    if (video.value.position >= video.value.duration) {
      _advanceToNextSegment();
    }
    _scheduleEnsureForCurrentPosition();
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
    await _applyTrimToController(nextIndex, controller, shouldSeek: true);
    controller.video.play();
    await _prefetchNextSegment();
    _scheduleEnsureForCurrentPosition();
  }

  Future<void> _reloadCurrentSegment() async {
    if (_currentIndex < 0 || _currentIndex >= segments.length) {
      return;
    }
    final seg = segments[_currentIndex];
    final previous = _editorController;
    final currentPosition =
        previous?.video.value.position ?? const Duration(milliseconds: 0);
    if (previous != null) {
      previous.removeListener(_onEditorUpdate);
      await previous.dispose();
    }

    final controller = await _acquireControllerForIndex(
      _currentIndex,
      failureLabel: 'segment ${seg.index}',
    );
    if (controller == null) {
      return;
    }
    controller.addListener(_onEditorUpdate);
    _editorController = controller;
    await _applyTrimToController(
      _currentIndex,
      controller,
      shouldSeek: false,
    );
    final seekMs = currentPosition.inMilliseconds.clamp(
      0,
      math.max(0, seg.durationMs - 1),
    );
    await controller.video.seekTo(Duration(milliseconds: seekMs));
    controller.video.play();
    await _prefetchNextSegment();
    _scheduleEnsureForCurrentPosition();
  }

  VideoEditorController? get editor => _editorController;

  Future<void> updateGlobalTrim({
    required int startMs,
    required int endMs,
  }) async {
    final total = totalDurationMs;
    final clampedStart =
        segments.isEmpty ? startMs : startMs.clamp(0, total).toInt();
    final rawEnd = segments.isEmpty ? endMs : endMs.clamp(0, total).toInt();
    final adjustedEnd = rawEnd <= clampedStart
        ? (segments.isEmpty ? rawEnd : math.min(total, clampedStart + 1))
        : rawEnd;
    _globalStartMs = clampedStart;
    _globalEndMs = adjustedEnd;

    if (_editorController != null && segments.isNotEmpty) {
      await seekTo(Duration(milliseconds: clampedStart));
    }

    final current = _editorController;
    if (current != null) {
      await _applyTrimToController(_currentIndex, current, shouldSeek: false);
    }
    for (final entry in _preparedControllers.entries) {
      await _applyTrimToController(entry.key, entry.value, shouldSeek: false);
    }
  }

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
          final currentEditor = editor;
          if (currentEditor != null) {
            await currentEditor.video.seekTo(Duration(milliseconds: inSeg));
            await _applyTrimToController(i, currentEditor, shouldSeek: false);
          }
        }
        _scheduleEnsureForCurrentPosition();
        return;
      }
      acc += s.durationMs;
    }
    final bufferedTotal = totalDurationMs;
    if (ms >= bufferedTotal) {
      onBuffering?.call();
      _lastEnsureCenterMs = null;
      unawaited(_ensureWindowAroundPosition(ms));
      return;
    }
    final last = segments.isNotEmpty ? segments.last : null;
    if (last != null) {
      await _switchToSegmentIndex(segments.length - 1,
          seekMs: last.durationMs - 1);
    }
    _scheduleEnsureForCurrentPosition();
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
    await _applyTrimToController(index, controller, shouldSeek: false);
    await controller.video.seekTo(Duration(milliseconds: seekMs));
    controller.video.play();
    await _prefetchNextSegment();
    _scheduleEnsureForCurrentPosition();
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
    _pendingEnsures.clear();
    _lastEnsureCenterMs = null;
    onBuffering?.call();
  }

  Future<VideoEditorController?> _acquireControllerForIndex(int index,
      {required String failureLabel}) async {
    if (index < 0 || index >= segments.length) return null;
    final cached = _preparedControllers.remove(index);
    if (cached != null) {
      await _applyTrimToController(index, cached, shouldSeek: false);
      return cached;
    }
    final controller =
        await _createControllerForIndex(index, failureLabel: failureLabel);
    if (controller != null) {
      await _applyTrimToController(index, controller, shouldSeek: false);
    }
    return controller;
  }

  Future<void> _prefetchNextSegment() async {
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= segments.length) return;
    await _prefetchControllerForIndex(nextIndex);
  }

  int? get _currentGlobalPositionMs {
    final ctrl = _editorController;
    if (ctrl == null) {
      return null;
    }
    final value = ctrl.video.value;
    if (!value.isInitialized) {
      return null;
    }
    final localMs = value.position.inMilliseconds;
    final base = _segmentOffsetMs(_currentIndex);
    return base + localMs;
  }

  void _scheduleEnsureForCurrentPosition() {
    if (_session == null || _prefetchWindowMs <= 0) {
      return;
    }
    final position = _currentGlobalPositionMs;
    if (position == null) {
      return;
    }
    final previous = _lastEnsureCenterMs;
    if (previous != null && (position - previous).abs() < (_prefetchWindowMs ~/ 3)) {
      return;
    }
    _lastEnsureCenterMs = position;
    unawaited(_ensureWindowAroundPosition(position));
  }

  Future<void> _ensureWindowAroundPosition(int centerMs) async {
    if (_session == null || _prefetchWindowMs <= 0) {
      return;
    }
    final manifest = _currentManifest;
    final startWindow = math.max(0, centerMs - _prefetchWindowMs);
    final endWindow = centerMs + _prefetchWindowMs;

    if (manifest != null && manifest.segments.isNotEmpty) {
      var offset = 0;
      final ordered = [...manifest.segments]
        ..sort((a, b) => a.index.compareTo(b.index));
      for (final segment in ordered) {
        final start = offset;
        final end = start + segment.durationMs;
        offset = end;
        if (end < startWindow) {
          continue;
        }
        if (start > endWindow) {
          break;
        }
        await _ensureSegmentRange(segment.index, start, end);
      }
      await _evictPreparedControllersOutside(startWindow, endWindow);
      return;
    }

    // Fallback to known segments when manifest not yet populated.
    var offset = 0;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final start = offset;
      final end = start + segment.durationMs;
      offset = end;
      if (end < startWindow) {
        continue;
      }
      if (start > endWindow) {
        break;
      }
      await _ensureSegmentRange(segment.index, start, end);
    }
  }

  Future<void> _ensureSegmentRange(
    int segmentIndex,
    int startMs,
    int endMs, {
    ProxyQuality quality = ProxyQuality.preview,
  }) async {
    if (_session == null) {
      return;
    }
    if (endMs <= startMs) {
      return;
    }
    final key = _SegmentEnsureKey(segmentIndex, quality);
    if (_pendingEnsures.contains(key)) {
      return;
    }
    _pendingEnsures.add(key);
    try {
      await _session!.ensureSegment(startMs, endMs, quality: quality);
    } on VideoProxyException catch (error) {
      debugPrint(
          '[ProxyPlaylistController] ensureSegment failed index=$segmentIndex quality=${quality.name}: ${error.message}');
      _pendingEnsures.remove(key);
    } catch (error) {
      debugPrint(
          '[ProxyPlaylistController] ensureSegment error index=$segmentIndex quality=${quality.name}: $error');
      _pendingEnsures.remove(key);
    }
  }

  Future<void> _evictPreparedControllersOutside(
    int windowStart,
    int windowEnd,
  ) async {
    if (_preparedControllers.isEmpty) {
      return;
    }
    final manifest = _currentManifest;
    final removals = <int>[];
    for (final entry in _preparedControllers.entries) {
      final bounds = _segmentWindowForListIndex(entry.key, manifest: manifest);
      if (bounds == null) {
        continue;
      }
      final buffer = manifest?.segmentDurationMs ?? 0;
      if (bounds.endMs < windowStart - buffer ||
          bounds.startMs > windowEnd + buffer) {
        removals.add(entry.key);
      }
    }
    for (final index in removals) {
      final controller = _preparedControllers.remove(index);
      if (controller != null) {
        try {
          await controller.dispose();
        } catch (_) {}
      }
    }
  }

  ProxyManifestData? get manifest => _currentManifest;

  ProxyManifestData? get _currentManifest {
    final manifest = _session?.manifest ??
        VideoProxyService().manifestForJob(jobId);
    return manifest;
  }

  _SegmentWindow? _segmentWindowForListIndex(
    int index, {
    ProxyManifestData? manifest,
  }) {
    if (index < 0 || index >= segments.length) {
      return null;
    }
    final segIndex = segments[index].index;
    manifest ??= _currentManifest;
    if (manifest != null && manifest.segments.isNotEmpty) {
      var offset = 0;
      final ordered = [...manifest.segments]
        ..sort((a, b) => a.index.compareTo(b.index));
      for (final segment in ordered) {
        final start = offset;
        final end = start + segment.durationMs;
        offset = end;
        if (segment.index == segIndex) {
          return _SegmentWindow(start, end);
        }
      }
    }
    final start = _segmentOffsetMs(index);
    final duration = segments[index].durationMs;
    return _SegmentWindow(start, start + duration);
  }

  Future<void> _prefetchControllerForIndex(int index) async {
    if (index < 0 || index >= segments.length) return;
    if (_preparedControllers.containsKey(index)) return;
    final seg = segments[index];
    final controller = await _createControllerForIndex(index,
        failureLabel: 'segment ${seg.index}');
    if (controller != null) {
      await _applyTrimToController(index, controller, shouldSeek: false);
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

  Future<void> _applyTrimToController(
    int index,
    VideoEditorController controller, {
    required bool shouldSeek,
  }) async {
    if (index < 0 || index >= segments.length) {
      return;
    }
    final seg = segments[index];
    final durationMs = seg.durationMs;
    if (durationMs <= 0) {
      controller.updateTrim(0, 1);
      if (shouldSeek) {
        await controller.video.seekTo(Duration.zero);
      }
      return;
    }

    final start = _globalStartMs;
    final end = _globalEndMs;
    if (start == null || end == null) {
      controller.updateTrim(0, 1);
      if (shouldSeek) {
        await controller.video.seekTo(Duration.zero);
      }
      return;
    }

    final segStart = _segmentOffsetMs(index);
    final segEnd = segStart + durationMs;
    final overlapStart = math.max(start, segStart);
    final overlapEnd = math.min(end, segEnd);
    final hasOverlap = overlapEnd > overlapStart;

    double minFraction = 0;
    double maxFraction = 1;
    int seekMs = 0;

    if (hasOverlap) {
      final localStart = overlapStart - segStart;
      final localEnd = overlapEnd - segStart;
      minFraction = (localStart / durationMs).clamp(0.0, 1.0);
      maxFraction = (localEnd / durationMs).clamp(minFraction, 1.0);
      seekMs = math.max(0, math.min(durationMs - 1, localStart));
    }

    controller.updateTrim(minFraction, maxFraction);

    if (shouldSeek) {
      final targetMs = hasOverlap ? seekMs : 0;
      await controller.video.seekTo(Duration(milliseconds: targetMs));
    }
  }

  int _segmentOffsetMs(int index) {
    var offset = 0;
    for (var i = 0; i < index && i < segments.length; i++) {
      offset += segments[i].durationMs;
    }
    return offset;
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
    this.quality,
  });

  final String type;
  final int? segmentIndex;
  final String? path;
  final int? durationMs;
  final int? width;
  final int? height;
  final double? progress;
  final bool fallbackTriggered;
  final ProxyQuality? quality;

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
    final qualityLabel = read('quality');

    return _ProxyPlaylistEvent(
      type: typeValue,
      segmentIndex: (segmentIndexValue as num?)?.toInt(),
      path: pathValue?.toString(),
      durationMs: (durationValue as num?)?.toInt(),
      width: (widthValue as num?)?.toInt(),
      height: (heightValue as num?)?.toInt(),
      progress: (progressValue as num?)?.toDouble(),
      fallbackTriggered: fallbackValue == true,
      quality: proxyQualityFromLabel(qualityLabel?.toString()),
    );
  }
}

class _SegmentWindow {
  const _SegmentWindow(this.startMs, this.endMs);

  final int startMs;
  final int endMs;
}

class _SegmentEnsureKey {
  const _SegmentEnsureKey(this.segmentIndex, this.quality);

  final int segmentIndex;
  final ProxyQuality quality;

  @override
  bool operator ==(Object other) {
    return other is _SegmentEnsureKey &&
        other.segmentIndex == segmentIndex &&
        other.quality == quality;
  }

  @override
  int get hashCode => Object.hash(segmentIndex, quality);
}
