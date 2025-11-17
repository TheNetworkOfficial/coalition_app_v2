import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Legacy testing shim — do not use in new code outside of tests/fakes.
abstract class TusUploader {
  const TusUploader();

  Future<void> uploadFile({
    required File file,
    required String tusUploadUrl,
    Map<String, String>? headers,
    void Function(int sent, int total)? onProgress,
    int chunkSize = 8 * 1024 * 1024,
    CancelToken? cancelToken,
  });

  Future<void> cancelTusUpload(String taskId) async {}
  Future<void> pauseTusUpload(String taskId) async {}
  Future<void> resumeTusUpload(String taskId) async {}
}

/// Bridges old tests (TusUploader) to the new Uploader interface.
class TusUploaderAdapter implements Uploader {
  TusUploaderAdapter(this.inner);

  final TusUploader inner;
  final StreamController<TusUploadEvent> _eventsController =
      StreamController<TusUploadEvent>.broadcast();
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};

  @override
  Stream<TusUploadEvent> get events => _eventsController.stream;

  @override
  Future<String> enqueue(TusUploadRequest request) async {
    final CancelToken cancelToken = CancelToken();
    _cancelTokens[request.taskId] = cancelToken;
    _emit(
      TusUploadEvent(
        taskId: request.taskId,
        state: TusUploadState.queued,
        bytesSent: 0,
        bytesTotal: request.fileSize,
      ),
    );
    _runUpload(request, cancelToken);
    return request.taskId;
  }

  void _runUpload(TusUploadRequest request, CancelToken cancelToken) {
    unawaited(() async {
      _emit(
        TusUploadEvent(
          taskId: request.taskId,
          state: TusUploadState.running,
          bytesSent: 0,
          bytesTotal: request.fileSize,
        ),
      );
      try {
        await inner.uploadFile(
          file: File(request.filePath),
          tusUploadUrl: request.endpoint.toString(),
          headers: request.headers,
          chunkSize: request.chunkSize,
          cancelToken: cancelToken,
          onProgress: (int sent, int total) {
            _emit(
              TusUploadEvent(
                taskId: request.taskId,
                state: TusUploadState.running,
                bytesSent: sent,
                bytesTotal: total,
              ),
            );
          },
        );
        _emit(
          TusUploadEvent(
            taskId: request.taskId,
            state: TusUploadState.uploaded,
            bytesSent: request.fileSize,
            bytesTotal: request.fileSize,
          ),
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          _emit(
            TusUploadEvent(
              taskId: request.taskId,
              state: TusUploadState.canceled,
              bytesSent: 0,
              bytesTotal: request.fileSize,
              error: error.message,
            ),
          );
        } else {
          _emit(
            TusUploadEvent(
              taskId: request.taskId,
              state: TusUploadState.failed,
              bytesSent: 0,
              bytesTotal: request.fileSize,
              error: error.message,
            ),
          );
        }
      } catch (error) {
        _emit(
          TusUploadEvent(
            taskId: request.taskId,
            state: TusUploadState.failed,
            bytesSent: 0,
            bytesTotal: request.fileSize,
            error: error.toString(),
          ),
        );
      } finally {
        _cancelTokens.remove(request.taskId);
      }
    }());
  }

  void _emit(TusUploadEvent event) {
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  @override
  Future<void> cancel(String taskId) async {
    final cancelToken = _cancelTokens.remove(taskId);
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('canceled');
    }
    await inner.cancelTusUpload(taskId);
  }

  @override
  Future<void> markPostReady(String taskId, String message) async {
    debugPrint(
      '[TusUploaderAdapter] markPostReady ignored for legacy uploader task=$taskId',
    );
  }

  @override
  Future<void> dispose() async {
    for (final token in _cancelTokens.values) {
      if (!token.isCancelled) {
        token.cancel('disposed');
      }
    }
    _cancelTokens.clear();
    await _eventsController.close();
  }
}

/// Upload phases reported by native or Dart-based uploaders.
enum TusUploadState {
  queued,
  running,
  resumed,
  uploaded,
  failed,
  canceled,
}

/// Lightweight progress snapshot that mirrors native events.
class TusUploadEvent {
  TusUploadEvent({
    required this.taskId,
    required this.state,
    required this.bytesSent,
    required this.bytesTotal,
    this.error,
  });

  final String taskId;
  final TusUploadState state;
  final int bytesSent;
  final int bytesTotal;
  final String? error;

  bool get isTerminal =>
      state == TusUploadState.uploaded ||
      state == TusUploadState.failed ||
      state == TusUploadState.canceled;

  TusUploadEvent copyWith({
    TusUploadState? state,
    int? bytesSent,
    int? bytesTotal,
    String? error,
  }) {
    return TusUploadEvent(
      taskId: taskId,
      state: state ?? this.state,
      bytesSent: bytesSent ?? this.bytesSent,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      error: error ?? this.error,
    );
  }

