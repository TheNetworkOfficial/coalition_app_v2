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
  bool _reminderShown = false;
  bool _wasVisible = false;

  @override
  Widget build(BuildContext context) {
    final manager = ref.watch(uploadManagerProvider);
    final bool shouldShow = manager.isUploadHudActive;

    if (!shouldShow) {
      _wasVisible = false;
      _reminderShown = false;
      return const SizedBox.shrink();
    }

    if (!_wasVisible) {
      _wasVisible = true;
      debugPrint('[UploadHud][metric] upload_hud_visible');
    }

    if (!_reminderShown && manager.hasActiveUpload) {
      _reminderShown = true;
      unawaited(
        LocalNotificationService.showUploadReminder(
          title: 'Upload in progress',
          body: 'Keep the app open to monitor progress.',
        ),
      );
    }

    final double progress = manager.hasActiveUpload
        ? manager.uploadProgress.clamp(0.0, 1.0)
        : 1.0;
    final int percent =
        (progress * 100).round().clamp(0, 100).toInt();

    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 16, bottom: 32),
          child: _CircularUploadIndicator(
            percent: percent,
            progress: progress,
          ),
        ),
      ),
    );
  }
}

class _CircularUploadIndicator extends StatelessWidget {
  const _CircularUploadIndicator({
    required this.percent,
    required this.progress,
  });

  final int percent;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color background = theme.colorScheme.surface.withValues(alpha: 0.98);
    final Color border =
        theme.colorScheme.outlineVariant.withValues(alpha: 0.5);

    return Semantics(
      label: 'Upload progress',
      value: '$percent percent',
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: border),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                strokeWidth: 4,
              ),
            ),
            Text(
              '$percent%',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
