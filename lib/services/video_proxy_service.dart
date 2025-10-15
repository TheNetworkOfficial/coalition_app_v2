import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/video_proxy.dart';

const _uuid = Uuid();

const _kProxyChannelName = 'coalition/video_proxy';
const _kProxyProgressChannelName = 'coalition/video_proxy/progress';

const _methodChannel = MethodChannel(_kProxyChannelName);
const _progressChannel = EventChannel(_kProxyProgressChannelName);

const int _kCacheQuotaBytes = 512 * 1024 * 1024;
const Duration _kSegmentRetention = Duration(minutes: 20);

class _NativeProxyEvent {
  const _NativeProxyEvent({
    required this.jobId,
    required this.type,
    this.progress,
    this.fallbackTriggered = false,
    this.segmentIndex,
    this.path,
    this.durationMs,
    this.width,
    this.height,
    this.hasAudio,
    this.totalSegments,
    this.totalDurationMs,
    this.portraitPreferred,
    this.proxyBounding,
    this.metadataPayload,
    this.keyframePayload,
    this.previewPayload,
    this.timelinePayload,
    this.qualityLabel,
    this.sourceStartMs,
    this.sourceEndMs,
    this.orientation,
    this.videoCodec,
    this.audioCodec,
    this.matchesSourceVideoCodec,
    this.matchesSourceAudioCodec,
    Map<String, dynamic>? raw,
  }) : raw = raw ?? const {};

  final String jobId;
  final String type;
  final double? progress;
  final bool fallbackTriggered;
  final int? segmentIndex;
  final String? path;
  final int? durationMs;
  final int? width;
  final int? height;
  final bool? hasAudio;
  final int? totalSegments;
  final int? totalDurationMs;
  final bool? portraitPreferred;
  final String? proxyBounding;
  final Map<String, dynamic>? metadataPayload;
  final List<Map<String, dynamic>>? keyframePayload;
  final Map<String, dynamic>? previewPayload;
  final Map<String, dynamic>? timelinePayload;
  final String? qualityLabel;
  final int? sourceStartMs;
  final int? sourceEndMs;
  final String? orientation;
  final String? videoCodec;
  final String? audioCodec;
  final bool? matchesSourceVideoCodec;
  final bool? matchesSourceAudioCodec;
  final Map<String, dynamic> raw;

  factory _NativeProxyEvent.fromDynamic(Object? value) {
    if (value is! Map) {
      throw ArgumentError('Invalid proxy event payload: $value');
    }
    final map = value.map((key, dynamic v) {
      return MapEntry(key.toString(), v);
    });
    final jobId = map['jobId']?.toString();
    final type = map['type']?.toString();
    final progress = map['progress'];
    final fallbackTriggered = map['fallbackTriggered'] == true;
    final segmentIndex = (map['segmentIndex'] as num?)?.toInt();
    final path = map['path']?.toString();
    final durationMs = (map['durationMs'] as num?)?.toInt();
    final width = (map['width'] as num?)?.toInt();
    final height = (map['height'] as num?)?.toInt();
    final hasAudio = map['hasAudio'] == true;
    final totalSegments = (map['totalSegments'] as num?)?.toInt();
    final totalDurationMs = (map['totalDurationMs'] as num?)?.toInt();
    final portraitPreferred = map['portraitPreferred'] == true;
    final proxyBounding = map['proxyBounding']?.toString();
    final sourceStartMs = (map['sourceStartMs'] as num?)?.toInt();
    final sourceEndMs = (map['sourceEndMs'] as num?)?.toInt();
    final orientation = map['orientation']?.toString();
    final videoCodec = map['videoCodec']?.toString();
    final audioCodec = map['audioCodec']?.toString();
    final matchesSourceVideoCodec =
        map.containsKey('matchesSourceVideoCodec')
            ? map['matchesSourceVideoCodec'] == true
            : null;
    final matchesSourceAudioCodec =
        map.containsKey('matchesSourceAudioCodec')
            ? map['matchesSourceAudioCodec'] == true
            : null;
    Map<String, dynamic>? metadataPayload;
    final metadata = map['metadata'];
    if (metadata is Map) {
      metadataPayload = metadata.map((key, dynamic v) {
        return MapEntry(key.toString(), v);
      });
    }
    List<Map<String, dynamic>>? keyframePayload;
    final keyframes = map['keyframes'];
    if (keyframes is List) {
      keyframePayload = keyframes
          .whereType<Map>()
          .map((frame) => frame.map((key, dynamic v) {
                return MapEntry(key.toString(), v);
              }))
          .toList();
    }
    Map<String, dynamic>? previewPayload;
    final preview = map['preview'];
    if (preview is Map) {
      previewPayload = preview.map((key, dynamic v) {
        return MapEntry(key.toString(), v);
      });
    }
    Map<String, dynamic>? timelinePayload;
    final timeline = map['timeline'];
    if (timeline is Map) {
      timelinePayload = timeline.map((key, dynamic v) {
        return MapEntry(key.toString(), v);
      });
    }
    final qualityLabel = map['quality']?.toString();
    return _NativeProxyEvent(
      jobId: jobId ?? '',
      type: type ?? 'unknown',
      progress: progress is num ? progress.toDouble() : null,
      fallbackTriggered: fallbackTriggered,
      segmentIndex: segmentIndex,
      path: path,
      durationMs: durationMs,
      width: width,
      height: height,
      hasAudio: hasAudio,
      totalSegments: totalSegments,
      totalDurationMs: totalDurationMs,
      portraitPreferred: portraitPreferred,
      proxyBounding: proxyBounding,
      metadataPayload: metadataPayload,
      keyframePayload: keyframePayload,
      previewPayload: previewPayload,
      timelinePayload: timelinePayload,
      qualityLabel: qualityLabel,
      sourceStartMs: sourceStartMs,
      sourceEndMs: sourceEndMs,
      orientation: orientation,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      matchesSourceVideoCodec: matchesSourceVideoCodec,
      matchesSourceAudioCodec: matchesSourceAudioCodec,
      raw: map,
    );
  }

  bool get isProgress => type == 'progress';

  String? get previewPath => previewPayload?['path']?.toString();

  String? get previewQualityLabel {
    final label = previewPayload?['quality'] ?? qualityLabel;
    return label?.toString();
  }
}

class VideoProxyProgress {
  const VideoProxyProgress(this.fraction, {this.fallbackTriggered = false});

  final double? fraction;
  final bool fallbackTriggered;
}

class ProxySessionMetadataEvent {
  const ProxySessionMetadataEvent({
    this.durationMs,
    this.frameRate,
    this.keyframes = const [],
    this.segments = const [],
    this.sourceStartMs,
    this.sourceEndMs,
    this.orientation,
    this.videoCodec,
    this.audioCodec,
    this.matchesSourceVideoCodec,
    this.matchesSourceAudioCodec,
    this.activeQuality,
    this.availableQualities = const <ProxySessionQualityTier>{},
    this.variableFrameRate = false,
    this.hardwareDecodeUnsupported = false,
  });

  final int? durationMs;
  final double? frameRate;
  final List<ProxyKeyframe> keyframes;
  final List<ProxySegment> segments;
  final int? sourceStartMs;
  final int? sourceEndMs;
  final String? orientation;
  final String? videoCodec;
  final String? audioCodec;
  final bool? matchesSourceVideoCodec;
  final bool? matchesSourceAudioCodec;
  final ProxySessionQualityTier? activeQuality;
  final Set<ProxySessionQualityTier> availableQualities;
  final bool variableFrameRate;
  final bool hardwareDecodeUnsupported;
}

class ProxySourceRange {
  const ProxySourceRange({
    required this.startMs,
    required this.endMs,
    required this.durationMs,
  })  : assert(startMs >= 0),
        assert(endMs >= startMs),
        assert(durationMs >= 0);

  final int startMs;
  final int endMs;
  final int durationMs;
}

