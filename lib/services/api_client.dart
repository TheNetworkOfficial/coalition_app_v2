import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../env.dart';
import '../models/post_draft.dart';
import '../models/create_upload_response.dart';

class ApiException implements IOException {
  ApiException(this.message, {this.statusCode, this.details});

  final String message;
  final int? statusCode;
  final String? details;

  @override
  String toString() {
    final extras = details == null || details!.isEmpty ? '' : ', details: $details';
    return 'ApiException(statusCode: ${statusCode ?? 'unknown'}, message: $message$extras)';
  }
}

class CreateUploadResult {
  CreateUploadResult({
    required this.response,
    required this.rawJson,
  });

  final CreateUploadResponse response;
  final Map<String, dynamic> rawJson;
}

class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _httpClient = httpClient ?? http.Client(),
        _baseUrlOverride = baseUrl == null || baseUrl.isEmpty
            ? null
            : normalizeApiBaseUrl(baseUrl) {
    if (_baseUrlOverride == null) {
      assertApiBaseConfigured();
    }
  }

  final http.Client _httpClient;
  final String? _baseUrlOverride;
  int? _lastCreatePostStatusCode;

  Uri _resolve(String path) {
    assert(path.startsWith('/'), 'path must start with "/"');
    final override = _baseUrlOverride;
    final base = override ?? normalizedApiBaseUrl;
    if (base.isEmpty) {
      throw ApiException('API_BASE_URL dart-define is required');
    }
    return Uri.parse('$base$path');
  }

  Uri resolvePath(String path) => _resolve(path);

  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
  }) {
    final uri = _resolve(path);
    return _httpClient.get(uri, headers: headers);
  }

  http.Client get httpClient => _httpClient;

  int? get lastCreatePostStatusCode => _lastCreatePostStatusCode;

  @protected
  void recordCreatePostStatus(int status) {
    _lastCreatePostStatusCode = status;
  }

  void close() {
    _httpClient.close();
  }

  Future<CreateUploadResult> createUpload({
    required String type,
    required String fileName,
    required int fileSize,
    required String contentType,
    int? maxDurationSeconds,
  }) async {
    final uri = _resolve('/api/uploads/create');
    final payload = <String, dynamic>{
      'type': type,
      'fileName': fileName,
      'fileSize': fileSize,
      'contentType': contentType,
      if (maxDurationSeconds != null) 'maxDurationSeconds': maxDurationSeconds,
    };

    debugPrint('[ApiClient] POST $uri');
    debugPrint('[ApiClient] createUpload payload: $payload');

    final response = await _httpClient.post(
      uri,
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode(payload),
    );
    debugPrint('[ApiClient] createUpload status=${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'createUpload failed: ${response.statusCode} ${response.body}',
        statusCode: response.statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }

    final rawBody = response.body;
    debugPrint('[ApiClient] createUpload raw: $rawBody');

    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected response when creating upload');
    }

    final jsonMap = Map<String, dynamic>.from(decoded);

    final uploadResponse = CreateUploadResponse.fromJson(jsonMap, rawJson: rawBody);

    return CreateUploadResult(
      response: uploadResponse,
      rawJson: jsonMap,
    );
  }

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
    final uri = _resolve('/api/posts/metadata');
    final body = <String, dynamic>{
      'postId': postId,
      'uid': postId,
      'type': type,
      'description': description,
      'fileName': fileName,
      'fileSize': fileSize,
      'contentType': contentType,
      'trim': trim == null
          ? null
          : {
              'startMs': trim.startMs,
              'endMs': trim.endMs,
            },
      'coverFrameMs': coverFrameMs,
      'imageCrop': imageCrop == null
          ? null
          : {
              'x': imageCrop.x,
              'y': imageCrop.y,
              'width': imageCrop.width,
              'height': imageCrop.height,
              'rotation': imageCrop.rotation,
            },
    }..removeWhere((key, value) => value == null);

    final response = await _httpClient.post(
      uri,
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Failed to post metadata: ${response.body}',
        statusCode: response.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> createPost({
    required String postId,
    required String userId,
    required String type,
    required String uploadId,
    String? description,
  }) async {
    final uri = _resolve('/api/posts');
    final payload = <String, dynamic>{
      'postId': postId,
      'userId': userId,
      'type': type,
      'uploadId': uploadId,
    };

    final trimmedDescription = description?.trim();
    if (trimmedDescription != null && trimmedDescription.isNotEmpty) {
      payload['description'] = trimmedDescription;
    }

    debugPrint('[ApiClient] POST $uri');
    debugPrint('[ApiClient] createPost payload: $payload');

    final response = await _httpClient.post(
      uri,
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode(payload),
    );
    final status = response.statusCode;
    debugPrint('[ApiClient] createPost status=$status');

    recordCreatePostStatus(status);

    if (status < 200 || status >= 300) {
      throw ApiException(
        'createPost failed: $status ${response.body}',
        statusCode: status,
        details: response.body.isEmpty ? null : response.body,
      );
    }

    final rawBody = response.body;
    debugPrint('[ApiClient] createPost raw: $rawBody');

    if (rawBody.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected response when creating post');
    }

    return Map<String, dynamic>.from(decoded);
  }
}
