import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/post_draft.dart';

class ApiException implements IOException {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      'ApiException(statusCode: ${statusCode ?? 'unknown'}, message: $message)';
}

class CreateUploadResponse {
  CreateUploadResponse({
    required this.postId,
    required this.uploadUrl,
    this.requiresMultipart = false,
    Map<String, String>? headers,
    Map<String, String>? fields,
    this.method = 'PUT',
    this.taskId,
    this.fileFieldName,
    this.contentType,
  })  : headers = headers ?? const {},
        fields = fields ?? const {};

  factory CreateUploadResponse.fromJson(Map<String, dynamic> json) {
    final headers = <String, String>{};
    if (json['headers'] is Map) {
      (json['headers'] as Map).forEach((key, value) {
        if (key is String && value != null) {
          headers[key] = value.toString();
        }
      });
    }
    final fields = <String, String>{};
    if (json['fields'] is Map) {
      (json['fields'] as Map).forEach((key, value) {
        if (key is String && value != null) {
          fields[key] = value.toString();
        }
      });
    }

    final postId = json['postId'];
    final uploadUrl = json['uploadUrl'] ?? json['url'];
    if (postId is! String || uploadUrl is! String) {
      throw ApiException('Upload response missing required fields');
    }

    return CreateUploadResponse(
      postId: postId,
      uploadUrl: uploadUrl,
      requiresMultipart: json['requiresMultipart'] as bool? ?? false,
      headers: headers,
      fields: fields,
      method: json['method'] as String? ?? 'PUT',
      taskId: json['taskId'] as String?,
      fileFieldName: json['fileFieldName'] as String?,
      contentType: json['contentType'] as String?,
    );
  }

  final String postId;
  final String uploadUrl;
  final bool requiresMultipart;
  final Map<String, String> headers;
  final Map<String, String> fields;
  final String method;
  final String? taskId;
  final String? fileFieldName;
  final String? contentType;
}

class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _httpClient = httpClient ?? http.Client(),
        _baseUri = Uri.parse(baseUrl ?? 'http://localhost:54321');

  final http.Client _httpClient;
  final Uri _baseUri;

  Uri _resolve(String path) => _baseUri.resolve(path);

  Future<CreateUploadResponse> createUpload({
    required String type,
    required String fileName,
    required int fileSize,
    String? contentType,
  }) async {
    final uri = _resolve('/api/uploads/create');
    final response = await _httpClient.post(
      uri,
      headers: {HttpHeaders.contentTypeHeader: 'application/json'},
      body: jsonEncode({
        'type': type,
        'fileName': fileName,
        'fileSize': fileSize,
        if (contentType != null) 'contentType': contentType,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Failed to create upload: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw ApiException('Unexpected response when creating upload');
    }

    return CreateUploadResponse.fromJson(data);
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