class ProxyManifestData {
  ProxyManifestData({
    int? segmentDurationMs,
    int? width,
    int? height,
    double? fps,
    bool hasAudio = true,
    int? durationMs,
    int? sourceStartMs,
    int? sourceEndMs,
    String? orientation,
    String? videoCodec,
    String? audioCodec,
    bool? matchesSourceVideoCodec,
    bool? matchesSourceAudioCodec,
  })  : segmentDurationMs = segmentDurationMs ?? 0,
        width = width,
        height = height,
        fps = fps,
        hasAudio = hasAudio,
        durationMs = durationMs,
        sourceStartMs = sourceStartMs,
        sourceEndMs = sourceEndMs,
        orientation = orientation,
        videoCodec = videoCodec,
        audioCodec = audioCodec,
        matchesSourceVideoCodec = matchesSourceVideoCodec,
        matchesSourceAudioCodec = matchesSourceAudioCodec;

  int segmentDurationMs;
  int? width;
  int? height;
  double? fps;
  bool hasAudio;
  int? durationMs;
  int? sourceStartMs;
  int? sourceEndMs;
  String? orientation;
  String? videoCodec;
  String? audioCodec;
  bool? matchesSourceVideoCodec;
  bool? matchesSourceAudioCodec;
  final List<ProxySegment> segments = [];
  final List<ProxyKeyframe> keyframes = [];

  static int _qualityRank(ProxyQuality quality) {
    switch (quality) {
      case ProxyQuality.preview:
        return 0;
      case ProxyQuality.proxy:
        return 1;
      case ProxyQuality.mezzanine:
        return 2;
    }
  }

  void mergeMetadata({
    int? segmentDurationMs,
    int? width,
    int? height,
    double? fps,
    bool? hasAudio,
    int? durationMs,
    int? sourceStartMs,
    int? sourceEndMs,
    String? orientation,
    String? videoCodec,
    String? audioCodec,
    bool? matchesSourceVideoCodec,
    bool? matchesSourceAudioCodec,
  }) {
    if (segmentDurationMs != null && segmentDurationMs > 0) {
      this.segmentDurationMs = segmentDurationMs;
    }
    if (width != null && width > 0) {
      this.width = width;
    }
    if (height != null && height > 0) {
      this.height = height;
    }
    if (fps != null && fps > 0) {
      this.fps = fps;
    }
    if (hasAudio != null) {
      this.hasAudio = hasAudio;
    }
    if (durationMs != null && durationMs >= 0) {
      this.durationMs = durationMs;
    }
    if (sourceStartMs != null && sourceStartMs >= 0) {
      this.sourceStartMs = sourceStartMs;
    }
    if (sourceEndMs != null && sourceEndMs >= 0) {
      this.sourceEndMs = sourceEndMs;
    }
    if (orientation != null && orientation.isNotEmpty) {
      this.orientation = orientation;
    }
    if (videoCodec != null && videoCodec.isNotEmpty) {
      this.videoCodec = videoCodec;
    }
    if (audioCodec != null && audioCodec.isNotEmpty) {
      this.audioCodec = audioCodec;
    }
    if (matchesSourceVideoCodec != null) {
      this.matchesSourceVideoCodec = matchesSourceVideoCodec;
    }
    if (matchesSourceAudioCodec != null) {
      this.matchesSourceAudioCodec = matchesSourceAudioCodec;
    }
  }

  bool addSegment(ProxySegment segment) {
    final existingIndex =
        segments.indexWhere((existing) => existing.index == segment.index);
    if (existingIndex >= 0) {
      final existing = segments[existingIndex];
      if (_qualityRank(segment.quality) < _qualityRank(existing.quality)) {
        return false;
      }
      segments[existingIndex] = segment;
    } else {
      segments.add(segment);
    }
    segments.sort((a, b) => a.index.compareTo(b.index));
    durationMs = segments.fold<int>(0, (sum, s) => sum + s.durationMs);
    if (segment.durationMs > 0 && segmentDurationMs == 0) {
      segmentDurationMs = segment.durationMs;
    }
    if (segment.width > 0) {
      width = segment.width;
    }
    if (segment.height > 0) {
      height = segment.height;
    }
    hasAudio = segment.hasAudio;
    if (segment.sourceStartMs != null) {
      if (sourceStartMs == null || segment.sourceStartMs! < sourceStartMs!) {
        sourceStartMs = segment.sourceStartMs;
      }
    }
    if (segment.sourceEndMs != null) {
      if (sourceEndMs == null || segment.sourceEndMs! > sourceEndMs!) {
        sourceEndMs = segment.sourceEndMs;
      }
    }
    if (segment.orientation != null && segment.orientation!.isNotEmpty) {
      orientation ??= segment.orientation;
    }
    if (segment.videoCodec != null && segment.videoCodec!.isNotEmpty) {
      videoCodec ??= segment.videoCodec;
    }
    if (segment.audioCodec != null && segment.audioCodec!.isNotEmpty) {
      audioCodec ??= segment.audioCodec;
    }
    if (segment.matchesSourceVideoCodec != null) {
      matchesSourceVideoCodec = (matchesSourceVideoCodec ?? true) &&
          segment.matchesSourceVideoCodec!;
    }
    if (segment.matchesSourceAudioCodec != null) {
      matchesSourceAudioCodec = (matchesSourceAudioCodec ?? true) &&
          segment.matchesSourceAudioCodec!;
    }
    return true;
  }

  bool removeSegment({required int index, String? path}) {
    final originalLength = segments.length;
    segments.removeWhere((segment) {
      final matchesIndex = segment.index == index;
      final matchesPath = path == null || segment.path == path;
      return matchesIndex && matchesPath;
    });
    if (segments.length == originalLength) {
      return false;
    }
    segments.sort((a, b) => a.index.compareTo(b.index));
    durationMs = segments.fold<int>(0, (sum, s) => sum + s.durationMs);
    if (segments.isEmpty) {
      width = null;
      height = null;
    } else {
      width ??= segments.last.width;
      height ??= segments.last.height;
    }
    return true;
  }

  void addKeyframes(Iterable<ProxyKeyframe> frames) {
    for (final frame in frames) {
      final exists = keyframes.any((existing) =>
          existing.timestampMs == frame.timestampMs &&
          existing.fileOffsetBytes == frame.fileOffsetBytes);
      if (!exists) {
        keyframes.add(frame);
      }
    }
    keyframes.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  }

  ProxySegment? segmentForTimestamp(int timestampMs) {
    if (timestampMs < 0) return null;
    var elapsed = 0;
    final ordered = [...segments]..sort((a, b) => a.index.compareTo(b.index));
    for (final segment in ordered) {
      final start = elapsed;
      final end = start + segment.durationMs;
      if (timestampMs >= start && timestampMs < end) {
        return segment;
      }
      elapsed = end;
    }
    return null;
  }

  List<ProxyKeyframe> keyframesInRange(int startMs, int endMs) {
    if (endMs < startMs) {
      return const [];
    }
    return keyframes
        .where((frame) =>
            frame.timestampMs >= startMs && frame.timestampMs <= endMs)
        .toList(growable: false);
  }

  int? sourceTimestampForProxy(int timestampMs) {
    if (timestampMs < 0) {
      return null;
    }
    final range = sourceRangeForProxyRange(timestampMs, timestampMs + 1);
    if (range == null) {
      return null;
    }
    return range.startMs;
  }

  ProxySourceRange? sourceRangeForProxyRange(int startMs, int endMs) {
    if (endMs <= startMs) {
      return null;
    }
    final ordered = [...segments]..sort((a, b) => a.index.compareTo(b.index));
    if (ordered.isEmpty) {
      return null;
    }

    int? mappedStart;
    int? mappedEnd;
    var accumulatedDuration = 0;

    for (final segment in ordered) {
      final segmentDuration = segment.durationMs;
      final segmentStart = accumulatedDuration;
      final segmentEnd = segmentStart + segmentDuration;
      if (segmentEnd <= startMs) {
        accumulatedDuration = segmentEnd;
        continue;
      }
      if (segmentStart >= endMs) {
        break;
      }
      final overlapStart = math.max(startMs, segmentStart);
      final overlapEnd = math.min(endMs, segmentEnd);
      if (overlapEnd <= overlapStart) {
        accumulatedDuration = segmentEnd;
        continue;
      }
      final mapped = _mapWithinSegment(
        segment,
        overlapStart - segmentStart,
        overlapEnd - segmentStart,
      );
      if (mapped == null) {
        return null;
      }
      mappedStart ??= mapped.startMs;
      mappedEnd = mapped.endMs;
      accumulatedDuration = segmentEnd;
    }

    if (mappedStart == null || mappedEnd == null) {
      return null;
    }

    final duration = math.max(0, mappedEnd - mappedStart);
    return ProxySourceRange(
      startMs: mappedStart,
      endMs: mappedEnd,
      durationMs: duration,
    );
  }

