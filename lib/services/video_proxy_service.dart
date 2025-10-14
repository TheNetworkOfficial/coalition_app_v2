import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/return_code.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/statistics.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/video_proxy.dart';

const _uuid = Uuid();

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

  VideoProxyService._();

  static final VideoProxyService _instance = VideoProxyService._();

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
    final progressController = StreamController<VideoProxyProgress>.broadcast();
    final completer = Completer<VideoProxyResult>();
    var cancelled = false;
    final stopwatch = Stopwatch()..start();

    Future<void> emitProgress(Statistics statistics) async {
      if (cancelled) return;
      final durationMs = request.estimatedDurationMs;
      double? fraction;
      if (durationMs != null && durationMs > 0) {
        final time = statistics.getTime();
        final ratio = time / durationMs;
        fraction = ratio.clamp(0, 1.0);
      }
      if (!progressController.isClosed)
        progressController.add(VideoProxyProgress(fraction));
    }

    Future<VideoProxyResult> onSuccess(String outputPath) async {
      final infoSession = await FFprobeKit.getMediaInformation(outputPath);
      final info = await infoSession.getMediaInformation();
      int width = request.targetWidth;
      int height = request.targetHeight;
      int durationMs = request.estimatedDurationMs ?? 0;
      double? frameRate;

      if (info != null) {
        final duration = info.getDuration();
        if (duration != null) {
          final parsed = double.tryParse(duration);
          if (parsed != null) durationMs = (parsed * 1000).round();
        }

        final streams = info.getStreams();
        for (final stream in streams) {
          if (stream.getType() == 'video') {
            // getters can return non-String objects depending on ffprobe bindings; normalize to String
            final widthString = stream.getWidth()?.toString();
            final heightString = stream.getHeight()?.toString();
            final props = stream.getAllProperties();
            final frameRateString =
                (stream.getAverageFrameRate()?.toString()) ??
                    props?['r_frame_rate']?.toString() ??
                    props?['avg_frame_rate']?.toString();

            final parsedWidth = int.tryParse(widthString ?? '');
            final parsedHeight = int.tryParse(heightString ?? '');
            if (parsedWidth != null && parsedWidth > 0) width = parsedWidth;
            if (parsedHeight != null && parsedHeight > 0) height = parsedHeight;

            if (frameRateString != null && frameRateString.contains('/')) {
              final parts = frameRateString.split('/');
              final numerator = double.tryParse(parts[0]);
              final denominator =
                  double.tryParse(parts.length > 1 ? parts[1] : '1');
              if (numerator != null &&
                  denominator != null &&
                  denominator != 0) {
                frameRate = numerator / denominator;
              }
            } else if (frameRateString != null) {
              final parsed = double.tryParse(frameRateString);
              if (parsed != null) frameRate = parsed;
            }

            break;
          }
        }
      }

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
      );

      return VideoProxyResult(
        filePath: outputPath,
        metadata: metadata,
        request: request,
        transcodeDurationMs: stopwatch.elapsedMilliseconds,
      );
    }

    Future<void> finalizeFailure(String message, {String? code}) async {
      if (cancelled) {
        if (!completer.isCompleted)
          completer.completeError(const VideoProxyCancelException());
        return;
      }
      if (!completer.isCompleted)
        completer.completeError(VideoProxyException(message, code: code));
    }

    final startReady = Completer<void>();
    Future<void> Function()? _activeCancellation;

    Future<void> logSourceSummary() async {
      if (!enableLogging) return;
      try {
        final infoSession =
            await FFprobeKit.getMediaInformation(request.sourcePath);
        final info = await infoSession.getMediaInformation();
        if (info == null) return;

        String? codec;
        String? rotation;
        int? width;
        int? height;
        double? durationSeconds;

        final duration = info.getDuration();
        if (duration != null) durationSeconds = double.tryParse(duration);

        final streams = info.getStreams();
        for (final stream in streams) {
          if (stream.getType() == 'video') {
            codec = stream.getCodec();
            width = int.tryParse(stream.getWidth()?.toString() ?? '');
            height = int.tryParse(stream.getHeight()?.toString() ?? '');
            try {
              final properties = stream.getAllProperties();
              final rawRotation = properties?['rotation'];
              rotation = rawRotation?.toString();
            } catch (_) {}
            break;
          }
        }

        debugPrint(
          '[VideoProxyService] Source summary: codec=$codec ${width ?? '?'}x${height ?? '?'} rotation=$rotation duration=${durationSeconds != null ? (durationSeconds * 1000).round() : '?'}ms',
        );
      } catch (error) {
        debugPrint('[VideoProxyService] Failed to probe source: $error');
      }
    }

    Future<void> start() async {
      try {
        final cacheDir = await _ensureCacheDirectory();
        final outputPath = p.join(
          cacheDir.path,
          'proxy_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4()}.mp4',
        );

        await logSourceSummary();

        final filter = [
          "scale='min(${request.targetWidth},iw)':'min(${request.targetHeight},ih)':force_original_aspect_ratio=decrease",
          'format=yuv420p',
          'setsar=1',
          'pad=${request.targetWidth}:${request.targetHeight}:(ow-iw)/2:(oh-ih)/2:color=black',
        ].join(',');

        final command = <String>[
          '-hide_banner',
          '-y',
          '-i',
          request.sourcePath,
          '-vf',
          filter,
          '-c:v',
          'libx264',
          '-preset',
          'veryfast',
          '-profile:v',
          'high',
          '-level:v',
          '4.1',
          '-pix_fmt',
          'yuv420p',
          '-x264-params',
          'keyint=60:min-keyint=60:scenecut=0',
          '-movflags',
          '+faststart',
          '-c:a',
          'aac',
          '-b:a',
          '128k',
          '-ac',
          '2',
          '-ar',
          '48000',
          '-map_metadata',
          '-1',
          '-metadata:s:v:0',
          'rotate=0',
          outputPath,
        ];

        // Use executeAsync with a single command string. Joining args is fine here because
        // we control quoting for complex args like the filter above.
        final sessionFuture = FFmpegKit.executeAsync(
          command.join(' '),
          (session) async {
            final returnCode = await session.getReturnCode();
            final sessionState = await session.getState();
            stopwatch.stop();
            if (ReturnCode.isSuccess(returnCode)) {
              if (!completer.isCompleted) {
                try {
                  final result = await onSuccess(outputPath);
                  if (enableLogging) {
                    debugPrint(
                      '[VideoProxyService] Proxy created (${result.metadata.width}x${result.metadata.height}) in ${result.transcodeDurationMs} ms',
                    );
                  }
                  completer.complete(result);
                } catch (error) {
                  await deleteProxy(outputPath);
                  await finalizeFailure('Failed to inspect proxy: $error',
                      code: 'probe_failed');
                }
              }
            } else if (ReturnCode.isCancel(returnCode)) {
              await deleteProxy(outputPath);
              cancelled = true;
              await finalizeFailure('Proxy generation canceled',
                  code: 'cancelled');
            } else {
              final failStack = await session.getFailStackTrace();
              await deleteProxy(outputPath);
              await finalizeFailure(
                'Proxy generation failed (state=$sessionState, code=$returnCode, stack=$failStack)',
                code: returnCode?.getValue().toString(),
              );
            }
          },
          enableLogging
              ? (log) {
                  debugPrint('[VideoProxyService] ${log.getMessage()}');
                }
              : null,
          (statistics) async {
            await emitProgress(statistics);
          },
        );

        Future<void> cancelJob() async {
          if (cancelled) return;
          cancelled = true;
          try {
            await FFmpegKit.cancel();
          } catch (error) {
            debugPrint(
                '[VideoProxyService] Failed to cancel FFmpeg session: $error');
          }
          try {
            final session = await sessionFuture;
            final output = await session.getOutput();
            if (enableLogging)
              debugPrint(
                  '[VideoProxyService] Cancelled session output: $output');
          } catch (_) {}
        }

        completer.future.whenComplete(() async {
          await progressController.close();
        });

        _activeCancellation = cancelJob;
        if (!startReady.isCompleted) startReady.complete();
      } catch (error) {
        await finalizeFailure('Failed to prepare proxy: $error',
            code: 'start_failed');
        if (!progressController.isClosed) await progressController.close();
        if (!startReady.isCompleted) startReady.complete();
      }
    }

    unawaited(start());

    return VideoProxyJob(
      future: completer.future,
      progress: progressController.stream,
      cancel: () async {
        if (!startReady.isCompleted) await startReady.future;
        final canceller = _activeCancellation;
        if (canceller != null) await canceller();
      },
    );
  }
}
