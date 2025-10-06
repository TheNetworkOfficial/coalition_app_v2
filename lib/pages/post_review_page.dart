import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/post_draft.dart';
import '../services/upload_service.dart';

class PostReviewPage extends StatefulWidget {
  const PostReviewPage({super.key, required this.draft});

  final PostDraft draft;

  @override
  State<PostReviewPage> createState() => _PostReviewPageState();
}

class _PostReviewPageState extends State<PostReviewPage> {
  late final TextEditingController _descriptionController;
  late final UploadService _uploadService;
  StreamSubscription<TaskUpdate>? _updateSubscription;
  TaskStatus? _latestStatus;
  double? _latestProgress;
  String? _currentTaskId;
  String? _postId;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.draft.description);
    _uploadService = UploadService();
    _updateSubscription = _uploadService.updates.listen((update) {
      if (update.task.taskId != _currentTaskId) {
        return;
      }

      if (update is TaskStatusUpdate) {
        setState(() {
          _latestStatus = update.status;
          if (update.status == TaskStatus.complete) {
            _latestProgress = 1.0;
          } else if (update.status.isFinalState) {
            _latestProgress ??= 0.0;
          }
        });
      } else if (update is TaskProgressUpdate) {
        setState(() {
          _latestProgress = update.progress;
        });
      }
    });
  }

  @override
  void dispose() {
    _updateSubscription?.cancel();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _handlePost() async {
    if (_isPosting) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isPosting = true;
    });

    try {
      final result = await _uploadService.startUpload(
        draft: widget.draft,
        description: _descriptionController.text,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _currentTaskId = result.taskId;
        _postId = result.postId;
        _latestStatus = null;
        _latestProgress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload started in background')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start upload: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
        });
      }
    }
  }

  Future<void> _retryUpload() async {
    final taskId = _currentTaskId;
    if (taskId == null) {
      return;
    }
    try {
      await _uploadService.retryTask(taskId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Retrying upload...')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to retry upload: $error')),
        );
      }
    }
  }

  Widget _buildPreview() {
    final borderRadius = BorderRadius.circular(16);
    final trim = widget.draft.videoTrim;
    final crop = widget.draft.imageCrop;

    Widget detailsOverlay() {
      final details = <String>[];
      if (trim != null) {
        details.add('Trim: ${trim.startMs}ms - ${trim.endMs}ms');
      }
      if (widget.draft.coverFrameMs != null) {
        details.add('Cover @ ${widget.draft.coverFrameMs}ms');
      }
      if (crop != null) {
        details.add(
          'Crop x${crop.x.toStringAsFixed(2)}, y${crop.y.toStringAsFixed(2)}, '
          'w${crop.width.toStringAsFixed(2)}, h${crop.height.toStringAsFixed(2)}',
        );
      }
      if (details.isEmpty) {
        return const SizedBox.shrink();
      }
      return Positioned(
        left: 12,
        right: 12,
        bottom: 12,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in details)
                  Text(
                    line,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget previewContent;
    if (widget.draft.type == 'image' && !kIsWeb) {
      previewContent = ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(widget.draft.originalFilePath),
          height: 240,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _PreviewPlaceholder(
              icon: Icons.image_not_supported_outlined,
              label: 'Unable to load image preview',
            );
          },
        ),
      );
    } else {
      previewContent = ClipRRect(
        borderRadius: borderRadius,
        child: _PreviewPlaceholder(
          icon: widget.draft.type == 'video'
              ? Icons.videocam_outlined
              : Icons.image_outlined,
          label: widget.draft.type == 'video'
              ? 'Video preview unavailable'
              : 'Preview unavailable on web',
        ),
      );
    }

    return Stack(
      children: [
        previewContent,
        detailsOverlay(),
      ],
    );
  }

  Widget _buildStatusChip() {
    if (_currentTaskId == null) {
      return const SizedBox.shrink();
    }

    final status = _latestStatus;
    final rawProgress = _latestProgress ??
        (status == TaskStatus.complete ? 1.0 : 0.0);
    final progressValue = rawProgress.clamp(0.0, 1.0).toDouble();

    String label;
    Color background;
    IconData icon;

    switch (status) {
      case TaskStatus.complete:
        label = 'Upload complete';
        background = Colors.green.shade600;
        icon = Icons.check_circle_outline;
        break;
      case TaskStatus.running:
        label = 'Uploading ${(progressValue * 100).clamp(0, 100).toStringAsFixed(0)}%';
        background = Theme.of(context).colorScheme.primary;
        icon = Icons.cloud_upload_outlined;
        break;
      case TaskStatus.failed:
        label = 'Upload failed';
        background = Colors.red.shade600;
        icon = Icons.error_outline;
        break;
      case TaskStatus.enqueued:
      case TaskStatus.waitingToRetry:
      case TaskStatus.paused:
        label = 'Waiting to upload';
        background = Theme.of(context).colorScheme.secondary;
        icon = Icons.schedule_outlined;
        break;
      case TaskStatus.canceled:
        label = 'Upload canceled';
        background = Colors.grey.shade600;
        icon = Icons.cancel_outlined;
        break;
      case TaskStatus.notFound:
        label = 'Upload missing';
        background = Colors.orange.shade700;
        icon = Icons.help_outline;
        break;
      default:
        label = 'Uploading';
        background = Theme.of(context).colorScheme.primary;
        icon = Icons.cloud_upload_outlined;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white),
                ),
                if (status == TaskStatus.failed) ...[
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: _retryUpload,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (status == TaskStatus.running)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(
              value: progressValue <= 0 || progressValue >= 1 ? null : progressValue,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Post'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  _buildPreview(),
                  const SizedBox(height: 16),
                  Text(
                    widget.draft.type.toUpperCase(),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.draft.originalFilePath,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_postId != null) ...[
                    const SizedBox(height: 8),
                    Text('Post ID: $_postId', style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 5,
                    minLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_currentTaskId != null) ...[
                    const SizedBox(height: 16),
                    _buildStatusChip(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isPosting ? null : _handlePost,
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: _isPosting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
