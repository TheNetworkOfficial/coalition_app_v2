import 'video_proxy.dart';

class PostDraft {
  const PostDraft({
    required this.originalFilePath,
    required this.type,
    required this.description,
    this.proxyFilePath,
    this.proxyMetadata,
    this.originalDurationMs,
    this.videoTrim,
    this.coverFrameMs,
    this.imageCrop,
  }) : assert(type == 'image' || type == 'video');

  final String originalFilePath;
  final String type;
  final String description;
  final String? proxyFilePath;
  final VideoProxyMetadata? proxyMetadata;
  final int? originalDurationMs;
  final VideoTrimData? videoTrim;
  final int? coverFrameMs;
  final ImageCropData? imageCrop;

  bool get hasVideoProxy => proxyFilePath != null && proxyMetadata != null;

  String get videoPlaybackPath => proxyFilePath ?? originalFilePath;

  String resolveUploadPath({required bool preferProxy}) {
    if (preferProxy && hasVideoProxy) {
      return proxyFilePath!;
    }
    return originalFilePath;
  }
}

class VideoTrimData {
  const VideoTrimData({
    required this.startMs,
    required this.endMs,
    required this.durationMs,
  })  : assert(startMs >= 0 && endMs >= 0 && endMs >= startMs),
        assert(durationMs >= 0);

  final int startMs;
  final int endMs;
  final int durationMs;
}

class ImageCropData {
  const ImageCropData({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotation,
  })  : assert(x >= 0 && y >= 0),
        assert(width > 0 && height > 0);

  final double x;
  final double y;
  final double width;
  final double height;
  final double rotation;
}
