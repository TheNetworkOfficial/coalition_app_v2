import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'package:coalition_app_v2/models/create_upload_response.dart';
import 'package:coalition_app_v2/models/post_draft.dart';
import 'package:coalition_app_v2/models/upload_outcome.dart';
import 'package:coalition_app_v2/services/api_client.dart';
import 'package:coalition_app_v2/services/tus_uploader.dart';
import 'package:coalition_app_v2/services/upload_service.dart';

void main() {
  group('UploadService', () {
    late Directory tempDir;
    late File tempFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('upload_service_test');
      tempFile = File('${tempDir.path}/video.mp4');
      await tempFile.writeAsBytes(
        List<int>.generate(1024, (index) => index % 256),
      );
    });

    tearDown(() async {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('resolves with success after finalize and feed refresh', () async {
      final createResponse = CreateUploadResponse(
        uploadUrl: Uri.parse('https://example.com/upload'),
        uid: 'cf-upload-123',
        method: 'PATCH',
      );
      final createResult = CreateUploadResult(
        response: createResponse,
        rawJson: {
          'tusInfo': {
            'endpoint': 'https://tus.example.com/upload',
            'headers': {
              'Authorization': 'Bearer token',
            },
          },
        },
      );

      final apiClient = _StubbedApiClient(createResult: createResult);
      final tusUploader = _FakeTusUploader();
      final service = UploadService(
        apiClient: apiClient,
        tusUploader: tusUploader,
      );

      bool feedRefreshed = false;
      service.onFeedRefreshRequested = () {
        feedRefreshed = true;
      };

      final draft = PostDraft(
        originalFilePath: tempFile.path,
        type: 'video',
        description: 'example',
      );

      bool tusCompleteBeforeCreatePost = false;
      apiClient.onCreatePost = () {
        tusCompleteBeforeCreatePost = tusUploader.uploadCompleted;
      };

      final outcome = await service.startUpload(
        draft: draft,
        description: '  Final caption  ',
      );

      expect(outcome.ok, isTrue);
      expect(outcome.uploadId, 'cf-upload-123');
      expect(outcome.postId, 'post-abc');
      expect(feedRefreshed, isTrue);
      expect(tusUploader.uploadCompleted, isTrue);
      expect(tusCompleteBeforeCreatePost, isTrue);

      expect(apiClient.createPostCalls, 1);
      final args = apiClient.lastCreatePostArgs;
      expect(args, isNotNull);
      expect(args!.type, 'video');
      expect(args.cfUid, 'cf-upload-123');
      expect(args.visibility, 'public');
      expect(args.description, 'Final caption');
      expect(apiClient.lastPostedMetadataDescription, 'Final caption');

      service.dispose();
    });

    test('retries finalize on transient failures', () async {
      final createResponse = CreateUploadResponse(
        uploadUrl: Uri.parse('https://example.com/upload'),
        uid: 'cf-upload-123',
        method: 'PATCH',
      );
      final createResult = CreateUploadResult(
        response: createResponse,
        rawJson: {
          'tusInfo': {
            'endpoint': 'https://tus.example.com/upload',
            'headers': {
              'Authorization': 'Bearer token',
            },
          },
        },
      );

      final apiClient = _StubbedApiClient(
        createResult: createResult,
        createPostQueue: <Object>[
          _CreatePostError(
            ApiException('temporary failure', statusCode: 502),
          ),
          _CreatePostError(
            ApiException('temporary failure', statusCode: 502),
          ),
          const _CreatePostSuccess({'postId': 'post-abc'}, statusCode: 201),
        ],
      );
      final tusUploader = _FakeTusUploader();
      final service = UploadService(
        apiClient: apiClient,
        tusUploader: tusUploader,
      );

      bool feedRefreshed = false;
      service.onFeedRefreshRequested = () {
        feedRefreshed = true;
      };

      final draft = PostDraft(
        originalFilePath: tempFile.path,
        type: 'video',
        description: 'example',
      );

      final outcome = await service.startUpload(
        draft: draft,
        description: 'Caption',
      );

      expect(outcome.ok, isTrue);
      expect(feedRefreshed, isTrue);
      expect(apiClient.createPostCalls, 3);

      service.dispose();
    });

    test('treats 409 conflict as success', () async {
      final createResponse = CreateUploadResponse(
        uploadUrl: Uri.parse('https://example.com/upload'),
        uid: 'cf-upload-123',
        method: 'PATCH',
      );
      final createResult = CreateUploadResult(
        response: createResponse,
        rawJson: {
          'tusInfo': {
            'endpoint': 'https://tus.example.com/upload',
            'headers': {
              'Authorization': 'Bearer token',
            },
          },
        },
      );

      final apiClient = _StubbedApiClient(
        createResult: createResult,
        createPostQueue: <Object>[
          _CreatePostError(
            ApiException('duplicate', statusCode: 409),
          ),
        ],
      );
      final tusUploader = _FakeTusUploader();
      final service = UploadService(
        apiClient: apiClient,
        tusUploader: tusUploader,
      );

      bool feedRefreshed = false;
      service.onFeedRefreshRequested = () {
        feedRefreshed = true;
      };

      final draft = PostDraft(
        originalFilePath: tempFile.path,
        type: 'video',
        description: 'example',
      );

      final outcome = await service.startUpload(
        draft: draft,
        description: 'Caption',
      );

      expect(outcome.ok, isTrue);
      expect(outcome.statusCode, 409);
      expect(feedRefreshed, isTrue);
      expect(apiClient.createPostCalls, 1);

      service.dispose();
    });
  });
}

