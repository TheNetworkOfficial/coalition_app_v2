import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart' show CancelToken, DioException, DioExceptionType;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;

import '../env.dart';
import '../models/create_upload_response.dart';
import '../models/post_draft.dart';
import 'api_client.dart';
import 'tus_uploader.dart';

class UploadStartResult {
  const UploadStartResult({required this.postId, required this.taskId});

  final String postId;
  final String taskId;
}

class UploadService {
  UploadService({
    ApiClient? apiClient,
    FileDownloader? downloader,
    TusUploader? tusUploader,
  })  : _apiClient = apiClient ?? ApiClient(),
        _downloader = downloader ?? FileDownloader(),
        _tusUploader = tusUploader ?? TusUploader(),
        _updatesController = StreamController<TaskUpdate>.broadcast() {
    _downloaderSubscription = _downloader.updates.listen(_updatesController.add);
  }

  final ApiClient _apiClient;
  final FileDownloader _downloader;
  final TusUploader _tusUploader;
  final StreamController<TaskUpdate> _updatesController;
  StreamSubscription<TaskUpdate>? _downloaderSubscription;
  final Map<String, Task> _trackedTasks = {};
  final Map<String, _TusUploadState> _tusUploads = {};

  Stream<TaskUpdate> get updates => _updatesController.stream;

  void dispose() {
    _downloaderSubscription?.cancel();
    for (final entry in _tusUploads.values) {
      entry.cancelToken?.cancel('dispose');
    }
    _tusUploads.clear();
    _updatesController.close();
  }

  Future<UploadStartResult> startUpload({
    required PostDraft draft,
    required String description,
  }) async {
    final file = File(draft.originalFilePath);
    if (!await file.exists()) {
      throw const FileSystemException('Original file for upload not found');
    }

    final fileSize = await file.length();
    final resolvedFileName = p.basename(file.path);
    final fileName = (resolvedFileName.isEmpty || resolvedFileName == '.')
        ? 'upload'
        : resolvedFileName;

    final assumedContentType = draft.type == 'image'
        ? 'image/jpeg'
        : 'video/mp4';

    debugPrint(
      '[UploadService] starting createUpload() against $normalizedApiBaseUrl',
    );
    final CreateUploadResult createResult;
    try {
      createResult = await _apiClient.createUpload(
        type: draft.type,
        fileName: fileName,
        fileSize: fileSize,
        contentType: assumedContentType,
      );
    } on FormatException catch (error, stackTrace) {
      debugPrint('[UploadService] createUpload parse error: $error\n$stackTrace');
      rethrow;
    }

    final create = createResult.response;
    final rawUploadJson = createResult.rawJson;

    String? asNonEmptyString(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      return null;
    }

    Map<String, String> parseStringMap(dynamic value) {
      if (value is Map) {
        final result = <String, String>{};
        value.forEach((dynamic key, dynamic val) {
          if (key is String && val != null) {
            final stringValue = asNonEmptyString(val) ?? val.toString();
            result[key] = stringValue;
          }
        });
        return result;
      }
      return <String, String>{};
    }

    final dynamic tusInfoRaw = rawUploadJson['tusInfo'];
    final String? tusUrlFromInfo =
        tusInfoRaw is Map ? asNonEmptyString(tusInfoRaw['endpoint']) : null;
    final String? tusUrl = tusUrlFromInfo ?? asNonEmptyString(rawUploadJson['tusUploadUrl']);

    Uri? tusEndpoint;
    if (tusUrl != null) {
      final candidate = Uri.tryParse(tusUrl);
      if (candidate != null && candidate.hasScheme && candidate.host.isNotEmpty) {
        tusEndpoint = candidate;
      } else {
        debugPrint('[UploadService] Ignoring invalid TUS URL: $tusUrl');
      }
    }

    final Map<String, String> tusHeaders = parseStringMap(
      tusInfoRaw is Map ? tusInfoRaw['headers'] : null,
    );
    final hasTusResumable = tusHeaders.keys.any(
      (key) => key.toLowerCase() == 'tus-resumable',
    );
    if (!hasTusResumable) {
      tusHeaders['Tus-Resumable'] = '1.0.0';
    }

    final shouldUseTus = tusEndpoint != null && draft.type == 'video';
    if (shouldUseTus) {
      debugPrint('[UploadService] Using TUS endpoint: ${tusEndpoint.toString()}');
      return _startTusUpload(
        draft: draft,
        description: description,
        file: file,
        fileName: fileName,
        fileSize: fileSize,
        contentType: assumedContentType,
        create: create,
        tusEndpoint: tusEndpoint,
        tusHeaders: tusHeaders,
      );
    }

    debugPrint('[UploadService] Using legacy direct upload: ${create.uploadUrl}');

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
        fileName: fileName,
        fileSize: fileSize,
        contentType: assumedContentType,
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
      fileName: fileName,
      fileSize: fileSize,
      contentType: assumedContentType,
      trim: draft.videoTrim,
      coverFrameMs: draft.coverFrameMs,
      imageCrop: draft.imageCrop,
    );

