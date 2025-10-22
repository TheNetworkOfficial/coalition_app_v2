import 'dart:async';

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

  String? _currentTaskId;
  double? _progress;
  TaskStatus? _status;
  final List<PostItem> _pendingPosts = <PostItem>[];
  VideoProcessingUpdate? _processingStatus;
  Timer? _processingClearTimer;

  static const Duration _processingDismissDelay = Duration(seconds: 6);

  bool get hasActiveUpload => _currentTaskId != null;
  double? get progress => _progress;
  TaskStatus? get status => _status;
  String? get currentTaskId => _currentTaskId;
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
    _currentTaskId = _uploadService.lastStartedTaskId;
    if (_currentTaskId != null) {
      _progress = 0;
      _status = null;
      notifyListeners();
    }
    final outcome = await future;
    return outcome;
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
        notifyListeners();
        if (_clearCurrentUpload()) {
          notifyListeners();
        }
      } else {
        notifyListeners();
      }
    }
  }

  bool _clearCurrentUpload() {
    final hasChanges = _currentTaskId != null || _progress != null || _status != null;
    _currentTaskId = null;
    _progress = null;
    _status = null;
    return hasChanges;
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
    final index = _pendingPosts.indexWhere((existing) => existing.id == post.id);
    if (index >= 0) {
      _pendingPosts[index] = post;
    } else {
      _pendingPosts.insert(0, post);
    }
    notifyListeners();
  }

  void _handlePostStatusUpdated(PostItem post) {
    final index = _pendingPosts.indexWhere((existing) => existing.id == post.id);
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
}
