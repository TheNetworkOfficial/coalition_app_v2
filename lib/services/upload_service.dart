import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:background_downloader/background_downloader.dart';
import 'package:dio/dio.dart' show CancelToken, DioException, DioExceptionType;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import '../env.dart';
import '../models/create_upload_response.dart';
import '../models/post_draft.dart';
import '../models/upload_outcome.dart';
import '../models/posts_page.dart';
import 'api_client.dart';
import 'tus_uploader.dart';

const int _kDefaultTusChunkSizeBytes = 5 * 1024 * 1024; // 5 MB default TUS chunk size.

class UploadService {
  UploadService({
    ApiClient? apiClient,
    TusUploader? tusUploader,
  })  : _apiClient = apiClient ?? ApiClient(),
        _tusUploader = tusUploader ?? TusUploader(),
        _updatesController = StreamController<TaskUpdate>.broadcast();

  final ApiClient _apiClient;
  final TusUploader _tusUploader;
  final StreamController<TaskUpdate> _updatesController;
  final Map<String, _TusUploadState> _tusUploads = {};
  final Map<String, Future<UploadOutcome>> _finalizationInFlight = {};
  final Map<String, UploadOutcome> _finalizedOutcomes = {};
  final Map<String, Future<void>> _postReadyPolling = {};
  final Map<String, _PostReadyPoller> _postReadyControllers = {};
  final Map<String, PostItem> _pendingPostSnapshots = {};
  final Map<String, String> _postMediaTypes = {};

  static const Duration _postReadyPollInterval = Duration(seconds: 2);
  static const Duration _postReadyPollTimeout = Duration(minutes: 2);
  static const Duration _streamPollInitialDelay = Duration(seconds: 5);
  static const Duration _streamPollMaxDelay = Duration(seconds: 30);

