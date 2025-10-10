import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:get_thumbnail_video/src/image_format.dart';
import 'package:get_thumbnail_video/src/video_thumbnail_platform.dart';
import 'package:web/web.dart' as web;

// An error code value to error name Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorName = <int, String>{
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// An error code value to description Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorDescription = <int, String>{
  1: 'The user canceled the fetching of the video.',
  2: 'A network error occurred while fetching the video, despite having previously been available.',
  3: 'An error occurred while trying to decode the video, despite having previously been determined to be usable.',
  4: 'The video has been found to be unsuitable (missing or in a format not supported by your browser).',
};

// The default error message, when the error is an empty string
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/message
const String _kDefaultErrorMessage =
    'No further diagnostic information can be determined or provided.';

/// A web implementation of the VideoThumbnailPlatform of the VideoThumbnail plugin.
class VideoThumbnailWeb extends VideoThumbnailPlatform {
  /// Constructs a VideoThumbnailWeb
  VideoThumbnailWeb();

  static void registerWith(Registrar registrar) {
    VideoThumbnailPlatform.instance = VideoThumbnailWeb();
  }

  @override
  Future<XFile> thumbnailFile({
    required String video,
    required Map<String, String>? headers,
    required String? thumbnailPath,
    required ImageFormat imageFormat,
    required int maxHeight,
    required int maxWidth,
    required int timeMs,
    required int quality,
  }) async {
    final blob = await _createThumbnail(
      videoSrc: video,
      headers: headers,
      imageFormat: imageFormat,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      timeMs: timeMs,
      quality: quality,
    );

    return XFile(web.URL.createObjectURL(blob), mimeType: blob.type);
  }

  @override
  Future<Uint8List> thumbnailData({
    required String video,
    required Map<String, String>? headers,
    required ImageFormat imageFormat,
    required int maxHeight,
    required int maxWidth,
    required int timeMs,
    required int quality,
  }) async {
    final blob = await _createThumbnail(
      videoSrc: video,
      headers: headers,
      imageFormat: imageFormat,
      maxHeight: maxHeight,
      maxWidth: maxWidth,
      timeMs: timeMs,
      quality: quality,
    );
    final path = web.URL.createObjectURL(blob);
    final file = XFile(path, mimeType: blob.type);
    final bytes = await file.readAsBytes();
    web.URL.revokeObjectURL(path);

    return bytes;
  }

  Future<web.Blob> _createThumbnail({
    required String videoSrc,
    required Map<String, String>? headers,
    required ImageFormat imageFormat,
    required int maxHeight,
    required int maxWidth,
    required int timeMs,
    required int quality,
  }) async {
    final completer = Completer<web.Blob>();

    final video = web.HTMLVideoElement();
    final timeSec = math.max(timeMs / 1000, 0);
    final fetchVideo = headers != null && headers.isNotEmpty;

    web.EventStreamProviders.loadedMetadataEvent
        .forTarget(video)
        .listen((event) {
      video.currentTime = timeSec;

      if (fetchVideo) {
        final src = video.src;
        if (src.isNotEmpty) {
          web.URL.revokeObjectURL(src);
        }
      }
    });

    web.EventStreamProviders.seekedEvent
        .forTarget(video)
        .listen((event) async {
      if (!completer.isCompleted) {
        final canvas = web.HTMLCanvasElement();
        final ctx = canvas.context2D;

        var targetWidth = maxWidth;
        var targetHeight = maxHeight;

        if (targetWidth == 0 && targetHeight == 0) {
          canvas
            ..width = video.videoWidth
            ..height = video.videoHeight;
          ctx.drawImage(video, 0, 0);
        } else {
          final aspectRatio = video.videoWidth / video.videoHeight;
          if (targetWidth == 0) {
            targetWidth = (targetHeight * aspectRatio).round();
          } else if (targetHeight == 0) {
            targetHeight = (targetWidth / aspectRatio).round();
          }

          final inputAspectRatio = targetWidth / targetHeight;
          if (aspectRatio > inputAspectRatio) {
            targetHeight = (targetWidth / aspectRatio).round();
          } else {
            targetWidth = (targetHeight * aspectRatio).round();
          }

          canvas
            ..width = targetWidth
            ..height = targetHeight;
          ctx.drawImage(video, 0, 0, targetWidth, targetHeight);
        }

        try {
          final blob = await _canvasToBlob(
            canvas: canvas,
            format: _imageFormatToCanvasFormat(imageFormat),
            quality: quality / 100,
          );
          if (!completer.isCompleted) {
            completer.complete(blob);
          }
        } catch (error, stackTrace) {
          if (!completer.isCompleted) {
            completer.completeError(
              PlatformException(
                code: 'CANVAS_EXPORT_ERROR',
                details: error,
                stacktrace: stackTrace.toString(),
              ),
              stackTrace,
            );
          }
        }
      }
    });

    web.EventStreamProviders.errorEvent
        .forTarget(video)
        .listen((event) {
      // The Event itself (_) doesn't contain info about the actual error.
      // We need to look at the HTMLMediaElement.error.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/error
      if (!completer.isCompleted) {
        final mediaError = video.error;
        final errorCode = mediaError?.code;
        final errorMessage = mediaError?.message;
        completer.completeError(
          PlatformException(
            code: errorCode != null
                ? _kErrorValueToErrorName[errorCode] ?? 'UNKNOWN_ERROR'
                : 'UNKNOWN_ERROR',
            message: (errorMessage != null && errorMessage.isNotEmpty)
                ? errorMessage
                : _kDefaultErrorMessage,
            details: errorCode != null
                ? _kErrorValueToErrorDescription[errorCode]
                : null,
          ),
        );
      }
    });

    if (fetchVideo) {
      try {
        final blob = await _fetchVideoByHeaders(
          videoSrc: videoSrc,
          headers: headers,
        );

        video.src = web.URL.createObjectURL(blob);
      } catch (e, s) {
        completer.completeError(e, s);
      }
    } else {
      video
        ..crossOrigin = 'Anonymous'
        ..src = videoSrc;
    }

    return completer.future;
  }

