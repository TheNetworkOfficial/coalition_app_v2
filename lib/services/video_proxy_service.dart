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
  });

  final String jobId;
  final String type;
  final double? progress;

  factory _NativeProxyEvent.fromDynamic(Object? value) {
    if (value is! Map) {
      throw ArgumentError('Invalid proxy event payload: $value');
    }
    final jobId = value['jobId']?.toString();
    final type = value['type']?.toString();
    final progress = value['progress'];
    return _NativeProxyEvent(
      jobId: jobId ?? '',
      type: type ?? 'unknown',
      progress: progress is num ? progress.toDouble() : null,
    );
  }

  bool get isProgress => type == 'progress';
}

class VideoProxyProgress {
  const VideoProxyProgress(this.fraction);

  final double? fraction;
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

  VideoProxyJob createJob({
    required VideoProxyRequest request,
    bool enableLogging = true,
  }) {
    final jobId = _uuid.v4();
    final progressController = StreamController<VideoProxyProgress>.broadcast();
    final completer = Completer<VideoProxyResult>();
    final stopwatch = Stopwatch()..start();
    final useFallback = request.resolution == VideoProxyResolution.hd720;
    var cancelled = false;

    StreamSubscription<_NativeProxyEvent>? subscription;
    subscription = _progressEvents
        .where((event) => event.jobId == jobId && event.isProgress)
        .listen((event) {
      if (cancelled) return;
      progressController.add(VideoProxyProgress(event.progress));
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

    Future<void> startJob() async {
      try {
        final cacheDir = await _ensureCacheDirectory();
        final args = request.toPlatformRequest(jobId: jobId)
          ..addAll({
            'outputDirectory': cacheDir.path,
            'enableLogging': enableLogging,
          });

        await emitSourceSummary();

        final methodName = useFallback ? 'createProxyFallback720p' : 'createProxy';
        final response =
            await _methodChannel.invokeMapMethod<String, dynamic>(methodName, args);

        if (cancelled) {
          if (!completer.isCompleted) {
            completer.completeError(const VideoProxyCancelException());
          }
          return;
        }

        if (response == null || response['ok'] != true) {
          final code = response?['code']?.toString();
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
        if (proxyPath == null || proxyPath.isEmpty) {
          if (!completer.isCompleted) {
            completer.completeError(
              const VideoProxyException('Proxy path missing from response'),
            );
          }
          return;
        }

        final width = (response['width'] as num?)?.toInt() ?? request.targetWidth;
        final height = (response['height'] as num?)?.toInt() ?? request.targetHeight;
        final durationMs =
            (response['durationMs'] as num?)?.toInt() ?? request.estimatedDurationMs ?? 0;
        final frameRate = (response['frameRate'] as num?)?.toDouble();
        final rotationBaked = response['rotationBaked'] != false;
        final usedFallbackFlag = response['usedFallback720p'] == true;
        final transcodeDurationMs =
            (response['transcodeDurationMs'] as num?)?.toInt() ?? stopwatch.elapsedMilliseconds;

        final maxEdge = width >= height ? width : height;
        final resolution = maxEdge <= 1280
            ? VideoProxyResolution.hd720
            : VideoProxyResolution.hd1080;

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
          usedFallback720p: usedFallbackFlag,
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
        debugPrint('[VideoProxyService] Proxy generation error: $error\n$stackTrace');
        if (!completer.isCompleted) {
          completer.completeError(VideoProxyException('Failed to prepare proxy: $error'));
        }
      } finally {
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
          debugPrint('[VideoProxyService] Failed to cancel proxy job $jobId: $error');
        }
      },
    );
  }
}