  VoidCallback? onFeedRefreshRequested;
  ValueChanged<PostItem>? onPendingPostCreated;
  ValueChanged<PostItem>? onPostStatusUpdated;
  ValueChanged<VideoProcessingUpdate>? onVideoProcessingUpdate;
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
    _finalizationInFlight.clear();
    _finalizedOutcomes.clear();
    for (final controller in _postReadyControllers.values) {
      controller.cancel();
    }
    _postReadyControllers.clear();
    _pendingPostSnapshots.clear();
    _postMediaTypes.clear();
    _updatesController.close();
  }

  Future<UploadOutcome> startUpload({
    required PostDraft draft,
    required String description,
    VoidCallback? onFeedRefreshRequested,
  }) async {
    final preferProxy =
        draft.type == 'video' && draft.hasVideoProxy && kPreferVideoProxyUploads;
    var resolvedPath = draft.resolveUploadPath(preferProxy: preferProxy);
    var file = File(resolvedPath);
    if (!await file.exists() && preferProxy) {
      debugPrint('[UploadService] Proxy not found at $resolvedPath; using original file');
      resolvedPath = draft.resolveUploadPath(preferProxy: false);
      file = File(resolvedPath);
    }

    if (!await file.exists()) {
      debugPrint('[UploadService] Upload file missing at $resolvedPath');
      return const UploadOutcome(
        ok: false,
        message: 'Upload file not found',
      );
    }

    final fileSize = await file.length();
    final resolvedFileName = p.basename(resolvedPath);
    final fileName = (resolvedFileName.isEmpty || resolvedFileName == '.')
        ? 'upload'
        : resolvedFileName;

    if (preferProxy && resolvedPath == draft.proxyFilePath) {
      final resolution = draft.proxyMetadata?.resolution;
      debugPrint('[UploadService] Uploading proxy file (resolution=$resolution)');
    }

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

    int? asPositiveInt(dynamic value) {
      if (value is int) {
        return value > 0 ? value : null;
      }
      if (value is num) {
        final rounded = value.round();
        return rounded > 0 ? rounded : null;
      }
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty) {
          return null;
        }
        final parsed = int.tryParse(trimmed);
        if (parsed != null && parsed > 0) {
          return parsed;
        }
      }
      return null;
    }

    int? chunkSizeFromMap(Map<dynamic, dynamic>? source) {
      if (source == null || source.isEmpty) {
        return null;
      }
      const keys = <String>[
        'chunkSize',
        'chunk_size',
        'chunkSizeBytes',
        'chunk_size_bytes',
      ];
      for (final key in keys) {
        if (source.containsKey(key)) {
          final parsed = asPositiveInt(source[key]);
          if (parsed != null) {
            return parsed;
          }
        }
      }
      return null;
    }

    int resolveChunkSize(int? requestedBytes) {
      var chunkSize = requestedBytes ?? _kDefaultTusChunkSizeBytes;
      if (chunkSize <= 0) {
        chunkSize = _kDefaultTusChunkSizeBytes;
      }
      if (fileSize > 0 && chunkSize > fileSize) {
        chunkSize = fileSize;
      }
      return chunkSize;
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
      final chunkSizeHint =
          chunkSizeFromMap(tusInfoRaw is Map ? tusInfoRaw : null) ??
              chunkSizeFromMap(rawUploadJson);
      final resolvedChunkSize = resolveChunkSize(chunkSizeHint);
      debugPrint(
        '[UploadService] Using TUS endpoint: ${tusEndpoint.toString()} (chunkSize=$resolvedChunkSize'
        '${chunkSizeHint != null ? ', hinted=$chunkSizeHint' : ''})',
      );
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
        chunkSize: resolvedChunkSize,
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
      final trimmedDescription = description.trim();
      const visibility = 'public';
      final hasDescription = trimmedDescription.isNotEmpty;

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
        description: trimmedDescription,
        fileName: fileName,
        fileSize: fileSize,
        contentType: contentType,
        trim: draft.videoTrim,
        coverFrameMs: draft.coverFrameMs,
        imageCrop: draft.imageCrop,
      );

      debugPrint(
        '[UploadService] direct upload complete -> finalize createPost: '
        '{type: ${draft.type}, cfUid: ${create.uid}, hasDescription: $hasDescription, visibility: $visibility}',
      );

      final outcome = await _finalizePostUpload(
        type: draft.type,
        cfUid: create.uid,
        description: trimmedDescription,
        visibility: visibility,
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
    required int chunkSize,
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
      chunkSize: chunkSize,
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
        final trimmedDescription = state.description.trim();
        const visibility = 'public';
        final hasDescription = trimmedDescription.isNotEmpty;
        debugPrint(
          '[UploadService] TUS complete -> finalize createPost: '
          '{type: ${state.draft.type}, cfUid: ${state.response.uid}, hasDescription: $hasDescription, visibility: $visibility}',
        );
        outcome = await _finalizePostUpload(
          type: state.draft.type,
          cfUid: state.response.uid,
          description: trimmedDescription,
          visibility: visibility,
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
    required String cfUid,
    required String description,
    required String visibility,
    required VoidCallback? feedRefreshCallback,
  }) {
    final completed = _finalizedOutcomes[cfUid];
    if (completed != null) {
      return Future<UploadOutcome>.value(completed);
    }

    final inFlight = _finalizationInFlight[cfUid];
    if (inFlight != null) {
      return inFlight;
    }

    final future = () async {
      final trimmedDescription = description.trim();
      final hasDescription = trimmedDescription.isNotEmpty;
      final effectiveDescription = hasDescription ? trimmedDescription : null;

      const maxAttempts = 3;
      int attempt = 0;

      while (attempt < maxAttempts) {
        attempt += 1;
        try {
          final response = await _apiClient.createPost(
            type: type,
            cfUid: cfUid,
            description: effectiveDescription,
            visibility: visibility,
          );
          final status = _apiClient.lastCreatePostStatusCode;
          debugPrint(
            '[UploadService] finalize createPost: {type: $type, cfUid: $cfUid, hasDescription: $hasDescription, visibility: $visibility} -> status=${status ?? 'unknown'}',
          );
          _handleCreatePostSuccess(
            response: response,
            cfUid: cfUid,
            type: type,
            feedRefreshCallback: feedRefreshCallback,
          );
          await _notifyFeedRefreshRequested(feedRefreshCallback);
          final resolvedPostId = _extractPostId(response);
          return UploadOutcome(
            ok: true,
            postId: resolvedPostId,
            uploadId: cfUid,
            statusCode: status,
          );
        } on ApiException catch (error) {
          final status = error.statusCode;
          if (status == 409) {
            debugPrint(
              '[UploadService] finalize createPost: {type: $type, cfUid: $cfUid, hasDescription: $hasDescription, visibility: $visibility} -> status=409 (conflict treated as success)',
            );
            await _notifyFeedRefreshRequested(feedRefreshCallback);
            return UploadOutcome(
              ok: true,
              uploadId: cfUid,
              statusCode: status,
              message: error.message,
            );
          }

          final shouldRetry = status == null || status >= 500;
          if (shouldRetry && attempt < maxAttempts) {
            await Future<void>.delayed(_retryDelay(attempt));
            continue;
          }
          final statusLabel = status ?? 'unknown';
          final details =
              (error.details != null && error.details!.isNotEmpty)
                  ? error.details!
                  : error.message;
          debugPrint(
            '[UploadService] finalize error: createPost failed: $statusLabel $details',
          );
          return UploadOutcome(
            ok: false,
            uploadId: cfUid,
            message: error.message,
            statusCode: status,
          );
        } catch (error, stackTrace) {
          if (attempt < maxAttempts) {
            await Future<void>.delayed(_retryDelay(attempt));
            continue;
          }
          debugPrint(
            '[UploadService] finalize error: createPost failed: unknown $error\n$stackTrace',
          );
          return UploadOutcome(
            ok: false,
            uploadId: cfUid,
            message: error.toString(),
          );
        }
      }

      return UploadOutcome(
        ok: false,
        uploadId: cfUid,
        message: 'Failed to finalize upload',
      );
    }();

    final completer = Completer<UploadOutcome>();

    future.then((outcome) {
      if (outcome.ok) {
        _finalizedOutcomes[cfUid] = outcome;
      }
      _finalizationInFlight.remove(cfUid);
      completer.complete(outcome);
    }).catchError((Object error, StackTrace stackTrace) {
      _finalizationInFlight.remove(cfUid);
      completer.completeError(error, stackTrace);
    });

    _finalizationInFlight[cfUid] = completer.future;
    return completer.future;
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

  void _handleCreatePostSuccess({
    required Map<String, dynamic> response,
    required String cfUid,
    required String type,
    required VoidCallback? feedRefreshCallback,
  }) {
    final postId = _extractPostId(response) ?? cfUid;
    final status = _normalizeStatus(response['status']);
    final normalizedType = type.trim().toLowerCase();
    _postMediaTypes[postId] = normalizedType;
    PostItem placeholder;
    try {
      Map<String, dynamic>? rawPost;
      const candidateKeys = <String>['post', 'data', 'item'];
      for (final key in candidateKeys) {
        final value = response[key];
        if (value is Map<String, dynamic>) {
          rawPost = Map<String, dynamic>.from(value);
          break;
        }
      }
      rawPost ??= Map<String, dynamic>.from(response);
      rawPost['id'] ??= postId;
      rawPost['status'] ??= status;
      rawPost.putIfAbsent(
        'createdAt',
        () => DateTime.now().toUtc().toIso8601String(),
      );
      placeholder = PostItem.fromJson(rawPost);
    } catch (_) {
      placeholder = PostItem(
        id: postId,
        createdAt: DateTime.now().toUtc(),
        durationMs: 0,
        width: 1,
        height: 1,
        thumbUrl: null,
        status: status,
      );
    }

    if (placeholder.isPending || !placeholder.isReady) {
      onPendingPostCreated?.call(placeholder);
    } else {
      onPostStatusUpdated?.call(placeholder);
    }
    final shouldPoll = !placeholder.isReady || placeholder.thumbUrl == null;
    if (shouldPoll) {
      _pendingPostSnapshots[postId] = placeholder;
    } else {
      _pendingPostSnapshots.remove(postId);
      _postMediaTypes.remove(postId);
    }
    if (shouldPoll) {
      final isVideo = normalizedType == 'video';
      final streamUid = isVideo && cfUid.trim().isNotEmpty ? cfUid : null;
      if (isVideo) {
        _notifyVideoProcessing(
          postId: postId,
          mediaType: normalizedType,
          phase: VideoProcessingPhase.processing,
        );
      }
      _schedulePostReadyPolling(
        postId: postId,
        isVideo: isVideo,
        streamUid: streamUid,
        feedRefreshCallback: feedRefreshCallback,
      );
    }
  }

  void _schedulePostReadyPolling({
    required String postId,
    required bool isVideo,
    required String? streamUid,
    required VoidCallback? feedRefreshCallback,
  }) {
    if (_postReadyPolling.containsKey(postId)) {
      return;
    }
    final controller = _PostReadyPoller(streamUid: streamUid);
    final existingController = _postReadyControllers.remove(postId);
    existingController?.cancel();
    _postReadyControllers[postId] = controller;
    final future = _pollUntilPostReady(
      postId: postId,
      isVideo: isVideo,
      controller: controller,
      streamUid: streamUid,
      feedRefreshCallback: feedRefreshCallback,
    ).whenComplete(() {
      _postReadyPolling.remove(postId);
      final removed = _postReadyControllers.remove(postId);
      removed?.cancel();
      _postMediaTypes.remove(postId);
    });
    _postReadyPolling[postId] = future;
  }

  Future<void> _pollUntilPostReady({
    required String postId,
    required bool isVideo,
    required _PostReadyPoller controller,
    required String? streamUid,
    required VoidCallback? feedRefreshCallback,
  }) async {
    final deadline = DateTime.now().add(_postReadyPollTimeout);
    final mediaType = _postMediaTypes[postId] ?? (isVideo ? 'video' : 'unknown');
    var hasTriggeredRefresh = false;
    var streamDelay = _streamPollInitialDelay;
    var streamReady = streamUid == null;
    var streamFailed = false;

    while (!controller.isCancelled && DateTime.now().isBefore(deadline)) {
      if (!streamReady && !streamFailed && streamUid != null) {
        try {
          final result = await _apiClient.checkStreamStatus(streamUid);
          controller
            ..lastStreamResult = result
            ..streamReady = result.ready
            ..streamFailed = result.isFailed;
          streamReady = result.ready;
          streamFailed = result.isFailed;
        } on ApiException catch (error) {
          if (error.statusCode != HttpStatus.notFound) {
            debugPrint(
              '[UploadService] stream check api error for $streamUid: ${error.message}',
            );
          }
        } catch (error, stackTrace) {
          debugPrint(
            '[UploadService] stream check failed for $streamUid: $error\n$stackTrace',
          );
        }
      }

      if (controller.isCancelled) {
        return;
      }

      try {
        final snapshot = await _fetchPostSnapshot(postId);
        if (snapshot != null) {
          _pendingPostSnapshots[postId] = snapshot;
          onPostStatusUpdated?.call(snapshot);
          final hasThumb = snapshot.thumbUrl != null;
          final readyWithThumb = snapshot.isReady && hasThumb;
          final failed = snapshot.status.toUpperCase() == 'FAILED';
          if (readyWithThumb && !hasTriggeredRefresh) {
            await _notifyFeedRefreshRequested(feedRefreshCallback);
            hasTriggeredRefresh = true;
          }
          if (readyWithThumb) {
            if (isVideo) {
              _notifyVideoProcessing(
                postId: postId,
                mediaType: mediaType,
                phase: VideoProcessingPhase.ready,
                streamState: controller.lastStreamResult?.state,
              );
            }
            _pendingPostSnapshots.remove(postId);
            return;
          }
          if (failed) {
            if (isVideo) {
              _notifyVideoProcessing(
                postId: postId,
                mediaType: mediaType,
                phase: VideoProcessingPhase.failed,
                streamState: controller.lastStreamResult?.state,
              );
            }
            return;
          }
        } else if (streamFailed) {
          if (isVideo) {
            _notifyVideoProcessing(
              postId: postId,
              mediaType: mediaType,
              phase: VideoProcessingPhase.failed,
              streamState: controller.lastStreamResult?.state,
            );
          }
          _emitPostFailure(postId);
          return;
        }
      } catch (error, stackTrace) {
        debugPrint(
          '[UploadService] polling post $postId failed: $error\n$stackTrace',
        );
      }

      if (controller.isCancelled) {
        return;
      }

      if (streamFailed) {
        if (isVideo) {
          _notifyVideoProcessing(
            postId: postId,
            mediaType: mediaType,
            phase: VideoProcessingPhase.failed,
            streamState: controller.lastStreamResult?.state,
          );
        }
        _emitPostFailure(postId);
        return;
      }

      final waitDuration = streamReady
          ? _postReadyPollInterval
          : streamDelay;
      if (waitDuration > Duration.zero) {
        await Future<void>.delayed(waitDuration);
      }

      if (!streamReady && streamDelay < _streamPollMaxDelay) {
        final nextSeconds = math.min(
          _streamPollMaxDelay.inSeconds,
          math.max(
            streamDelay.inSeconds * 2,
            _streamPollInitialDelay.inSeconds,
          ),
        );
        streamDelay = Duration(seconds: nextSeconds);
      }
    }

    if (!controller.isCancelled) {
      if (streamUid != null && !streamReady) {
        if (isVideo) {
          _notifyVideoProcessing(
            postId: postId,
            mediaType: mediaType,
            phase: VideoProcessingPhase.failed,
            streamState:
                controller.lastStreamResult?.state ?? 'timeout',
          );
        }
        _emitPostFailure(postId);
      }
    }
  }

  Future<PostItem?> _fetchPostSnapshot(String postId) async {
    try {
      final post = await _apiClient.getPost(postId);
      if (post != null) {
        return post;
      }
    } on ApiException catch (error) {
      if (error.statusCode != HttpStatus.notFound) {
        debugPrint(
          '[UploadService] getPost($postId) failed: ${error.message} (${error.statusCode ?? 'unknown'})',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[UploadService] getPost($postId) unexpected error: $error\n$stackTrace');
    }

    try {
      final page = await _apiClient.getMyPosts(limit: 30);
      for (final item in page.items) {
        if (item.id == postId) {
          return item;
        }
      }
    } on ApiException catch (error) {
      if (error.statusCode != HttpStatus.notFound) {
        debugPrint(
          '[UploadService] getMyPosts fallback while polling $postId failed: ${error.message} (${error.statusCode ?? 'unknown'})',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[UploadService] getMyPosts fallback unexpected error for $postId: $error\n$stackTrace',
      );
    }
    return null;
  }

  String _normalizeStatus(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return 'UNKNOWN';
  }

  PostItem _clonePostWithStatus(PostItem source, String status) {
    return PostItem(
      id: source.id,
      createdAt: source.createdAt,
      durationMs: source.durationMs,
      width: source.width,
      height: source.height,
      thumbUrl: source.thumbUrl,
      status: status,
      playbackUrl: source.playbackUrl,
    );
  }

  void _emitPostFailure(String postId) {
    final existing = _pendingPostSnapshots[postId];
    final failed = existing != null
        ? _clonePostWithStatus(existing, 'FAILED')
        : PostItem(
            id: postId,
            createdAt: DateTime.now().toUtc(),
            durationMs: 0,
            width: 1,
            height: 1,
            thumbUrl: existing?.thumbUrl,
            status: 'FAILED',
            playbackUrl: existing?.playbackUrl,
          );
    _pendingPostSnapshots[postId] = failed;
    onPostStatusUpdated?.call(failed);
  }

  void _notifyVideoProcessing({
    required String postId,
    required String mediaType,
    required VideoProcessingPhase phase,
    String? streamState,
  }) {
    final callback = onVideoProcessingUpdate;
    if (callback == null) {
      return;
    }
    try {
      callback(
        VideoProcessingUpdate(
          postId: postId,
          mediaType: mediaType,
          phase: phase,
          streamState: streamState,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[UploadService] video processing callback error: $error\n$stackTrace',
      );
    }
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
    required this.chunkSize,
  })  : assert(chunkSize > 0),
        tusHeaders = Map.unmodifiable(Map<String, String>.from(tusHeaders));

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

class _PostReadyPoller {
  _PostReadyPoller({required this.streamUid});

  final String? streamUid;
  bool _cancelled = false;
  bool streamReady = false;
  bool streamFailed = false;
  StreamCheckResult? lastStreamResult;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }
}

enum VideoProcessingPhase { processing, ready, failed }

class VideoProcessingUpdate {
  const VideoProcessingUpdate({
    required this.postId,
    required this.mediaType,
    required this.phase,
    this.streamState,
    required this.timestamp,
  });

  final String postId;
  final String mediaType;
  final VideoProcessingPhase phase;
  final String? streamState;
  final DateTime timestamp;

  bool get isVideo => mediaType.toLowerCase() == 'video';
}
