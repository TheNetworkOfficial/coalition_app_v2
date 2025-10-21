import 'dart:async';
import 'dart:io';

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
    this.displayWidth,
    this.displayHeight,
    this.rotation,
    this.sourceRotation,
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
  final int? displayWidth;
  final int? displayHeight;
  final int? rotation;
  final int? sourceRotation;
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
    final displayWidth = (map['displayWidth'] as num?)?.toInt();
    final displayHeight = (map['displayHeight'] as num?)?.toInt();
    final rotation = (map['rotation'] as num?)?.toInt();
    final sourceRotation = (map['sourceRotation'] as num?)?.toInt();
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
      displayWidth: displayWidth,
      displayHeight: displayHeight,
      rotation: rotation,
      sourceRotation: sourceRotation,
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

class _SessionMetadataState {
  int? width;
  int? height;
  double? fps;
  bool? hasAudio;
  int? durationMs;
  int? sourceStartMs;
  int? sourceEndMs;
  String? orientation;
  String? videoCodec;
  String? audioCodec;
  bool? matchesSourceVideoCodec;
  bool? matchesSourceAudioCodec;
  final List<ProxyKeyframe> keyframes = [];

  void mergeMetadata({
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

  ProxySessionMetadataEvent buildEvent({
    required bool variableFrameRate,
    required bool hardwareDecodeUnsupported,
    ProxySessionQualityTier? activeQuality,
    Set<ProxySessionQualityTier> availableQualities =
        const <ProxySessionQualityTier>{},
  }) {
    return ProxySessionMetadataEvent(
      durationMs: durationMs,
      frameRate: fps,
      keyframes: List.unmodifiable(keyframes),
      sourceStartMs: sourceStartMs,
      sourceEndMs: sourceEndMs,
      orientation: orientation,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      matchesSourceVideoCodec: matchesSourceVideoCodec,
      matchesSourceAudioCodec: matchesSourceAudioCodec,
      activeQuality: activeQuality,
      availableQualities: availableQualities,
      variableFrameRate: variableFrameRate,
      hardwareDecodeUnsupported: hardwareDecodeUnsupported,
    );
  }
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
  })  : firstPreview = preview,
        metadata = metadataStream,
        progress = progressStream,
        completed = result,
        _cancel = cancel;

  final String jobId;
  final VideoProxyRequest request;
  final Future<ProxyPreview> firstPreview;
  final Stream<ProxySessionMetadataEvent> metadata;
  final Stream<VideoProxyProgress> progress;
  final Future<VideoProxyResult> completed;
  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
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
    if (onJobCreated != null) {
      try {
        onJobCreated(jobId);
      } catch (e, st) {
        debugPrint('[VideoProxyService] onJobCreated callback failed: $e\n$st');
      }
    }

    final metadataState = _SessionMetadataState();
    final progressController = StreamController<VideoProxyProgress>.broadcast();
    final metadataController =
        StreamController<ProxySessionMetadataEvent>.broadcast();
    final previewCompleter = Completer<ProxyPreview>();
    final resultCompleter = Completer<VideoProxyResult>();
    final stopwatch = Stopwatch()..start();

