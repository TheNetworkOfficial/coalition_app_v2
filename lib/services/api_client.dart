import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:coalition_app_v2/features/admin/models/admin_application.dart';
import 'package:coalition_app_v2/features/candidates/models/candidate.dart';
import 'package:coalition_app_v2/features/candidates/models/candidate_update.dart';
import 'package:coalition_app_v2/features/tags/models/tag_models.dart';

import 'package:coalition_app_v2/features/engagement/utils/ids.dart';
import '../debug/logging.dart';
import '../debug/logging_http_client.dart';
import '../env.dart';
import '../features/engagement/models/liker.dart';
import '../models/create_upload_response.dart';
import '../models/edit_manifest.dart';
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
    final extras =
        details == null || details!.isEmpty ? '' : ', details: $details';
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

class ImageUploadSession {
  ImageUploadSession({
    required this.uploadUrl,
    required this.method,
    required this.headers,
    required this.fields,
    required this.fileFieldName,
    required this.requiresMultipart,
    required this.contentType,
    this.deliveryUrl,
  });

  final String uploadUrl;
  final String method;
  final Map<String, String> headers;
  final Map<String, String> fields;
  final String fileFieldName;
  final bool requiresMultipart;
  final String? contentType;
  final String? deliveryUrl;
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

  bool get isFailed =>
      state.toLowerCase() == 'failed' || state.toLowerCase() == 'error';
}

class ApiClient {
  ApiClient({
    http.Client? httpClient,
    String? baseUrl,
    AuthService? authService,
  })  : _httpClient = httpClient ?? _createDefaultClient(),
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
  bool _loggedAuthHeaderPresence = false;

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

  Future<http.Response> putJson(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(path);
    final resolvedHeaders = await _jsonHeaders(headers: headers);
    final payload = jsonEncode(body ?? const <String, dynamic>{});
    return _httpClient.put(
      uri,
      headers: resolvedHeaders,
      body: payload,
    );
  }

  Future<http.Response> deleteJson(
    String path, {
    Map<String, String>? headers,
  }) async {
    final uri = _resolve(path);
    final resolvedHeaders = await _jsonHeaders(headers: headers);
    return _httpClient.delete(
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

    final uploadResponse =
        CreateUploadResponse.fromJson(jsonMap, rawJson: rawBody);

    return CreateUploadResult(
      response: uploadResponse,
      rawJson: jsonMap,
    );
  }

  Future<ImageUploadSession> createImageUploadSession({
    required String fileName,
    required int fileSize,
    required String contentType,
  }) async {
    final result = await createUpload(
      type: 'image',
      fileName: fileName,
      fileSize: fileSize,
      contentType: contentType,
    );
    final response = result.response;
    final method = (response.method).toUpperCase();
    final fileFieldName =
        (response.fileFieldName == null || response.fileFieldName!.isEmpty)
            ? 'file'
            : response.fileFieldName!;
    return ImageUploadSession(
      uploadUrl: response.uploadUrl.toString(),
      method: method,
      headers: Map<String, String>.from(response.headers),
      fields: Map<String, String>.from(response.fields),
      fileFieldName: fileFieldName,
      requiresMultipart: response.requiresMultipart,
      contentType: response.contentType ?? contentType,
      deliveryUrl: response.deliveryUrl,
    );
  }

  Future<void> uploadFileToUrl(
    String uploadUrl,
    File file, {
    Map<String, String>? headers,
    Map<String, String>? fields,
    String? method,
    String? fileFieldName,
    String? contentType,
  }) async {
    final uri = Uri.parse(uploadUrl);
    final host = uri.host.toLowerCase();
    final isCloudflareDirectUpload = host.contains('upload.imagedelivery.net');

    final normalizedMethod = (method?.toUpperCase() ?? 'POST');
    final effectiveFileFieldName =
        (fileFieldName != null && fileFieldName.trim().isNotEmpty)
            ? fileFieldName.trim()
            : 'file';

    final requestHeaders = Map<String, String>.from(headers ?? {});
    final requestFields = Map<String, String>.from(fields ?? {});

    if (isCloudflareDirectUpload) {
      final multipart = http.MultipartRequest('POST', uri);
      requestHeaders
          .removeWhere((k, _) => k.toLowerCase() == 'content-type');
      if (requestHeaders.isNotEmpty) {
        multipart.headers.addAll(requestHeaders);
      }
      if (requestFields.isNotEmpty) {
        multipart.fields.addAll(requestFields);
      }
      final mediaType =
          contentType != null ? MediaType.parse(contentType) : null;
      multipart.files.add(
        await http.MultipartFile.fromPath(
          effectiveFileFieldName,
          file.path,
          contentType: mediaType,
        ),
      );
      final streamed = await multipart.send();
      final responseBody = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw ApiException(
          'Upload failed with status ${streamed.statusCode}'
          '${responseBody.isEmpty ? '' : ': $responseBody'}',
          statusCode: streamed.statusCode,
          details: responseBody.isEmpty ? null : responseBody,
        );
      }
      return;
    }

    if (normalizedMethod == 'POST' && requestFields.isNotEmpty) {
      requestHeaders
          .removeWhere((k, _) => k.toLowerCase() == 'content-type');
      final multipart = http.MultipartRequest(normalizedMethod, uri);
      if (requestHeaders.isNotEmpty) {
        multipart.headers.addAll(requestHeaders);
      }
      multipart.fields.addAll(requestFields);
      final mediaType =
          contentType != null ? MediaType.parse(contentType) : null;
      multipart.files.add(
        await http.MultipartFile.fromPath(
          effectiveFileFieldName,
          file.path,
          contentType: mediaType,
        ),
      );
      final streamed = await multipart.send();
      final responseBody = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw ApiException(
          'Upload failed with status ${streamed.statusCode}'
          '${responseBody.isEmpty ? '' : ': $responseBody'}',
          statusCode: streamed.statusCode,
          details: responseBody.isEmpty ? null : responseBody,
        );
      }
      return;
    }

