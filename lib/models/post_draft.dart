import 'edit_manifest.dart';
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
    this.sourceAssetId,
    this.persistedFilePath,
    this.editManifest,
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
  final String? sourceAssetId;
  final String? persistedFilePath;
  final EditManifest? editManifest;

  PostDraft copyWith({
    String? originalFilePath,
    String? description,
    String? proxyFilePath,
    VideoProxyMetadata? proxyMetadata,
    int? originalDurationMs,
    VideoTrimData? videoTrim,
    int? coverFrameMs,
    ImageCropData? imageCrop,
    String? sourceAssetId,
    String? persistedFilePath,
    EditManifest? editManifest,
  }) {
    return PostDraft(
      originalFilePath: originalFilePath ?? this.originalFilePath,
      type: type,
      description: description ?? this.description,
      proxyFilePath: proxyFilePath ?? this.proxyFilePath,
      proxyMetadata: proxyMetadata ?? this.proxyMetadata,
      originalDurationMs: originalDurationMs ?? this.originalDurationMs,
      videoTrim: videoTrim ?? this.videoTrim,
      coverFrameMs: coverFrameMs ?? this.coverFrameMs,
      imageCrop: imageCrop ?? this.imageCrop,
      sourceAssetId: sourceAssetId ?? this.sourceAssetId,
      persistedFilePath: persistedFilePath ?? this.persistedFilePath,
      editManifest: editManifest ?? this.editManifest,
    );
  }

  bool get hasVideoProxy => proxyFilePath != null && proxyMetadata != null;

  String videoPlaybackPath({bool preferOriginal = true}) {
    final original = persistedFilePath ?? originalFilePath;
    final proxy = proxyFilePath;
    if (preferOriginal) {
      if (original.isNotEmpty) {
        return original;
      }
      if (proxy != null && proxy.isNotEmpty) {
        return proxy;
      }
      return original;
    }
    if (proxy != null && proxy.isNotEmpty) {
      return proxy;
    }
    return original;
  }
}

class VideoTrimData {
  const VideoTrimData({
    required this.startMs,
    required this.endMs,
    required this.durationMs,
    this.proxyStartMs,
    this.proxyEndMs,
  })  : assert(startMs >= 0 && endMs >= 0 && endMs >= startMs),
        assert(durationMs >= 0);

  final int startMs;
  final int endMs;
  final int durationMs;
  final int? proxyStartMs;
  final int? proxyEndMs;
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