  static TusUploadEvent fromMap(Map<dynamic, dynamic> raw) {
    TusUploadState parseState(String? rawState) {
      switch (rawState?.toLowerCase()) {
        case 'running':
        case 'uploading':
          return TusUploadState.running;
        case 'resumed':
          return TusUploadState.resumed;
        case 'uploaded':
        case 'complete':
          return TusUploadState.uploaded;
        case 'failed':
          return TusUploadState.failed;
        case 'canceled':
          return TusUploadState.canceled;
        case 'queued':
        default:
          return TusUploadState.queued;
      }
    }

    final taskId = raw['taskId']?.toString();
    if (taskId == null || taskId.isEmpty) {
      throw ArgumentError('TusUploadEvent is missing taskId');
    }
    return TusUploadEvent(
      taskId: taskId,
      state: parseState(raw['state']?.toString()),
      bytesSent: _toPositiveInt(raw['bytesSent']),
      bytesTotal: _toPositiveInt(raw['bytesTotal']),
      error: raw['error']?.toString(),
    );
  }

  static int _toPositiveInt(dynamic value) {
    if (value is num) {
      return value.isFinite ? value.round().clamp(0, 1 << 31) : 0;
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

/// Serialized payload that is sent to the uploader implementation.
class TusUploadRequest {
  TusUploadRequest({
    required this.taskId,
    required this.uploadId,
    required this.filePath,
    required this.fileSize,
    required this.fileName,
    required this.endpoint,
    required this.headers,
    required this.chunkSize,
    required this.contentType,
    required this.description,
    required this.postType,
    this.notificationTitle,
    this.notificationBody,
    this.metadata,
  })  : assert(taskId.isNotEmpty),
        assert(uploadId.isNotEmpty),
        assert(filePath.isNotEmpty),
        assert(fileSize > 0),
        assert(chunkSize > 0);

  final String taskId;
  final String uploadId;
  final String filePath;
  final int fileSize;
  final String fileName;
  final Uri endpoint;
  final Map<String, String> headers;
  final int chunkSize;
  final String contentType;
  final String description;
  final String postType;
  final String? notificationTitle;
  final String? notificationBody;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'taskId': taskId,
      'uploadId': uploadId,
      'filePath': filePath,
      'fileSize': fileSize,
      'fileName': fileName,
      'endpoint': endpoint.toString(),
      'headers': headers,
      'chunkSize': chunkSize,
      'contentType': contentType,
      'description': description,
      'postType': postType,
      'notification': <String, String?>{
        'title': notificationTitle,
        'body': notificationBody,
      }..removeWhere((_, value) => value == null),
      if (metadata != null) 'metadata': metadata,
    };
  }
}

abstract class Uploader {
  Stream<TusUploadEvent> get events;
  Future<String> enqueue(TusUploadRequest request);
  Future<void> cancel(String taskId);
  Future<void> markPostReady(String taskId, String message);
  Future<void> dispose();
}

class TusBackgroundUploader implements Uploader {
  TusBackgroundUploader({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel =
            methodChannel ?? const MethodChannel('coalition/native_tus'),
        _eventChannel =
            eventChannel ?? const EventChannel('coalition/native_tus/events') {
    _eventSubscription =
        _eventChannel.receiveBroadcastStream().listen(_handleEvent,
            onError: (Object error, StackTrace stackTrace) {
      debugPrint('[TusBackgroundUploader] event stream error: $error');
    });
  }

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final StreamController<TusUploadEvent> _eventsController =
      StreamController<TusUploadEvent>.broadcast();
  StreamSubscription<dynamic>? _eventSubscription;

  @override
  Stream<TusUploadEvent> get events => _eventsController.stream;

  @override
  Future<String> enqueue(TusUploadRequest request) async {
    final result = await _methodChannel.invokeMethod<String>(
      'enqueueTusUpload',
      request.toJson(),
    );
    final resolvedTaskId =
        (result != null && result.isNotEmpty) ? result : request.taskId;
    debugPrint(
      '[TusBackgroundUploader][metric] native_tus_enqueued task=$resolvedTaskId upload=${request.uploadId}',
    );
    return resolvedTaskId;
  }

  @override
  Future<void> cancel(String taskId) {
    return _methodChannel.invokeMethod<void>(
      'cancelTusUpload',
      <String, dynamic>{'taskId': taskId},
    );
  }

  @override
  Future<void> markPostReady(String taskId, String message) async {
    try {
      await _methodChannel.invokeMethod<void>(
        'markPostReady',
        <String, dynamic>{'taskId': taskId, 'message': message},
      );
      debugPrint(
        '[TusBackgroundUploader][metric] post_ready_notification_sent task=$taskId',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[TusBackgroundUploader] markPostReady failed: $error\n$stackTrace',
      );
    }
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) {
      return;
    }
    try {
      final parsed = TusUploadEvent.fromMap(event);
      if (parsed.state == TusUploadState.resumed) {
        debugPrint(
          '[TusBackgroundUploader][metric] native_tus_resumed task=${parsed.taskId}',
        );
      }
      _eventsController.add(parsed);
    } catch (error, stackTrace) {
      debugPrint(
        '[TusBackgroundUploader] Failed to parse event: $error\n$stackTrace',
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _eventsController.close();
  }
}

class TusDioUploader implements Uploader {
  TusDioUploader({TusDioClient? client})
      : _client = client ?? TusDioClient(),
        _eventsController = StreamController<TusUploadEvent>.broadcast();

  final TusDioClient _client;
  final StreamController<TusUploadEvent> _eventsController;
  final Map<String, _TusUploadJob> _jobs = <String, _TusUploadJob>{};

  @override
  Stream<TusUploadEvent> get events => _eventsController.stream;

  @override
  Future<String> enqueue(TusUploadRequest request) async {
    final job = _TusUploadJob(
      request: request,
      cancelToken: CancelToken(),
    );
    _jobs[request.taskId] = job;
    _emit(
      TusUploadEvent(
        taskId: request.taskId,
        state: TusUploadState.queued,
        bytesSent: 0,
        bytesTotal: request.fileSize,
      ),
    );
    _run(job);
    return request.taskId;
  }

  void _run(_TusUploadJob job) {
    unawaited(() async {
      final request = job.request;
      try {
        _emit(
          TusUploadEvent(
            taskId: request.taskId,
            state: TusUploadState.running,
            bytesSent: 0,
            bytesTotal: request.fileSize,
          ),
        );
        await _client.uploadFile(
          file: File(request.filePath),
          tusUploadUrl: request.endpoint.toString(),
          chunkSize: request.chunkSize,
          headers: request.headers,
          cancelToken: job.cancelToken,
          onProgress: (int sent, int total) {
            _emit(
              TusUploadEvent(
                taskId: request.taskId,
                state: TusUploadState.running,
                bytesSent: sent,
                bytesTotal: total,
              ),
            );
          },
        );
        _emit(
          TusUploadEvent(
            taskId: request.taskId,
            state: TusUploadState.uploaded,
            bytesSent: request.fileSize,
            bytesTotal: request.fileSize,
          ),
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error)) {
          _emit(
            TusUploadEvent(
              taskId: request.taskId,
              state: TusUploadState.canceled,
              bytesSent: 0,
              bytesTotal: request.fileSize,
              error: error.message,
            ),
          );
        } else {
          _emit(
            TusUploadEvent(
              taskId: request.taskId,
              state: TusUploadState.failed,
              bytesSent: job.lastProgress,
              bytesTotal: request.fileSize,
              error: error.message ?? error.toString(),
            ),
          );
        }
      } catch (error) {
        _emit(
          TusUploadEvent(
            taskId: request.taskId,
            state: TusUploadState.failed,
            bytesSent: job.lastProgress,
            bytesTotal: request.fileSize,
            error: error.toString(),
          ),
        );
      } finally {
        _jobs.remove(request.taskId);
      }
    }());
  }

  void _emit(TusUploadEvent event) {
    _eventsController.add(event);
    final job = _jobs[event.taskId];
    if (event.state == TusUploadState.running) {
      job?.lastProgress = event.bytesSent;
    }
  }

  @override
  Future<void> cancel(String taskId) async {
    final job = _jobs.remove(taskId);
    job?.cancelToken.cancel('cancel');
  }

  @override
  Future<void> markPostReady(String taskId, String message) async {
    // No native notification to update for pure Dart uploads.
  }

  @override
  Future<void> dispose() async {
    for (final job in _jobs.values) {
      job.cancelToken.cancel('dispose');
    }
    _jobs.clear();
    await _eventsController.close();
  }
}

class _TusUploadJob {
  _TusUploadJob({
    required this.request,
    required this.cancelToken,
  });

  final TusUploadRequest request;
  final CancelToken cancelToken;
  int lastProgress = 0;
}

/// Minimal TUS 1.0.0 uploader (Cloudflare Stream compatible) using Dio.
class TusDioClient {
  TusDioClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 30),
                followRedirects: true,
                validateStatus: (int? code) =>
                    code != null && (code < 400 || code == 409 || code == 412),
              ),
            );

