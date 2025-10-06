import 'dart:io';

import 'package:background_downloader/background_downloader.dart';

import '../models/post_draft.dart';
import 'api_client.dart';

class UploadStartResult {
  const UploadStartResult({required this.postId, required this.taskId});

  final String postId;
  final String taskId;
}

class UploadService {
  UploadService({ApiClient? apiClient, FileDownloader? downloader})
      : _apiClient = apiClient ?? ApiClient(),
        _downloader = downloader ?? FileDownloader();

  final ApiClient _apiClient;
  final FileDownloader _downloader;
  final Map<String, Task> _trackedTasks = {};

  Stream<TaskUpdate> get updates => _downloader.updates;

  Future<UploadStartResult> startUpload({
    required PostDraft draft,
    required String description,
  }) async {
    final file = File(draft.originalFilePath);
    if (!await file.exists()) {
      throw const FileSystemException('Original file for upload not found');
    }

    final fileSize = await file.length();
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'upload';

    final assumedContentType = draft.type == 'image'
        ? 'image/jpeg'
        : 'video/mp4';

    final createResponse = await _apiClient.createUpload(
      type: draft.type,
      fileName: fileName,
      fileSize: fileSize,
      contentType: assumedContentType,
    );

    final taskId = createResponse.taskId ?? createResponse.postId;

    final String httpMethod = createResponse.method;

    final UploadTask task = createResponse.requiresMultipart
        ? UploadTask.fromFile(
            taskId: taskId,
            file: file,
            url: createResponse.uploadUrl,
            httpRequestMethod: httpMethod,
            headers: createResponse.headers,
            fields: createResponse.fields,
            fileField: createResponse.fileFieldName ?? 'file',
            mimeType: createResponse.contentType ?? assumedContentType,
            updates: Updates.statusAndProgress,
          )
        : UploadTask.fromFile(
            taskId: taskId,
            file: file,
            url: createResponse.uploadUrl,
            httpRequestMethod: httpMethod,
            post: 'binary',
            headers: {
              HttpHeaders.contentTypeHeader:
                  createResponse.contentType ?? assumedContentType,
              ...createResponse.headers,
            },
            mimeType: createResponse.contentType ?? assumedContentType,
            updates: Updates.statusAndProgress,
          );

    final enqueued = await _downloader.enqueue(task);
    if (!enqueued) {
      throw const FileSystemException('Failed to enqueue upload task');
    }

    _trackedTasks[task.taskId] = task;

    await _apiClient.postMetadata(
      postId: createResponse.postId,
      type: draft.type,
      description: description.trim(),
      trim: draft.videoTrim,
      coverFrameMs: draft.coverFrameMs,
      imageCrop: draft.imageCrop,
    );

    return UploadStartResult(postId: createResponse.postId, taskId: task.taskId);
  }

  Future<void> retryTask(String taskId) async {
    Task? task = _trackedTasks[taskId];
    task ??= await _downloader.taskForId(taskId);
    task ??= await _downloader.database.recordForId(taskId).then((record) => record?.task);

    if (task == null) {
      throw const FileSystemException('Upload task not found for retry');
    }

    final enqueued = await _downloader.enqueue(task);
    if (!enqueued) {
      throw const FileSystemException('Failed to enqueue upload task');
    }
  }
}