    return UploadStartResult(postId: create.uid, taskId: task.taskId);
  }

  UploadTask _createSyntheticTusTask({
    required String taskId,
    required File file,
    required Uri tusEndpoint,
    required String contentType,
  }) {
    return UploadTask.fromFile(
      taskId: taskId,
      file: file,
      url: tusEndpoint.toString(),
      httpRequestMethod: 'PATCH',
      post: 'binary',
      headers: const {
        HttpHeaders.contentTypeHeader: 'application/offset+octet-stream',
        'Tus-Resumable': '1.0.0',
      },
      mimeType: contentType,
      updates: Updates.statusAndProgress,
    );
  }

  Future<UploadStartResult> _startTusUpload({
    required PostDraft draft,
    required String description,
    required File file,
    required String fileName,
    required int fileSize,
    required String contentType,
    required CreateUploadResponse create,
    required Uri tusEndpoint,
    required Map<String, String> tusHeaders,
  }) async {
    final taskId = create.taskId ?? create.uid;
    final task = _createSyntheticTusTask(
      taskId: taskId,
      file: file,
      tusEndpoint: tusEndpoint,
      contentType: contentType,
    );

    _trackedTasks[taskId] = task;

    final state = _TusUploadState(
      task: task,
      file: file,
      fileName: fileName,
      fileSize: fileSize,
      contentType: contentType,
      tusEndpoint: tusEndpoint,
      tusHeaders: tusHeaders,
      response: create,
      draft: draft,
      description: description.trim(),
    );
    _tusUploads[taskId] = state;

    state.lastProgress = 0;
    _emitProgress(task, 0);

    _startTusTransfer(state);

    return UploadStartResult(postId: create.uid, taskId: taskId);
  }

  void _startTusTransfer(_TusUploadState state) {
    if (state.isUploading) {
      return;
    }
    state.isPaused = false;
    state.lastError = null;
    final existingProgress = state.lastProgress;
    if (existingProgress > 0) {
      _emitProgress(state.task, existingProgress);
    }
    state.isUploading = true;
    final cancelToken = CancelToken();
    state.cancelToken = cancelToken;
    _emitStatus(state.task, TaskStatus.running);

    unawaited(() async {
      try {
        await _tusUploader.uploadFile(
          file: state.file,
          tusUploadUrl: state.tusEndpoint.toString(),
          chunkSize: state.chunkSize,
          cancelToken: cancelToken,
          headers: state.tusHeaders,
          onProgress: (sent, total) {
            if (total <= 0) {
              state.lastProgress = 0;
              _emitProgress(state.task, 0);
              return;
            }
            final fraction = (sent / total).clamp(0.0, 1.0);
            state.lastProgress = fraction;
            _emitProgress(state.task, fraction);
          },
        );
        state.lastProgress = 1;
        _emitProgress(state.task, 1);
        await _apiClient.postMetadata(
          postId: state.response.uid,
          type: state.draft.type,
          description: state.description,
          fileName: state.fileName,
          fileSize: state.fileSize,
          contentType: state.contentType,
          trim: state.draft.videoTrim,
          coverFrameMs: state.draft.coverFrameMs,
          imageCrop: state.draft.imageCrop,
        );
        _emitStatus(state.task, TaskStatus.complete);
        _tusUploads.remove(state.task.taskId);
        _trackedTasks.remove(state.task.taskId);
      } on DioException catch (dioError, stackTrace) {
        if (dioError.type == DioExceptionType.cancel) {
          if (state.isPaused) {
            debugPrint(
              '[UploadService] TUS upload paused for ${state.response.uid}',
            );
            _emitStatus(state.task, TaskStatus.paused);
          } else {
            debugPrint(
              '[UploadService] TUS upload canceled for ${state.response.uid}',
            );
            _emitStatus(state.task, TaskStatus.canceled);
          }
        } else {
          debugPrint(
            '[UploadService] TUS upload Dio failure for ${state.response.uid}: $dioError\n$stackTrace',
          );
          _emitStatus(state.task, TaskStatus.failed);
          state.lastError = dioError;
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[UploadService] TUS upload failed for ${state.response.uid}: $error\n$stackTrace',
        );
        _emitStatus(state.task, TaskStatus.failed);
        state.lastError = error;
      } finally {
        state.isUploading = false;
        state.cancelToken = null;
      }
    }());
  }

  void _emitStatus(Task task, TaskStatus status) {
    if (_updatesController.isClosed) {
      return;
    }
    _updatesController.add(TaskStatusUpdate(task, status));
  }

  void _emitProgress(Task task, double progress) {
    if (_updatesController.isClosed) {
      return;
    }
    final normalized = progress.clamp(0.0, 1.0);
    _updatesController.add(TaskProgressUpdate(task, normalized));
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
    final tusState = _tusUploads[taskId];
    if (tusState != null) {
      if (tusState.isUploading) {
        tusState.isPaused = false;
        tusState.cancelToken?.cancel('retry');
        while (tusState.isUploading) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      tusState.lastError = null;
      _startTusTransfer(tusState);
      return;
    }

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

  Future<void> pauseTusUpload(String taskId) async {
    final state = _tusUploads[taskId];
    if (state == null || !state.isUploading) {
      return;
    }
    state.isPaused = true;
    state.cancelToken?.cancel('pause');
    while (state.isUploading) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> resumeTusUpload(String taskId) async {
    final state = _tusUploads[taskId];
    if (state == null || state.isUploading) {
      return;
    }
    state.isPaused = false;
    _startTusTransfer(state);
  }
}

class _TusUploadState {
  _TusUploadState({
    required this.task,
    required this.file,
    required this.fileName,
    required this.fileSize,
    required this.contentType,
    required this.tusEndpoint,
    required Map<String, String> tusHeaders,
    required this.response,
    required this.draft,
    required this.description,
    this.chunkSize = 5 * 1024 * 1024,
  }) : tusHeaders = Map.unmodifiable(Map<String, String>.from(tusHeaders));

  final UploadTask task;
  final File file;
  final String fileName;
  final int fileSize;
  final String contentType;
  final Uri tusEndpoint;
  final Map<String, String> tusHeaders;
  final CreateUploadResponse response;
  final PostDraft draft;
  final String description;
  final int chunkSize;
  CancelToken? cancelToken;
  bool isUploading = false;
  bool isPaused = false;
  Object? lastError;
  double lastProgress = 0.0;
}
