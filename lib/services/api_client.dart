import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../env.dart';
import '../models/create_upload_response.dart';
import '../models/post_draft.dart';
import '../models/posts_page.dart';
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

class StreamCheckResult {
  const StreamCheckResult({
    required this.ok,
    required this.state,
    required this.ready,
  });

  final bool ok;
  final String state;
  final bool ready;

  bool get isFailed => state.toLowerCase() == 'failed' || state.toLowerCase() == 'error';
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
    Map<String, String>? queryParameters,
  }) async {
    final baseUri = _resolve(path);
    final uri = queryParameters == null || queryParameters.isEmpty
        ? baseUri
        : baseUri.replace(
            queryParameters: {
              if (baseUri.hasQuery) ...baseUri.queryParameters,
              ...queryParameters,
            },
          );
    final resolvedHeaders = await _composeHeaders(headers);
    return _httpClient.get(
      uri,
      headers: resolvedHeaders.isEmpty ? null : resolvedHeaders,
    );
  }

  Future<http.Response> postJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(path);
    final resolvedHeaders = await _jsonHeaders(headers: headers);
    final payload = jsonEncode(body ?? const <String, dynamic>{});
    return _httpClient.post(
      uri,
      headers: resolvedHeaders,
      body: payload,
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
              'durationMs': trim.durationMs,
              if (trim.proxyStartMs != null) 'proxyStartMs': trim.proxyStartMs,
              if (trim.proxyEndMs != null) 'proxyEndMs': trim.proxyEndMs,
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

  Future<PostItem?> getPost(String postId) async {
    final uri = _resolve('/api/posts/$postId');
    final headers = await _composeHeaders(null);
    final response = await _httpClient.get(
      uri,
      headers: headers.isEmpty ? null : headers,
    );

    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.notFound) {
      return null;
    }
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while loading post $postId',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to load post: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }

    if (response.body.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected post response');
    }

    Map<String, dynamic>? rawPost;
    final candidateKeys = <String>['post', 'data', 'item'];
    for (final key in candidateKeys) {
      final value = decoded[key];
      if (value is Map<String, dynamic>) {
        rawPost = Map<String, dynamic>.from(value);
        break;
      }
    }
    rawPost ??= Map<String, dynamic>.from(decoded);
    rawPost.putIfAbsent('id', () => postId);
    rawPost.putIfAbsent(
      'createdAt',
      () => DateTime.now().toUtc().toIso8601String(),
    );
    return PostItem.fromJson(rawPost);
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

  Future<Profile> getProfile(String userId) async {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('userId must not be empty');
    }
    final encodedId = Uri.encodeComponent(trimmed);
    final response = await get('/api/profile/$encodedId');
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

  Future<PostsPage> getMyPosts({int limit = 30, String? cursor}) async {
    final resolvedLimit = limit <= 0 ? 30 : limit;
    final baseUri = _resolve('/api/users/me/posts');
    final queryParameters = <String, String>{
      'limit': resolvedLimit.toString(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = baseUri.replace(queryParameters: queryParameters);

    http.Response? response;
    for (var attempt = 0; attempt < 2; attempt++) {
      final forceRefresh = attempt == 1;
      final headers = await _composeHeaders(
        null,
        forceRefreshAuth: forceRefresh,
      );
      response = await _httpClient.get(
        uri,
        headers: headers.isEmpty ? null : headers,
      );

      final statusCode = response.statusCode;
      final isAuthError =
          statusCode == HttpStatus.unauthorized || statusCode == HttpStatus.forbidden;
      if (isAuthError && !forceRefresh) {
        await _authService?.fetchAuthToken(forceRefresh: true);
        continue;
      }
      debugPrint(
        '[ApiClient] getMyPosts attempt=$attempt status=$statusCode',
      );
      break;
    }

    if (response == null) {
      throw ApiException('Failed to load posts: no response');
    }

    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while loading posts',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode == HttpStatus.notFound) {
      return PostsPage(items: const <PostItem>[], nextCursor: null);
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to load posts: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }

    if (response.body.isEmpty) {
      return PostsPage(items: const <PostItem>[], nextCursor: null);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected posts response');
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw ApiException('Unexpected posts response: missing items');
    }

    final items = <PostItem>[];
    for (final entry in rawItems) {
      if (entry is! Map<String, dynamic>) {
        debugPrint('[ApiClient] Ignoring non-map post item: ${entry.runtimeType}');
        continue;
      }
      try {
        items.add(PostItem.fromJson(entry));
      } catch (error, stackTrace) {
        debugPrint('[ApiClient] Skipping malformed post item: $error\n$stackTrace');
      }
    }

    if (items.isEmpty) {
      debugPrint('[ApiClient] getMyPosts empty items payload=${response.body}');
    }

    final nextCursorRaw = decoded['nextCursor'];
    String? nextCursor;
    if (nextCursorRaw is String && nextCursorRaw.trim().isNotEmpty) {
      nextCursor = nextCursorRaw;
    } else if (nextCursorRaw != null && nextCursorRaw is! String) {
      debugPrint('[ApiClient] Unexpected nextCursor type: ${nextCursorRaw.runtimeType}');
    }

    debugPrint(
      '[ApiClient] getMyPosts items=${items.length} nextCursor=${nextCursor ?? 'null'}',
    );
    return PostsPage(items: items, nextCursor: nextCursor);
  }

  Future<PostsPage> getUserPosts(
    String userId, {
    int limit = 30,
    String? cursor,
  }) async {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('userId must not be empty');
    }
    final resolvedLimit = limit <= 0 ? 30 : limit;
    final encodedId = Uri.encodeComponent(trimmed);
    final baseUri = _resolve('/api/users/$encodedId/posts');
    final queryParameters = <String, String>{
      'limit': resolvedLimit.toString(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = baseUri.replace(queryParameters: queryParameters);

    http.Response? response;
    for (var attempt = 0; attempt < 2; attempt++) {
      final forceRefresh = attempt == 1;
      final headers = await _composeHeaders(
        null,
        forceRefreshAuth: forceRefresh,
      );
      response = await _httpClient.get(
        uri,
        headers: headers.isEmpty ? null : headers,
      );

      final statusCode = response.statusCode;
      final isAuthError =
          statusCode == HttpStatus.unauthorized || statusCode == HttpStatus.forbidden;
      if (isAuthError && !forceRefresh) {
        await _authService?.fetchAuthToken(forceRefresh: true);
        continue;
      }
      debugPrint(
        '[ApiClient] getUserPosts attempt=$attempt status=$statusCode',
      );
      break;
    }

    if (response == null) {
      throw ApiException('Failed to load posts: no response');
    }

    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while loading posts',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode == HttpStatus.notFound) {
      return PostsPage(items: const <PostItem>[], nextCursor: null);
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to load posts: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }

    if (response.body.isEmpty) {
      return PostsPage(items: const <PostItem>[], nextCursor: null);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected posts response');
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw ApiException('Unexpected posts response: missing items');
    }

    final items = <PostItem>[];
    for (final entry in rawItems) {
      if (entry is! Map<String, dynamic>) {
        debugPrint('[ApiClient] Ignoring non-map post item: ${entry.runtimeType}');
        continue;
      }
      try {
        items.add(PostItem.fromJson(entry));
      } catch (error, stackTrace) {
        debugPrint('[ApiClient] Skipping malformed post item: $error\n$stackTrace');
      }
    }

    if (items.isEmpty) {
      debugPrint('[ApiClient] getUserPosts empty items payload=${response.body}');
    }

    final nextCursorRaw = decoded['nextCursor'];
    String? nextCursor;
    if (nextCursorRaw is String && nextCursorRaw.trim().isNotEmpty) {
      nextCursor = nextCursorRaw;
    } else if (nextCursorRaw != null && nextCursorRaw is! String) {
      debugPrint('[ApiClient] Unexpected nextCursor type: ${nextCursorRaw.runtimeType}');
    }

    debugPrint(
      '[ApiClient] getUserPosts items=${items.length} nextCursor=${nextCursor ?? 'null'}',
    );
    return PostsPage(items: items, nextCursor: nextCursor);
  }

  Future<StreamCheckResult> checkStreamStatus(String uid) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) {
      throw ArgumentError('uid must not be empty');
    }
    final uri = _resolve('/api/stream/check');
    final headers = await _jsonHeaders();
    final payload = jsonEncode({'uid': trimmedUid});
    debugPrint('[ApiClient] POST $uri');
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: payload,
    );
    final statusCode = response.statusCode;
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Stream check failed: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (response.body.isEmpty) {
      return const StreamCheckResult(ok: false, state: 'unknown', ready: false);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected stream check response');
    }

    bool _asBool(dynamic value) {
      if (value is bool) {
        return value;
      }
      if (value is num) {
        return value != 0;
      }
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'true' || normalized == '1') {
          return true;
        }
        if (normalized == 'false' || normalized == '0') {
          return false;
        }
      }
      return false;
    }

    String _asString(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      }
      if (value is num) {
        return value.toString();
      }
      return 'unknown';
    }

    final ok = _asBool(decoded['ok']) || statusCode == HttpStatus.ok;
    final ready = _asBool(decoded['ready']);
    final state = _asString(decoded['state']);
    return StreamCheckResult(ok: ok, state: state, ready: ready);
  }

  Future<Map<String, String>> _jsonHeaders({
    Map<String, String>? headers,
    bool forceRefreshAuth = false,
  }) async {
    final resolved = await _composeHeaders(
      headers,
      forceRefreshAuth: forceRefreshAuth,
    );
    resolved.putIfAbsent(HttpHeaders.contentTypeHeader, () => 'application/json');
    return resolved;
  }

  Future<Map<String, String>> _composeHeaders(
    Map<String, String>? headers, {
    bool forceRefreshAuth = false,
  }) async {
    final resolved = <String, String>{};
    if (headers != null) {
      resolved.addAll(headers);
    }
    final authorization = await _authorizationHeader(forceRefreshAuth: forceRefreshAuth);
    if (authorization != null) {
      resolved.putIfAbsent(HttpHeaders.authorizationHeader, () => authorization);
    }
    return resolved;
  }

  Future<String?> _authorizationHeader({bool forceRefreshAuth = false}) async {
    if (kAuthBypassEnabled) {
      return null;
    }
    final service = _authService;
    if (service == null) {
      return null;
    }
    final token = await service.fetchAuthToken(forceRefresh: forceRefreshAuth);
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

}
