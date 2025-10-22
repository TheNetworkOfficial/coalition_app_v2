import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'logging.dart';

class LoggingClient extends http.BaseClient {
  LoggingClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!kDebugMode) {
      return _inner.send(request);
    }

    const tag = 'HTTP';
    final started = DateTime.now();
    final redactedRequestHeaders = _redactHeaders(request.headers);
    final bodyPreview = _requestBodyPreview(request);

    logDebug(
      tag,
      '→ ${request.method} ${request.url}',
      extra: <String, Object?>{
        'headers': redactedRequestHeaders,
        if (bodyPreview != null) 'body': bodyPreview,
      },
    );

    try {
      final streamed = await _inner.send(request);
      final elapsed = DateTime.now().difference(started).inMilliseconds;

      late http.Response materialized;
      try {
        materialized = await http.Response.fromStream(streamed);
      } catch (error, stackTrace) {
        logDebug(
          tag,
          '← ${request.method} ${request.url} [stream error] in ${elapsed}ms: $error',
          extra: stackTrace.toString(),
        );
        rethrow;
      }

      final responsePreview = _responseBodyPreview(materialized);
      logDebug(
        tag,
        '← ${request.method} ${request.url} [${materialized.statusCode}] in ${elapsed}ms',
        extra: <String, Object?>{
          'headers': _redactHeaders(materialized.headers),
          if (responsePreview != null) 'body': responsePreview,
        },
      );

      return http.StreamedResponse(
        Stream<List<int>>.value(materialized.bodyBytes),
        materialized.statusCode,
        contentLength: materialized.contentLength,
        request: request,
        headers: materialized.headers,
        reasonPhrase: materialized.reasonPhrase,
        isRedirect: materialized.isRedirect,
        persistentConnection: materialized.persistentConnection,
      );
    } catch (error, stackTrace) {
      logDebug(
        tag,
        '⨯ ${request.method} ${request.url}: $error',
        extra: stackTrace.toString(),
      );
      rethrow;
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

Map<String, String> _redactHeaders(Map<String, String> headers) {
  final sanitized = <String, String>{};
  headers.forEach((key, value) {
    if (key.toLowerCase() == 'authorization') {
      sanitized[key] = '***';
    } else {
      sanitized[key] = value;
    }
  });
  return sanitized;
}

Object? _requestBodyPreview(http.BaseRequest request) {
  if (request is http.Request && request.body.isNotEmpty) {
    return _tryDecodeJson(request.body) ?? _truncate(request.body, 512);
  }
  return null;
}

Object? _responseBodyPreview(http.Response response) {
  final body = response.body;
  if (body.isEmpty) {
    return null;
  }
  return _tryDecodeJson(body) ?? _truncate(body, 1024);
}

Object? _tryDecodeJson(String input) {
  try {
    return jsonDecode(input);
  } catch (_) {
    return null;
  }
}

String _truncate(String input, int maxChars) {
  if (input.length <= maxChars) {
    return input;
  }
  return '${input.substring(0, maxChars)}…';
}
