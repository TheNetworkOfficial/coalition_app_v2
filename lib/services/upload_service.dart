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

    final Task task;
    if (createResponse.requiresMultipart) {
      task = MultipartUploadTask(
        taskId: taskId,
        url: createResponse.uploadUrl,
        files: [
          MultipartFile(
            fieldName: createResponse.fileFieldName ?? 'file',
            filePath: file.path,
            filename: fileName,
            contentType: createResponse.contentType ?? assumedContentType,
          ),
        ],
        fields: createResponse.fields,
        method: createResponse.method,
        headers: createResponse.headers,
      );
    } else {
      task = UploadTask(
        taskId: taskId,
        url: createResponse.uploadUrl,
        filename: fileName,
        filePath: file.path,
        method: createResponse.method,
        headers: {
          HttpHeaders.contentTypeHeader:
              createResponse.contentType ?? assumedContentType,
          ...createResponse.headers,
        },
      );
    }

    final enqueued = await _downloader.enqueue(task);
    if (!enqueued) {
      throw const FileSystemException('Failed to enqueue upload task');
    }

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

  Future<void> retryTask(String taskId) => _downloader.retryTaskWithId(taskId);
}
