import 'package:flutter/foundation.dart';

const String kApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
const bool kAuthBypassEnabled =
    bool.fromEnvironment('AUTH_BYPASS', defaultValue: false);
const bool kPreferVideoProxyUploads =
    bool.fromEnvironment('UPLOAD_VIDEO_PROXY', defaultValue: true);

String normalizeApiBaseUrl(String base) {
  if (base.isEmpty) {
    return base;
  }
  return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
}

String get normalizedApiBaseUrl => normalizeApiBaseUrl(kApiBaseUrl);

Uri resolveApiUri(String path, {String? baseOverride}) {
  assert(path.startsWith('/'), 'path must start with "/"');
  final base = normalizeApiBaseUrl(baseOverride ?? kApiBaseUrl);
  if (base.isEmpty) {
    return Uri.parse(path);
  }
  return Uri.parse('$base$path');
}

void assertApiBaseConfigured() {
  assert(kApiBaseUrl.isNotEmpty, 'API_BASE_URL dart-define is required');
  debugPrint('[Env] API_BASE_URL = $kApiBaseUrl');
}
