import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/post_draft.dart';
import '../services/upload_service.dart';

final uploadManagerProvider = ChangeNotifierProvider<UploadManager>((ref) {
  final manager = UploadManager();
  ref.onDispose(manager.dispose);
  return manager;
});

class UploadManager extends ChangeNotifier {
  UploadManager({UploadService? uploadService})
      : _uploadService = uploadService ?? UploadService() {
    _updatesSubscription = _uploadService.updates.listen(_handleUpdate);
  }

  final UploadService _uploadService;
  StreamSubscription<TaskUpdate>? _updatesSubscription;

  String? _currentTaskId;
  double? _progress;
  TaskStatus? _status;

  bool get hasActiveUpload => _currentTaskId != null;
  double? get progress => _progress;
  TaskStatus? get status => _status;
  String? get currentTaskId => _currentTaskId;

  Future<UploadStartResult> startUpload({
    required PostDraft draft,
    required String description,
  }) async {
    final result = await _uploadService.startUpload(
      draft: draft,
      description: description,
    );
    _currentTaskId = result.taskId;
    _progress = 0;
    _status = null;
    notifyListeners();
    return result;
  }

  void _handleUpdate(TaskUpdate update) {
    if (_currentTaskId == null || update.task.taskId != _currentTaskId) {
      return;
    }

    if (update is TaskProgressUpdate) {
      final clamped = update.progress.clamp(0.0, 1.0).toDouble();
      if (_progress != clamped) {
        _progress = clamped;
        notifyListeners();
      }
      return;
    }

    if (update is TaskStatusUpdate) {
      _status = update.status;
      if (update.status.isFinalState) {
        _clearCurrentUpload();
      } else {
        notifyListeners();
      }
    }
  }

  void _clearCurrentUpload() {
    final hasChanges = _currentTaskId != null || _progress != null || _status != null;
    _currentTaskId = null;
    _progress = null;
    _status = null;
    if (hasChanges) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _updatesSubscription?.cancel();
    _uploadService.dispose();
    super.dispose();
  }
}
