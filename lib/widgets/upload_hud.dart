import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/upload_manager.dart';
import '../services/local_notifications.dart';

class UploadHud extends ConsumerStatefulWidget {
  const UploadHud({super.key});

  @override
  ConsumerState<UploadHud> createState() => _UploadHudState();
}

class _UploadHudState extends ConsumerState<UploadHud> {
  bool _wasVisible = false;

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(uploadManagerProvider);
    final uploads = manager.activeUploads;
    final pending = manager.pendingPosts;
    final processingMessage = manager.processingMessage;
    final bool hasProcessing = processingMessage != null || pending.isNotEmpty;
    final bool shouldShow = uploads.isNotEmpty || hasProcessing;

    if (!shouldShow) {
      _wasVisible = false;
      return const SizedBox.shrink();
    }
    if (!_wasVisible) {
      _wasVisible = true;
      debugPrint('[UploadHud][metric] upload_hud_visible');
      unawaited(
        LocalNotificationService.showUploadReminder(
          title: 'Upload in progress',
          body: 'Keep the app open to monitor progress.',
        ),
      );
    }

    final UploadTaskInfo? primary = uploads.isNotEmpty ? uploads.first : null;
    final theme = Theme.of(context);
    final Color background =
        theme.colorScheme.surface.withValues(alpha: 0.95);
    final Color border =
        theme.colorScheme.outlineVariant.withValues(alpha: 0.6);

    final String title = primary != null ? 'Uploading' : 'Processing';
    final List<String> details = <String>[];
    if (primary != null) {
      final double progressValue = primary.progress.clamp(0.0, 1.0);
      final int percent = (progressValue * 100).round();
      details.add('$percent%');
      if (uploads.length > 1) {
        details.add('${uploads.length} files');
      }
    } else if (processingMessage != null) {
      details.add(processingMessage);
    } else if (pending.isNotEmpty) {
      details.add('${pending.length} post(s)');
    }

    return Positioned(
      right: 16,
      bottom: 32,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDetailsSheet(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: border),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      primary != null
                          ? Icons.cloud_upload_outlined
                          : Icons.timelapse,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  details.join(' • '),
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (primary != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: primary.progress.clamp(0.0, 1.0),
                    minHeight: 4,
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 4),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDetailsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return const _UploadDetailsSheet();
      },
    );
  }
}

class _UploadDetailsSheet extends ConsumerWidget {
  const _UploadDetailsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(uploadManagerProvider);
    final uploads = manager.activeUploads;
    final pending = manager.pendingPosts;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Uploads',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (uploads.isEmpty && pending.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No active uploads'),
              )
            else ...[
              for (final upload in uploads)
                _UploadListTile(
                  title: upload.task?.taskId ?? upload.taskId,
                  subtitle:
                      'Uploading ${(upload.progress * 100).round()}%',
                  progress: upload.progress,
                  actionIcon: Icons.close,
                  onAction: () {
                    unawaited(
                      ref
                          .read(uploadManagerProvider)
                          .cancelUpload(upload.taskId),
                    );
                  },
                ),
              for (final post in pending)
                _UploadListTile(
                  title: post.id,
                  subtitle: post.isReady ? 'Ready' : post.status,
                  progress: null,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UploadListTile extends StatelessWidget {
  const _UploadListTile({
    required this.title,
    required this.subtitle,
    required this.progress,
    this.actionIcon,
    this.onAction,
  });

  final String title;
  final String subtitle;
  final double? progress;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (actionIcon != null && onAction != null)
                IconButton(
                  icon: Icon(actionIcon),
                  tooltip: 'Cancel upload',
                  onPressed: onAction,
                ),
            ],
          ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 4,
              ),
            ),
        ],
      ),
    );
  }
}
