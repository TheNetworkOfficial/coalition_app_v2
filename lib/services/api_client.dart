import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../env.dart';
import '../features/feed/models/post.dart';
import '../models/create_upload_response.dart';
import '../models/post_draft.dart';
import '../models/profile.dart';
import 'auth_service.dart';

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
  ApiClient({
    http.Client? httpClient,
    String? baseUrl,
    AuthService? authService,
  })  : _httpClient = httpClient ?? http.Client(),
        _baseUrlOverride = baseUrl == null || baseUrl.isEmpty
            ? null
            : normalizeApiBaseUrl(baseUrl),
        _authService = authService {
    if (_baseUrlOverride == null) {
      assertApiBaseConfigured();
    }
  }

  final http.Client _httpClient;
  final String? _baseUrlOverride;
  AuthService? _authService;
  int? _lastCreatePostStatusCode;

  set authService(AuthService? service) => _authService = service;

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
  }) async {
    final uri = _resolve(path);
    final resolvedHeaders = await _composeHeaders(headers);
    return _httpClient.get(
      uri,
      headers: resolvedHeaders.isEmpty ? null : resolvedHeaders,
    );
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

    final headers = await _jsonHeaders();
    final response = await _httpClient.post(
      uri,
      headers: headers,
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

    final headers = await _jsonHeaders();
    final response = await _httpClient.post(
      uri,
      headers: headers,
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
    required String type,
    required String cfUid,
    String? description,
    String visibility = 'public',
  }) async {
    final uri = _resolve('/api/posts');
    final trimmedDescription = description?.trim();
    final payload = <String, dynamic>{
      'type': type,
      'cfUid': cfUid,
      'visibility': visibility,
      if (trimmedDescription != null && trimmedDescription.isNotEmpty)
        'description': trimmedDescription,
    };

    debugPrint('[ApiClient] POST $uri');
    debugPrint('[ApiClient] createPost payload: $payload');

    final headers = await _jsonHeaders();
    final response = await _httpClient.post(
      uri,
      headers: headers,
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

  Future<Profile> getMyProfile() async {
    final response = await get('/api/profile/me');
    if (response.statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: response.statusCode);
    }
    if (response.statusCode == HttpStatus.notFound) {
      throw ApiException(
        'Profile not found',
        statusCode: response.statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Failed to load profile: ${response.statusCode}',
        statusCode: response.statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    final dynamic decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    final profileMap = _extractProfileMap(decoded);
    if (profileMap != null) {
      return Profile.fromJson(profileMap);
    }
    throw ApiException('Unexpected profile response format');
  }

  Future<Profile> upsertMyProfile(ProfileUpdate update) async {
    final uri = _resolve('/api/profile');
    final headers = await _jsonHeaders();
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(update.toJson()),
    );

    if (response.statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Failed to update profile: ${response.statusCode}',
        statusCode: response.statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    final dynamic decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    final profileMap = _extractProfileMap(decoded);
    if (profileMap != null) {
      return Profile.fromJson(profileMap);
    }
    throw ApiException('Unexpected profile update response');
  }

  Future<List<Post>> getMyPosts({bool includePending = false}) async {
    final query = includePending ? '?includePending=true' : '';
    final response = await get('/api/users/me/posts$query');
    if (response.statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: response.statusCode);
    }
    if (response.statusCode == HttpStatus.notFound) {
      return const [];
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Failed to load posts: ${response.statusCode}',
        statusCode: response.statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    final dynamic decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    final items = _extractItemsList(decoded);
    if (items == null) {
      throw ApiException('Unexpected posts response');
    }
    final posts = <Post>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is Map<String, dynamic>) {
        try {
          posts.add(Post.fromJson(item, fallbackId: 'me-$i'));
        } catch (error, stackTrace) {
          debugPrint('[ApiClient] Skipping malformed post: $error\n$stackTrace');
        }
      }
    }
    return posts;
  }

  Future<Map<String, String>> _jsonHeaders([Map<String, String>? headers]) async {
    final resolved = await _composeHeaders(headers);
    resolved.putIfAbsent(HttpHeaders.contentTypeHeader, () => 'application/json');
    return resolved;
  }

  Future<Map<String, String>> _composeHeaders(
    Map<String, String>? headers,
  ) async {
    final resolved = <String, String>{};
    if (headers != null) {
      resolved.addAll(headers);
    }
    final authorization = await _authorizationHeader();
    if (authorization != null) {
      resolved.putIfAbsent(HttpHeaders.authorizationHeader, () => authorization);
    }
    return resolved;
  }

  Future<String?> _authorizationHeader() async {
    if (kAuthBypassEnabled) {
      return null;
    }
    final service = _authService;
    if (service == null) {
      return null;
    }
    final token = await service.fetchAuthToken();
    if (token == null || token.isEmpty) {
      return null;
    }
    return 'Bearer $token';
  }

  Map<String, dynamic>? _extractProfileMap(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final profile = payload['profile'];
      if (profile is Map<String, dynamic>) {
        return Map<String, dynamic>.from(profile);
      }
      final data = payload['data'];
      if (data is Map<String, dynamic>) {
        return Map<String, dynamic>.from(data);
      }
      final hasUserIdentifiers = payload.containsKey('userId') ||
          payload.containsKey('id') ||
          payload.containsKey('sub');
      if (hasUserIdentifiers) {
        return Map<String, dynamic>.from(payload);
      }
    }
    return null;
  }

  List<dynamic>? _extractItemsList(dynamic payload) {
    if (payload is List) {
      return payload;
    }
    if (payload is Map<String, dynamic>) {
      final items = payload['items'];
      if (items is List) {
        return List<dynamic>.from(items);
      }
      final data = payload['data'];
      if (data is List) {
        return List<dynamic>.from(data);
      }
    }
    return null;
  }
}
