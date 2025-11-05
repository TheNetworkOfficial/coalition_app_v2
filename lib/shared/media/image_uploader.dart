import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../pickers/lightweight_asset_picker.dart';
import '../../providers/app_providers.dart';
import '../../services/api_client.dart';

class ImageUploadResult {
  ImageUploadResult({
    required this.remoteUrl,
    this.preview,
  });

  final String remoteUrl;
  final ImageProvider? preview;
}

Future<ImageUploadResult?> pickAndUploadProfileImage({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final file = await _selectSingleImage(context);
  if (file == null) {
    return null;
  }

  final preview = FileImage(file);
  final apiClient = ref.read(apiClientProvider);
  final contentType = _inferContentType(file.path);
  final session = await apiClient.createImageUploadSession(
    fileName: p.basename(file.path),
    fileSize: await file.length(),
    contentType: contentType,
  );

  debugPrint(
    '[ProfileUpload] → ${session.uploadUrl} method=${session.method} fields=${session.fields.keys.toList()} headers=${session.headers.keys.toList()}',
  );

  await apiClient.uploadFileToUrl(
    session.uploadUrl,
    file,
    headers: session.headers,
    fields: session.fields,
    method: session.method.isNotEmpty ? session.method : 'POST',
    fileFieldName: session.fileFieldName.isNotEmpty
        ? session.fileFieldName
        : 'file',
    contentType: session.contentType ?? contentType,
  );

  final remoteUrl = session.deliveryUrl;
  if (remoteUrl == null || remoteUrl.isEmpty) {
    throw ApiException(
      'Upload succeeded but no delivery URL was returned.',
    );
  }

  return ImageUploadResult(
    remoteUrl: remoteUrl,
    preview: preview,
  );
}

Future<File?> _selectSingleImage(BuildContext context) async {
  if (!await _ensureMediaPermissions(context)) {
    return null;
  }

  final permissionOption = const PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      mediaLocation: false,
    ),
  );

  final initialPermission = await AssetPicker.permissionCheck(
    requestOption: permissionOption,
  );

  final provider = LightweightAssetPickerProvider(
    maxAssets: 1,
    pathThumbnailSize: const ThumbnailSize.square(120),
    initializeDelayDuration: const Duration(milliseconds: 250),
  );

  final delegate = LightweightAssetPickerBuilderDelegate(
    provider: provider,
    initialPermission: initialPermission,
    gridCount: 4,
    gridThumbnailSize: const ThumbnailSize.square(200),
  );

  List<AssetEntity>? assets;
  try {
    assets =
        await AssetPicker.pickAssetsWithDelegate<AssetEntity, AssetPathEntity,
            LightweightAssetPickerProvider>(
      context,
      delegate: delegate,
      permissionRequestOption: permissionOption,
    );
  } on StateError catch (_) {
    _showMessage(context, 'Enable photo permissions to continue.');
    return null;
  }

  if (assets == null || assets.isEmpty) {
    return null;
  }

  final asset = assets.first;
  if (asset.type != AssetType.image) {
    throw Exception('Please select an image file.');
  }
  final file = await asset.file;
  if (file == null) {
    throw Exception('Unable to read the selected file.');
  }
  return file;
}

Future<bool> _ensureMediaPermissions(BuildContext context) async {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return true;
  }

  final permissions = <Permission>[];
  if (Platform.isAndroid) {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    if (sdkInt >= 33) {
      permissions.addAll(const [Permission.photos, Permission.videos]);
    } else {
      permissions.add(Permission.storage);
    }
  } else {
    permissions.add(Permission.photos);
  }

  if (permissions.isEmpty) {
    return true;
  }

  final results = await permissions.request();
  final granted = results.values.every(
    (status) =>
        status == PermissionStatus.granted ||
        status == PermissionStatus.limited,
  );
  if (!granted) {
    _showMessage(context, 'Enable photo permissions to continue.');
  }
  return granted;
}

String _inferContentType(String path) {
  final extension = p.extension(path).toLowerCase();
  switch (extension) {
    case '.png':
      return 'image/png';
    case '.gif':
      return 'image/gif';
    case '.webp':
      return 'image/webp';
    case '.heic':
    case '.heif':
      return 'image/heic';
    default:
      return 'image/jpeg';
  }
}

void _showMessage(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
