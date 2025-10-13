import 'dart:math' as math;

enum VideoProxyResolution {
  hd1080,
  hd720,
}

class VideoProxyRequest {
  const VideoProxyRequest({
    required this.sourcePath,
    required this.targetWidth,
    required this.targetHeight,
    this.estimatedDurationMs,
  })  : assert(targetWidth > 0),
        assert(targetHeight > 0);

  final String sourcePath;
  final int targetWidth;
  final int targetHeight;
  final int? estimatedDurationMs;

  bool get isPortraitCanvas => targetHeight >= targetWidth;

  VideoProxyResolution get resolution {
    final maxEdge = math.max(targetWidth, targetHeight);
    return maxEdge <= 1280 ? VideoProxyResolution.hd720 : VideoProxyResolution.hd1080;
  }

  VideoProxyRequest copyWith({
    String? sourcePath,
    int? targetWidth,
    int? targetHeight,
    int? estimatedDurationMs,
  }) {
    return VideoProxyRequest(
      sourcePath: sourcePath ?? this.sourcePath,
      targetWidth: targetWidth ?? this.targetWidth,
      targetHeight: targetHeight ?? this.targetHeight,
      estimatedDurationMs: estimatedDurationMs ?? this.estimatedDurationMs,
    );
  }

  VideoProxyRequest fallback720() {
    if (isPortraitCanvas) {
      return copyWith(targetWidth: 720, targetHeight: 1280);
    }
    return copyWith(targetWidth: 1280, targetHeight: 720);
  }
}

class VideoProxyMetadata {
  const VideoProxyMetadata({
    required this.width,
    required this.height,
    required this.durationMs,
    required this.resolution,
    this.frameRate,
  })  : assert(width > 0),
        assert(height > 0),
        assert(durationMs >= 0);

  final int width;
  final int height;
  final int durationMs;
  final VideoProxyResolution resolution;
  final double? frameRate;

  bool get isPortrait => height >= width;
}

class VideoProxyResult {
  const VideoProxyResult({
    required this.filePath,
    required this.metadata,
    required this.request,
    required this.transcodeDurationMs,
  });

  final String filePath;
  final VideoProxyMetadata metadata;
  final VideoProxyRequest request;
  final int transcodeDurationMs;

  bool get usedFallback =>
      metadata.resolution == VideoProxyResolution.hd720 &&
      request.resolution == VideoProxyResolution.hd720;
}

class VideoProxyException implements Exception {
  const VideoProxyException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'VideoProxyException($message${code != null ? ', code=$code' : ''})';
}

class VideoProxyCancelException extends VideoProxyException {
  const VideoProxyCancelException() : super('Video proxy generation canceled', code: 'cancelled');
}
