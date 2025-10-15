import 'dart:async';
import 'dart:convert';
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
    this.hasAudio,
    this.totalSegments,
    this.totalDurationMs,
    this.portraitPreferred,
    this.proxyBounding,
  });

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

  factory _NativeProxyEvent.fromDynamic(Object? value) {
    if (value is! Map) {
      throw ArgumentError('Invalid proxy event payload: $value');
    }
    final jobId = value['jobId']?.toString();
    final type = value['type']?.toString();
    final progress = value['progress'];
    final fallbackTriggered = value['fallbackTriggered'] == true;
    final segmentIndex = (value['segmentIndex'] as num?)?.toInt();
    final path = value['path']?.toString();
    final durationMs = (value['durationMs'] as num?)?.toInt();
    final width = (value['width'] as num?)?.toInt();
    final height = (value['height'] as num?)?.toInt();
    final hasAudio = value['hasAudio'] == true;
    final totalSegments = (value['totalSegments'] as num?)?.toInt();
    final totalDurationMs = (value['totalDurationMs'] as num?)?.toInt();
    final portraitPreferred = value['portraitPreferred'] == true;
    final proxyBounding = value['proxyBounding']?.toString();
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
    );
  }

  bool get isProgress => type == 'progress';
}

class VideoProxyProgress {
  const VideoProxyProgress(this.fraction, {this.fallbackTriggered = false});

  final double? fraction;
  final bool fallbackTriggered;
}

class ProxyManifestData {
  ProxyManifestData({
    required this.segmentDurationMs,
    required this.width,
    required this.height,
    required this.fps,
    required this.hasAudio,
  });

  final int segmentDurationMs;
  final int width;
  final int height;
  final double fps;
  final bool hasAudio;
  final List<ProxySegment> segments = [];
}

class VideoProxyJob {
  VideoProxyJob({
    required this.future,
    required this.progress,
    required Future<void> Function() cancel,
  }) : _cancel = cancel;