    var cancelled = false;
    var autoFallbackRequested = request.forceFallback;
    var fallbackScheduled = request.forceFallback;
    var finalized = false;
    Timer? timeoutTimer;
    Timer? stallTimer;
    Map<String, dynamic>? lastTimelinePayload;
    var variableFrameRateDetected = false;
    var hardwareDecodeUnsupported = false;
    ProxySessionQualityTier? finalActiveTier;
    Set<ProxySessionQualityTier> finalAvailableTiers =
        const <ProxySessionQualityTier>{};

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
        .listen((event) {
      if (enableLogging) {
        debugPrint(
            '[VideoProxyService] native event for job $jobId: type=${event.type} progress=${event.progress}');
      }
      if (cancelled) {
        return;
      }
      resetStallTimer();
      scheduleTimeouts();

      final shouldNotifyFallback =
          event.fallbackTriggered && !autoFallbackRequested;
      if (shouldNotifyFallback) {
        autoFallbackRequested = true;
        progressController
            .add(const VideoProxyProgress(null, fallbackTriggered: true));
      }

      if (event.type == 'progress') {
        progressController.add(
          VideoProxyProgress(
            event.progress,
            fallbackTriggered: shouldNotifyFallback,
          ),
        );
        return;
      }

      if (event.timelinePayload != null) {
        lastTimelinePayload = event.timelinePayload;
      }

      var metadataUpdated = false;

      final metadataPayload = event.metadataPayload;
      if (metadataPayload != null) {
        final metaDuration = (metadataPayload['durationMs'] as num?)?.toInt();
        final metaFps =
            (metadataPayload['frameRate'] as num?)?.toDouble() ??
                (metadataPayload['fps'] as num?)?.toDouble();
        final metaWidth = (metadataPayload['displayWidth'] as num?)?.toInt() ??
            (metadataPayload['width'] as num?)?.toInt() ??
            event.displayWidth ??
            event.width;
        final metaHeight = (metadataPayload['displayHeight'] as num?)?.toInt() ??
            (metadataPayload['height'] as num?)?.toInt() ??
            event.displayHeight ??
            event.height;
        final metaHasAudio = metadataPayload['hasAudio'] as bool?;
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

        metadataState.mergeMetadata(
          width: metaWidth,
          height: metaHeight,
          fps: metaFps,
          hasAudio: metaHasAudio,
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
          metadataState.addKeyframes(frames);
        }
        metadataUpdated = true;
      }

      final keyframePayload = event.keyframePayload;
      if (keyframePayload != null && keyframePayload.isNotEmpty) {
        metadataState
            .addKeyframes(keyframePayload.map(ProxyKeyframe.fromJson));
        metadataUpdated = true;
      }

      if (event.type == 'preview_ready' || event.type == 'poster_ready') {
        final previewPath = event.previewPath ?? event.path;
        if (previewPath != null && previewPath.isNotEmpty) {
          final previewWidth = event.displayWidth ??
              event.width ??
              metadataState.width ??
              request.targetWidth;
          final previewHeight = event.displayHeight ??
              event.height ??
              metadataState.height ??
              request.targetHeight;
          final previewDuration = event.durationMs ??
              metadataState.durationMs ??
              request.estimatedDurationMs ??
              0;
          final previewFrameRate =
              metadataState.fps ?? request.frameRateHint?.toDouble();

          metadataState.mergeMetadata(
            width: previewWidth,
            height: previewHeight,
            durationMs: previewDuration,
            fps: previewFrameRate,
            hasAudio: event.hasAudio,
          );
          metadataUpdated = true;

          VideoProxyResolution inferResolution(int width, int height) {
            final maxEdge = width >= height ? width : height;
            if (maxEdge <= 640) return VideoProxyResolution.p360;
            if (maxEdge <= 960) return VideoProxyResolution.p540;
            if (maxEdge <= 1280) return VideoProxyResolution.hd720;
            return VideoProxyResolution.hd1080;
          }

          final previewMetadata = VideoProxyMetadata(
            width: previewWidth,
            height: previewHeight,
            durationMs: previewDuration,
            frameRate: previewFrameRate,
            resolution: inferResolution(previewWidth, previewHeight),
            rotationBaked: true,
          );

          if (!previewCompleter.isCompleted) {
            previewCompleter.complete(
              ProxyPreview(
                quality: proxyQualityFromLabel(event.previewQualityLabel),
                filePath: previewPath,
                metadata: previewMetadata,
              ),
            );
          }
        }
      }

      if (metadataUpdated) {
        metadataController.add(
          metadataState.buildEvent(
            variableFrameRate: variableFrameRateDetected,
            hardwareDecodeUnsupported: hardwareDecodeUnsupported,
          ),
        );
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
          {'sourcePath': request.sourcePath},
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

      if (enableLogging) {
        debugPrint(
          '[VideoProxyService] Invoking native proxy for job $jobId '
          'args=${args.keys.toList()}',
        );
      }

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

        while (true) {
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

          fallbackScheduled = currentRequest.forceFallback;
          final responseFuture = _invokeProxy(currentRequest);
          if (!currentRequest.forceFallback) {
            scheduleTimeouts();
          }
          response = await responseFuture;
          cancelTimers();

          if (response != null && response['ok'] == true) {
            break;
          }

          final failure = response ?? const <String, dynamic>{};
          final code = failure['code']?.toString();

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

          final message = failure['message']?.toString() ??
              failure['error']?.toString() ??
              'Proxy generation failed';
          throw VideoProxyException(message, code: code);
        }

        final responseMap = Map<String, dynamic>.from(response!);
        final usedFallbackFlag = responseMap['usedFallback720p'] == true;

        VideoProxyResolution inferResolution(int width, int height) {
          final maxEdge = width >= height ? width : height;
          if (maxEdge <= 640) return VideoProxyResolution.p360;
          if (maxEdge <= 960) return VideoProxyResolution.p540;
          if (maxEdge <= 1280) return VideoProxyResolution.hd720;
          return VideoProxyResolution.hd1080;
        }

        VideoProxyMetadata buildMetadata({
          required int width,
          required int height,
          required int durationMs,
          double? frameRate,
          bool rotationBaked = true,
        }) {
          return VideoProxyMetadata(
            width: width,
            height: height,
            durationMs: durationMs,
            frameRate: frameRate,
            resolution: inferResolution(width, height),
            rotationBaked: rotationBaked,
          );
        }

        List<Map<String, dynamic>> tierResponses =
            (responseMap['tiers'] as List?)
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
                (tier['displayWidth'] as num?)?.toInt() ??
                    (tier['width'] as num?)?.toInt() ??
                    fallbackMetadata.width;
            final tierHeight =
                (tier['displayHeight'] as num?)?.toInt() ??
                    (tier['height'] as num?)?.toInt() ??
                    fallbackMetadata.height;
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
            results.add(
              ProxyTierResult(
                quality: proxyQualityFromLabel(tier['quality']?.toString()),
                filePath: tierPath,
                metadata: tierMetadata,
              ),
            );
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
          final tierResults = parseTierResults(
            tierResponses,
            metadata,
            filePath,
          );

          final timelineMappings = <VideoProxyTimelineMapping>[];
          int? sourceStartMs = request.sourceStartMs;
          int? sourceDurationMs =
              request.sourceDurationMs ?? metadata.durationMs;
          int? sourceRotationDegrees = request.sourceRotationDegrees;
          String? sourceVideoCodec = request.sourceVideoCodec;
          String? sourceOrientation = request.sourceOrientation;
          bool? sourceMirrored = request.sourceMirrored;
          bool? matchesSourceVideoCodec = metadataState.matchesSourceVideoCodec;
          bool? matchesSourceAudioCodec = metadataState.matchesSourceAudioCodec;
          final responseVideoCodec = responseMap['videoCodec']?.toString();
          final responseAudioCodec = responseMap['audioCodec']?.toString();

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

          mergeTimelineValue(responseMap['timeline']);
          mergeTimelineValue(lastTimelinePayload);
          final responseMappings = responseMap['timelineMappings'];
          if (responseMappings is List) {
            for (final mapping in responseMappings.whereType<Map>()) {
              final casted = mapping.map((key, dynamic value) {
                return MapEntry(key.toString(), value);
              });
              timelineMappings
                  .add(VideoProxyTimelineMapping.fromJson(casted));
            }
          }

          if (responseMap['sourceStartMs'] != null) {
            sourceStartMs =
                (responseMap['sourceStartMs'] as num?)?.toInt();
          }
          if (responseMap['sourceDurationMs'] != null) {
            sourceDurationMs =
                (responseMap['sourceDurationMs'] as num?)?.toInt();
          }
          if (responseMap['sourceRotationDegrees'] != null) {
            sourceRotationDegrees =
                (responseMap['sourceRotationDegrees'] as num?)?.toInt();
          }
          if (responseMap['sourceVideoCodec'] != null) {
            sourceVideoCodec = responseMap['sourceVideoCodec']?.toString();
          }
          if (responseMap['sourceOrientation'] != null) {
            sourceOrientation = responseMap['sourceOrientation']?.toString();
          }
          if (responseMap['sourceMirrored'] != null) {
            sourceMirrored = responseMap['sourceMirrored'] as bool?;
          }
          if (responseMap['matchesSourceVideoCodec'] != null) {
            matchesSourceVideoCodec =
                responseMap['matchesSourceVideoCodec'] == true;
          }
          if (responseMap['matchesSourceAudioCodec'] != null) {
            matchesSourceAudioCodec =
                responseMap['matchesSourceAudioCodec'] == true;
          }


          if (timelineMappings.isEmpty) {
            final defaultQuality = tierResults.isNotEmpty
                ? tierResults.first.quality
                : ProxyQuality.proxy;
            final fallbackSourceStart =
                sourceStartMs ?? request.sourceStartMs;
            final fallbackSourceDuration =
                sourceDurationMs ?? metadata.durationMs;
            sourceStartMs ??= fallbackSourceStart;
            sourceDurationMs ??= fallbackSourceDuration;
            timelineMappings.add(
              VideoProxyTimelineMapping(
                quality: defaultQuality,
                sourceStartMs: fallbackSourceStart,
                sourceDurationMs: fallbackSourceDuration,
                proxyStartMs: 0,
                proxyDurationMs: metadata.durationMs,
              ),
            );
          }

          final computedSourceEnd =
              (sourceStartMs != null && sourceDurationMs != null)
                  ? sourceStartMs! + sourceDurationMs!
                  : metadataState.sourceEndMs;

          metadataState.mergeMetadata(
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

          finalAvailableTiers = tierResults
              .map((tier) => proxySessionTierForQuality(tier.quality))
              .toSet();

          final bestQuality = tierResults.isEmpty
              ? null
              : tierResults
                  .map((tier) => tier.quality)
                  .reduce((a, b) => a.index >= b.index ? a : b);
          finalActiveTier = bestQuality != null
              ? proxySessionTierForQuality(bestQuality)
              : null;

          return VideoProxyResult(
            filePath: filePath,
            metadata: metadata,
            request: request,
            transcodeDurationMs:
                (responseMap['transcodeDurationMs'] as num?)?.toInt() ??
                    stopwatch.elapsedMilliseconds,
            usedFallback720p: usedFallbackFlag || autoFallbackRequested,
            sourceStartMs: sourceStartMs,
            sourceDurationMs: sourceDurationMs,
            sourceRotationDegrees: sourceRotationDegrees,
            sourceVideoCodec: sourceVideoCodec ?? responseVideoCodec,
            sourceOrientation: sourceOrientation,
            sourceMirrored: sourceMirrored,
            tiers: tierResults,
            timelineMappings: timelineMappings,
          );
        }

        Future<VideoProxyResult> buildSingleResult() async {
          final path = responseMap['proxyPath']?.toString();
          if (path == null || path.isEmpty) {
            throw const VideoProxyException('Proxy path missing from response');
          }
          final width = (responseMap['displayWidth'] as num?)?.toInt() ??
              (responseMap['width'] as num?)?.toInt() ??
              request.targetWidth;
          final height = (responseMap['displayHeight'] as num?)?.toInt() ??
              (responseMap['height'] as num?)?.toInt() ??
              request.targetHeight;
          final durationMs =
              (responseMap['durationMs'] as num?)?.toInt() ??
                  request.estimatedDurationMs ??
                  0;
          final frameRate = (responseMap['frameRate'] as num?)?.toDouble();
          final rotation =
              (responseMap['rotation'] as num?)?.toInt() ?? 0;
          if (rotation != 0) {
            debugPrint(
              '[VideoProxyService] Warning: proxy rotation=$rotation (expected 0)',
            );
          }
          final rotationBaked = true;
          final metadata = buildMetadata(
            width: width,
            height: height,
            durationMs: durationMs,
            frameRate: frameRate,
            rotationBaked: rotationBaked,
          );
          return buildResult(filePath: path, metadata: metadata);
        }

        final result = await buildSingleResult();

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
          previewCompleter.complete(
            ProxyPreview(
              quality: primaryTier?.quality ?? ProxyQuality.proxy,
              filePath: result.filePath,
              metadata: primaryTier?.metadata ?? result.metadata,
            ),
          );
        }

        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(result);
        }

        metadataController.add(
          metadataState.buildEvent(
            variableFrameRate: variableFrameRateDetected,
            hardwareDecodeUnsupported: hardwareDecodeUnsupported,
            activeQuality: finalActiveTier,
            availableQualities: finalAvailableTiers,
          ),
        );
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
