import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/video_proxy.dart';
import '../services/video_proxy_service.dart';

class VideoProxyDialogOutcome {
  const VideoProxyDialogOutcome._({
    this.result,
    this.error,
    required this.cancelled,
  });

  const VideoProxyDialogOutcome.success(VideoProxyResult result)
      : this._(result: result, error: null, cancelled: false);

  const VideoProxyDialogOutcome.error(Object error)
      : this._(result: null, error: error, cancelled: false);

  const VideoProxyDialogOutcome.cancelled()
      : this._(result: null, error: null, cancelled: true);

  final VideoProxyResult? result;
  final Object? error;
  final bool cancelled;

  bool get isSuccess => result != null;
  bool get isError => !cancelled && error != null;
}

class VideoProxyProgressDialog extends StatefulWidget {
  const VideoProxyProgressDialog({
    super.key,
    required this.job,
    this.title = 'Preparing video…',
    this.message,
    this.allowCancel = true,
    this.posterBytes,
  });

  final VideoProxyJob job;
  final String title;
  final String? message;
  final bool allowCancel;
  final Uint8List? posterBytes;

  @override
  State<VideoProxyProgressDialog> createState() =>
      _VideoProxyProgressDialogState();
}

class _VideoProxyProgressDialogState extends State<VideoProxyProgressDialog> {
  StreamSubscription<VideoProxyProgress>? _subscription;
  double? _progress;
  bool _didPop = false;
  bool _fallbackNotified = false;

  @override
  void initState() {
    super.initState();
    // Defer subscription and future handlers until after the first frame so
    // that InheritedWidget lookups (e.g. ScaffoldMessenger.of) succeed and we
    // avoid DependOnInheritedWidgetOfExactTypeError when events fire very
    // early (before the dialog is inserted into the element tree).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _subscription = widget.job.progress.listen((event) {
        if (!mounted) return;
        setState(() {
          _progress = event.fraction;
        });
        if (event.fallbackTriggered && !_fallbackNotified) {
          _fallbackNotified = true;
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            const SnackBar(
              content: Text('Optimizing for quick editing…'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      });

      widget.job.future.then((result) {
        if (!mounted) return;
        _pop(VideoProxyDialogOutcome.success(result));
      }).catchError((error) {
        if (!mounted) return;
        if (error is VideoProxyCancelException) {
          _pop(const VideoProxyDialogOutcome.cancelled());
        } else {
          _pop(VideoProxyDialogOutcome.error(error));
        }
      });
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _pop(VideoProxyDialogOutcome outcome) {
    if (_didPop) {
      return;
    }
    _didPop = true;
    if (mounted) {
      Navigator.of(context).pop(outcome);
    }
  }

  Future<void> _handleCancel() async {
    await widget.job.cancel();
    _pop(const VideoProxyDialogOutcome.cancelled());
  }

  @override
  Widget build(BuildContext context) {
    final value = _progress != null ? _progress!.clamp(0.0, 1.0) : null;
    final percent = value != null ? (value * 100).clamp(0, 100).round() : null;
    final message = widget.message ?? 'This may take a moment.';

    // WillPopScope is deprecated in newer Flutter versions; ignore the deprecation
    // to preserve the original behavior until a safe migration to PopScope is available.
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async => false,
      child: AlertDialog(
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.posterBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: Image.memory(
                      widget.posterBytes!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(value: value?.toDouble()),
            ),
            if (percent != null) Text('$percent%') else Text(message),
          ],
        ),
        actions: [
          if (widget.allowCancel)
            TextButton(
              onPressed: _handleCancel,
              child: const Text('Cancel'),
            ),
        ],
      ),
    );
  }
}