  _SegmentSourceWindow? _mapWithinSegment(
    ProxySegment segment,
    int localStartMs,
    int localEndMs,
  ) {
    final segmentDuration = segment.durationMs;
    final sourceStart = segment.sourceStartMs;
    final sourceEnd = segment.sourceEndMs;
    if (segmentDuration <= 0 ||
        sourceStart == null ||
        sourceEnd == null ||
        sourceEnd <= sourceStart) {
      return null;
    }
    final clampedStart = localStartMs.clamp(0, segmentDuration);
    final clampedEnd = localEndMs.clamp(0, segmentDuration);
    if (clampedEnd <= clampedStart) {
      return null;
    }

    final segmentSourceDuration = (sourceEnd - sourceStart).toDouble();
    final ratioStart = clampedStart / segmentDuration;
    final ratioEnd = clampedEnd / segmentDuration;
    final mappedStart =
        (sourceStart + (segmentSourceDuration * ratioStart)).round();
    final mappedEnd =
        (sourceStart + (segmentSourceDuration * ratioEnd)).round();
    return _SegmentSourceWindow(mappedStart, mappedEnd);
  }

  ProxyManifestData copy() {
    final copy = ProxyManifestData(
      segmentDurationMs: segmentDurationMs,
      width: width,
      height: height,
      fps: fps,
      hasAudio: hasAudio,
      durationMs: durationMs,
      sourceStartMs: sourceStartMs,
      sourceEndMs: sourceEndMs,
      orientation: orientation,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      matchesSourceVideoCodec: matchesSourceVideoCodec,
      matchesSourceAudioCodec: matchesSourceAudioCodec,
    );
    copy.segments.addAll(segments);
    copy.keyframes.addAll(keyframes);
    return copy;
  }

  ProxyQuality? bestAvailableQuality() {
    if (segments.isEmpty) {
      return null;
    }
    return segments
        .map((segment) => segment.quality)
        .reduce((a, b) =>
            _qualityRank(a) >= _qualityRank(b) ? a : b);
  }

  Set<ProxySessionQualityTier> availableQualityTiers() {
    if (segments.isEmpty) {
      return const <ProxySessionQualityTier>{};
    }
    final tiers = segments
        .map((segment) => proxySessionTierForQuality(segment.quality))
        .toSet();
    return Set<ProxySessionQualityTier>.unmodifiable(tiers);
  }
}

class _SegmentSourceWindow {
  const _SegmentSourceWindow(this.startMs, this.endMs);

  final int startMs;
  final int endMs;
}

class _CachedSegmentRecord {
  _CachedSegmentRecord({
    required this.path,
    required this.segmentIndex,
    required this.quality,
    required this.generatedAt,
    required this.sizeBytes,
  }) : lastAccessed = generatedAt;

  final String path;
  final int segmentIndex;
  final ProxyQuality quality;
  final DateTime generatedAt;
  final int sizeBytes;
  DateTime lastAccessed;
}

class _CacheEntry {
  _CacheEntry(this.jobId, this.record);

  final String jobId;
  final _CachedSegmentRecord record;
}

class VideoProxySession {
  VideoProxySession._({
    required this.jobId,
    required this.request,
    required Future<ProxyPreview> preview,
    required Stream<ProxySessionMetadataEvent> metadataStream,
    required Stream<VideoProxyProgress> progressStream,
    required Future<VideoProxyResult> result,
    required Future<void> Function() cancel,
    required Future<void> Function(int, int, ProxyQuality) ensureSegment,
    required ProxyManifestData? Function() manifestLookup,
  })  : firstPreview = preview,
        metadata = metadataStream,
        progress = progressStream,
        completed = result,
        _cancel = cancel,
        _ensureSegment = ensureSegment,
        _manifestLookup = manifestLookup;

  final String jobId;
  final VideoProxyRequest request;
  final Future<ProxyPreview> firstPreview;
  final Stream<ProxySessionMetadataEvent> metadata;
  final Stream<VideoProxyProgress> progress;
  final Future<VideoProxyResult> completed;
  final Future<void> Function() _cancel;
  final Future<void> Function(int, int, ProxyQuality) _ensureSegment;
  final ProxyManifestData? Function() _manifestLookup;

  Future<void> cancel() => _cancel();

  Future<void> ensureSegment(int startMs, int endMs,
      {ProxyQuality quality = ProxyQuality.preview}) {
    return _ensureSegment(startMs, endMs, quality);
  }

  ProxyManifestData? get manifest => _manifestLookup()?.copy();

  ProxySegment? segmentForTimestamp(int timestampMs) {
    final manifest = _manifestLookup();
    return manifest?.segmentForTimestamp(timestampMs);
  }

  List<ProxyKeyframe> keyframesInRange(int startMs, int endMs) {
    final manifest = _manifestLookup();
    if (manifest == null) {
      return const [];
    }
    return manifest.keyframesInRange(startMs, endMs);
  }
}

class VideoProxyJob {
  VideoProxyJob({
    required this.future,
    required this.progress,
    required Future<void> Function() cancel,
    this.session,
  }) : _cancel = cancel;

  final Future<VideoProxyResult> future;
  final Stream<VideoProxyProgress> progress;
  final Future<void> Function() _cancel;
  final VideoProxySession? session;

  Future<void> cancel() => _cancel();
}

class VideoProxyService {
  factory VideoProxyService() => _instance;

  VideoProxyService._()
      : _progressEvents = _progressChannel
            .receiveBroadcastStream()
            .map<_NativeProxyEvent>(_NativeProxyEvent.fromDynamic)
            .handleError((Object error, StackTrace stackTrace) {
          debugPrint('[VideoProxyService] Progress stream error: $error');
        }).asBroadcastStream();

  static final VideoProxyService _instance = VideoProxyService._();

  final Stream<_NativeProxyEvent> _progressEvents;
  final Map<String, ProxyManifestData> _manifests = {};
  final Map<String, StreamController<Map<String, dynamic>>>
      _syntheticEventControllers = {};
  final Map<String, List<_CachedSegmentRecord>> _cachedSegments = {};

  ProxyManifestData? manifestForJob(String jobId) {
    final manifest = _manifests[jobId];
    return manifest?.copy();
  }

  Stream<Map<String, dynamic>> syntheticEventsFor(String jobId) {
    return _syntheticEventControllerFor(jobId).stream;
  }

  StreamController<Map<String, dynamic>> _syntheticEventControllerFor(
      String jobId) {
    return _syntheticEventControllers.putIfAbsent(
      jobId,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    );
  }

  void _emitSyntheticEvent(String jobId, Map<String, dynamic> event) {
    final controller = _syntheticEventControllers[jobId];
    if (controller != null && !controller.isClosed) {
      controller.add(event);
    }
  }

