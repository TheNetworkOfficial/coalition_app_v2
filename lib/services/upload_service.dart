import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../env.dart';
import '../models/create_upload_response.dart';
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

    debugPrint(
      '[UploadService] starting createUpload() against $normalizedApiBaseUrl',
    );
    final CreateUploadResponse create;
    try {
      create = await _apiClient.createUpload(
        type: draft.type,
        fileName: fileName,
        fileSize: fileSize,
        contentType: assumedContentType,
      );
    } on FormatException catch (error, stackTrace) {
      debugPrint('[UploadService] createUpload parse error: $error\n$stackTrace');
      rethrow;
    }

    final method = create.method.toUpperCase();
    final bool isDirectPost = method == 'POST';
    if (isDirectPost) {
      debugPrint('[UploadService] using direct POST upload for asset ${create.uid}');
      if (create.requiresMultipart) {
        await _performDirectMultipartUpload(
          file: file,
          create: create,
          fallbackContentType: assumedContentType,
        );
      } else {
        await _performDirectBinaryUpload(
          file: file,
          create: create,
          fallbackContentType: assumedContentType,
        );
      }

      await _apiClient.postMetadata(
        postId: create.uid,
        type: draft.type,
        description: description.trim(),
        trim: draft.videoTrim,
        coverFrameMs: draft.coverFrameMs,
        imageCrop: draft.imageCrop,
      );

      return UploadStartResult(postId: create.uid, taskId: create.uid);
    }

    final taskId = create.taskId ?? create.uid;

    final UploadTask task = create.requiresMultipart
        ? UploadTask.fromFile(
            taskId: taskId,
            file: file,
            url: create.uploadUrl.toString(),
            httpRequestMethod: method,
            headers: create.headers,
            fields: create.fields,
            fileField: create.fileFieldName ?? 'file',
            mimeType: create.contentType ?? assumedContentType,
            updates: Updates.statusAndProgress,
          )
        : UploadTask.fromFile(
            taskId: taskId,
            file: file,
            url: create.uploadUrl.toString(),
            httpRequestMethod: method,
            post: 'binary',
            headers: {
              HttpHeaders.contentTypeHeader:
                  create.contentType ?? assumedContentType,
              ...create.headers,
            },
            mimeType: create.contentType ?? assumedContentType,
            updates: Updates.statusAndProgress,
          );

    final enqueued = await _downloader.enqueue(task);
    if (!enqueued) {
      throw const FileSystemException('Failed to enqueue upload task');
    }

    _trackedTasks[task.taskId] = task;

    await _apiClient.postMetadata(
      postId: create.uid,
      type: draft.type,
      description: description.trim(),
      trim: draft.videoTrim,
      coverFrameMs: draft.coverFrameMs,
      imageCrop: draft.imageCrop,
    );

    return UploadStartResult(postId: create.uid, taskId: task.taskId);
  }

  Future<void> _performDirectMultipartUpload({
    required File file,
    required CreateUploadResponse create,
    required String fallbackContentType,
  }) async {
    final request = http.MultipartRequest('POST', create.uploadUrl);
    if (create.headers.isNotEmpty) {
      create.headers.forEach((key, value) {
        if (key.toLowerCase() == HttpHeaders.contentTypeHeader) {
          return;
        }
        request.headers[key] = value;
      });
    }
    if (create.fields.isNotEmpty) {
      request.fields.addAll(create.fields);
    }

    final resolvedContentType =
        _resolveMediaType(create.contentType, fallbackContentType);

    request.files.add(
      await http.MultipartFile.fromPath(
        create.fileFieldName ?? 'file',
        file.path,
        contentType: resolvedContentType,
      ),
    );

    final streamed = await request.send();
    final status = streamed.statusCode;
    if (status < 200 || status >= 300) {
      final body = await streamed.stream.bytesToString();
      throw ApiException(
        'Direct upload failed',
        statusCode: status,
        details: body.isEmpty ? null : body,
      );
    }
    debugPrint('[UploadService] direct upload completed for asset ${create.uid} (status $status)');
    await streamed.stream.drain();
  }

  Future<void> _performDirectBinaryUpload({
    required File file,
    required CreateUploadResponse create,
    required String fallbackContentType,
  }) async {
    final bytes = await file.readAsBytes();
    final resolvedContentType = (create.contentType != null && create.contentType!.trim().isNotEmpty)
        ? create.contentType!.trim()
        : fallbackContentType;
    final headers = <String, String>{};
    if (create.headers.isNotEmpty) {
      headers.addAll(create.headers);
    }
    headers[HttpHeaders.contentTypeHeader] = resolvedContentType;

    final response = await http.post(
      create.uploadUrl,
      headers: headers,
      body: bytes,
    );

    final status = response.statusCode;
    if (status < 200 || status >= 300) {
      throw ApiException(
        'Direct upload failed',
        statusCode: status,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    debugPrint('[UploadService] direct upload completed for asset ${create.uid} (status $status)');
  }

  MediaType _resolveMediaType(String? provided, String fallback) {
    final candidate = (provided != null && provided.trim().isNotEmpty)
        ? provided.trim()
        : fallback;
    try {
      return MediaType.parse(candidate);
    } catch (_) {
      final parts = candidate.split('/');
      if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        return MediaType(parts[0], parts[1]);
      }
    }
    return MediaType('application', 'octet-stream');
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