  final Dio _dio;

  Future<void> uploadFile({
    required File file,
    required String tusUploadUrl,
    Map<String, String>? headers,
    void Function(int sent, int total)? onProgress,
    int chunkSize = 8 * 1024 * 1024,
    CancelToken? cancelToken,
  }) async {
    final int length = await file.length();
    final Map<String, String> baseHeaders = _normalizeBaseHeaders(headers);

    int offset = await _getOffset(tusUploadUrl, baseHeaders);
    if (offset > length) {
      throw Exception(
        'Server offset ($offset) exceeds local file length ($length).',
      );
    }

    while (offset < length) {
      final int start = offset;
      final int proposedEnd = start + chunkSize;
      final int end = proposedEnd > length ? length : proposedEnd;
      final int chunkLen = end - start;
      if (chunkLen <= 0) {
        break;
      }

      final Stream<List<int>> stream = file.openRead(start, end);

      final Map<String, dynamic> patchHeaders = <String, dynamic>{
        ...baseHeaders,
        'Content-Type': 'application/offset+octet-stream',
        'Upload-Offset': start.toString(),
        'Content-Length': chunkLen.toString(),
      };

      final Response<Object?> resp = await _dio.patch<Object?>(
        tusUploadUrl,
        data: stream,
        options: Options(
          headers: patchHeaders,
          responseType: ResponseType.stream,
        ),
        onSendProgress: (int sent, int total) {
          final int overallSent = start + sent;
          final int clampedSent = overallSent > length ? length : overallSent;
          onProgress?.call(clampedSent, length);
        },
        cancelToken: cancelToken,
      );

      final int? statusCode = resp.statusCode;
      if (statusCode == 204 || statusCode == 200) {
        final String? newOffsetHeader = resp.headers.value('Upload-Offset');
        if (newOffsetHeader == null) {
          offset = end;
        } else {
          final int newOffset =
              int.tryParse(newOffsetHeader) ?? (start + chunkLen);
          if (newOffset < start) {
            throw Exception(
              'Server returned decreasing offset: $newOffset < $start',
            );
          }
          offset = newOffset;
        }
      } else if (statusCode == 409 || statusCode == 412) {
        offset = await _getOffset(tusUploadUrl, baseHeaders);
      } else {
        throw Exception(
          'TUS PATCH failed: ${resp.statusCode} ${resp.statusMessage}',
        );
      }
    }

    onProgress?.call(length, length);
  }