  Future<void> _closeSyntheticEvents(String jobId) async {
    final controller = _syntheticEventControllers.remove(jobId);
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  ProxySegment? manifestSegmentFor(String jobId, int timestampMs) {
    return _manifests[jobId]?.segmentForTimestamp(timestampMs);
  }

  List<ProxyKeyframe> manifestKeyframesFor(
      String jobId, int startMs, int endMs) {
    final manifest = _manifests[jobId];
    if (manifest == null) return const [];
    return manifest.keyframesInRange(startMs, endMs);
  }

  ProxyManifestData _manifestForJob(String jobId) {
    return _manifests.putIfAbsent(jobId, () => ProxyManifestData());
  }

  Future<void> releaseJob(String jobId) async {
    await _cleanupCacheForJob(jobId);
    _cachedSegments.remove(jobId);
    _manifests.remove(jobId);
    await _closeSyntheticEvents(jobId);
  }

  /// Returns a stream of raw native proxy events for a specific jobId.
  Stream<_NativeProxyEvent> nativeEventsFor(String jobId) {
    return _progressEvents.where((e) => e.jobId == jobId).asBroadcastStream();
  }

  Directory? _cacheDirectory;

  Future<Directory> _ensureCacheDirectory() async {
    final existing = _cacheDirectory;
    if (existing != null) return existing;
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'video_proxies'));
    await dir.create(recursive: true);
    _cacheDirectory = dir;
    return dir;
  }

  /// Create or update a manifest JSON for segmented proxies.
  Future<void> _updateManifest(
      String jobId, ProxyManifestData manifestData) async {
    final cacheDir = await _ensureCacheDirectory();
    final jobDir = Directory(p.join(cacheDir.path, jobId));
    await jobDir.create(recursive: true);
    final manifestFile = File(p.join(jobDir.path, 'manifest.json'));
    final json = {
      'version': 1,
      'segmentDurationMs': manifestData.segmentDurationMs,
      'segments': manifestData.segments
          .map((s) {
            final data = Map<String, Object?>.from(s.toJson());
            data['path'] = p.basename(s.path);
            return data;
          })
          .toList(),
      'width': manifestData.width,
      'height': manifestData.height,
      'fps': manifestData.fps,
      'hasAudio': manifestData.hasAudio,
      'durationMs': manifestData.durationMs,
      'sourceStartMs': manifestData.sourceStartMs,
      'sourceEndMs': manifestData.sourceEndMs,
      'orientation': manifestData.orientation,
      'videoCodec': manifestData.videoCodec,
      'audioCodec': manifestData.audioCodec,
      'matchesSourceVideoCodec': manifestData.matchesSourceVideoCodec,
      'matchesSourceAudioCodec': manifestData.matchesSourceAudioCodec,
      'keyframes': manifestData.keyframes.map((k) => k.toJson()).toList(),
    };
    await manifestFile
        .writeAsString(JsonEncoder.withIndent('  ').convert(json));
  }

  Future<void> _cleanupCacheForJob(String jobId) async {
    final records = _cachedSegments.remove(jobId);
    if (records != null) {
      for (final record in records) {
        await _deleteSegmentFile(record.path);
      }
    }
    try {
      final cacheDir = await _ensureCacheDirectory();
      final jobDir = Directory(p.join(cacheDir.path, jobId));
      if (await jobDir.exists()) {
        await jobDir.delete(recursive: true);
      }
    } catch (error) {
      debugPrint(
          '[VideoProxyService] Failed to cleanup cache for job $jobId: $error');
    }
  }

  Future<void> _registerSegmentFile(String jobId, ProxySegment segment,
      {ProxySegment? replaced}) async {
    final records =
        _cachedSegments.putIfAbsent(jobId, () => <_CachedSegmentRecord>[]);
    records.removeWhere((record) => record.segmentIndex == segment.index);
    if (replaced != null) {
      records.removeWhere((record) => record.path == replaced.path);
    }

    var sizeBytes = 0;
    try {
      final file = File(segment.path);
      if (await file.exists()) {
        final stat = await file.stat();
        sizeBytes = stat.size;
      }
    } catch (error) {
      debugPrint('[VideoProxyService] Failed to stat segment '
          '${segment.path}: $error');
    }

    records.add(_CachedSegmentRecord(
      path: segment.path,
      segmentIndex: segment.index,
      quality: segment.quality,
      generatedAt: DateTime.now(),
      sizeBytes: sizeBytes,
    ));

    await _pruneExpiredSegments(jobId);
    await _enforceCacheQuota();

    if (replaced != null && replaced.path != segment.path) {
      await _deleteSegmentFile(replaced.path);
    }
  }

  Future<void> _pruneExpiredSegments(String jobId) async {
    final records = _cachedSegments[jobId];
    if (records == null || records.isEmpty) {
      return;
    }
    final manifest = _manifests[jobId];
    if (manifest == null) {
      return;
    }
    final cutoff = DateTime.now().subtract(_kSegmentRetention);
    final expired =
        records.where((record) => record.generatedAt.isBefore(cutoff)).toList();
    if (expired.isEmpty) {
      return;
    }
    var manifestUpdated = false;
    for (final record in expired) {
      await _deleteSegmentFile(record.path);
      if (manifest.removeSegment(
          index: record.segmentIndex, path: record.path)) {
        manifestUpdated = true;
      }
    }
    records.removeWhere((record) => record.generatedAt.isBefore(cutoff));
    if (manifestUpdated) {
      await _updateManifest(jobId, manifest);
    }
  }

  Future<void> _enforceCacheQuota() async {
    var totalSize = _currentCacheSize;
    if (totalSize <= _kCacheQuotaBytes) {
      return;
    }
    final entries = <_CacheEntry>[];
    _cachedSegments.forEach((jobId, records) {
      for (final record in records) {
        entries.add(_CacheEntry(jobId, record));
      }
    });
    entries.sort((a, b) =>
        a.record.generatedAt.compareTo(b.record.generatedAt));
    final manifestNeedsUpdate = <String, bool>{};
    for (final entry in entries) {
      if (totalSize <= _kCacheQuotaBytes) {
        break;
      }
      await _deleteSegmentFile(entry.record.path);
      final manifest = _manifests[entry.jobId];
      if (manifest != null &&
          manifest.removeSegment(
              index: entry.record.segmentIndex,
              path: entry.record.path)) {
        manifestNeedsUpdate[entry.jobId] = true;
      }
      final records = _cachedSegments[entry.jobId];
      records?.remove(entry.record);
      totalSize -= entry.record.sizeBytes;
    }
    for (final jobId in manifestNeedsUpdate.keys) {
      final manifest = _manifests[jobId];
      if (manifest != null) {
        await _updateManifest(jobId, manifest);
      }
    }
  }

  int get _currentCacheSize {
    var total = 0;
    for (final records in _cachedSegments.values) {
      for (final record in records) {
        total += record.sizeBytes;
      }
    }
    return total;
  }

  Future<void> _deleteSegmentFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint(
          '[VideoProxyService] Failed to delete cached segment at $path: $error');
    }
  }

  Future<void> deleteProxy(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('[VideoProxyService] Failed to delete proxy at $path: $error');
    }
  }

  VideoProxySession createSession({
    required VideoProxyRequest request,
    bool enableLogging = true,
    void Function(String jobId)? onJobCreated,
  }) {
    final jobId = _uuid.v4();
    var variableFrameRateDetected = false;
    var hardwareDecodeUnsupported = false;
    if (onJobCreated != null) {
      try {
        onJobCreated(jobId);
      } catch (e, st) {
        debugPrint('[VideoProxyService] onJobCreated callback failed: $e\n$st');
      }
    }
    final progressController = StreamController<VideoProxyProgress>.broadcast();
    final metadataController =
        StreamController<ProxySessionMetadataEvent>.broadcast();
    final previewCompleter = Completer<ProxyPreview>();
    final resultCompleter = Completer<VideoProxyResult>();
    final stopwatch = Stopwatch()..start();
    var cancelled = false;
    var autoFallbackRequested = request.forceFallback;
    Timer? timeoutTimer;
    Timer? stallTimer;
    var fallbackScheduled = request.forceFallback;
    var finalized = false;
    Map<String, dynamic>? lastTimelinePayload;

    _manifestForJob(jobId);

    void cancelTimers() {
      timeoutTimer?.cancel();
      stallTimer?.cancel();
    }

    void triggerFallback() {
      if (cancelled || fallbackScheduled) {
        return;
      }
      fallbackScheduled = true;
      autoFallbackRequested = true;
      progressController.add(
        const VideoProxyProgress(null, fallbackTriggered: true),
      );
      unawaited(_methodChannel.invokeMethod('cancelProxy', {
        'jobId': jobId,
      }));
    }

    void scheduleTimeouts() {
      if (fallbackScheduled || cancelled) {
        return;
      }
      timeoutTimer?.cancel();
      timeoutTimer = Timer(const Duration(seconds: 40), triggerFallback);
      stallTimer?.cancel();
      stallTimer = Timer(const Duration(seconds: 10), triggerFallback);
    }

    void scheduleSegmentedTimeouts() {
      if (fallbackScheduled || cancelled) {
        return;
      }
      timeoutTimer?.cancel();
      // Segmented previews can take longer to produce the first segment
      // (trimming + transcode). Give more generous timeouts here.
      timeoutTimer = Timer(const Duration(seconds: 180), triggerFallback);
      stallTimer?.cancel();
      stallTimer = Timer(const Duration(seconds: 30), triggerFallback);
    }

    void resetStallTimer() {
      if (fallbackScheduled || cancelled) {
        return;
      }
      stallTimer?.cancel();
      stallTimer = Timer(const Duration(seconds: 10), triggerFallback);
    }

    StreamSubscription<_NativeProxyEvent>? subscription;
    subscription = _progressEvents
        .where((event) => event.jobId == jobId)
        .listen((event) async {
      if (enableLogging) {
        debugPrint(
            '[VideoProxyService] native event for job $jobId: type=${event.type} segmentIndex=${event.segmentIndex} path=${event.path} progress=${event.progress}');
      }
      if (cancelled) return;
      resetStallTimer();

      // Handle fallback notifications and progress
      final shouldNotifyFallback =
          event.fallbackTriggered && !autoFallbackRequested;
      if (shouldNotifyFallback) {
        autoFallbackRequested = true;
        progressController
            .add(const VideoProxyProgress(null, fallbackTriggered: true));
      }

      if (event.type == 'progress') {
        progressController.add(VideoProxyProgress(event.progress,
            fallbackTriggered: shouldNotifyFallback));
        return;
      }

      final manifest = _manifestForJob(jobId);
      var manifestChanged = false;

      if (event.timelinePayload != null) {
        lastTimelinePayload = event.timelinePayload;
      }

      final metadataPayload = event.metadataPayload;
      if (metadataPayload != null) {
        final metaDuration = (metadataPayload['durationMs'] as num?)?.toInt();
        final metaFps =
            (metadataPayload['frameRate'] as num?)?.toDouble() ??
                (metadataPayload['fps'] as num?)?.toDouble();
        final metaSegmentDuration =
            (metadataPayload['segmentDurationMs'] as num?)?.toInt();
        final metaWidth =
            (metadataPayload['width'] as num?)?.toInt() ?? event.width;
        final metaHeight =
            (metadataPayload['height'] as num?)?.toInt() ?? event.height;
        final metaHasAudio = metadataPayload['hasAudio'];
        final metaSourceStart =
            (metadataPayload['sourceStartMs'] as num?)?.toInt();
        final metaSourceEnd =
            (metadataPayload['sourceEndMs'] as num?)?.toInt();
        final metaOrientation = metadataPayload['orientation']?.toString();
        final metaVideoCodec = metadataPayload['videoCodec']?.toString();
        final metaAudioCodec = metadataPayload['audioCodec']?.toString();
        final metaMatchesVideo = metadataPayload.containsKey('matchesSourceVideoCodec')
            ? metadataPayload['matchesSourceVideoCodec'] == true
            : null;
        final metaMatchesAudio = metadataPayload.containsKey('matchesSourceAudioCodec')
            ? metadataPayload['matchesSourceAudioCodec'] == true
            : null;
        manifest.mergeMetadata(
          segmentDurationMs: metaSegmentDuration,
          width: metaWidth,
          height: metaHeight,
          fps: metaFps,
          hasAudio: metaHasAudio is bool ? metaHasAudio : null,
          durationMs: metaDuration ?? event.durationMs,
          sourceStartMs: metaSourceStart,
          sourceEndMs: metaSourceEnd,
          orientation: metaOrientation,
          videoCodec: metaVideoCodec,
          audioCodec: metaAudioCodec,
          matchesSourceVideoCodec: metaMatchesVideo,
          matchesSourceAudioCodec: metaMatchesAudio,
        );
        final metadataKeyframes = metadataPayload['keyframes'];
        if (metadataKeyframes is List) {
          final frames = metadataKeyframes.whereType<Map>().map((frame) {
            final casted = frame.map((key, dynamic value) {
              return MapEntry(key.toString(), value);
            });
            return ProxyKeyframe.fromJson(casted);
          });
          manifest.addKeyframes(frames);
        }
        manifestChanged = true;
      }

      final keyframePayload = event.keyframePayload;
      if (keyframePayload != null && keyframePayload.isNotEmpty) {
        manifest.addKeyframes(
          keyframePayload.map(ProxyKeyframe.fromJson),
        );
        manifestChanged = true;
      }

      final isSegmentEvent =
          (event.type == 'segment_ready' || event.type == 'segment_upgraded');
      if (isSegmentEvent && event.segmentIndex != null && event.path != null) {
        try {
          // Ensure job manifest exists
          final width =
              event.width ?? manifest.width ?? request.targetWidth;
          final height =
              event.height ?? manifest.height ?? request.targetHeight;
          final fps = manifest.fps ??
              ((event.totalDurationMs != null &&
                      event.totalSegments != null &&
                      event.totalSegments! > 0)
                  ? ((event.totalDurationMs! / 1000.0) / event.totalSegments!)
                  : (request.frameRateHint?.toDouble() ?? 24.0));
          final existingIndex =
              manifest.segments.indexWhere((s) => s.index == event.segmentIndex);
          final previousSegment =
              existingIndex >= 0 ? manifest.segments[existingIndex] : null;
          final incomingQuality = proxyQualityFromLabel(
            event.qualityLabel,
            fallback: previousSegment?.quality ?? ProxyQuality.preview,
          );
          manifest.mergeMetadata(
            segmentDurationMs: manifest.segmentDurationMs == 0
                ? event.durationMs
                : manifest.segmentDurationMs,
            width: width,
            height: height,
            fps: fps,
            hasAudio: event.hasAudio,
            durationMs: event.totalDurationMs,
            sourceStartMs: event.sourceStartMs,
            sourceEndMs: event.sourceEndMs,
            orientation: event.orientation,
            videoCodec: event.videoCodec,
            audioCodec: event.audioCodec,
            matchesSourceVideoCodec: event.matchesSourceVideoCodec,
            matchesSourceAudioCodec: event.matchesSourceAudioCodec,
          );

          final resolvedDuration =
              event.durationMs ?? manifest.segmentDurationMs;
          final segmentSourceEnd = event.sourceEndMs ??
              ((event.sourceStartMs != null && resolvedDuration > 0)
                  ? event.sourceStartMs! + resolvedDuration
                  : null);
          final segment = ProxySegment(
            index: event.segmentIndex!,
            path: event.path!,
            durationMs: resolvedDuration,
            width: width,
            height: height,
            hasAudio: event.hasAudio ?? manifest.hasAudio,
            quality: incomingQuality,
            sourceStartMs: event.sourceStartMs,
            sourceEndMs: segmentSourceEnd,
            orientation: event.orientation,
            videoCodec: event.videoCodec,
            audioCodec: event.audioCodec,
            matchesSourceVideoCodec: event.matchesSourceVideoCodec,
            matchesSourceAudioCodec: event.matchesSourceAudioCodec,
          );
          final added = manifest.addSegment(segment);
          if (!added) {
            return;
          }
          manifestChanged = true;

          final isUpgrade = previousSegment != null &&
              ProxyManifestData._qualityRank(segment.quality) >
                  ProxyManifestData._qualityRank(previousSegment.quality);
          await _registerSegmentFile(
            jobId,
            segment,
            replaced: isUpgrade ? previousSegment : null,
          );

          if (isUpgrade || event.type == 'segment_upgraded') {
            _emitSyntheticEvent(jobId, {
              'type': 'segment_upgraded',
              'segmentIndex': segment.index,
              'path': segment.path,
              'durationMs': segment.durationMs,
              'width': segment.width,
              'height': segment.height,
              'quality': segment.quality.platformLabel,
            });
          }

          // Emit a small progress update based on segments available if total known
          if (event.totalSegments != null && event.totalDurationMs != null) {
            final ratio = (manifest.segments.length / event.totalSegments!)
                .clamp(0.0, 1.0);
            progressController.add(VideoProxyProgress(ratio));
          }
        } catch (e, st) {
          debugPrint(
              '[VideoProxyService] Failed handling segment_ready: $e\n$st');
        }
      }

      if (event.type == 'preview_ready' || event.type == 'poster_ready') {
        final previewPath = event.previewPath ?? event.path;
        if (previewPath != null && previewPath.isNotEmpty) {
          final width =
              event.width ?? manifest.width ?? request.targetWidth;
          final height =
              event.height ?? manifest.height ?? request.targetHeight;
          final durationMs = event.durationMs ??
              manifest.durationMs ??
              request.estimatedDurationMs ??
              0;
          final frameRate = manifest.fps ??
              request.frameRateHint?.toDouble();
          final metadata = VideoProxyMetadata(
            width: width,
            height: height,
            durationMs: durationMs,
            frameRate: frameRate,
            resolution: () {
              final maxEdge = width >= height ? width : height;
              if (maxEdge <= 640) return VideoProxyResolution.p360;
              if (maxEdge <= 960) return VideoProxyResolution.p540;
              if (maxEdge <= 1280) return VideoProxyResolution.hd720;
              return VideoProxyResolution.hd1080;
            }(),
            rotationBaked: true,
          );
          if (!previewCompleter.isCompleted) {
            previewCompleter.complete(ProxyPreview(
              quality: proxyQualityFromLabel(event.previewQualityLabel),
              filePath: previewPath,
              metadata: metadata,
              segmentIndex: event.segmentIndex,
            ));
          }
        }
      }

      if (event.type == 'completed') {
        manifestChanged = true;
      }

      if (manifestChanged) {
        final bestQuality = manifest.bestAvailableQuality();
        final availableTiers = manifest.availableQualityTiers();
        final activeTier =
            bestQuality != null ? proxySessionTierForQuality(bestQuality) : null;
        await _updateManifest(jobId, manifest);
        metadataController.add(ProxySessionMetadataEvent(
          durationMs: manifest.durationMs,
          frameRate: manifest.fps,
          keyframes: List.unmodifiable(manifest.keyframes),
          segments: List.unmodifiable(manifest.segments),
          sourceStartMs: manifest.sourceStartMs,
          sourceEndMs: manifest.sourceEndMs,
          orientation: manifest.orientation,
          videoCodec: manifest.videoCodec,
          audioCodec: manifest.audioCodec,
          matchesSourceVideoCodec: manifest.matchesSourceVideoCodec,
          matchesSourceAudioCodec: manifest.matchesSourceAudioCodec,
          activeQuality: activeTier,
          availableQualities: availableTiers,
          variableFrameRate: variableFrameRateDetected,
          hardwareDecodeUnsupported: hardwareDecodeUnsupported,
        ));
      }
    });

    Future<void> finalize() async {
      if (finalized) {
        return;
      }
      finalized = true;
      await subscription?.cancel();
      await progressController.close();
      await metadataController.close();
    }

    Future<void> emitSourceSummary() async {
      if (!enableLogging) return;
      try {
        final response = await _methodChannel.invokeMapMethod<String, dynamic>(
          'probeSource',
          {
            'sourcePath': request.sourcePath,
          },
        );
        if (response == null || response['ok'] == false) {
          return;
        }
        final frameRateMode =
            response['frameRateMode']?.toString().toLowerCase();
        if (frameRateMode == 'vfr' || frameRateMode == 'variable') {
          variableFrameRateDetected = true;
        }
        if (response['variableFrameRate'] == true) {
          variableFrameRateDetected = true;
        }
        if (response['hardwareDecodeSupported'] == false ||
            response['decodeSupported'] == false ||
            response['hardwareDecodeCapable'] == false) {
          hardwareDecodeUnsupported = true;
        }
        final warnings = response['warnings'];
        if (warnings is List) {
          for (final warning in warnings) {
            final text = warning.toString().toLowerCase();
            if (text.contains('hardware decode') ||
                text.contains('hw decode')) {
              hardwareDecodeUnsupported = true;
            }
            if (text.contains('variable frame')) {
              variableFrameRateDetected = true;
            }
          }
        }
        debugPrint(
          '[VideoProxyService] Source summary: '
          'codec=${response['codec'] ?? '?'} '
          'size=${response['width'] ?? '?'}x${response['height'] ?? '?'} '
          'rotation=${response['rotation'] ?? '?'} '
          'durationMs=${response['durationMs'] ?? '?'}',
        );
      } catch (error) {
        debugPrint('[VideoProxyService] Failed to probe source: $error');
      }
    }

    Future<Map<String, dynamic>?> _invokeProxy(
        VideoProxyRequest proxyRequest) async {
      final cacheDir = await _ensureCacheDirectory();
      final args = proxyRequest.toPlatformRequest(jobId: jobId)
        ..addAll({
          'outputDirectory': cacheDir.path,
          'enableLogging': enableLogging,
        });

      debugPrint(
          '[VideoProxyService] Invoking native proxy for job $jobId segmented=${proxyRequest.segmentedPreview} args=${args.keys.toList()}');

      final methodName = proxyRequest.forceFallback
          ? 'createProxyFallback720p'
          : 'createProxy';

      return _methodChannel.invokeMapMethod<String, dynamic>(methodName, args);
    }

    Future<void> startJob() async {
      try {
        await emitSourceSummary();

        var currentRequest = request;
        Map<String, dynamic>? response;

        if (cancelled) {
          final error = const VideoProxyCancelException();
          if (!resultCompleter.isCompleted) {
            resultCompleter.completeError(error);
          }
          if (!previewCompleter.isCompleted) {
            previewCompleter.completeError(error);
          }
          return;
        }

        while (true) {
          fallbackScheduled = currentRequest.forceFallback;
          final responseFuture = _invokeProxy(currentRequest);
          if (!currentRequest.forceFallback) {
            if (currentRequest.segmentedPreview) {
              scheduleSegmentedTimeouts();
            } else {
              scheduleTimeouts();
            }
          }
          response = await responseFuture;
          cancelTimers();

          if (response != null && response['ok'] == true) {
            break;
          }

          final code = response?['code']?.toString();

          if (code == 'hardware_decode_failed' ||
              code == 'hardware_decode_unsupported') {
            hardwareDecodeUnsupported = true;
            currentRequest = currentRequest.fallbackPreview();
            autoFallbackRequested = true;
            continue;
          }

          if (cancelled) {
            final error = const VideoProxyCancelException();
            if (!resultCompleter.isCompleted) {
              resultCompleter.completeError(error);
            }
            if (!previewCompleter.isCompleted) {
              previewCompleter.completeError(error);
            }
            return;
          }

          if (fallbackScheduled && code == 'cancelled') {
            currentRequest = currentRequest.fallbackPreview();
            continue;
          }

          if (code == 'cancelled') {
            final error = const VideoProxyCancelException();
            if (!resultCompleter.isCompleted) {
              resultCompleter.completeError(error);
            }
            if (!previewCompleter.isCompleted) {
              previewCompleter.completeError(error);
            }
            return;
          }

          final message = response?['message']?.toString() ?? 'Unknown error';
          final error = VideoProxyException(message, code: code);
          if (!resultCompleter.isCompleted) {
            resultCompleter.completeError(error);
          }
          if (!previewCompleter.isCompleted) {
            previewCompleter.completeError(error);
          }
          return;
        }

        final manifest = _manifestForJob(jobId);
        final usedFallbackFlag = response?['usedFallback720p'] == true;

        VideoProxyMetadata buildMetadata({
          required int width,
          required int height,
          required int durationMs,
          double? frameRate,
          bool rotationBaked = true,
        }) {
          final maxEdge = width >= height ? width : height;
          final resolution = () {
            if (maxEdge <= 640) return VideoProxyResolution.p360;
            if (maxEdge <= 960) return VideoProxyResolution.p540;
            if (maxEdge <= 1280) return VideoProxyResolution.hd720;
            return VideoProxyResolution.hd1080;
          }();
          return VideoProxyMetadata(
            width: width,
            height: height,
            durationMs: durationMs,
            frameRate: frameRate,
            resolution: resolution,
            rotationBaked: rotationBaked,
          );
        }

        List<Map<String, dynamic>> tierResponses =
            (response?['tiers'] as List?)
                    ?.whereType<Map>()
                    .map((tier) => tier.map((key, dynamic value) {
                          return MapEntry(key.toString(), value);
                        }))
                    .toList() ??
                const <Map<String, dynamic>>[];

        List<ProxyTierResult> parseTierResults(
          List<Map<String, dynamic>> tiers,
          VideoProxyMetadata fallbackMetadata,
          String fallbackPath,
        ) {
          final results = <ProxyTierResult>[];
          for (final tier in tiers) {
            final tierPath = tier['filePath']?.toString() ?? fallbackPath;
            final tierWidth =
                (tier['width'] as num?)?.toInt() ?? fallbackMetadata.width;
            final tierHeight =
                (tier['height'] as num?)?.toInt() ?? fallbackMetadata.height;
            final tierDuration =
                (tier['durationMs'] as num?)?.toInt() ??
                    fallbackMetadata.durationMs;
            final tierFrameRate =
                (tier['frameRate'] as num?)?.toDouble() ??
                    fallbackMetadata.frameRate;
            final tierMetadata = buildMetadata(
              width: tierWidth,
              height: tierHeight,
              durationMs: tierDuration,
              frameRate: tierFrameRate,
            );
            results.add(ProxyTierResult(
              quality:
                  proxyQualityFromLabel(tier['quality']?.toString()),
              filePath: tierPath,
              metadata: tierMetadata,
            ));
          }
          if (results.every((tier) => tier.filePath != fallbackPath)) {
            results.insert(
              0,
              ProxyTierResult(
                quality: ProxyQuality.proxy,
                filePath: fallbackPath,
                metadata: fallbackMetadata,
              ),
            );
          }
          return results;
        }

        Future<VideoProxyResult> buildResult({
          required String filePath,
          required VideoProxyMetadata metadata,
        }) async {
          final tierResults = parseTierResults(tierResponses, metadata, filePath);

          final timelineMappings = <VideoProxyTimelineMapping>[];
          int? sourceStartMs = request.sourceStartMs;
          int? sourceDurationMs =
              request.sourceDurationMs ?? metadata.durationMs;
          int? sourceRotationDegrees = request.sourceRotationDegrees;
          String? sourceVideoCodec = request.sourceVideoCodec;
          String? sourceOrientation = request.sourceOrientation;
          bool? sourceMirrored = request.sourceMirrored;
          bool? matchesSourceVideoCodec = manifest.matchesSourceVideoCodec;
          bool? matchesSourceAudioCodec = manifest.matchesSourceAudioCodec;
          final responseVideoCodec = response?['videoCodec']?.toString();
          final responseAudioCodec = response?['audioCodec']?.toString();

          void mergeTimeline(Map<String, dynamic> json) {
            if (json.containsKey('sourceStartMs')) {
              sourceStartMs = (json['sourceStartMs'] as num?)?.toInt();
            }
            if (json.containsKey('sourceDurationMs')) {
              sourceDurationMs =
                  (json['sourceDurationMs'] as num?)?.toInt();
            }
            if (json.containsKey('sourceRotationDegrees')) {
              sourceRotationDegrees =
                  (json['sourceRotationDegrees'] as num?)?.toInt();
            }
            if (json.containsKey('sourceVideoCodec')) {
              sourceVideoCodec = json['sourceVideoCodec']?.toString();
            }
            if (json.containsKey('sourceOrientation')) {
              sourceOrientation = json['sourceOrientation']?.toString();
            }
            if (json.containsKey('sourceMirrored')) {
              sourceMirrored = json['sourceMirrored'] as bool?;
            }
            if (json.containsKey('matchesSourceVideoCodec')) {
              matchesSourceVideoCodec = json['matchesSourceVideoCodec'] == true;
            }
            if (json.containsKey('matchesSourceAudioCodec')) {
              matchesSourceAudioCodec = json['matchesSourceAudioCodec'] == true;
            }
            final mappings = json['mappings'];
            if (mappings is List) {
              for (final mapping in mappings.whereType<Map>()) {
                final casted = mapping.map((key, dynamic value) {
                  return MapEntry(key.toString(), value);
                });
                timelineMappings
                    .add(VideoProxyTimelineMapping.fromJson(casted));
              }
            }
          }

          void mergeTimelineValue(Object? value) {
            if (value is Map) {
              final casted = value.map((key, dynamic v) {
                return MapEntry(key.toString(), v);
              });
              mergeTimeline(casted);
            }
          }

          mergeTimelineValue(response?['timeline']);
          mergeTimelineValue(lastTimelinePayload);
          final responseMappings = response?['timelineMappings'];
          if (responseMappings is List) {
            for (final mapping in responseMappings.whereType<Map>()) {
              final casted = mapping.map((key, dynamic value) {
                return MapEntry(key.toString(), value);
              });
              timelineMappings
                  .add(VideoProxyTimelineMapping.fromJson(casted));
            }
          }

          if (response?['sourceStartMs'] != null) {
            sourceStartMs =
                (response?['sourceStartMs'] as num?)?.toInt();
          }
          if (response?['sourceDurationMs'] != null) {
            sourceDurationMs =
                (response?['sourceDurationMs'] as num?)?.toInt();
          }
          if (response?['sourceRotationDegrees'] != null) {
            sourceRotationDegrees =
                (response?['sourceRotationDegrees'] as num?)?.toInt();
          }
          if (response?['sourceVideoCodec'] != null) {
            sourceVideoCodec = response?['sourceVideoCodec']?.toString();
          }
          if (response?['sourceOrientation'] != null) {
            sourceOrientation = response?['sourceOrientation']?.toString();
          }
          if (response?['sourceMirrored'] != null) {
            sourceMirrored = response?['sourceMirrored'] as bool?;
          }
          if (response?['matchesSourceVideoCodec'] != null) {
            matchesSourceVideoCodec =
                response?['matchesSourceVideoCodec'] == true;
          }
          if (response?['matchesSourceAudioCodec'] != null) {
            matchesSourceAudioCodec =
                response?['matchesSourceAudioCodec'] == true;
          }

          if (timelineMappings.isEmpty) {
            final defaultQuality = tierResults.isNotEmpty
                ? tierResults.first.quality
                : ProxyQuality.proxy;
            timelineMappings.add(VideoProxyTimelineMapping(
              quality: defaultQuality,
              sourceStartMs: sourceStartMs ?? request.sourceStartMs,
              sourceDurationMs:
                  sourceDurationMs ?? metadata.durationMs,
              proxyStartMs: 0,
              proxyDurationMs: metadata.durationMs,
            ));
          }

          final computedSourceEnd = (sourceStartMs != null &&
                  sourceDurationMs != null &&
                  sourceDurationMs! >= 0)
              ? sourceStartMs! + sourceDurationMs!
              : null;

          manifest.mergeMetadata(
            width: metadata.width,
            height: metadata.height,
            fps: metadata.frameRate,
            durationMs: metadata.durationMs,
            sourceStartMs: sourceStartMs,
            sourceEndMs: computedSourceEnd,
            orientation: sourceOrientation,
            videoCodec: sourceVideoCodec ?? responseVideoCodec,
            audioCodec: responseAudioCodec,
            matchesSourceVideoCodec: matchesSourceVideoCodec,
            matchesSourceAudioCodec: matchesSourceAudioCodec,
          );
          await _updateManifest(jobId, manifest);

          return VideoProxyResult(
            filePath: filePath,
            metadata: metadata,
            request: request,
            transcodeDurationMs:
                (response?['transcodeDurationMs'] as num?)?.toInt() ??
                    stopwatch.elapsedMilliseconds,
            usedFallback720p: usedFallbackFlag || autoFallbackRequested,
            sourceStartMs: sourceStartMs,
            sourceDurationMs: sourceDurationMs,
            sourceRotationDegrees: sourceRotationDegrees,
            sourceVideoCodec: sourceVideoCodec,
            sourceOrientation: sourceOrientation,
            sourceMirrored: sourceMirrored,
            tiers: tierResults,
            timelineMappings: timelineMappings,
          );
        }

        Future<VideoProxyResult> buildSegmentedResult() async {
          final cacheDir = await _ensureCacheDirectory();
          final jobDir = Directory(p.join(cacheDir.path, jobId));
          final manifestFile = File(p.join(jobDir.path, 'manifest.json'));

          var waited = 0;
          const pollMs = 500;
          const maxWaitMs = 180000;
          while (!await manifestFile.exists()) {
            if (cancelled) {
              throw const VideoProxyCancelException();
            }
            if (waited >= maxWaitMs) {
              throw const VideoProxyException(
                  'Timed out waiting for segmented preview manifest');
            }
            await Future.delayed(const Duration(milliseconds: pollMs));
            waited += pollMs;
          }

          var width = manifest.width ?? request.targetWidth;
          var height = manifest.height ?? request.targetHeight;
          var durationMs = manifest.durationMs ??
              manifest.segments.fold<int>(0, (sum, seg) => sum + seg.durationMs);
          var fps = manifest.fps ?? request.frameRateHint?.toDouble();

          if (manifest.segments.isEmpty) {
            try {
              final content = await manifestFile.readAsString();
              final json = jsonDecode(content) as Map<String, dynamic>;
              width = (json['width'] as num?)?.toInt() ?? width;
              height = (json['height'] as num?)?.toInt() ?? height;
              fps = (json['fps'] as num?)?.toDouble() ?? fps;
              durationMs = (json['durationMs'] as num?)?.toInt() ?? durationMs;
            } catch (error) {
              throw VideoProxyException(
                  'Failed to read segmented manifest: $error');
            }
          }

          manifest.mergeMetadata(
            width: width,
            height: height,
            fps: fps,
            durationMs: durationMs,
          );

          final metadata = buildMetadata(
            width: width,
            height: height,
            durationMs: durationMs,
            frameRate: fps,
          );

          return buildResult(
            filePath: manifestFile.path,
            metadata: metadata,
          );
        }

        Future<VideoProxyResult> buildSingleResult() async {
          final path = response?['proxyPath']?.toString();
          if (path == null || path.isEmpty) {
            throw const VideoProxyException('Proxy path missing from response');
          }
          final width =
              (response?['width'] as num?)?.toInt() ?? request.targetWidth;
          final height =
              (response?['height'] as num?)?.toInt() ?? request.targetHeight;
          final durationMs =
              (response?['durationMs'] as num?)?.toInt() ??
                  request.estimatedDurationMs ??
                  0;
          final frameRate = (response?['frameRate'] as num?)?.toDouble();
          final rotationBaked = response?['rotationBaked'] != false;
          final metadata = buildMetadata(
            width: width,
            height: height,
            durationMs: durationMs,
            frameRate: frameRate,
            rotationBaked: rotationBaked,
          );
          return buildResult(filePath: path, metadata: metadata);
        }

        final result =
            (response?['proxyPath'] == null ||
                    (response?['proxyPath'] as String?)?.isEmpty == true) &&
                    currentRequest.segmentedPreview
                ? await buildSegmentedResult()
                : await buildSingleResult();

        if (enableLogging) {
          debugPrint(
            '[VideoProxyService] Proxy ready ${result.metadata.width}x${result.metadata.height} '
            '(${result.metadata.resolution}) in ${result.transcodeDurationMs} ms '
            '(fallback=${result.usedFallback720p})',
          );
        }

        if (!previewCompleter.isCompleted) {
          final primaryTier =
              result.tiers.isNotEmpty ? result.tiers.first : null;
          previewCompleter.complete(ProxyPreview(
            quality: primaryTier?.quality ?? ProxyQuality.proxy,
            filePath: result.filePath,
            metadata: primaryTier?.metadata ?? result.metadata,
          ));
        }

        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(result);
        }
      } on PlatformException catch (error) {
        if (cancelled) {
          final cancelError = const VideoProxyCancelException();
          if (!resultCompleter.isCompleted) {
            resultCompleter.completeError(cancelError);
          }
          if (!previewCompleter.isCompleted) {
            previewCompleter.completeError(cancelError);
          }
          return;
        }
        final code = error.code;
        final message = error.message ?? 'Proxy generation failed';
        final proxyError = VideoProxyException(message, code: code);
        if (!resultCompleter.isCompleted) {
          resultCompleter.completeError(proxyError);
        }
        if (!previewCompleter.isCompleted) {
          previewCompleter.completeError(proxyError);
        }
      } on VideoProxyException catch (error) {
        if (!resultCompleter.isCompleted) {
          resultCompleter.completeError(error);
        }
        if (!previewCompleter.isCompleted) {
          previewCompleter.completeError(error);
        }
      } on VideoProxyCancelException catch (error) {
        if (!resultCompleter.isCompleted) {
          resultCompleter.completeError(error);
        }
        if (!previewCompleter.isCompleted) {
          previewCompleter.completeError(error);
        }
      } catch (error, stackTrace) {
        if (cancelled) {
          final cancelError = const VideoProxyCancelException();
          if (!resultCompleter.isCompleted) {
            resultCompleter.completeError(cancelError);
          }
          if (!previewCompleter.isCompleted) {
            previewCompleter.completeError(cancelError);
          }
          return;
        }
        debugPrint(
            '[VideoProxyService] Proxy generation error: $error\n$stackTrace');
        final proxyError =
            VideoProxyException('Failed to prepare proxy: $error');
        if (!resultCompleter.isCompleted) {
          resultCompleter.completeError(proxyError);
        }
        if (!previewCompleter.isCompleted) {
          previewCompleter.completeError(proxyError);
        }
      } finally {
        cancelTimers();
        stopwatch.stop();
        await finalize();
      }
    }

    final session = VideoProxySession._(
      jobId: jobId,
      request: request,
      preview: previewCompleter.future,
      metadataStream: metadataController.stream,
      progressStream: progressController.stream,
      result: resultCompleter.future,
      cancel: () async {
        if (cancelled) {
          return;
        }
        cancelled = true;
        try {
          await _methodChannel.invokeMethod('cancelProxy', {
            'jobId': jobId,
          });
        } catch (error) {
          debugPrint(
              '[VideoProxyService] Failed to cancel proxy job $jobId: $error');
        }
        if (!previewCompleter.isCompleted) {
          previewCompleter
              .completeError(const VideoProxyCancelException());
        }
      },
      ensureSegment: (startMs, endMs, quality) async {
        if (cancelled) {
          throw const VideoProxyCancelException();
        }
        try {
          await _methodChannel.invokeMethod('ensureSegment', {
            'jobId': jobId,
            'startMs': startMs,
            'endMs': endMs,
            'quality': quality.platformLabel,
          });
        } on PlatformException catch (error) {
          throw VideoProxyException(
            error.message ?? 'Failed to ensure segment',
            code: error.code,
          );
        }
      },
      manifestLookup: () => _manifests[jobId],
    );

    unawaited(startJob());

    return session;
  }

  VideoProxyJob createJob({
    required VideoProxyRequest request,
    bool enableLogging = true,
    void Function(String jobId)? onJobCreated,
  }) {
    final session = createSession(
      request: request,
      enableLogging: enableLogging,
      onJobCreated: onJobCreated,
    );
    return VideoProxyJob(
      future: session.completed,
      progress: session.progress,
      cancel: session.cancel,
      session: session,
    );
  }
}