class _StubbedApiClient extends ApiClient {
  _StubbedApiClient({
    required this.createResult,
    List<Object>? createPostQueue,
  })  : _createPostQueue =
            createPostQueue == null ? <Object>[] : List<Object>.from(createPostQueue),
        super(httpClient: _NoopHttpClient(), baseUrl: 'https://example.com');

  final CreateUploadResult createResult;
  final List<Object> _createPostQueue;
  int createPostCalls = 0;
  _CreatePostArgs? lastCreatePostArgs;
  String? lastPostedMetadataDescription;
  void Function()? onCreatePost;

  @override
  Future<CreateUploadResult> createUpload({
    required String type,
    required String fileName,
    required int fileSize,
    required String contentType,
    int? maxDurationSeconds,
  }) async {
    return createResult;
  }

  @override
  Future<void> postMetadata({
    required String postId,
    required String type,
    required String description,
    required String fileName,
    required int fileSize,
    required String contentType,
    VideoTrimData? trim,
    int? coverFrameMs,
    ImageCropData? imageCrop,
  }) async {
    lastPostedMetadataDescription = description;
  }

  @override
  Future<Map<String, dynamic>> createPost({
    required String type,
    required String cfUid,
    String? description,
    String visibility = 'public',
  }) async {
    createPostCalls += 1;
    onCreatePost?.call();
    lastCreatePostArgs = _CreatePostArgs(
      type: type,
      cfUid: cfUid,
      description: description,
      visibility: visibility,
    );

    Object? behavior;
    if (_createPostQueue.isNotEmpty) {
      behavior = _createPostQueue.removeAt(0);
    }

    if (behavior is _CreatePostError) {
      throw behavior.exception;
    }

    final success = behavior is _CreatePostSuccess
        ? behavior
        : const _CreatePostSuccess({'postId': 'post-abc'}, statusCode: 201);

    recordCreatePostStatus(success.statusCode);
    return success.body;
  }
}

class _CreatePostSuccess {
  const _CreatePostSuccess(this.body, {this.statusCode = 201});

  final Map<String, dynamic> body;
  final int statusCode;
}

class _CreatePostError {
  const _CreatePostError(this.exception);

  final ApiException exception;
}

class _FakeTusUploader extends TusUploader {
  _FakeTusUploader() : super();

  bool uploadCompleted = false;

  @override
  Future<void> uploadFile({
    required File file,
    required String tusUploadUrl,
    Map<String, String>? headers,
    void Function(int sent, int total)? onProgress,
    int chunkSize = 8 * 1024 * 1024,
    CancelToken? cancelToken,
  }) async {
    final total = await file.length();
    onProgress?.call(total, total);
    uploadCompleted = true;
  }
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError('Network calls are not supported in FakeApiClient');
  }
}

class _CreatePostArgs {
  const _CreatePostArgs({
    required this.type,
    required this.cfUid,
    this.description,
    this.visibility = 'public',
  });

  final String type;
  final String cfUid;
  final String? description;
  final String visibility;

  @override
  bool operator ==(Object other) {
    return other is _CreatePostArgs &&
        other.type == type &&
        other.cfUid == cfUid &&
        other.description == description &&
        other.visibility == visibility;
  }

  @override
  int get hashCode => Object.hash(type, cfUid, description, visibility);
}
