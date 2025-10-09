class CreateUploadResponse {
  CreateUploadResponse({
    required this.uploadUrl,
    required this.uid,
    bool? requiresMultipart,
    Map<String, String>? headers,
    Map<String, String>? fields,
    String? method,
    String? taskId,
    this.fileFieldName,
    this.contentType,
  })  : requiresMultipart = requiresMultipart ?? false,
        headers = headers ?? const {},
        fields = fields ?? const {},
        method = (method == null || method.isEmpty)
            ? ((requiresMultipart ?? false) ? 'POST' : 'PUT')
            : method.toUpperCase(),
        taskId = taskId ?? uid;

  factory CreateUploadResponse.fromJson(
    Map<String, dynamic> json, {
    String? rawJson,
  }) {
    final cfAsset = json['cfAsset'];
    Map<String, dynamic>? cfAssetMap;
    if (cfAsset is Map<String, dynamic>) {
      cfAssetMap = cfAsset;
    }

    String? _stringValue(dynamic value) {
      if (value == null) {
        return null;
      }
      if (value is String) {
        return value;
      }
      return value.toString();
    }

    bool? _boolValue(dynamic value) {
      if (value is bool) {
        return value;
      }
      if (value is String) {
        if (value.toLowerCase() == 'true') {
          return true;
        }
        if (value.toLowerCase() == 'false') {
          return false;
        }
      }
      return null;
    }

    Map<String, String>? _stringMap(dynamic value) {
      if (value is Map) {
        final result = <String, String>{};
        value.forEach((key, val) {
          if (key is String && val != null) {
            result[key] = _stringValue(val) ?? '';
          }
        });
        return result;
      }
      return null;
    }

    String? urlString;
    for (final entry in <MapEntry<String, dynamic?>>[
      MapEntry('uploadUrl', json['uploadUrl']),
      MapEntry('uploadURL', json['uploadURL']),
      MapEntry('url', json['url']),
      if (cfAssetMap != null) ...[
        MapEntry('cfAsset.uploadUrl', cfAssetMap['uploadUrl']),
        MapEntry('cfAsset.uploadURL', cfAssetMap['uploadURL']),
        MapEntry('cfAsset.url', cfAssetMap['url']),
      ],
    ]) {
      final candidate = _stringValue(entry.value);
      if (candidate != null && candidate.isNotEmpty) {
        urlString = candidate;
        break;
      }
    }

    String? uidString;
    for (final entry in <MapEntry<String, dynamic?>>[
      MapEntry('uid', json['uid']),
      if (cfAssetMap != null) MapEntry('cfAsset.uid', cfAssetMap['uid']),
    ]) {
      final candidate = _stringValue(entry.value);
      if (candidate != null && candidate.isNotEmpty) {
        uidString = candidate;
        break;
      }
    }

    final missing = <String>[];
    if (urlString == null) {
      missing.add('uploadUrl');
    }
    if (uidString == null) {
      missing.add('uid');
    }
    if (missing.isNotEmpty) {
      final snippetRaw = rawJson;
      final truncated = snippetRaw == null
          ? null
          : snippetRaw.length > 200
              ? '${snippetRaw.substring(0, 200)}...'
              : snippetRaw;
      final sanitized = truncated
          ?.replaceAll('\n', '\\n')
          ?.replaceAll('\r', '\\r');
      final details =
          sanitized == null || sanitized.isEmpty ? '' : ' | raw: $sanitized';
      throw FormatException(
        'Upload response missing required fields: ${missing.join(', ')}$details',
      );
    }

    final requiresMultipart =
        _boolValue(json['requiresMultipart']) ??
            _boolValue(cfAssetMap?['requiresMultipart']) ??
            false;
    final headers =
        _stringMap(json['headers']) ?? _stringMap(cfAssetMap?['headers']);
    final fields =
        _stringMap(json['fields']) ?? _stringMap(cfAssetMap?['fields']);
    final method = _stringValue(json['method']) ?? _stringValue(cfAssetMap?['method']);
    final taskId =
        _stringValue(json['taskId']) ?? _stringValue(cfAssetMap?['taskId']);
    final fileFieldName = _stringValue(json['fileFieldName']) ??
        _stringValue(cfAssetMap?['fileFieldName']);
    final contentType = _stringValue(json['contentType']) ??
        _stringValue(cfAssetMap?['contentType']);

    return CreateUploadResponse(
      uploadUrl: Uri.parse(urlString!),
      uid: uidString!,
      requiresMultipart: requiresMultipart,
      headers: headers,
      fields: fields,
      method: method,
      taskId: taskId,
      fileFieldName: fileFieldName,
      contentType: contentType,
    );
  }

  final Uri uploadUrl;
  final String uid;
  final bool requiresMultipart;
  final Map<String, String> headers;
  final Map<String, String> fields;
  final String method;
  final String? taskId;
  final String? fileFieldName;
  final String? contentType;
}
