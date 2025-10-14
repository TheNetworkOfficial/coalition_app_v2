import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../models/video_proxy.dart';
import '../pickers/lightweight_asset_picker.dart';
import '../services/video_proxy_service.dart';
import '../widgets/video_proxy_dialog.dart';
import 'edit_media_page.dart';

enum _ProxyRetryDecision { cancel, retry, fallback }

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
    VideoProxyResult? proxy;
    VideoProxyRequest? request;
    final originalDurationMs =
        isVideo ? Duration(seconds: asset.duration).inMilliseconds : null;

    if (isVideo) {
      final videoRequest = VideoProxyRequest(
        sourcePath: file.path,
        targetWidth: 1080,
        targetHeight: 1920,
        estimatedDurationMs: originalDurationMs,
      );
      final result = await _prepareVideoProxy(context, videoRequest);
      if (result == null) {
        return;
      }
      proxy = result;
      request = videoRequest;
    }

    final media = EditMediaData(
      type: isVideo ? 'video' : 'image',
      sourceAssetId: asset.id,
      originalFilePath: file.path,
      originalDurationMs: originalDurationMs,
      proxyResult: proxy,
      proxyRequest: request,
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

  Future<VideoProxyResult?> _prepareVideoProxy(
    BuildContext context,
    VideoProxyRequest request,
  ) async {
    var currentRequest = request;
    final service = VideoProxyService();

    while (mounted) {
      final job = service.createJob(request: currentRequest);
      final outcome = await showDialog<VideoProxyDialogOutcome>(
        context: context,
        barrierDismissible: false,
        builder: (_) => VideoProxyProgressDialog(
          job: job,
          title: 'Preparing video…',
          message: 'Optimizing for editing.',
          allowCancel: true,
        ),
      );

      if (outcome == null) {
        return null;
      }

      if (outcome.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video preparation canceled.')),
        );
        return null;
      }

      if (outcome.isSuccess && outcome.result != null) {
        final result = outcome.result!;
        debugPrint(
          '[CreateEntryPage] Proxy ready ${result.metadata.width}x${result.metadata.height} in ${result.transcodeDurationMs}ms (resolution=${result.metadata.resolution})',
        );
        if (currentRequest.resolution == VideoProxyResolution.hd720) {
          debugPrint('[CreateEntryPage] Using 720p proxy fallback.');
        }
        return result;
      }

      final errorMessage = outcome.error is VideoProxyException
          ? (outcome.error as VideoProxyException).message
          : outcome.error?.toString() ?? 'Unknown error';

      final decision = await _showProxyErrorDialog(
        context,
        errorMessage: errorMessage,
        allowFallback: currentRequest.resolution != VideoProxyResolution.hd720,
      );

      if (decision == _ProxyRetryDecision.retry) {
        currentRequest = request;
        continue;
      }

      if (decision == _ProxyRetryDecision.fallback) {
        currentRequest = request.fallback720();
        continue;
      }

      return null;
    }

    return null;
  }

  Future<_ProxyRetryDecision> _showProxyErrorDialog(
    BuildContext context, {
    required String errorMessage,
    required bool allowFallback,
  }) async {
    final actions = <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(_ProxyRetryDecision.cancel),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(_ProxyRetryDecision.retry),
        child: const Text('Retry'),
      ),
      if (allowFallback)
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_ProxyRetryDecision.fallback),
          child: const Text('Try smaller version'),
        ),
    ];

    final decision = await showDialog<_ProxyRetryDecision>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Video preparation failed'),
        content: Text(
          'We couldn\'t optimize your video. $errorMessage',
        ),
        actions: actions,
      ),
    );

    return decision ?? _ProxyRetryDecision.cancel;
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
