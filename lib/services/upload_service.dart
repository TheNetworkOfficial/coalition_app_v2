import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart' show CancelToken, DioException, DioExceptionType;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../env.dart';
import '../models/create_upload_response.dart';
import '../models/post_draft.dart';
import '../models/upload_outcome.dart';
import 'api_client.dart';
import 'tus_uploader.dart';

typedef UserIdResolver = FutureOr<String> Function();

class UploadService {
  UploadService({
    ApiClient? apiClient,
    TusUploader? tusUploader,
    UserIdResolver? userIdResolver,
  })  : _apiClient = apiClient ?? ApiClient(),
        _tusUploader = tusUploader ?? TusUploader(),
        _userIdResolver = userIdResolver,
        _updatesController = StreamController<TaskUpdate>.broadcast();

  final ApiClient _apiClient;
  final TusUploader _tusUploader;
  final UserIdResolver? _userIdResolver;
  final StreamController<TaskUpdate> _updatesController;
  final Map<String, _TusUploadState> _tusUploads = {};
  String? _cachedUserId;

  static const String _fallbackUserId = 'local-user';

  VoidCallback? onFeedRefreshRequested;
  String? _lastStartedTaskId;

  String? get lastStartedTaskId => _lastStartedTaskId;

  Stream<TaskUpdate> get updates => _updatesController.stream;

  void dispose() {
    for (final state in _tusUploads.values) {
      state.cancelToken?.cancel('dispose');
      if (!state.completer.isCompleted) {
        state.completer.complete(
          UploadOutcome(
            ok: false,
            uploadId: state.response.uid,
            message: 'Upload canceled',
          ),
        );
      }
    }
    _tusUploads.clear();
    _updatesController.close();
  }

  Future<UploadOutcome> startUpload({
    required PostDraft draft,
    required String description,
    VoidCallback? onFeedRefreshRequested,
  }) async {
    final file = File(draft.originalFilePath);
    if (!await file.exists()) {
      const message = 'Original file for upload not found';
      debugPrint('[UploadService] $message');
      return const UploadOutcome(ok: false, message: message);
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
    } on ApiException catch (error) {
      debugPrint(
        '[UploadService] createUpload failed: ${error.message} (status=${error.statusCode ?? 'unknown'})',
      );
      return UploadOutcome(
        ok: false,
        message: error.message,
        statusCode: error.statusCode,
      );
    } on FormatException catch (error, stackTrace) {
      debugPrint('[UploadService] createUpload parse error: $error\n$stackTrace');
      return UploadOutcome(ok: false, message: error.toString());
    } catch (error, stackTrace) {
      debugPrint('[UploadService] createUpload unexpected error: $error\n$stackTrace');
      return UploadOutcome(ok: false, message: error.toString());
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

    final feedRefreshCallback =
        onFeedRefreshRequested ?? this.onFeedRefreshRequested;

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
        feedRefreshCallback: feedRefreshCallback,
      );
    }

