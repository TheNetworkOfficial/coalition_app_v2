import 'package:flutter/material.dart';

import '../models/post_draft.dart';

class PostReviewPage extends StatelessWidget {
  const PostReviewPage({super.key, required this.draft});

  final PostDraft draft;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Post'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            _ReviewTile(title: 'Type', value: draft.type),
            _ReviewTile(title: 'File', value: draft.originalFilePath),
            _ReviewTile(
              title: 'Description',
              value: draft.description.isEmpty ? '(empty)' : draft.description,
            ),
            if (draft.videoTrim != null)
              _ReviewTile(
                title: 'Video Trim',
                value:
                    '${draft.videoTrim!.startMs}ms - ${draft.videoTrim!.endMs}ms',
              ),
            if (draft.coverFrameMs != null)
              _ReviewTile(
                title: 'Cover Frame',
                value: '${draft.coverFrameMs}ms',
              ),
            if (draft.imageCrop != null)
              _ReviewTile(
                title: 'Image Crop',
                value:
                    'x=${draft.imageCrop!.x.toStringAsFixed(3)}, y=${draft.imageCrop!.y.toStringAsFixed(3)}, '
                    'w=${draft.imageCrop!.width.toStringAsFixed(3)}, h=${draft.imageCrop!.height.toStringAsFixed(3)}, '
                    'rotation=${draft.imageCrop!.rotation.toStringAsFixed(0)}°',
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
