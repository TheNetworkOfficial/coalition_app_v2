import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

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
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        maxAssets: 1,
        requestType: RequestType.common,
      ),
    );

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
}
