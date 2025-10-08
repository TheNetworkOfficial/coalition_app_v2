import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../pickers/lightweight_asset_picker.dart';
import 'edit_media_page.dart';

class CreateEntryPage extends StatelessWidget {
  const CreateEntryPage({super.key});

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
          onPressed: () => _onCreatePressed(context),
          child: const Text('Create'),
        ),
      ),
    );
  }

  Future<void> _onCreatePressed(BuildContext context) async {
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
      assets = await AssetPicker.pickAssetsWithDelegate<
          AssetEntity,
          AssetPathEntity,
          LightweightAssetPickerProvider>(
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

    if (!context.mounted || file == null) {
      return;
    }

    final isVideo = asset.type == AssetType.video;
    final media = EditMediaData(
      type: isVideo ? 'video' : 'image',
      sourceAssetId: asset.id,
      originalFilePath: file.path,
      originalDurationMs:
          isVideo ? Duration(seconds: asset.duration).inMilliseconds : null,
    );

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
