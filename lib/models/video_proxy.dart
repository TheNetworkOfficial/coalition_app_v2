import 'dart:math' as math;

enum VideoProxyResolution {
  p360,
  p540,
  hd720,
  hd1080,
}

enum VideoProxyPreviewQuality { fast, quality }

class VideoProxyRequest {
  const VideoProxyRequest({
    required this.sourcePath,
    required this.targetWidth,
    required this.targetHeight,
    this.estimatedDurationMs,
    this.frameRateHint,
    this.keyframeIntervalSeconds = 2,
    this.audioBitrateKbps = 128,
    this.previewQuality = VideoProxyPreviewQuality.fast,
    this.forceFallback = false,
  })  : assert(targetWidth > 0),
        assert(targetHeight > 0);

  final String sourcePath;
  final int targetWidth;
  final int targetHeight;
  final int? estimatedDurationMs;
  final int? frameRateHint;
  final int keyframeIntervalSeconds;
  final int audioBitrateKbps;
  final VideoProxyPreviewQuality previewQuality;
  final bool forceFallback;

  bool get isPortraitCanvas => targetHeight >= targetWidth;

  VideoProxyResolution get resolution {
    final maxEdge = math.max(targetWidth, targetHeight);
    if (maxEdge <= 640) {
      return VideoProxyResolution.p360;
    }
    if (maxEdge <= 960) {
      return VideoProxyResolution.p540;
    }
    if (maxEdge <= 1280) {
      return VideoProxyResolution.hd720;
    }
    return VideoProxyResolution.hd1080;
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
      'previewQuality': previewQuality.name.toUpperCase(),
      'forceFallback': forceFallback,
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
    VideoProxyPreviewQuality? previewQuality,
    bool? forceFallback,
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
      previewQuality: previewQuality ?? this.previewQuality,
      forceFallback: forceFallback ?? this.forceFallback,
    );
  }

  VideoProxyRequest fallbackPreview() {
    final portrait = isPortraitCanvas;
    return copyWith(
      targetWidth: portrait ? 360 : 640,
      targetHeight: portrait ? 640 : 360,
      frameRateHint: 24,
      keyframeIntervalSeconds: 1,
      audioBitrateKbps: 96,
      previewQuality: VideoProxyPreviewQuality.fast,
      forceFallback: true,
    );
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

  bool get usedFallback => usedFallback720p ||
      metadata.resolution == VideoProxyResolution.p360;
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
