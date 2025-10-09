import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../env.dart';
import '../models/create_upload_response.dart';
import '../models/post_draft.dart';

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

  Uri _resolve(String path) {
    assert(path.startsWith('/'), 'path must start with "/"');
    final override = _baseUrlOverride;
    final base = override ?? normalizedApiBaseUrl;
    if (base.isEmpty) {
      throw ApiException('API_BASE_URL dart-define is required');
    }
    return Uri.parse('$base$path');
  }

  Future<CreateUploadResponse> createUpload({
    required String type,
    required String fileName,
    required int fileSize,
    String? contentType,
  }) async {
    final url = _resolve('/api/uploads/create');
    debugPrint('[ApiClient] POST $url');
    debugPrint(
      '[ApiClient] createUpload payload type=$type fileName=$fileName fileSize=$fileSize contentType=$contentType',
    );
    final response = await _httpClient.post(
      url,
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({}),
    );
    debugPrint('[ApiClient] createUpload status=${response.statusCode}');

    if (response.statusCode != 200) {
      throw ApiException(
        'createUpload failed: ${response.statusCode} ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final rawBody = response.body;
    debugPrint('[ApiClient] createUpload raw: $rawBody');

    final decoded = jsonDecode(rawBody);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected response when creating upload');
    }

    final create = CreateUploadResponse.fromJson(decoded, rawJson: rawBody);
    return create;
  }

  Future<void> postMetadata({
    required String postId,
    required String type,
    required String description,
    VideoTrimData? trim,
    int? coverFrameMs,
    ImageCropData? imageCrop,
  }) async {
    final uri = _resolve('/api/posts/metadata');
    final body = <String, dynamic>{
      'postId': postId,
      'type': type,
      'description': description,
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
}
