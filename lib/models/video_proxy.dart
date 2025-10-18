import 'dart:math' as math;

enum VideoProxyResolution {
  p360,
  p540,
  hd720,
  hd1080,
}

enum VideoProxyPreviewQuality { fast, quality }

enum ProxyQuality { preview, proxy, mezzanine }

enum ProxySessionQualityTier { low, medium, full }

ProxySessionQualityTier proxySessionTierForQuality(ProxyQuality quality) {
  switch (quality) {
    case ProxyQuality.preview:
      return ProxySessionQualityTier.low;
    case ProxyQuality.proxy:
      return ProxySessionQualityTier.medium;
    case ProxyQuality.mezzanine:
      return ProxySessionQualityTier.full;
  }
}

ProxyQuality proxyQualityFromLabel(String? label,
    {ProxyQuality fallback = ProxyQuality.preview}) {
  switch (label?.toLowerCase()) {
    case 'proxy':
      return ProxyQuality.proxy;
    case 'mezzanine':
    case 'high':
      return ProxyQuality.mezzanine;
    default:
      return fallback;
  }
}

extension ProxyQualityPlatformLabel on ProxyQuality {
  String get platformLabel {
    switch (this) {
      case ProxyQuality.preview:
        return 'PREVIEW';
      case ProxyQuality.proxy:
        return 'PROXY';
      case ProxyQuality.mezzanine:
        return 'MEZZANINE';
    }
  }
}

class ProxyTierDescription {
  const ProxyTierDescription({
    required this.quality,
    this.maxLongEdge,
    this.videoBitrateKbps,
    this.audioBitrateKbps,
  });

  final ProxyQuality quality;
  final int? maxLongEdge;
  final int? videoBitrateKbps;
  final int? audioBitrateKbps;

  Map<String, Object?> toJson() {
    return {
      'quality': quality.platformLabel,
      'maxLongEdge': maxLongEdge,
      'videoBitrateKbps': videoBitrateKbps,
      'audioBitrateKbps': audioBitrateKbps,
    };
  }
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
    this.previewQuality = VideoProxyPreviewQuality.fast,
    this.forceFallback = false,
    this.segmentedPreview = false,
    this.sourceStartMs = 0,
    this.sourceDurationMs,
    this.sourceRotationDegrees,
    this.sourceVideoCodec,
    this.sourceOrientation,
    this.sourceMirrored,
    this.tiers = const [],
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

  /// When true, request a segmented preview where the native side emits
  /// segment_ready/progress/completed events and writes per-job cache dir.
  final bool segmentedPreview;
  final int sourceStartMs;
  final int? sourceDurationMs;
  final int? sourceRotationDegrees;
  final String? sourceVideoCodec;
  final String? sourceOrientation;
  final bool? sourceMirrored;
  final List<ProxyTierDescription> tiers;

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
      'segmentedPreview': segmentedPreview,
      'sourceStartMs': sourceStartMs,
      'sourceDurationMs': sourceDurationMs,
      'sourceRotationDegrees': sourceRotationDegrees,
      'sourceVideoCodec': sourceVideoCodec,
      'sourceOrientation': sourceOrientation,
      'sourceMirrored': sourceMirrored,
      'tiers': tiers.map((tier) => tier.toJson()).toList(),
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
    bool? segmentedPreview,
    int? sourceStartMs,
    int? sourceDurationMs,
    int? sourceRotationDegrees,
    String? sourceVideoCodec,
    String? sourceOrientation,
    bool? sourceMirrored,
    List<ProxyTierDescription>? tiers,
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
      segmentedPreview: segmentedPreview ?? this.segmentedPreview,
      sourceStartMs: sourceStartMs ?? this.sourceStartMs,
      sourceDurationMs: sourceDurationMs ?? this.sourceDurationMs,
      sourceRotationDegrees:
          sourceRotationDegrees ?? this.sourceRotationDegrees,
      sourceVideoCodec: sourceVideoCodec ?? this.sourceVideoCodec,
      sourceOrientation: sourceOrientation ?? this.sourceOrientation,
      sourceMirrored: sourceMirrored ?? this.sourceMirrored,
      tiers: tiers ?? this.tiers,
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
      segmentedPreview: false,
      sourceStartMs: sourceStartMs,
      sourceDurationMs: sourceDurationMs,
      sourceRotationDegrees: sourceRotationDegrees,
      sourceVideoCodec: sourceVideoCodec,
      sourceOrientation: sourceOrientation,
      sourceMirrored: sourceMirrored,
      tiers: tiers,
    );
  }
}

class ProxySegment {
  const ProxySegment({
    required this.index,
    required this.path,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasAudio,
    this.quality = ProxyQuality.preview,
    this.sourceStartMs,
    this.sourceEndMs,
    this.orientation,
    this.videoCodec,
    this.audioCodec,
    this.matchesSourceVideoCodec,
    this.matchesSourceAudioCodec,
  });

  final int index;
  final String path;
  final int durationMs;
  final int width;
  final int height;
  final bool hasAudio;
  final ProxyQuality quality;
  final int? sourceStartMs;
  final int? sourceEndMs;
  final String? orientation;
  final String? videoCodec;
  final String? audioCodec;
  final bool? matchesSourceVideoCodec;
  final bool? matchesSourceAudioCodec;