    final bytes = await file.readAsBytes();
    final request = http.Request(normalizedMethod, uri);
    if (requestHeaders.isNotEmpty) {
      request.headers.addAll(requestHeaders);
    }
    if (!request.headers.containsKey('Content-Type') && contentType != null) {
      request.headers['Content-Type'] = contentType;
    }
    request.bodyBytes = bytes;
    final streamed = await request.send();
    final responseBody = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException(
        'Upload failed with status ${streamed.statusCode}'
        '${responseBody.isEmpty ? '' : ': $responseBody'}',
        statusCode: streamed.statusCode,
        details: responseBody.isEmpty ? null : responseBody,
      );
    }
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
    EditManifest? editManifest,
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
      'editTimeline': editManifest == null
          ? null
          : jsonEncode(editManifest.toJson()),
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
    const path = '/api/profile/me';
    final uri = resolvePath(path);
    debugPrint('[ApiClient][TEMP] GET $uri');
    final response = await get(path);
    debugPrint(
      '[ApiClient][TEMP] getMyProfile status=${response.statusCode}',
    );
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
    final dynamic decoded =
        response.body.isEmpty ? null : jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      debugPrint(
        '[ApiClient][TEMP] getMyProfile decoded keys=${decoded.keys.toList()}',
      );
    } else {
      debugPrint(
        '[ApiClient][TEMP] getMyProfile decoded type=${decoded.runtimeType}',
      );
    }
    final profileMap = _extractProfileMap(decoded);
    if (profileMap != null) {
      debugPrint(
        '[ApiClient][TEMP] profileMap keys=${profileMap.keys.toList()}',
      );
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
    final dynamic decoded =
        response.body.isEmpty ? null : jsonDecode(response.body);
    final profileMap = _extractProfileMap(decoded);
    if (profileMap != null) {
      return Profile.fromJson(profileMap);
    }
    throw ApiException('Unexpected profile response format');
  }

  Future<Map<String, dynamic>> toggleFollow(String userId) async {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('userId must not be empty');
    }
    final uri = _resolve('/api/users/${Uri.encodeComponent(trimmed)}/follow');
    final headers = await _composeHeaders({'Content-Type': 'application/json'});
    final response = await _httpClient.post(uri, headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Failed to toggle follow (${response.statusCode})');
    }
    if (response.body.isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw Exception('Unexpected toggle follow response format');
  }

  Future<Map<String, dynamic>> createCandidateApplication({
    required String fullName,
    required String campaignAddress,
    required String fecCandidateId,
    required String fecCommitteeId,
    required String level,
    String? state,
    String? county,
    String? city,
    String? district,
  }) async {
    final payload = <String, dynamic>{
      'fullName': fullName,
      'campaignAddress': campaignAddress,
      'fecCandidateId': fecCandidateId,
      'fecCommitteeId': fecCommitteeId,
      'level': level,
      if (state != null && state.trim().isNotEmpty) 'state': state.trim(),
      if (county != null && county.trim().isNotEmpty) 'county': county.trim(),
      if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
      if (district != null && district.trim().isNotEmpty)
        'district': district.trim(),
    };
    final response = await postJson(
      '/api/candidateApplications',
      body: payload,
    );
    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to submit candidate application: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (response.body.isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw ApiException('Unexpected candidate application response format');
  }

  Future<Map<String, dynamic>?> getMyCandidateApplication() async {
    final response = await get('/api/candidateApplications/me');
    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.notFound) {
      return null;
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to load candidate application: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (response.body.isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    throw ApiException('Unexpected candidate application response format');
  }

  Future<AdminApplicationsPage> listAdminApplications({
    String status = 'pending',
    int limit = 20,
    String? cursor,
  }) async {
    final resolvedLimit = limit <= 0 ? 20 : limit;
    final trimmedCursor = cursor?.trim();
    final queryParameters = <String, String>{
      'status': status,
      'limit': '$resolvedLimit',
      if (trimmedCursor != null && trimmedCursor.isNotEmpty)
        'cursor': trimmedCursor,
    };
    final response = await get(
      '/api/candidateApplications',
      queryParameters: queryParameters,
    );
    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while loading candidate applications',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to load candidate applications: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (response.body.isEmpty) {
      return const AdminApplicationsPage(
        items: <AdminApplication>[],
        nextCursor: null,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected candidate applications response');
    }
    final rawItems = decoded['applications'];
    final items = <AdminApplication>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map<String, dynamic>) {
          try {
            items.add(_adminApplicationFromJson(entry));
          } catch (error, stackTrace) {
            debugPrint(
              '[ApiClient] Skipping malformed admin application: $error\n$stackTrace',
            );
          }
        }
      }
    }
    final nextCursor = (decoded['nextCursor'] as String?)?.trim();
    return AdminApplicationsPage(
      items: List<AdminApplication>.unmodifiable(items),
      nextCursor: (nextCursor != null && nextCursor.isNotEmpty)
          ? nextCursor
          : null,
    );
  }

  Future<AdminApplication> getAdminApplication(String applicationId) async {
    final trimmed = applicationId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('applicationId must not be empty');
    }
    final encoded = Uri.encodeComponent(trimmed);
    final response = await get('/api/candidateApplications/$encoded');
    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while loading application',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode == HttpStatus.notFound) {
      throw ApiException(
        'Application not found',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to load application: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (response.body.isEmpty) {
      throw ApiException('Empty application response', statusCode: statusCode);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected application response');
    }
    final raw = decoded['application'];
    if (raw is! Map<String, dynamic>) {
      throw ApiException('Missing application payload');
    }
    return _adminApplicationFromJson(raw);
  }

  Future<ApprovalResult> approveAdminApplication(
    String applicationId, {
    String? reason,
  }) async {
    final trimmed = applicationId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('applicationId must not be empty');
    }
    final encoded = Uri.encodeComponent(trimmed);
    final response = await postJson(
      '/api/candidateApplications/$encoded/approve',
      body: const <String, dynamic>{},
    );
    return _parseApprovalResponse(response, fallbackId: trimmed);
  }

  Future<ApprovalResult> rejectAdminApplication(
    String applicationId, {
    String? reason,
  }) async {
    final trimmed = applicationId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('applicationId must not be empty');
    }
    final encoded = Uri.encodeComponent(trimmed);
    final payload = <String, dynamic>{
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };
    final response = await postJson(
      '/api/candidateApplications/$encoded/reject',
      body: payload,
    );
    return _parseApprovalResponse(response, fallbackId: trimmed);
  }

  Future<List<TagCategory>> getTagCatalog() async {
    final uri = _resolve('/api/tagCatalog');
    final headers = await _jsonHeaders();
    final response = await _httpClient.get(uri, headers: headers);
    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while loading tag catalog',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw HttpException('tagCatalog $statusCode');
    }
    if (response.body.isEmpty) {
      return const <TagCategory>[];
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected tag catalog response');
    }
    final rawCategories = decoded['categories'];
    final categories = <TagCategory>[];
    if (rawCategories is List) {
      for (final entry in rawCategories) {
        if (entry is Map<String, dynamic>) {
          categories.add(TagCategory.fromJson(entry));
        }
      }
    }
    return List<TagCategory>.unmodifiable(categories);
  }

  Future<TagCategory> createTagCategory({
    required String name,
    int order = 0,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('name must not be empty');
    }
    final uri = _resolve('/api/tagCatalog');
    final headers = await _jsonHeaders();
    final payload = <String, dynamic>{
      'name': trimmedName,
      'order': order,
    };
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    return _parseTagCategoryResponse(
      response,
      fallbackName: trimmedName,
      operation: 'create tag category',
    );
  }

  Future<TagCategory> updateTagCategory({
    required String categoryId,
    String? name,
    int? order,
  }) async {
    final trimmedId = categoryId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError('categoryId must not be empty');
    }
    if ((name == null || name.trim().isEmpty) && order == null) {
      throw ArgumentError('name or order must be provided');
    }
    final encodedId = Uri.encodeComponent(trimmedId);
    final uri = _resolve('/api/tagCatalog/$encodedId');
    final headers = await _jsonHeaders();
    final payload = <String, dynamic>{
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      if (order != null) 'order': order,
    };
    final response = await _httpClient.patch(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    return _parseTagCategoryResponse(
      response,
      fallbackId: trimmedId,
      fallbackName: name?.trim(),
      operation: 'update tag category',
    );
  }

  Future<void> deleteTagCategory(String categoryId) async {
    final trimmedId = categoryId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError('categoryId must not be empty');
    }
    final encodedId = Uri.encodeComponent(trimmedId);
    final uri = _resolve('/api/tagCatalog/$encodedId');
    final headers = await _jsonHeaders();
    final response = await _httpClient.delete(uri, headers: headers);
    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while deleting tag category',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode == HttpStatus.notFound) {
      throw ApiException(
        'Tag category not found',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to delete tag category: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
  }

  Future<TagCategory> addTagToCategory({
    required String categoryId,
    required String label,
    String? value,
  }) async {
    final trimmedId = categoryId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError('categoryId must not be empty');
    }
    final trimmedLabel = label.trim();
    if (trimmedLabel.isEmpty) {
      throw ArgumentError('label must not be empty');
    }
    final encodedId = Uri.encodeComponent(trimmedId);
    final uri = _resolve('/api/tagCatalog/$encodedId/tags');
    final headers = await _jsonHeaders();
    final payload = <String, dynamic>{
      'label': trimmedLabel,
      if (value != null && value.trim().isNotEmpty) 'value': value.trim(),
    };
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    return _parseTagCategoryResponse(
      response,
      fallbackId: trimmedId,
      operation: 'add tag to category',
    );
  }

  Future<TagCategory> updateTagInCategory({
    required String categoryId,
    required String tagId,
    String? label,
    String? value,
  }) async {
    final trimmedCategoryId = categoryId.trim();
    final trimmedTagId = tagId.trim();
    if (trimmedCategoryId.isEmpty) {
      throw ArgumentError('categoryId must not be empty');
    }
    if (trimmedTagId.isEmpty) {
      throw ArgumentError('tagId must not be empty');
    }
    if ((label == null || label.trim().isEmpty) &&
        (value == null || value.trim().isEmpty)) {
      throw ArgumentError('label or value must be provided');
    }
    final encodedCategoryId = Uri.encodeComponent(trimmedCategoryId);
    final encodedTagId = Uri.encodeComponent(trimmedTagId);
    final uri =
        _resolve('/api/tagCatalog/$encodedCategoryId/tags/$encodedTagId');
    final headers = await _jsonHeaders();
    final payload = <String, dynamic>{
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
      if (value != null && value.trim().isNotEmpty) 'value': value.trim(),
    };
    final response = await _httpClient.patch(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );
    return _parseTagCategoryResponse(
      response,
      fallbackId: trimmedCategoryId,
      operation: 'update tag in category',
    );
  }

  Future<TagCategory> deleteTagInCategory({
    required String categoryId,
    required String tagId,
  }) async {
    final trimmedCategoryId = categoryId.trim();
    final trimmedTagId = tagId.trim();
    if (trimmedCategoryId.isEmpty) {
      throw ArgumentError('categoryId must not be empty');
    }
    if (trimmedTagId.isEmpty) {
      throw ArgumentError('tagId must not be empty');
    }
    final encodedCategoryId = Uri.encodeComponent(trimmedCategoryId);
    final encodedTagId = Uri.encodeComponent(trimmedTagId);
    final uri =
        _resolve('/api/tagCatalog/$encodedCategoryId/tags/$encodedTagId');
    final headers = await _jsonHeaders();
    final response = await _httpClient.delete(uri, headers: headers);
    return _parseTagCategoryResponse(
      response,
      fallbackId: trimmedCategoryId,
      operation: 'delete tag in category',
    );
  }

  TagCategory _parseTagCategoryResponse(
    http.Response response, {
    String? fallbackId,
    String? fallbackName,
    required String operation,
  }) {
    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while attempting to $operation',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode == HttpStatus.notFound) {
      throw ApiException(
        'Tag category not found',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to $operation: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (response.body.isEmpty) {
      throw ApiException('Empty response while attempting to $operation');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected response while attempting to $operation');
    }
    final rawCategory = decoded['category'];
    if (rawCategory is Map<String, dynamic>) {
      return TagCategory.fromJson(rawCategory);
    }
    if (decoded['ok'] == true && fallbackId != null) {
      return TagCategory(
        categoryId: fallbackId,
        name: fallbackName ?? fallbackId,
        order: 0,
        tags: const <TagDefinition>[],
      );
    }
    throw ApiException('Missing category in response while attempting to $operation');
  }

  ApprovalResult _parseApprovalResponse(
    http.Response response, {
    required String fallbackId,
  }) {
    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while moderating application',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode == HttpStatus.notFound) {
      throw ApiException(
        'Application not found',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Application moderation failed: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (response.body.isEmpty) {
      return ApprovalResult(applicationId: fallbackId, status: 'unknown');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected moderation response');
    }
    final raw = decoded['application'];
    if (raw is! Map<String, dynamic>) {
      return ApprovalResult(
        applicationId: fallbackId,
        status: (decoded['status'] as String?) ?? 'unknown',
        reason: decoded['reason'] as String?,
      );
    }
    final map = raw;
    final applicationId =
        (map['applicationId'] as String?)?.trim().isNotEmpty == true
            ? map['applicationId'] as String
            : fallbackId;
    final status =
        (map['status'] as String?)?.trim().toLowerCase() ?? 'unknown';
    return ApprovalResult(
      applicationId: applicationId,
      status: status,
      reason: (map['reason'] as String?)?.trim().isNotEmpty == true
          ? (map['reason'] as String).trim()
          : null,
    );
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
    final dynamic decoded =
        response.body.isEmpty ? null : jsonDecode(response.body);
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
      final isAuthError = statusCode == HttpStatus.unauthorized ||
          statusCode == HttpStatus.forbidden;
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
        debugPrint(
            '[ApiClient] Ignoring non-map post item: ${entry.runtimeType}');
        continue;
      }
      try {
        items.add(PostItem.fromJson(entry));
      } catch (error, stackTrace) {
        debugPrint(
            '[ApiClient] Skipping malformed post item: $error\n$stackTrace');
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
      debugPrint(
          '[ApiClient] Unexpected nextCursor type: ${nextCursorRaw.runtimeType}');
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
      final isAuthError = statusCode == HttpStatus.unauthorized ||
          statusCode == HttpStatus.forbidden;
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
        debugPrint(
            '[ApiClient] Ignoring non-map post item: ${entry.runtimeType}');
        continue;
      }
      try {
        items.add(PostItem.fromJson(entry));
      } catch (error, stackTrace) {
        debugPrint(
            '[ApiClient] Skipping malformed post item: $error\n$stackTrace');
      }
    }

    if (items.isEmpty) {
      debugPrint(
          '[ApiClient] getUserPosts empty items payload=${response.body}');
    }

    final nextCursorRaw = decoded['nextCursor'];
    String? nextCursor;
    if (nextCursorRaw is String && nextCursorRaw.trim().isNotEmpty) {
      nextCursor = nextCursorRaw;
    } else if (nextCursorRaw != null && nextCursorRaw is! String) {
      debugPrint(
          '[ApiClient] Unexpected nextCursor type: ${nextCursorRaw.runtimeType}');
    }

    debugPrint(
      '[ApiClient] getUserPosts items=${items.length} nextCursor=${nextCursor ?? 'null'}',
    );
    return PostsPage(items: items, nextCursor: nextCursor);
  }

  Future<PostsPage> getCandidatePosts(
    String candidateId, {
    int limit = 30,
    String? cursor,
  }) async {
    final trimmed = candidateId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('candidateId must not be empty');
    }
    final resolvedLimit = limit <= 0 ? 30 : limit;
    final encodedId = Uri.encodeComponent(trimmed);
    final baseUri = _resolve('/api/candidates/$encodedId/posts');
    final queryParameters = <String, String>{
      'limit': resolvedLimit.toString(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = baseUri.replace(queryParameters: queryParameters);

    var omitAuth = true;
    final authService = _authService;
    if (authService != null) {
      try {
        final signedIn = await authService.isSignedIn();
        omitAuth = !signedIn;
      } catch (_) {
        omitAuth = true;
      }
    }
    final headers = await _composeHeaders(
      null,
      omitAuth: omitAuth,
    );
    final response = await _httpClient.get(
      uri,
      headers: headers.isEmpty ? null : headers,
    );
    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while loading candidate posts',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode == HttpStatus.notFound) {
      return PostsPage(items: const <PostItem>[], nextCursor: null);
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to load candidate posts: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }

    if (response.body.isEmpty) {
      return PostsPage(items: const <PostItem>[], nextCursor: null);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected candidate posts response format');
    }

    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw ApiException('Unexpected candidate posts response: missing items');
    }

    final items = <PostItem>[];
    for (final entry in rawItems) {
      if (entry is! Map<String, dynamic>) {
        debugPrint(
            '[ApiClient] Ignoring non-map candidate post item: ${entry.runtimeType}');
        continue;
      }
      try {
        items.add(PostItem.fromJson(entry));
      } catch (error, stackTrace) {
        debugPrint(
            '[ApiClient] Skipping malformed candidate post item: $error\n$stackTrace');
      }
    }

    final nextCursorRaw = decoded['nextCursor'];
    String? nextCursor;
    if (nextCursorRaw is String && nextCursorRaw.trim().isNotEmpty) {
      nextCursor = nextCursorRaw;
    } else if (nextCursorRaw != null && nextCursorRaw is! String) {
      debugPrint(
          '[ApiClient] Unexpected candidate posts nextCursor type: ${nextCursorRaw.runtimeType}');
    }

    debugPrint(
      '[ApiClient] getCandidatePosts items=${items.length} nextCursor=${nextCursor ?? 'null'}',
    );
    return PostsPage(items: items, nextCursor: nextCursor);
  }

  Future<LikersPage> getPostLikers(
    String postId, {
    int limit = 50,
    String? cursor,
  }) async {
    final normalized = normalizePostId(postId);
    if (normalized.isEmpty) {
      return const LikersPage(items: <Liker>[], nextCursor: null);
    }
    final encoded = Uri.encodeComponent(normalized);
    final baseUri = _resolve('/api/posts/$encoded/likes');
    final queryParameters = <String, String>{
      'limit': limit <= 0 ? '50' : '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = baseUri.replace(queryParameters: queryParameters);

    final headers = await _composeHeaders(null);
    final response = await _httpClient.get(
      uri,
      headers: headers.isEmpty ? null : headers,
    );

    if (response.statusCode == HttpStatus.notFound) {
      return const LikersPage(items: <Liker>[], nextCursor: null);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Failed to load post likers: ${response.statusCode}',
        statusCode: response.statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }

    if (response.body.isEmpty) {
      return const LikersPage(items: <Liker>[], nextCursor: null);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected likers response');
    }

    return LikersPage.fromJson(decoded);
  }

  Future<({List<Candidate> items, String? cursor})> getCandidates({
    int limit = 20,
    String? cursor,
    String? level,
    String? district,
    String? tag,
    String? tags,
    String? query,
  }) async {
    final resolvedLimit = limit <= 0 ? 20 : limit;
    final queryParameters = <String, String>{
      'limit': resolvedLimit.toString(),
      if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      if (level != null && level.trim().isNotEmpty) 'level': level.trim(),
      if (district != null && district.trim().isNotEmpty)
        'district': district.trim(),
      if (tag != null && tag.trim().isNotEmpty) 'tag': tag.trim(),
      if (tags != null && tags.trim().isNotEmpty) 'tags': tags.trim(),
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    };

    final baseUri = _resolve('/api/candidates');
    final uri = queryParameters.isEmpty
        ? baseUri
        : baseUri.replace(
            queryParameters: {
              if (baseUri.hasQuery) ...baseUri.queryParameters,
              ...queryParameters,
            },
          );

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
      final isAuthError = statusCode == HttpStatus.unauthorized ||
          statusCode == HttpStatus.forbidden;
      if (isAuthError && !forceRefresh) {
        await _authService?.fetchAuthToken(forceRefresh: true);
        continue;
      }
      break;
    }

    if (response == null) {
      throw ApiException('Failed to load candidates: no response');
    }

    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.forbidden) {
      throw ApiException(
        'Forbidden while loading candidates',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode == HttpStatus.notFound) {
      return (items: const <Candidate>[], cursor: null);
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to load candidates: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }

    if (response.body.isEmpty) {
      return (items: const <Candidate>[], cursor: null);
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException('Unexpected candidates response format');
    }

    final rawItems = decoded['items'];
    final items = rawItems is List
        ? rawItems
            .whereType<Map>()
            .map((raw) {
              try {
                final m = Map<String, dynamic>.from(raw);
                final fallbackId = (m['candidateId'] ??
                        m['id'] ??
                        m['candidate_id'] ??
                        '')
                    .toString()
                    .trim();
                m['candidateId'] = fallbackId;
                return Candidate.fromJson(m);
              } catch (error, stackTrace) {
                debugPrint(
                  '[ApiClient] Skipping malformed candidate item: $error\n$stackTrace',
                );
                return null;
              }
            })
            .whereType<Candidate>()
            .toList()
        : <Candidate>[];

    final rawCursor = decoded['cursor'] ?? decoded['nextCursor'];
    String? nextCursor;
    if (rawCursor is String) {
      final trimmed = rawCursor.trim();
      if (trimmed.isNotEmpty) {
        nextCursor = trimmed;
      }
    }

    return (
      items: List<Candidate>.unmodifiable(items),
      cursor: nextCursor,
    );
  }

  Future<({Candidate candidate})> getCandidate(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('id must not be empty');
    }
    final encodedId = Uri.encodeComponent(trimmed);
    final response = await get('/api/candidates/$encodedId');

    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.notFound) {
      throw ApiException(
        'Candidate not found',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to load candidate: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }

    if (response.body.isEmpty) {
      throw ApiException('Empty response while loading candidate');
    }

    final decoded = jsonDecode(response.body);
    final map = _extractCandidateMap(decoded);
    if (map == null) {
      throw ApiException('Unexpected candidate response format');
    }

    return (candidate: Candidate.fromJson(map));
  }

  Future<Candidate> updateCandidate(String id, CandidateUpdate update) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('id must not be empty');
    }
    final encodedId = Uri.encodeComponent(trimmed);
    final uri = _resolve('/api/candidates/$encodedId');
    final headers = await _jsonHeaders();
    final response = await _httpClient.patch(
      uri,
      headers: headers,
      body: jsonEncode(update.toJson()),
    );

    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode == HttpStatus.notFound) {
      throw ApiException(
        'Candidate not found',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to update candidate: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
    if (response.body.isEmpty) {
      throw ApiException('Empty response while updating candidate');
    }

    final decoded = jsonDecode(response.body);
    final map = _extractCandidateMap(decoded);
    if (map == null) {
      throw ApiException('Unexpected candidate response format');
    }

    return Candidate.fromJson(map);
  }

  Future<void> toggleCandidateFollow(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('id must not be empty');
    }
    final encodedId = Uri.encodeComponent(trimmed);
    final uri = _resolve('/api/candidates/$encodedId/follow');
    final headers = await _jsonHeaders();
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: jsonEncode(const <String, String>{}),
    );

    final statusCode = response.statusCode;
    if (statusCode == HttpStatus.unauthorized) {
      throw ApiException('Unauthorized', statusCode: statusCode);
    }
    if (statusCode < 200 || statusCode >= 300) {
      throw ApiException(
        'Failed to toggle candidate follow: $statusCode',
        statusCode: statusCode,
        details: response.body.isEmpty ? null : response.body,
      );
    }
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

  AdminApplication _adminApplicationFromJson(Map<String, dynamic> json) {
    String? stringValue(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      if (value is num) {
        return value.toString();
      }
      return null;
    }

    final id = stringValue(json['applicationId']) ??
        stringValue(json['id']) ??
        stringValue(json['candidateApplicationId']) ??
        '';
    if (id.isEmpty) {
      throw ApiException('Missing application id');
    }
    final fullName =
        stringValue(json['fullName']) ?? stringValue(json['name']) ?? 'Unknown applicant';
    final status = stringValue(json['status'])?.toLowerCase() ?? 'pending';
    final avatarUrl = stringValue(json['avatarUrl']) ??
        stringValue(json['userAvatarUrl']) ??
        stringValue(json['profileImageUrl']);
    final level = stringValue(json['level']);
    final state = stringValue(json['state']);
    final county = stringValue(json['county']);
    final city = stringValue(json['city']);
    final district = stringValue(json['district']);
    final reason = stringValue(json['reason']);
    final fecCandidateId = stringValue(json['fecCandidateId']);
    final fecCommitteeId = stringValue(json['fecCommitteeId']);
    final campaignAddress = stringValue(json['campaignAddress']);
    final email = stringValue(json['email']);
    final phone = stringValue(json['phone']);

    final createdAtMs =
        (json['createdAt'] as num?)?.toInt() ?? (json['submittedAt'] as num?)?.toInt();
    DateTime submittedAt = DateTime.now();
    if (createdAtMs != null) {
      submittedAt = DateTime.fromMillisecondsSinceEpoch(
        createdAtMs,
        isUtc: true,
      ).toLocal();
    } else {
      final createdAtIso = stringValue(json['createdAt']) ??
          stringValue(json['submittedAt']) ??
          stringValue(json['createdAtIso']);
      if (createdAtIso != null) {
        final parsed = DateTime.tryParse(createdAtIso);
        if (parsed != null) {
          submittedAt = parsed.toLocal();
        }
      }
    }

    final tags = <String>[];
    void addTag(String? value) {
      if (value == null) {
        return;
      }
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (!tags.contains(trimmed)) {
        tags.add(trimmed);
      }
    }

    addTag(level);
    addTag(state);
    if (district != null && district.trim().isNotEmpty) {
      addTag('District ${district.trim()}');
    }
    if (county != null && county.trim().isNotEmpty) {
      addTag('${county.trim()} County');
    }
    addTag(city);

    final summary = _buildAdminSummary(
      level: level,
      state: state,
      city: city,
      district: district,
    );

    final details = <String, Object?>{
      'Full name': fullName,
      'User ID': stringValue(json['userId']),
      'Status': status,
      'Reason': reason,
      'Campaign address': campaignAddress,
      'FEC candidate ID': fecCandidateId,
      'FEC committee ID': fecCommitteeId,
      'Level': level,
      'State': state,
      'County': county,
      'City': city,
      'District': district,
      'Email': email,
      'Phone': phone,
      'Submitted at': submittedAt.toIso8601String(),
      'Updated at': stringValue(json['updatedAt']),
    };

    return AdminApplication(
      id: id,
      fullName: fullName,
      status: status,
      submittedAt: submittedAt,
      avatarUrl: avatarUrl,
      summary: summary,
      details: details,
      tags: List<String>.unmodifiable(tags),
    );
  }

  String? _buildAdminSummary({
    String? level,
    String? state,
    String? city,
    String? district,
  }) {
    final parts = <String>[];
    if (level != null && level.trim().isNotEmpty) {
      parts.add(level.trim());
    }
    if (state != null && state.trim().isNotEmpty) {
      parts.add(state.trim());
    }
    if (city != null && city.trim().isNotEmpty) {
      parts.add(city.trim());
    }
    if (district != null && district.trim().isNotEmpty) {
      parts.add('District ${district.trim()}');
    }
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' • ');
  }

  Future<Map<String, String>> _jsonHeaders({
    Map<String, String>? headers,
    bool forceRefreshAuth = false,
  }) async {
    final resolved = await _composeHeaders(
      headers,
      forceRefreshAuth: forceRefreshAuth,
    );
    resolved.putIfAbsent(
        HttpHeaders.contentTypeHeader, () => 'application/json');
    return resolved;
  }

  Future<Map<String, String>> _composeHeaders(
    Map<String, String>? headers, {
    bool forceRefreshAuth = false,
    bool omitAuth = false,
  }) async {
    final resolved = <String, String>{};
    if (headers != null) {
      resolved.addAll(headers);
    }
    resolved.putIfAbsent(
      HttpHeaders.acceptHeader,
      () => 'application/json',
    );
    if (!omitAuth) {
      final authorization =
          await _authorizationHeader(forceRefreshAuth: forceRefreshAuth);
      if (authorization != null) {
        resolved.putIfAbsent(
          HttpHeaders.authorizationHeader,
          () => authorization,
        );
      }
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
    if (!_loggedAuthHeaderPresence) {
      logDebug(
        'AUTH',
        'auth header present?',
        extra: <String, Object?>{'present': token != null && token.isNotEmpty},
      );
      _loggedAuthHeaderPresence = true;
    }
    if (token == null || token.isEmpty) {
      return null;
    }
    return 'Bearer $token';
  }

  static http.Client _createDefaultClient() {
    final client = http.Client();
    if (!kDebugMode) {
      return client;
    }
    return LoggingClient(client);
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

  Map<String, dynamic>? _extractCandidateMap(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      final candidate = payload['candidate'];
      if (candidate is Map<String, dynamic>) {
        return Map<String, dynamic>.from(candidate);
      }
      final hasCandidateFields = payload.containsKey('candidateId') ||
          payload.containsKey('id') ||
          payload.containsKey('name');
      if (hasCandidateFields) {
        return Map<String, dynamic>.from(payload);
      }
    }
    return null;
  }
}
