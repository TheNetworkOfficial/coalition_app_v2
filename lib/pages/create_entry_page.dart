import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import 'package:video_thumbnail/video_thumbnail.dart';

import '../env.dart';
import '../models/video_proxy.dart';
import '../pickers/lightweight_asset_picker.dart';
import '../services/video_proxy_service.dart';
import 'edit_media_page.dart';

class CreateEntryPage extends StatefulWidget {
  const CreateEntryPage({super.key});

  @override
  State<CreateEntryPage> createState() => _CreateEntryPageState();
}

class _CreateEntryPageState extends State<CreateEntryPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create'),
      ),
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
            textStyle: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.white),
          ),
          onPressed: _onCreatePressed,
          child: const Text('Create'),
        ),
      ),
    );
  }

  Future<void> _onCreatePressed() async {
    final context = this.context;
    if (!await _ensureMediaPermissions(context)) {
      return;
    }

    final permissionOption = const PermissionRequestOption(
      androidPermission: AndroidPermission(
        type: RequestType.common,
        mediaLocation: false,
      ),
    );

    final permissionState = await AssetPicker.permissionCheck(
      requestOption: permissionOption,
    );

    final provider = LightweightAssetPickerProvider(
      maxAssets: 1,
      pathThumbnailSize: const ThumbnailSize.square(120),
      initializeDelayDuration: const Duration(milliseconds: 250),
    );

    final delegate = LightweightAssetPickerBuilderDelegate(
      provider: provider,
      initialPermission: permissionState,
      gridCount: 4,
      gridThumbnailSize: const ThumbnailSize.square(200),
    );

    List<AssetEntity>? assets;
    try {
      assets = await AssetPicker.pickAssetsWithDelegate<AssetEntity,
          AssetPathEntity, LightweightAssetPickerProvider>(
        context,
        delegate: delegate,
        permissionRequestOption: permissionOption,
      );
    } on StateError catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enable photo and video permissions to continue.'),
          ),
        );
      }
      return;
    }

    if (!context.mounted || assets == null || assets.isEmpty) {
      return;
    }

    final asset = assets.first;
    final file = await asset.file;

    if (!mounted || file == null) {
      return;
    }

    final isVideo = asset.type == AssetType.video;
    VideoProxyRequest? request;
    VideoProxyJob? proxyJob;
    final originalDurationMs =
        isVideo ? Duration(seconds: asset.duration).inMilliseconds : null;

    Uint8List? posterBytes;

    if (isVideo) {
      try {
        posterBytes = await VideoThumbnail.thumbnailData(
          video: file.path,
          imageFormat: ImageFormat.PNG,
          timeMs: 300,
          maxWidth: 360,
          quality: 75,
        );
      } catch (error) {
        debugPrint('[CreateEntryPage] Failed to create video poster: $error');
      }

      if (!kEnableNativeEditorPreview) {
        final service = VideoProxyService();
        // Request a fast, low-bitrate proxy that covers the entire clip.
        final videoRequest = VideoProxyRequest(
          sourcePath: file.path,
          targetWidth: 540,
          targetHeight: 960,
          estimatedDurationMs: originalDurationMs,
          frameRateHint: 24,
          keyframeIntervalSeconds: 1,
          audioBitrateKbps: 96,
          previewQuality: VideoProxyPreviewQuality.fast,
          segmentedPreview: false,
        );
        request = videoRequest;
        proxyJob = service.createJob(
          request: videoRequest,
          enableLogging: true,
        );
      } else {
        debugPrint('[Proxy] Skipped: native editor preview is enabled');
      }
    }

    final media = EditMediaData(
      type: isVideo ? 'video' : 'image',
      sourceAssetId: asset.id,
      originalFilePath: file.path,
      originalDurationMs: originalDurationMs,
      proxyRequest: request,
      proxyPosterBytes: posterBytes,
      proxyJob: proxyJob,
    );

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditMediaPage(media: media),
      ),
    );
  }

  Future<bool> _ensureMediaPermissions(BuildContext context) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return true;
    }

    final permissions = <Permission>{};
    if (Platform.isAndroid) {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (sdkInt >= 33) {
        permissions.addAll({Permission.photos, Permission.videos});
      } else {
        permissions.add(Permission.storage);
      }
    } else {
      permissions.add(Permission.photos);
    }

    if (permissions.isEmpty) {
      return true;
    }

    final requested = permissions.toList();
    final results = await requested.request();
    final isGranted = results.values.every(
      (status) =>
          status == PermissionStatus.granted ||
          status == PermissionStatus.limited,
    );

    if (!isGranted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable photo and video permissions to continue.'),
        ),
      );
    }
    return isGranted;
  }
}