  Map<String, Object?> toJson() {
    return {
      'index': index,
      'path': path,
      'durationMs': durationMs,
      'width': width,
      'height': height,
      'hasAudio': hasAudio,
      'quality': quality.platformLabel,
      'sourceStartMs': sourceStartMs,
      'sourceEndMs': sourceEndMs,
      'orientation': orientation,
      'videoCodec': videoCodec,
      'audioCodec': audioCodec,
      'matchesSourceVideoCodec': matchesSourceVideoCodec,
      'matchesSourceAudioCodec': matchesSourceAudioCodec,
    }..removeWhere((key, value) => value == null);
  }
}

class ProxyManifest {
  const ProxyManifest({
    required this.version,
    required this.segmentDurationMs,
    required this.segments,
    required this.width,
    required this.height,
    required this.fps,
    required this.hasAudio,
    this.keyframes = const [],
    this.durationMs,
    this.sourceStartMs,
    this.sourceEndMs,
    this.orientation,
    this.videoCodec,
    this.audioCodec,
    this.matchesSourceVideoCodec,
    this.matchesSourceAudioCodec,
  });

  final int version;
  final int segmentDurationMs;
  final List<ProxySegment> segments;
  final int width;
  final int height;
  final double fps;
  final bool hasAudio;
  final List<ProxyKeyframe> keyframes;
  final int? durationMs;
  final int? sourceStartMs;
  final int? sourceEndMs;
  final String? orientation;
  final String? videoCodec;
  final String? audioCodec;
  final bool? matchesSourceVideoCodec;
  final bool? matchesSourceAudioCodec;
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
    this.sourceStartMs,
    this.sourceDurationMs,
    this.sourceRotationDegrees,
    this.sourceVideoCodec,
    this.sourceOrientation,
    this.sourceMirrored,
    this.tiers = const [],
    this.timelineMappings = const [],
  });

  final String filePath;
  final VideoProxyMetadata metadata;
  final VideoProxyRequest request;
  final int transcodeDurationMs;
  final bool usedFallback720p;
  final int? sourceStartMs;
  final int? sourceDurationMs;
  final int? sourceRotationDegrees;
  final String? sourceVideoCodec;
  final String? sourceOrientation;
  final bool? sourceMirrored;
  final List<ProxyTierResult> tiers;
  final List<VideoProxyTimelineMapping> timelineMappings;

  bool get usedFallback =>
      usedFallback720p || metadata.resolution == VideoProxyResolution.p360;

  ProxyTierResult? tierForQuality(ProxyQuality quality) {
    for (final tier in tiers) {
      if (tier.quality == quality) {
        return tier;
      }
    }
    return null;
  }
}

class VideoProxyException implements Exception {
  const VideoProxyException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() =>
      'VideoProxyException($message${code != null ? ', code=$code' : ''})';
}

class VideoProxyCancelException extends VideoProxyException {
  const VideoProxyCancelException()
      : super('Video proxy generation canceled', code: 'cancelled');
}

class ProxyTierResult {
  const ProxyTierResult({
    required this.quality,
    required this.filePath,
    required this.metadata,
  });

  final ProxyQuality quality;
  final String filePath;
  final VideoProxyMetadata metadata;
}

class ProxyPreview {
  const ProxyPreview({
    required this.quality,
    required this.filePath,
    required this.metadata,
    this.segmentIndex,
  });

  final ProxyQuality quality;
  final String filePath;
  final VideoProxyMetadata metadata;
  final int? segmentIndex;
}

class ProxyKeyframe {
  const ProxyKeyframe({
    required this.timestampMs,
    this.fileOffsetBytes,
    this.byteLength,
    this.isPoster = false,
  });

  final int timestampMs;
  final int? fileOffsetBytes;
  final int? byteLength;
  final bool isPoster;

  Map<String, Object?> toJson() {
    return {
      'timestampMs': timestampMs,
      'fileOffsetBytes': fileOffsetBytes,
      'byteLength': byteLength,
      'isPoster': isPoster,
    };
  }

  factory ProxyKeyframe.fromJson(Map<String, dynamic> json) {
    return ProxyKeyframe(
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
      fileOffsetBytes: (json['fileOffsetBytes'] as num?)?.toInt(),
      byteLength: (json['byteLength'] as num?)?.toInt(),
      isPoster: json['isPoster'] == true,
    );
  }
}

class VideoProxyTimelineMapping {
  const VideoProxyTimelineMapping({
    required this.quality,
    required this.sourceStartMs,
    required this.sourceDurationMs,
    this.proxyStartMs = 0,
    this.proxyDurationMs,
  });

  final ProxyQuality quality;
  final int sourceStartMs;
  final int sourceDurationMs;
  final int proxyStartMs;
  final int? proxyDurationMs;

  Map<String, Object?> toJson() {
    return {
      'quality': quality.platformLabel,
      'sourceStartMs': sourceStartMs,
      'sourceDurationMs': sourceDurationMs,
      'proxyStartMs': proxyStartMs,
      'proxyDurationMs': proxyDurationMs,
    };
  }

  factory VideoProxyTimelineMapping.fromJson(Map<String, dynamic> json) {
    return VideoProxyTimelineMapping(
      quality: proxyQualityFromLabel(json['quality']?.toString()),
      sourceStartMs: (json['sourceStartMs'] as num?)?.toInt() ?? 0,
      sourceDurationMs: (json['sourceDurationMs'] as num?)?.toInt() ?? 0,
      proxyStartMs: (json['proxyStartMs'] as num?)?.toInt() ?? 0,
      proxyDurationMs: (json['proxyDurationMs'] as num?)?.toInt(),
    );
  }
}
