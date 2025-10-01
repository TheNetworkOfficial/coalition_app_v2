class PostDraft {
  const PostDraft({
    required this.originalFilePath,
    required this.type,
    required this.description,
    this.videoTrim,
    this.coverFrameMs,
    this.imageCrop,
  }) : assert(type == 'image' || type == 'video');

  final String originalFilePath;
  final String type;
  final String description;
  final VideoTrimData? videoTrim;
  final int? coverFrameMs;
  final ImageCropData? imageCrop;
}

class VideoTrimData {
  const VideoTrimData({
    required this.startMs,
    required this.endMs,
  }) : assert(startMs >= 0 && endMs >= 0 && endMs >= startMs);

  final int startMs;
  final int endMs;
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