  /// Fetching video by [headers].
  ///
  /// To avoid reading the video's bytes into memory, set the
  /// [XMLHttpRequest.responseType] to 'blob'. This allows the blob to be stored in
  /// the browser's disk or memory cache.
  Future<web.Blob> _fetchVideoByHeaders({
    required String videoSrc,
    required Map<String, String> headers,
  }) async {
    final completer = Completer<web.Blob>();

    final xhr = web.XMLHttpRequest()
      ..open('GET', videoSrc)
      ..responseType = 'blob';
    headers.forEach((key, value) => xhr.setRequestHeader(key, value));

    web.EventStreamProviders.loadEvent.forTarget(xhr).first.then((event) {
      final response = xhr.response;
      if (response == null) {
        if (!completer.isCompleted) {
          completer.completeError(
            PlatformException(
              code: 'VIDEO_FETCH_ERROR',
              message: 'Empty response body.',
            ),
          );
        }
        return;
      }
      if (!completer.isCompleted) {
        completer.complete(response as web.Blob);
      }
    });

    web.EventStreamProviders.errorEvent.forTarget(xhr).first.then((event) {
      if (!completer.isCompleted) {
        completer.completeError(
          PlatformException(
            code: 'VIDEO_FETCH_ERROR',
            message: 'Status: ${xhr.statusText}',
          ),
        );
      }
    });

    xhr.send();

    return completer.future;
  }

  Future<web.Blob> _canvasToBlob({
    required web.HTMLCanvasElement canvas,
    required String format,
    required num quality,
  }) {
    final completer = Completer<web.Blob>();

    final normalizedQuality = quality.clamp(0, 1);

    canvas.toBlob(
      ((web.Blob? blob) {
        if (blob == null) {
          if (!completer.isCompleted) {
            completer.completeError(
              PlatformException(
                code: 'CANVAS_EXPORT_ERROR',
                message: 'Canvas.toBlob returned null.',
              ),
            );
          }
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(blob);
        }
      }).toJS,
      format,
      normalizedQuality.toDouble().toJS,
    );

    return completer.future;
  }

  String _imageFormatToCanvasFormat(ImageFormat imageFormat) {
    switch (imageFormat) {
      case ImageFormat.JPEG:
        return 'image/jpeg';
      case ImageFormat.PNG:
        return 'image/png';
      case ImageFormat.WEBP:
        return 'image/webp';
    }
  }
}
