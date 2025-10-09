import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';

/// Minimal TUS 1.0.0 uploader (Cloudflare Stream compatible) using Dio.
/// - Works with large files (chunked PATCH uploads)
/// - Supports resume via HEAD (reads Upload-Offset)
/// - Progress callbacks
///
/// Usage:
///   final uploader = TusUploader();
///   await uploader.uploadFile(
///     file: File('/path/to/video.mp4'),
///     tusUploadUrl: tusUrlFromBackend, // e.g. returned by your /api/uploads/create when TUS is enabled
///     onProgress: (sent, total) { /* update UI */ },
///   );
class TusUploader {
  final Dio _dio;

  TusUploader({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              followRedirects: true,
              validateStatus: (code) =>
                  code != null && code < 400 || code == 409,
              // 409 can occur for some TUS conflict responses; we’ll handle explicitly.
            ));

  /// Upload in chunks to an existing TUS upload URL.
  /// If the upload was previously started, this method will resume from server offset.
  /// Additional headers (auth, custom metadata) can be provided via [headers];
  /// `Tus-Resumable: 1.0.0` is injected automatically if absent.
  Future<void> uploadFile({
    required File file,
    required String tusUploadUrl,
    Map<String, String>? headers,
    void Function(int sent, int total)? onProgress,
    int chunkSize = 8 * 1024 * 1024, // 8 MB chunks
    CancelToken? cancelToken,
  }) async {
    final length = await file.length();
    final baseHeaders = _normalizeBaseHeaders(headers);

    // 1) Ask server where to resume from.
    int offset = await _getOffset(tusUploadUrl, baseHeaders);
    if (offset > length) {
      throw Exception(
          'Server offset ($offset) exceeds local file length ($length).');
    }

    final raf = await file.open(mode: FileMode.read);
    try {
      while (offset < length) {
        final remaining = length - offset;
        final send = remaining < chunkSize ? remaining : chunkSize;

        // Read next chunk.
        await raf.setPosition(offset);
        final bytes = await raf.read(send);

        // 2) PATCH chunk to the TUS upload URL.
        final patchHeaders = <String, dynamic>{
          ...baseHeaders,
          'Content-Type': 'application/offset+octet-stream',
          'Upload-Offset': offset.toString(),
        };

        final resp = await _dio.patch<List<int>>(
          tusUploadUrl,
          data: Stream.fromIterable(<List<int>>[bytes]),
          options: Options(headers: patchHeaders, responseType: ResponseType.bytes),
          onSendProgress: (sent, total) {
            // sent here is bytes of THIS chunk; translate to global progress:
            onProgress?.call(offset + sent, length);
          },
          cancelToken: cancelToken,
        );

        // Cloudflare Stream typically returns 204 No Content on PATCH with updated Upload-Offset
        if (resp.statusCode == 204) {
          final newOffsetHeader = resp.headers.value('Upload-Offset');
          if (newOffsetHeader == null) {
            // If no header, assume success and advance by chunk size
            offset += bytes.length;
          } else {
            final newOffset =
                int.tryParse(newOffsetHeader) ?? (offset + bytes.length);
            if (newOffset < offset) {
              throw Exception(
                  'Server returned decreasing offset: $newOffset < $offset');
            }
            offset = newOffset;
          }
        } else if (resp.statusCode == 409) {
          // Conflict — typically means our Upload-Offset didn’t match server’s.
          // Refresh offset via HEAD and retry this iteration.
          offset = await _getOffset(tusUploadUrl, baseHeaders);
        } else {
          throw Exception(
              'TUS PATCH failed: ${resp.statusCode} ${resp.statusMessage}');
        }
      }

      // Completed
      onProgress?.call(length, length);
    } finally {
      await raf.close();
    }
  }

  Map<String, String> _normalizeBaseHeaders(Map<String, String>? headers) {
    final normalized = <String, String>{};
    if (headers != null && headers.isNotEmpty) {
      headers.forEach((key, value) {
        if (key.isEmpty) {
          return;
        }
        normalized[key] = value;
      });
    }
    final hasTusResumable = normalized.keys.any(
      (key) => key.toLowerCase() == 'tus-resumable',
    );
    if (!hasTusResumable) {
      normalized['Tus-Resumable'] = '1.0.0';
    }
    return normalized;
  }

  /// Query server for current Upload-Offset via HEAD.
  Future<int> _getOffset(
    String tusUploadUrl,
    Map<String, String> baseHeaders,
  ) async {
    final resp = await _dio.head(
      tusUploadUrl,
      options: Options(headers: Map<String, dynamic>.from(baseHeaders)),
    );

    if (resp.statusCode == 204 || resp.statusCode == 200) {
      final offsetHeader = resp.headers.value('Upload-Offset') ?? '0';
      final parsed = int.tryParse(offsetHeader) ?? 0;
      return parsed;
    }

    // Some implementations return 404 if the upload URL doesn’t exist.
    if (resp.statusCode == 404) {
      throw Exception('TUS upload not found (404). Did you create it first?');
    }

    throw Exception(
        'TUS HEAD failed: ${resp.statusCode} ${resp.statusMessage}');
  }

  /// (Optional) If you want to CREATE a TUS upload directly from the app (not recommended if you need secrets),
  /// you can use this helper. Prefer having your backend create and return the per-upload URL instead.
  Future<String> createUploadDirect({
    required Uri tusCreationEndpoint,
    required int uploadLength,
    required String filename,
    required String filetype, // e.g. "video/mp4"
    Map<String, String>? extraHeaders,
  }) async {
    // Encode Upload-Metadata per TUS spec: key base64(value), comma separated
    final metadata = {
      'filename': base64.encode(utf8.encode(filename)),
      'filetype': base64.encode(utf8.encode(filetype)),
    };
    final metadataHeader =
        metadata.entries.map((e) => '${e.key} ${e.value}').join(',');

    final headers = <String, dynamic>{
      'Tus-Resumable': '1.0.0',
      'Upload-Length': uploadLength.toString(),
      'Upload-Metadata': metadataHeader,
      // Cloudflare direct TUS creation usually also needs auth headers if hitting CF API directly.
      if (extraHeaders != null) ...extraHeaders,
    };

    final resp = await _dio.postUri(
      tusCreationEndpoint,
      options: Options(
          headers: headers, validateStatus: (c) => c != null && c < 400),
    );

    // The creation response must include a `Location` header with the per-upload URL
    final loc = resp.headers.value('Location');
    if (loc == null || loc.isEmpty) {
      throw Exception('TUS create did not return Location header.');
    }
    return loc;
  }
}
