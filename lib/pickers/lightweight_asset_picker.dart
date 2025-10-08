import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../widgets/asset_thumb.dart';

class LightweightAssetPickerProvider extends DefaultAssetPickerProvider {
  LightweightAssetPickerProvider({
    super.selectedAssets,
    super.maxAssets,
    super.pageSize,
    super.pathThumbnailSize,
    super.requestType = RequestType.common,
    super.sortPathDelegate,
    super.sortPathsByModifiedDate,
    super.filterOptions,
    super.initializeDelayDuration,
    this.thumbnailQuality = 80,
  });

  final int thumbnailQuality;

  @override
  Future<Uint8List?> getThumbnailFromPath(
    PathWrapper<AssetPathEntity> path,
  ) async {
    try {
      if (requestType == RequestType.audio) {
        return null;
      }
      final int assetCount = path.assetCount ?? await path.path.assetCountAsync;
      if (assetCount == 0) {
        return null;
      }
      final assets = await path.path.getAssetListRange(start: 0, end: 1);
      if (assets.isEmpty) {
        return null;
      }
      final asset = assets.single;
      Uint8List? data;
      if (asset.type == AssetType.image) {
        data = await asset.thumbnailDataWithOption(
          ThumbnailOption(
            size: pathThumbnailSize,
            format: ThumbnailFormat.jpeg,
            quality: thumbnailQuality.clamp(1, 100).toInt(),
          ),
        );
      } else if (asset.type != AssetType.video) {
        return null;
      }
      final index = paths.indexWhere(
        (wrapper) => wrapper.path == path.path,
      );
      if (index != -1) {
        paths[index] = paths[index].copyWith(
          assetCount: assetCount,
          thumbnailData: data,
        );
        notifyListeners();
      }
      return data;
    } catch (error, stack) {
      debugPrint(
        'Path thumbnail generation failed: $error\n$stack',
      );
      return null;
    }
  }
}

class LightweightAssetPickerBuilderDelegate
    extends DefaultAssetPickerBuilderDelegate {
  LightweightAssetPickerBuilderDelegate({
    required LightweightAssetPickerProvider super.provider,
    required super.initialPermission,
    super.gridCount,
    super.pickerTheme,
    super.specialItemPosition,
    super.specialItemBuilder,
    super.loadingIndicatorBuilder,
    super.selectPredicate,
    super.shouldRevertGrid,
    super.limitedPermissionOverlayPredicate,
    super.pathNameBuilder,
    super.assetsChangeCallback,
    super.assetsChangeRefreshPredicate,
    super.viewerUseRootNavigator,
    super.viewerPageRouteSettings,
    super.viewerPageRouteBuilder,
    super.themeColor,
    super.textDelegate,
    super.locale,
    super.gridThumbnailSize,
    super.previewThumbnailSize,
    super.specialPickerType,
    super.keepScrollOffset,
    super.shouldAutoplayPreview,
    super.dragToSelect,
    this.thumbnailQuality = 80,
  });

  final int thumbnailQuality;

  @override
  Widget imageAndVideoItemBuilder(
    BuildContext context,
    int index,
    AssetEntity asset,
  ) {
    final thumb = AssetThumb(
      asset: asset,
      size: gridThumbnailSize,
      quality: thumbnailQuality,
    );
    final overlays = <Widget>[
      if ((asset.mimeType ?? '').toLowerCase().contains('gif'))
        gifIndicator(context, asset),
      if (asset.isLivePhoto) buildLivePhotoIndicator(context, asset),
    ];
    if (overlays.isEmpty) {
      return thumb;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        thumb,
        ...overlays,
      ],
    );
  }
}
