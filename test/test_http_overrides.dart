import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

class TestHttpOverrides extends HttpOverrides {
  TestHttpOverrides({HttpOverrides? previous}) : _previous = previous;

  final HttpOverrides? _previous;

  static const _pngBytes = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ];

  static final Uint8List _png = Uint8List.fromList(_pngBytes);

  static const _feedResponse = {
    'items': [
      {
        'id': 'test-1',
        'userId': 'user-1',
        'userDisplayName': 'Test User 1',
        'userAvatarUrl': 'https://i.pravatar.cc/150?img=1',
        'description': 'Test description 1',
        'mediaUrl': 'https://example.com/video1.mp4',
        'thumbUrl': 'https://i.pravatar.cc/150?img=11',
        'isVideo': true,
      },
      {
        'id': 'test-2',
        'userId': 'user-2',
        'userDisplayName': 'Test User 2',
        'userAvatarUrl': 'https://i.pravatar.cc/150?img=2',
        'description': 'Test description 2',
        'mediaUrl': 'https://example.com/image1.jpg',
        'thumbUrl': 'https://i.pravatar.cc/150?img=12',
        'isVideo': false,
      },
      {
        'id': 'test-3',
        'userId': 'user-3',
        'userDisplayName': 'Test User 3',
        'userAvatarUrl': 'https://i.pravatar.cc/150?img=3',
        'description': 'Test description 3',
        'mediaUrl': 'https://example.com/video2.mp4',
        'thumbUrl': 'https://i.pravatar.cc/150?img=13',
        'isVideo': true,
      },
    ],
  };

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = _TestHttpClient(_previous?.createHttpClient(context));
    return client;
  }
}

class _TestHttpClient implements HttpClient {
  _TestHttpClient(this._fallback);

  final HttpClient? _fallback;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) {}

  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) {}

  @override
  Future<bool> Function(Uri url, String scheme, String realm)? authenticate;

  @override
  Future<bool> Function(String host, int port, String scheme, String realm)? authenticateProxy;

  @override
  void Function(String line)? badCertificateCallback;

  @override
  void close({bool force = false}) {}

  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String proxyHost, int proxyPort)? f) {}

  @override
  set keyLog(Function(String line)? callback) {}

  @override
  Duration? idleTimeout;

  @override
  int? maxConnectionsPerHost;

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) => _notSupported('DELETE');

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _notSupported('DELETE');

  @override
  Future<HttpClientRequest> get(String host, int port, String path) => _handle(Uri(scheme: 'https', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _handle(url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) => _notSupported('HEAD');

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _notSupported('HEAD');

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) => _handle(Uri(scheme: 'https', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _handle(url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => _notSupported('PATCH');

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _notSupported('PATCH');

  @override
  Future<HttpClientRequest> post(String host, int port, String path) => _notSupported('POST');

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _notSupported('POST');

  @override
  Future<HttpClientRequest> put(String host, int port, String path) => _notSupported('PUT');

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _notSupported('PUT');

  @override
  set userAgent(String? userAgent) {}

  Future<HttpClientRequest> _handle(Uri url) async {
    final handler = _handlerFor(url);
    if (handler != null) {
      final request = _TestHttpClientRequest(url, handler);
      return request;
    }
    if (_fallback != null) {
      return _fallback!.getUrl(url);
    }
    throw StateError('Unhandled URL: $url');
  }

  _ResponseHandler? _handlerFor(Uri url) {
    if (url.host.contains('i.pravatar.cc')) {
      return () async => _TestHttpClientResponse.bytes(TestHttpOverrides._png, contentType: 'image/png');
    }

    if (url.path == '/api/feed') {
      final bytes = utf8.encode(jsonEncode(TestHttpOverrides._feedResponse));
      return () async => _TestHttpClientResponse.bytes(Uint8List.fromList(bytes), contentType: 'application/json');
    }

    return () async => _TestHttpClientResponse.bytes(Uint8List.fromList(utf8.encode('Not Found')), statusCode: HttpStatus.notFound);
  }

  Future<HttpClientRequest> _notSupported(String method) => Future.error(UnsupportedError('$method not supported in TestHttpClient'));
}

typedef _ResponseHandler = Future<_TestHttpClientResponse> Function();

class _TestHttpClientRequest implements HttpClientRequest {
  _TestHttpClientRequest(this.uri, this._handler);

  @override
  final Uri uri;
  final _ResponseHandler _handler;

  @override
  final Encoding encoding = utf8;

  final HttpHeaders _headers = _TestHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream<List<int>> stream) => stream.drain();

  @override
  Future<HttpClientResponse> close() async => _handler();

  @override
  Future<HttpClientResponse> get done async => _handler();

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  void addUtf8Text(List<int> bytes) {}

  @override
  void bufferOutput(bool state) {}

  @override
  bool get bufferOutput => false;

  @override
  void flush() {}

  @override
  bool get followRedirects => false;

  @override
  set followRedirects(bool value) {}

  @override
  int get maxRedirects => 5;

  @override
  set maxRedirects(int value) {}

  @override
  String get method => 'GET';

  @override
  bool get persistentConnection => false;

  @override
  set persistentConnection(bool value) {}

  @override
  void addCredentials(HttpClientCredentials credentials, [bool invalid = false]) {}

  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) async => _handler();

  @override
  void setProxy(String host, int port) {}

  @override
  void setProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) {}
}

class _TestHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  _TestHttpClientResponse.bytes(this._bytes, {required this.contentType, this.statusCode = HttpStatus.ok})
      : headers = _TestHttpHeaders()..contentType = ContentType.parse(contentType);

  final Uint8List _bytes;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  final String contentType;

  @override
  int get contentLength => _bytes.length;

  @override
  String get reasonPhrase => statusCode == HttpStatus.ok ? 'OK' : 'Not Found';

  @override
  Future<void> cancel() async {}

  @override
  X509Certificate? get certificate => null;

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  BrowserHttpClientResponse? get webSocketUpgrade => null;

  @override
  Future<Uint8List> fold<Uint8List>(Uint8List initialValue, Uint8List Function(Uint8List previous, List<int> element) combine) => Future.value(_bytes);

  @override
  int get statusCode => _statusCode;
  int _statusCode;

  @override
  Future<dynamic> drain([dynamic futureValue]) => Future.value(futureValue);

  @override
  void setRedirectInfo(List<RedirectInfo> redirects) {}

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError}) => Stream<List<int>>.value(_bytes).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
}

class _TestHttpHeaders extends HttpHeaders {
  _TestHttpHeaders() : super();

  final Map<String, List<String>> _headers = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers.putIfAbsent(name, () => []).add(value.toString());
  }

  @override
  void clear() {
    _headers.clear();
  }

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _headers.forEach(action);
  }

  @override
  void noFolding(String name) {}

  @override
  void remove(String name, Object value) {
    final values = _headers[name];
    values?.remove(value.toString());
    if (values != null && values.isEmpty) {
      _headers.remove(name);
    }
  }

  @override
  void removeAll(String name) {
    _headers.remove(name);
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name] = [value.toString()];
  }

  @override
  List<String>? operator [](String name) => _headers[name];

  @override
  int get length => _headers.length;
}

Future<void> runWithHttpOverrides(WidgetTester tester, Future<void> Function() body) async {
  final overrides = TestHttpOverrides(previous: HttpOverrides.current);
  return HttpOverrides.runWithHttpOverrides(
    () => runZoned(body),
    overrides,
  );
}
