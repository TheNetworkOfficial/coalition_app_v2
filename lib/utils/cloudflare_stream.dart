const String _defaultStreamBaseUrl = 'https://videodelivery.net';

const String _configuredStreamBaseUrl = String.fromEnvironment(
  'CF_STREAM_BASE_URL',
  defaultValue: _defaultStreamBaseUrl,
);

String get cloudflareStreamBaseUrl {
  final configured = _configuredStreamBaseUrl.trim();
  if (configured.isEmpty) {
    return _defaultStreamBaseUrl;
  }
  final withScheme = configured.startsWith('http://') || configured.startsWith('https://')
      ? configured
      : 'https://$configured';
  return withScheme.endsWith('/')
      ? withScheme.substring(0, withScheme.length - 1)
      : withScheme;
}

String? resolveCloudflareHlsUrl(Map<String, dynamic> json) {
  final direct = _findString(json, _directHlsUrlKeys, predicate: _looksLikeHttpUrl);
  if (direct != null) {
    return direct;
  }

  final playbackId = _findString(json, _playbackIdKeys);
  if (playbackId == null) {
    return null;
  }
  if (_looksLikeHttpUrl(playbackId)) {
    return playbackId;
  }
  final base = cloudflareStreamBaseUrl;
  return '$base/$playbackId/manifest/video.m3u8';
}

String? _findString(
  Map<String, dynamic> root,
  Set<String> candidateKeys, {
  bool Function(String value)? predicate,
}) {
  final queue = <dynamic>[root];

  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    if (current is Map<String, dynamic>) {
      for (final entry in current.entries) {
        final key = entry.key.toString().toLowerCase();
        final value = entry.value;
        if (candidateKeys.contains(key)) {
          final stringValue = _stringValue(value);
          if (stringValue != null && (predicate == null || predicate(stringValue))) {
            return stringValue;
          }
        }

        if (value is Map<String, dynamic>) {
          queue.add(value);
        } else if (value is Iterable && value is! String) {
          for (final element in value) {
            if (element is Map<String, dynamic> || (element is Iterable && element is! String)) {
              queue.add(element);
            }
          }
        }
      }
    } else if (current is Iterable && current is! String) {
      for (final element in current) {
        if (element is Map<String, dynamic> || (element is Iterable && element is! String)) {
          queue.add(element);
        }
      }
    }
  }

  return null;
}

String? _stringValue(dynamic value) {
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

bool _looksLikeHttpUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) {
    return false;
  }
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

const Set<String> _directHlsUrlKeys = {
  'cfplaybackurl',
  'cfplaybackurlhls',
  'cfplaybackurl_hls',
  'cfplaybackurlhlssigned',
  'cfplaybackurl_hls_signed',
  'cfhlsurl',
  'cloudflarehlsurl',
  'hlsmanifest',
  'hls_manifest',
  'hlsmanifesturl',
  'hls_manifest_url',
  'hlsurl',
  'hls_url',
  'manifesturl',
  'manifest_url',
  'streammanifesturl',
  'stream_manifest_url',
};

const Set<String> _playbackIdKeys = {
  'cfplaybackid',
  'cf_playback_id',
  'cf-playback-id',
  'cfplayback_id',
  'cfplaybackuuid',
  'cf_playback_uuid',
  'cfstreamplaybackid',
  'playbackid',
  'playback_id',
  'streamplaybackid',
};