    debugPrint('[UploadService] Using legacy direct upload: ${create.uploadUrl}');
    return _startDirectUpload(
      draft: draft,
      description: description,
      file: file,
      fileName: fileName,
      fileSize: fileSize,
      contentType: assumedContentType,
      create: create,
      feedRefreshCallback: feedRefreshCallback,
    );
  }

  Future<UploadOutcome> _startDirectUpload({
    required PostDraft draft,
    required String description,
    required File file,
    required String fileName,
    required int fileSize,
    required String contentType,
    required CreateUploadResponse create,
    required VoidCallback? feedRefreshCallback,
  }) async {
    final taskId = create.taskId ?? create.uid;
    final task = UploadTask.fromFile(
      taskId: taskId,
      file: file,
      url: create.uploadUrl.toString(),
      httpRequestMethod: create.method,
      headers: create.headers,
      fields: create.fields,
      fileField: create.fileFieldName ?? 'file',
      mimeType: create.contentType ?? contentType,
      updates: Updates.statusAndProgress,
    );

    _lastStartedTaskId = taskId;
    _emitStatus(task, TaskStatus.running);
    _emitProgress(task, 0);

    try {
      if (create.requiresMultipart) {
        await _performDirectMultipartUpload(
          file: file,
          create: create,
          fallbackContentType: contentType,
        );
      } else {
        await _performDirectBinaryUpload(
          file: file,
          create: create,
          fallbackContentType: contentType,
        );
      }

      _emitProgress(task, 1);

      await _apiClient.postMetadata(
        postId: create.uid,
        type: draft.type,
        description: description.trim(),
        fileName: fileName,
        fileSize: fileSize,
        contentType: contentType,
        trim: draft.videoTrim,
        coverFrameMs: draft.coverFrameMs,
        imageCrop: draft.imageCrop,
      );

      final outcome = await _finalizePostUpload(
        type: draft.type,
        uploadId: create.uid,
        description: description,
        feedRefreshCallback: feedRefreshCallback,
      );

      if (outcome.ok) {
        _emitStatus(task, TaskStatus.complete);
      } else {
        _emitStatus(task, TaskStatus.failed);
      }
      return outcome;
    } catch (error, stackTrace) {
      final failure = _mapFailure(error, uploadId: create.uid);
      debugPrint('[UploadService] direct upload failed: $error\n$stackTrace');
      _emitStatus(task, TaskStatus.failed);
      return failure;
    }
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

  Future<UploadOutcome> _startTusUpload({
    required PostDraft draft,
    required String description,
    required File file,
    required String fileName,
    required int fileSize,
    required String contentType,
    required CreateUploadResponse create,
    required Uri tusEndpoint,
    required Map<String, String> tusHeaders,
    required VoidCallback? feedRefreshCallback,
  }) {
    final taskId = create.taskId ?? create.uid;
    final task = _createSyntheticTusTask(
      taskId: taskId,
      file: file,
      tusEndpoint: tusEndpoint,
      contentType: contentType,
    );

    _lastStartedTaskId = taskId;

    final completer = Completer<UploadOutcome>();
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
      completer: completer,
      feedRefreshCallback: feedRefreshCallback,
    );
    _tusUploads[taskId] = state;

    state.lastProgress = 0;
    _emitProgress(task, 0);

    _startTusTransfer(state);

    return completer.future;
  }

  void _startTusTransfer(_TusUploadState state) {
    if (state.isUploading) {
      return;
    }
    state.isPaused = false;
    final existingProgress = state.lastProgress;
    if (existingProgress > 0) {
      _emitProgress(state.task, existingProgress);
    }
    state.isUploading = true;
    final cancelToken = CancelToken();
    state.cancelToken = cancelToken;
    _emitStatus(state.task, TaskStatus.running);

    unawaited(() async {
      UploadOutcome? outcome;
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
        outcome = await _finalizePostUpload(
          type: state.draft.type,
          uploadId: state.response.uid,
          description: state.description,
          feedRefreshCallback: state.feedRefreshCallback,
        );
        if (outcome.ok) {
          _emitStatus(state.task, TaskStatus.complete);
        } else {
          _emitStatus(state.task, TaskStatus.failed);
        }
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
            outcome = UploadOutcome(
              ok: false,
              uploadId: state.response.uid,
              message: 'Upload canceled',
            );
          }
        } else {
          debugPrint(
            '[UploadService] TUS upload Dio failure for ${state.response.uid}: $dioError\n$stackTrace',
          );
          _emitStatus(state.task, TaskStatus.failed);
          outcome = UploadOutcome(
            ok: false,
            uploadId: state.response.uid,
            message: dioError.message ?? dioError.toString(),
            statusCode: dioError.response?.statusCode,
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[UploadService] TUS upload failed for ${state.response.uid}: $error\n$stackTrace',
        );
        _emitStatus(state.task, TaskStatus.failed);
        outcome = _mapFailure(error, uploadId: state.response.uid);
      } finally {
        state.isUploading = false;
        state.cancelToken = null;
        if (outcome != null) {
          _completeTusState(state, outcome);
        }
      }
    }());
  }

  void _completeTusState(_TusUploadState state, UploadOutcome outcome) {
    final taskId = state.task.taskId;
    final tracked = _tusUploads.remove(taskId);
    if (tracked != null && !tracked.completer.isCompleted) {
      tracked.completer.complete(outcome);
    }
  }

  Future<UploadOutcome> _finalizePostUpload({
    required String type,
    required String uploadId,
    required String description,
    required VoidCallback? feedRefreshCallback,
  }) async {
    final trimmedDescription = description.trim();
    final hasDescription = trimmedDescription.isNotEmpty;
    final effectiveDescription = hasDescription ? trimmedDescription : null;
    final userId = await _resolveUserId();
    final String postId = const Uuid().v4();

    const maxAttempts = 3;
    int attempt = 0;

    while (attempt < maxAttempts) {
      attempt += 1;
      try {
        final response = await _apiClient.createPost(
          postId: postId,
          userId: userId,
          type: type,
          uploadId: uploadId,
          description: effectiveDescription,
        );
        final status = _apiClient.lastCreatePostStatusCode;
        debugPrint(
          '[UploadService] finalize createPost: {type: $type, uploadId: $uploadId, hasDescription: $hasDescription, userId: $userId} -> status=${status ?? 'unknown'}',
        );
        await _notifyFeedRefreshRequested(feedRefreshCallback);
        final resolvedPostId = _extractPostId(response) ?? postId;
        return UploadOutcome(
          ok: true,
          postId: resolvedPostId,
          uploadId: uploadId,
          statusCode: status,
        );
      } on ApiException catch (error) {
        final status = error.statusCode;
        if (status == 409) {
          debugPrint(
            '[UploadService] finalize createPost: {type: $type, uploadId: $uploadId, hasDescription: $hasDescription, userId: $userId} -> status=409 (conflict treated as success)',
          );
          await _notifyFeedRefreshRequested(feedRefreshCallback);
          return UploadOutcome(
            ok: true,
            postId: postId,
            uploadId: uploadId,
            statusCode: status,
            message: error.message,
          );
        }

        final shouldRetry = status == null || status >= 500;
        if (shouldRetry && attempt < maxAttempts) {
          await Future<void>.delayed(_retryDelay(attempt));
          continue;
        }
        final statusString = status ?? 'unknown';
        debugPrint(
          '[UploadService] finalize error: ${error.message} (status=$statusString)',
        );
        return UploadOutcome(
          ok: false,
          uploadId: uploadId,
          message: error.message,
          statusCode: status,
        );
      } catch (error, stackTrace) {
        if (attempt < maxAttempts) {
          await Future<void>.delayed(_retryDelay(attempt));
          continue;
        }
        debugPrint(
          '[UploadService] finalize error: $error (status=unknown)\n$stackTrace',
        );
        return UploadOutcome(
          ok: false,
          uploadId: uploadId,
          message: error.toString(),
        );
      }
    }

    return UploadOutcome(
      ok: false,
      uploadId: uploadId,
      message: 'Failed to finalize upload',
    );
  }

  Future<void> _notifyFeedRefreshRequested(VoidCallback? callback) async {
    if (callback != null) {
      try {
        callback();
      } catch (error, stackTrace) {
        debugPrint(
          '[UploadService] feed refresh callback threw: $error\n$stackTrace',
        );
      }
    }
    debugPrint('[UploadService] finalize success -> requested feed refresh');
  }

  UploadOutcome _mapFailure(Object error, {String? uploadId}) {
    if (error is ApiException) {
      return UploadOutcome(
        ok: false,
        uploadId: uploadId,
        message: error.message,
        statusCode: error.statusCode,
      );
    }
    if (error is IOException) {
      return UploadOutcome(
        ok: false,
        uploadId: uploadId,
        message: error.toString(),
      );
    }
    return UploadOutcome(
      ok: false,
      uploadId: uploadId,
      message: error.toString(),
    );
  }

  Future<String> _resolveUserId() async {
    final cached = _cachedUserId;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final resolver = _userIdResolver;
    if (resolver != null) {
      try {
        final resolved = await Future<String>.value(resolver());
        final trimmed = resolved.trim();
        if (trimmed.isNotEmpty) {
          _cachedUserId = trimmed;
          return trimmed;
        }
      } catch (error, stackTrace) {
        debugPrint('[UploadService] userId resolver failed: $error\n$stackTrace');
      }
    }

    _cachedUserId = _fallbackUserId;
    return _fallbackUserId;
  }

  Duration _retryDelay(int attempt) {
    if (attempt <= 1) {
      return const Duration(milliseconds: 300);
    }
    if (attempt == 2) {
      return const Duration(milliseconds: 1000);
    }
    return const Duration(milliseconds: 3000);
  }

  String? _extractPostId(Map<String, dynamic> response) {
    if (response.containsKey('postId')) {
      final value = response['postId'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    if (response.containsKey('id')) {
      final value = response['id'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
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
    required this.completer,
    required this.feedRefreshCallback,
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
  final Completer<UploadOutcome> completer;
  final VoidCallback? feedRefreshCallback;
  final int chunkSize;
  CancelToken? cancelToken;
  bool isUploading = false;
  bool isPaused = false;
  double lastProgress = 0.0;
}