  final Future<VideoProxyResult> future;
  final Stream<VideoProxyProgress> progress;
  final Future<void> Function() _cancel;

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
          .map((s) => {
                'index': s.index,
                'path': p.basename(s.path),
                'durationMs': s.durationMs,
              })
          .toList(),
      'width': manifestData.width,
      'height': manifestData.height,
      'fps': manifestData.fps,
      'hasAudio': manifestData.hasAudio,
    };
    await manifestFile
        .writeAsString(JsonEncoder.withIndent('  ').convert(json));
  }

  Future<void> deleteProxy(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (error) {
      debugPrint('[VideoProxyService] Failed to delete proxy at $path: $error');
    }
  }

  VideoProxyJob createJob({
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
    final progressController = StreamController<VideoProxyProgress>.broadcast();
    final completer = Completer<VideoProxyResult>();
    final stopwatch = Stopwatch()..start();
    var cancelled = false;
    var autoFallbackRequested = request.forceFallback;
    Timer? timeoutTimer;
    Timer? stallTimer;
    var fallbackScheduled = request.forceFallback;

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
      debugPrint(
          '[VideoProxyService] native event for job $jobId: type=${event.type} segmentIndex=${event.segmentIndex} path=${event.path} progress=${event.progress}');
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

      if (event.type == 'segment_ready' &&
          event.segmentIndex != null &&
          event.path != null) {
        try {
          // Ensure job manifest exists
          final width = event.width ?? request.targetWidth;
          final height = event.height ?? request.targetHeight;
          final fps = (event.totalDurationMs != null &&
                  event.totalSegments != null &&
                  event.totalSegments! > 0)
              ? ((event.totalDurationMs! / 1000.0) / event.totalSegments!)
              : (request.frameRateHint?.toDouble() ?? 24.0);
          final manifest = _manifests.putIfAbsent(
              jobId,
              () => ProxyManifestData(
                    segmentDurationMs: 10000,
                    width: width,
                    height: height,
                    fps: fps,
                    hasAudio: event.hasAudio ?? true,
                  ));

          final segment = ProxySegment(
            index: event.segmentIndex!,
            path: event.path!,
            durationMs: event.durationMs ?? manifest.segmentDurationMs,
            width: width,
            height: height,
            hasAudio: event.hasAudio ?? true,
          );
          manifest.segments.add(segment);
          await _updateManifest(jobId, manifest);

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
        return;
      }

      if (event.type == 'completed') {
        try {
          // finalize manifest if present
          final manifest = _manifests[jobId];
          if (manifest != null) {
            await _updateManifest(jobId, manifest);
          }
        } catch (e, st) {
          debugPrint('[VideoProxyService] Failed finalizing manifest: $e\n$st');
        }
        return;
      }
    });

    Future<void> finalize() async {
      await subscription?.cancel();
      await progressController.close();
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
          if (!completer.isCompleted) {
            completer.completeError(const VideoProxyCancelException());
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

          if (cancelled) {
            if (!completer.isCompleted) {
              completer.completeError(const VideoProxyCancelException());
            }
            return;
          }

          if (fallbackScheduled && code == 'cancelled') {
            currentRequest = currentRequest.fallbackPreview();
            continue;
          }

          if (code == 'cancelled') {
            if (!completer.isCompleted) {
              completer.completeError(const VideoProxyCancelException());
            }
            return;
          }

          final message = response?['message']?.toString() ?? 'Unknown error';
          if (!completer.isCompleted) {
            completer.completeError(VideoProxyException(message, code: code));
          }
          return;
        }

        final proxyPath = response['proxyPath']?.toString();
        if ((proxyPath == null || proxyPath.isEmpty) &&
            currentRequest.segmentedPreview) {
          // Segmented preview flow: native may not return a single proxyPath.
          // Instead, it emits segment_ready/completed events and writes a
          // per-job manifest to the cache directory. Wait for that manifest to
          // appear and use it as the proxy result.
          try {
            final cacheDir = await _ensureCacheDirectory();
            final jobDir = Directory(p.join(cacheDir.path, jobId));
            final manifestFile = File(p.join(jobDir.path, 'manifest.json'));

            // Wait for manifest to be written by the event handler. Give a
            // generous timeout for segmented jobs.
            var waited = 0;
            const pollMs = 500;
            const maxWaitMs = 180000; // 3 minutes
            while (!await manifestFile.exists()) {
              if (cancelled) {
                if (!completer.isCompleted) {
                  completer.completeError(const VideoProxyCancelException());
                }
                return;
              }
              if (waited >= maxWaitMs) {
                if (!completer.isCompleted) {
                  completer.completeError(const VideoProxyException(
                      'Timed out waiting for segmented preview manifest'));
                }
                return;
              }
              await Future.delayed(const Duration(milliseconds: pollMs));
              waited += pollMs;
            }

            // Manifest should be available in our in-memory manifests map from
            // the event handler; if not, parse the file as a fallback.
            final manifestData = _manifests[jobId];
            int width, height, durationMs;
            double fps;
            if (manifestData != null) {
              width = manifestData.width;
              height = manifestData.height;
              fps = manifestData.fps;
              durationMs = manifestData.segments
                  .fold<int>(0, (a, s) => a + s.durationMs);
            } else {
              // Parse manifest.json as a fallback
              try {
                final content = await manifestFile.readAsString();
                final json = jsonDecode(content) as Map<String, dynamic>;
                width = (json['width'] as num?)?.toInt() ?? request.targetWidth;
                height =
                    (json['height'] as num?)?.toInt() ?? request.targetHeight;
                fps = (json['fps'] as num?)?.toDouble() ??
                    (request.frameRateHint?.toDouble() ?? 24.0);
                final segs = (json['segments'] as List<dynamic>?) ?? [];
                durationMs = segs.fold<int>(
                    0,
                    (a, s) =>
                        a + ((s as Map)['durationMs'] as num? ?? 0).toInt());
              } catch (e) {
                if (!completer.isCompleted) {
                  completer.completeError(VideoProxyException(
                      'Failed to read segmented manifest: $e'));
                }
                return;
              }
            }

            final frameRate = fps;
            final rotationBaked = true;
            final usedFallbackFlag = response['usedFallback720p'] == true;
            final transcodeDurationMs =
                (response['transcodeDurationMs'] as num?)?.toInt() ??
                    stopwatch.elapsedMilliseconds;

            final metadata = VideoProxyMetadata(
              width: width,
              height: height,
              durationMs: durationMs,
              frameRate: frameRate,
              resolution: request.resolution,
              rotationBaked: rotationBaked,
            );

            final result = VideoProxyResult(
              filePath: manifestFile.path,
              metadata: metadata,
              request: request,
              transcodeDurationMs: transcodeDurationMs,
              usedFallback720p: usedFallbackFlag || autoFallbackRequested,
            );

            if (!completer.isCompleted) {
              completer.complete(result);
            }
            return;
          } catch (e, st) {
            debugPrint(
                '[VideoProxyService] Error handling segmented response: $e\n$st');
            if (!completer.isCompleted) {
              completer.completeError(VideoProxyException(
                  'Failed to handle segmented proxy response: $e'));
            }
            return;
          }
        }

        // Non-segmented single-file proxy path handling
        if (proxyPath == null || proxyPath.isEmpty) {
          if (!completer.isCompleted) {
            completer.completeError(
              const VideoProxyException('Proxy path missing from response'),
            );
          }
          return;
        }

        final width =
            (response['width'] as num?)?.toInt() ?? request.targetWidth;
        final height =
            (response['height'] as num?)?.toInt() ?? request.targetHeight;
        final durationMs = (response['durationMs'] as num?)?.toInt() ??
            request.estimatedDurationMs ??
            0;
        final frameRate = (response['frameRate'] as num?)?.toDouble();
        final rotationBaked = response['rotationBaked'] != false;
        final usedFallbackFlag = response['usedFallback720p'] == true;
        final transcodeDurationMs =
            (response['transcodeDurationMs'] as num?)?.toInt() ??
                stopwatch.elapsedMilliseconds;

        final maxEdge = width >= height ? width : height;
        final resolution = () {
          if (maxEdge <= 640) return VideoProxyResolution.p360;
          if (maxEdge <= 960) return VideoProxyResolution.p540;
          if (maxEdge <= 1280) return VideoProxyResolution.hd720;
          return VideoProxyResolution.hd1080;
        }();

        final metadata = VideoProxyMetadata(
          width: width,
          height: height,
          durationMs: durationMs,
          frameRate: frameRate,
          resolution: resolution,
          rotationBaked: rotationBaked,
        );

        final result = VideoProxyResult(
          filePath: proxyPath,
          metadata: metadata,
          request: request,
          transcodeDurationMs: transcodeDurationMs,
          usedFallback720p: usedFallbackFlag || autoFallbackRequested,
        );

        if (enableLogging) {
          debugPrint(
            '[VideoProxyService] Proxy ready ${metadata.width}x${metadata.height} '
            '(${metadata.resolution}) in ${result.transcodeDurationMs} ms '
            '(fallback=$usedFallbackFlag)',
          );
        }

        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } on PlatformException catch (error) {
        if (cancelled) {
          if (!completer.isCompleted) {
            completer.completeError(const VideoProxyCancelException());
          }
          return;
        }
        final code = error.code;
        final message = error.message ?? 'Proxy generation failed';
        if (!completer.isCompleted) {
          completer.completeError(VideoProxyException(message, code: code));
        }
      } catch (error, stackTrace) {
        if (cancelled) {
          if (!completer.isCompleted) {
            completer.completeError(const VideoProxyCancelException());
          }
          return;
        }
        debugPrint(
            '[VideoProxyService] Proxy generation error: $error\n$stackTrace');
        if (!completer.isCompleted) {
          completer.completeError(
              VideoProxyException('Failed to prepare proxy: $error'));
        }
      } finally {
        cancelTimers();
        stopwatch.stop();
        await finalize();
      }
    }

    unawaited(startJob());

    return VideoProxyJob(
      future: completer.future,
      progress: progressController.stream,
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
      },
    );
  }
}
