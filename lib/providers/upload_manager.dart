import 'dart:async';
import 'dart:collection';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/post_draft.dart';
import '../models/posts_page.dart';
import '../models/upload_outcome.dart';
import 'app_providers.dart';
import '../services/upload_service.dart';

final uploadManagerProvider = ChangeNotifierProvider<UploadManager>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final manager = UploadManager(
    uploadService: UploadService(apiClient: apiClient),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

class UploadManager extends ChangeNotifier {
  UploadManager({UploadService? uploadService})
      : _uploadService = uploadService ?? UploadService() {
    _updatesSubscription = _uploadService.updates.listen(_handleUpdate);
    _uploadService.onPendingPostCreated = _handlePendingPostCreated;
    _uploadService.onPostStatusUpdated = _handlePostStatusUpdated;
    _uploadService.onVideoProcessingUpdate = _handleProcessingUpdate;
  }

  final UploadService _uploadService;
  StreamSubscription<TaskUpdate>? _updatesSubscription;

  final LinkedHashMap<String, UploadTaskInfo> _activeUploads =
      LinkedHashMap<String, UploadTaskInfo>();
  final List<PostItem> _pendingPosts = <PostItem>[];
  VideoProcessingUpdate? _processingStatus;
  Timer? _processingClearTimer;

  static const Duration _processingDismissDelay = Duration(seconds: 6);

  bool get hasActiveUpload => _activeUploads.isNotEmpty;
  double? get progress => _activeUploads.isEmpty
      ? null
      : _activeUploads.values.first.progress;
  TaskStatus? get status => _activeUploads.isEmpty
      ? null
      : _activeUploads.values.first.status;
  String? get currentTaskId =>
      _activeUploads.isEmpty ? null : _activeUploads.keys.first;
  List<UploadTaskInfo> get activeUploads =>
      List<UploadTaskInfo>.unmodifiable(_activeUploads.values);
  List<PostItem> get pendingPosts => List<PostItem>.unmodifiable(_pendingPosts);
  VideoProcessingUpdate? get processingStatus => _processingStatus;
  String? get processingMessage {
    final status = _processingStatus;
    if (status == null || !status.isVideo) {
      return null;
    }
    switch (status.phase) {
      case VideoProcessingPhase.processing:
        return 'Processing video…';
      case VideoProcessingPhase.ready:
        return 'Video ready to view';
      case VideoProcessingPhase.failed:
        return 'Video processing failed.';
    }
  }

  bool get showProcessingSpinner =>
      _processingStatus?.phase == VideoProcessingPhase.processing;

  bool get processingSucceeded =>
      _processingStatus?.phase == VideoProcessingPhase.ready;

  bool get processingFailed =>
      _processingStatus?.phase == VideoProcessingPhase.failed;

  Future<UploadOutcome> startUpload({
    required PostDraft draft,
    required String description,
  }) async {
    final future = _uploadService.startUpload(
      draft: draft,
      description: description,
    );
    final taskId = _uploadService.lastStartedTaskId;
    if (taskId != null) {
      _activeUploads.putIfAbsent(
        taskId,
        () => UploadTaskInfo(taskId: taskId),
      );
      notifyListeners();
    }
    final outcome = await future;
    return outcome;
  }

  void _handleUpdate(TaskUpdate update) {
    final taskId = update.task.taskId;
    final info = _activeUploads.putIfAbsent(
      taskId,
      () => UploadTaskInfo(
        taskId: taskId,
        task: update.task,
      ),
    );
    info.task = update.task;

    bool changed = false;

    if (update is TaskProgressUpdate) {
      final clamped = update.progress.clamp(0.0, 1.0).toDouble();
      if (info.progress != clamped) {
        info.progress = clamped;
        changed = true;
      }
    } else if (update is TaskStatusUpdate) {
      if (info.status != update.status) {
        info.status = update.status;
        changed = true;
      }
      if (update.status.isFinalState) {
        _activeUploads.remove(taskId);
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _updatesSubscription?.cancel();
    _processingClearTimer?.cancel();
    _processingClearTimer = null;
    _processingStatus = null;
    _uploadService.dispose();
    _uploadService.onPendingPostCreated = null;
    _uploadService.onPostStatusUpdated = null;
    _uploadService.onFeedRefreshRequested = null;
    _uploadService.onVideoProcessingUpdate = null;
    super.dispose();
  }

  void _handlePendingPostCreated(PostItem post) {
    final index =
        _pendingPosts.indexWhere((existing) => existing.id == post.id);
    if (index >= 0) {
      _pendingPosts[index] = post;
    } else {
      _pendingPosts.insert(0, post);
    }
    notifyListeners();
  }

  void _handlePostStatusUpdated(PostItem post) {
    final index =
        _pendingPosts.indexWhere((existing) => existing.id == post.id);
    final isReady = post.isReady;
    if (isReady) {
      if (index >= 0) {
        _pendingPosts.removeAt(index);
        notifyListeners();
      }
      return;
    }
    if (index >= 0) {
      _pendingPosts[index] = post;
    } else {
      _pendingPosts.insert(0, post);
    }
    notifyListeners();
  }

  void removePendingPostsByIds(Iterable<String> ids) {
    final idSet = ids.toSet();
    if (idSet.isEmpty) {
      return;
    }
    final beforeLength = _pendingPosts.length;
    _pendingPosts.removeWhere((post) => idSet.contains(post.id));
    if (_pendingPosts.length != beforeLength) {
      notifyListeners();
    }
  }

  void _handleProcessingUpdate(VideoProcessingUpdate update) {
    if (!update.isVideo) {
      return;
    }
    _processingClearTimer?.cancel();
    _processingStatus = update;
    notifyListeners();
    if (update.phase == VideoProcessingPhase.ready ||
        update.phase == VideoProcessingPhase.failed) {
      _processingClearTimer = Timer(_processingDismissDelay, () {
        if (_processingStatus == update) {
          _processingStatus = null;
          notifyListeners();
        }
      });
    }
  }

  Future<void> cancelUpload(String taskId) async {
    try {
      await _uploadService.cancelTusUpload(taskId);
    } finally {
      _activeUploads.remove(taskId);
      notifyListeners();
    }
  }
}

class UploadTaskInfo {
  UploadTaskInfo({
    required this.taskId,
    this.task,
    this.progress = 0,
    this.status,
  });

  final String taskId;
  Task? task;
  double progress;
  TaskStatus? status;

  bool get isFinal => status?.isFinalState ?? false;
}