  Map<String, String> _normalizeBaseHeaders(Map<String, String>? headers) {
    final Map<String, String> normalized = <String, String>{};
    if (headers != null && headers.isNotEmpty) {
      headers.forEach((String key, String value) {
        if (key.isNotEmpty) {
          normalized[key] = value;
        }
      });
    }
    final bool hasTusResumable = normalized.keys.any(
      (String key) => key.toLowerCase() == 'tus-resumable',
    );
    if (!hasTusResumable) {
      normalized['Tus-Resumable'] = '1.0.0';
    }
    return normalized;
  }

  Future<int> _getOffset(
    String tusUploadUrl,
    Map<String, String> baseHeaders,
  ) async {
    final Response<Object?> resp = await _dio.head(
      tusUploadUrl,
      options: Options(headers: Map<String, dynamic>.from(baseHeaders)),
    );

    if (resp.statusCode == 204 || resp.statusCode == 200) {
      final String offsetHeader = resp.headers.value('Upload-Offset') ?? '0';
      final int parsed = int.tryParse(offsetHeader) ?? 0;
      return parsed;
    }

    if (resp.statusCode == 404) {
      throw Exception('TUS upload not found (404). Did you create it first?');
    }

    throw Exception(
      'TUS HEAD failed: ${resp.statusCode} ${resp.statusMessage}',
    );
  }

  Future<String> createUploadDirect({
    required Uri tusCreationEndpoint,
    required int uploadLength,
    required String filename,
    required String filetype,
    Map<String, String>? extraHeaders,
  }) async {
    final Map<String, String> metadata = <String, String>{
      'filename': base64.encode(utf8.encode(filename)),
      'filetype': base64.encode(utf8.encode(filetype)),
    };
    final String metadataHeader =
        metadata.entries.map((MapEntry<String, String> e) {
      return '${e.key} ${e.value}';
    }).join(',');

    final Map<String, dynamic> headers = <String, dynamic>{
      'Tus-Resumable': '1.0.0',
      'Upload-Length': uploadLength.toString(),
      'Upload-Metadata': metadataHeader,
      if (extraHeaders != null) ...extraHeaders,
    };

    final Response<Object?> resp = await _dio.postUri(
      tusCreationEndpoint,
      options: Options(
        headers: headers,
        validateStatus: (int? c) => c != null && c < 400,
      ),
    );

    final String? loc = resp.headers.value('Location');
    if (loc == null || loc.isEmpty) {
      throw Exception('TUS create did not return Location header.');
    }
    return loc;
  }
}
