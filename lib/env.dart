import 'package:flutter/foundation.dart';

const String kApiBaseUrl =
    String.fromEnvironment('API_BASE_URL', defaultValue: '');
const bool kAuthBypassEnabled =
    bool.fromEnvironment('AUTH_BYPASS', defaultValue: false);
const bool kPreferVideoProxyUploads =
    bool.fromEnvironment('UPLOAD_VIDEO_PROXY', defaultValue: false);
const bool _kLegacyNativeTusUploader =
    bool.fromEnvironment('USE_NATIVE_TUS_UPLOADER', defaultValue: true);
const bool kUseNativeTusUploader =
    bool.fromEnvironment('USE_NATIVE_TUS', defaultValue: _kLegacyNativeTusUploader);
const bool kShowUploadHud =
    bool.fromEnvironment('SHOW_UPLOAD_HUD', defaultValue: true);
const bool kUsePushReplacementForReview = bool.fromEnvironment(
  'USE_PUSH_REPLACEMENT_FOR_REVIEW',
  defaultValue: false,
);
const bool kShowEditContinueBarrier =
    bool.fromEnvironment('SHOW_EDIT_CONTINUE_BARRIER', defaultValue: false);
const bool kTusRequireUnmeteredNetwork =
    bool.fromEnvironment('TUS_REQUIRE_UNMETERED', defaultValue: false);
// Feature flag to enable segmented (chunked) preview proxying (10s segments).
// Enabled by default; pass --dart-define=ENABLE_SEGMENTED_PREVIEW=false to opt out.
const bool kEnableSegmentedPreview =
    bool.fromEnvironment('ENABLE_SEGMENTED_PREVIEW', defaultValue: true);
const bool kBlockOnUpload =
    bool.fromEnvironment('BLOCK_ON_UPLOAD', defaultValue: false);
const String kCloudflareImagesAccountHash =
    String.fromEnvironment('CF_IMAGES_ACCOUNT_HASH', defaultValue: '');
const String kCloudflareImagesVariant =
    String.fromEnvironment('CF_IMAGES_VARIANT', defaultValue: 'public');
const String kImagesPublicBaseUrl = String.fromEnvironment(
  'IMAGE_PUBLIC_BASE_URL',
  defaultValue: '',
);

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

String? buildImageDeliveryUrl(String? primaryKey, {String? fallbackKey}) {
  String? normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  final key = normalize(primaryKey) ?? normalize(fallbackKey);
  if (key == null) {
    return null;
  }

  final accountHash = kCloudflareImagesAccountHash.trim();
  if (accountHash.isNotEmpty) {
    final variant = kCloudflareImagesVariant.trim().isEmpty
        ? 'public'
        : kCloudflareImagesVariant.trim();
    final normalizedKey = key.contains('/')
        ? key
        : '$key/$variant';
    return 'https://imagedelivery.net/$accountHash/$normalizedKey';
  }

  final publicBase = kImagesPublicBaseUrl.trim();
  if (publicBase.isNotEmpty) {
    final sanitizedBase = publicBase.endsWith('/')
        ? publicBase.substring(0, publicBase.length - 1)
        : publicBase;
    final sanitizedKey = key.startsWith('/') ? key.substring(1) : key;
    return '$sanitizedBase/$sanitizedKey';
  }

  return null;
}

void assertApiBaseConfigured() {
  assert(kApiBaseUrl.isNotEmpty, 'API_BASE_URL dart-define is required');
  debugPrint('[Env] API_BASE_URL = $kApiBaseUrl');
}
