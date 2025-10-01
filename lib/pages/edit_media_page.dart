import 'package:flutter/material.dart';

class EditMediaData {
  const EditMediaData({
    required this.type,
    required this.sourceAssetId,
    required this.originalFilePath,
    this.originalDurationMs,
  }) : assert(type == 'image' || type == 'video');

  final String type;
  final String sourceAssetId;
  final String originalFilePath;
  final int? originalDurationMs;
}

class EditMediaPage extends StatelessWidget {
  const EditMediaPage({super.key, required this.media});

  final EditMediaData media;

  @override
  Widget build(BuildContext context) {
    final duration = media.originalDurationMs;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${media.type == 'video' ? 'Video' : 'Image'}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Source asset ID: ${media.sourceAssetId}'),
            const SizedBox(height: 8),
            Text('File path: ${media.originalFilePath}'),
            if (duration != null) ...[
              const SizedBox(height: 8),
              Text('Duration: ${duration}ms'),
            ],
          ],
        ),
      ),
    );
  }
}
