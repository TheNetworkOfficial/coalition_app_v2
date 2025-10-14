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
    this.frameRateHint,
    this.keyframeIntervalSeconds = 2,
    this.audioBitrateKbps = 128,
  })  : assert(targetWidth > 0),
        assert(targetHeight > 0);

  final String sourcePath;
  final int targetWidth;
  final int targetHeight;
  final int? estimatedDurationMs;
  final int? frameRateHint;
  final int keyframeIntervalSeconds;
  final int audioBitrateKbps;

  bool get isPortraitCanvas => targetHeight >= targetWidth;

  VideoProxyResolution get resolution {
    final maxEdge = math.max(targetWidth, targetHeight);
    return maxEdge <= 1280 ? VideoProxyResolution.hd720 : VideoProxyResolution.hd1080;
  }

  int get maxLongEdge => math.max(targetWidth, targetHeight);

  Map<String, Object?> toPlatformRequest({
    required String jobId,
  }) {
    return {
      'jobId': jobId,
      'sourcePath': sourcePath,
      'targetCanvas': {
        'width': targetWidth,
        'height': targetHeight,
      },
      'maxLongEdge': maxLongEdge,
      'frameRateHint': frameRateHint,
      'keyframeIntervalSeconds': keyframeIntervalSeconds,
      'audioBitrateKbps': audioBitrateKbps,
      'bakeRotation': true,
      'letterbox': true,
      'fastStart': true,
      'estimatedDurationMs': estimatedDurationMs,
    };
  }

  VideoProxyRequest copyWith({
    String? sourcePath,
    int? targetWidth,
    int? targetHeight,
    int? estimatedDurationMs,
    int? frameRateHint,
    int? keyframeIntervalSeconds,
    int? audioBitrateKbps,
  }) {
    return VideoProxyRequest(
      sourcePath: sourcePath ?? this.sourcePath,
      targetWidth: targetWidth ?? this.targetWidth,
      targetHeight: targetHeight ?? this.targetHeight,
      estimatedDurationMs: estimatedDurationMs ?? this.estimatedDurationMs,
      frameRateHint: frameRateHint ?? this.frameRateHint,
      keyframeIntervalSeconds:
          keyframeIntervalSeconds ?? this.keyframeIntervalSeconds,
      audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
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
    required this.rotationBaked,
    this.frameRate,
  })  : assert(width > 0),
        assert(height > 0),
        assert(durationMs >= 0);

  final int width;
  final int height;
  final int durationMs;
  final VideoProxyResolution resolution;
  final double? frameRate;
  final bool rotationBaked;

  bool get isPortrait => height >= width;
}

class VideoProxyResult {
  const VideoProxyResult({
    required this.filePath,
    required this.metadata,
    required this.request,
    required this.transcodeDurationMs,
    this.usedFallback720p = false,
  });

  final String filePath;
  final VideoProxyMetadata metadata;
  final VideoProxyRequest request;
  final int transcodeDurationMs;
  final bool usedFallback720p;

  bool get usedFallback =>
      usedFallback720p || metadata.resolution == VideoProxyResolution.hd720;
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
