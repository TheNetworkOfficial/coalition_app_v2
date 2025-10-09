import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => TestHttpOverridesClient();
}

class TestHttpOverridesClient implements HttpClient {
  TestHttpOverridesClient();

  static final Uint8List _transparentPng = Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  static final Uint8List _feedPayload = Uint8List.fromList(
    utf8.encode(
      jsonEncode(
        <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'test-1',
              'userId': 'user-1',
              'userDisplayName': 'Test User 1',
              'userAvatarUrl': 'https://i.pravatar.cc/150?img=1',
              'description': 'Test description 1',
              'mediaUrl': 'https://example.com/video1.mp4',
              'thumbUrl': 'https://i.pravatar.cc/150?img=11',
              'isVideo': true,
            },
            <String, dynamic>{
              'id': 'test-2',
              'userId': 'user-2',
              'userDisplayName': 'Test User 2',
              'userAvatarUrl': 'https://i.pravatar.cc/150?img=2',
              'description': 'Test description 2',
              'mediaUrl': 'https://example.com/image1.jpg',
              'thumbUrl': 'https://i.pravatar.cc/150?img=12',
              'isVideo': false,
            },
            <String, dynamic>{
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
        },
      ),
    ),
  );

  bool _autoUncompress = true;
  Duration? _connectionTimeout;
  Duration _idleTimeout = const Duration(seconds: 15);
  int? _maxConnectionsPerHost;
  String? _userAgent;
  Future<bool> Function(Uri url, String scheme, String realm)? _authenticate;
  Future<bool> Function(String host, int port, String scheme, String realm)? _authenticateProxy;
  bool Function(X509Certificate cert, String host, int port)? _badCertificateCallback;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) {}

  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) {}

  @override
  Future<bool> Function(Uri url, String scheme, String realm)? get authenticate => _authenticate;

  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String realm)? f) {
    _authenticate = f;
  }

  @override
  Future<bool> Function(String host, int port, String scheme, String realm)? get authenticateProxy => _authenticateProxy;

  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String realm)? f) {
    _authenticateProxy = f;
  }

  @override
  bool get autoUncompress => _autoUncompress;

  @override
  set autoUncompress(bool value) {
    _autoUncompress = value;
  }

  @override
  bool Function(X509Certificate cert, String host, int port)? get badCertificateCallback => _badCertificateCallback;

  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) {
    _badCertificateCallback = callback;
  }

  @override
  void close({bool force = false}) {}

  @override
  set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri url, String proxyHost, int proxyPort)? factory) {}

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) {
    _connectionTimeout = value;
  }

  @override
  void set keyLog(Function(String line)? callback) {}

  @override
  Duration get idleTimeout => _idleTimeout;

  @override
  set idleTimeout(Duration value) {
    _idleTimeout = value;
  }

  @override
  int? get maxConnectionsPerHost => _maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) {
    _maxConnectionsPerHost = value;
  }

  @override
  String? get userAgent => _userAgent;

  @override
  set userAgent(String? value) {
    _userAgent = value;
  }

  Future<HttpClientRequest> _requestFor(Uri url) {
    final responseFactory = _responseFactoryFor(url);
    return Future<HttpClientRequest>.value(
      _TestHttpClientRequest(url, responseFactory),
    );
  }

  _ResponseFactory _responseFactoryFor(Uri url) {
    if (url.host.contains('i.pravatar.cc')) {
      return () => Future<HttpClientResponse>.value(
            _TestHttpClientResponse.bytes(
              Uint8List.fromList(_transparentPng),
              contentType: 'image/png',
            ),
          );
    }

    if (url.path == '/api/feed') {
      return () => Future<HttpClientResponse>.value(
            _TestHttpClientResponse.bytes(
              Uint8List.fromList(_feedPayload),
              contentType: 'application/json',
            ),
          );
    }

    return () => Future<HttpClientResponse>.value(
          _TestHttpClientResponse.notFound(),
        );
  }

  Future<HttpClientRequest> _unsupported(String method) {
    return Future<HttpClientRequest>.error(
      UnsupportedError('$method is not supported by TestHttpOverridesClient'),
    );
  }

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) => _unsupported('DELETE');

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _unsupported('DELETE');

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _requestFor(Uri(scheme: 'https', host: host, port: port == 0 ? null : port, path: path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _requestFor(url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) => _unsupported('HEAD');

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _unsupported('HEAD');

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) {
    if (method.toUpperCase() == 'GET') {
      return get(host, port, path);
    }
    return _unsupported(method);
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (method.toUpperCase() == 'GET') {
      return _requestFor(url);
    }
    return _unsupported(method);
  }

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) => _unsupported('PATCH');

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _unsupported('PATCH');

  @override
  Future<HttpClientRequest> post(String host, int port, String path) => _unsupported('POST');

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _unsupported('POST');

  @override
  Future<HttpClientRequest> put(String host, int port, String path) => _unsupported('PUT');

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _unsupported('PUT');

  @override
  String findProxyFromEnvironment(Uri url, [Map<String, String>? environment]) => 'DIRECT';

}

typedef _ResponseFactory = Future<HttpClientResponse> Function();

class _TestHttpClientRequest implements HttpClientRequest {
  _TestHttpClientRequest(this.uri, this._responseFactory);

  @override
  final Uri uri;
  final _ResponseFactory _responseFactory;

  Encoding _encoding = utf8;
  int _contentLength = 0;
  bool _bufferOutput = false;
  bool _followRedirects = true;
  int _maxRedirects = 5;
  bool _persistentConnection = true;

  @override
  final HttpHeaders headers = HttpHeaders();

  @override
  int get contentLength => _contentLength;

  @override
  set contentLength(int value) {
    _contentLength = value;
  }

  @override
  Encoding get encoding => _encoding;

  @override
  set encoding(Encoding value) {
    _encoding = value;
  }

  @override
  bool get bufferOutput => _bufferOutput;

  @override
  set bufferOutput(bool value) {
    _bufferOutput = value;
  }

  @override
  bool get followRedirects => _followRedirects;

  @override
  set followRedirects(bool value) {
    _followRedirects = value;
  }

  @override
  int get maxRedirects => _maxRedirects;

  @override
  set maxRedirects(int value) {
    _maxRedirects = value;
  }

  @override
  bool get persistentConnection => _persistentConnection;

  @override
  set persistentConnection(bool value) {
    _persistentConnection = value;
  }

  @override
  String get method => 'GET';

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<HttpClientResponse> close() => _responseFactory();

  @override
  Future<HttpClientResponse> get done => close();

  @override
  void write(Object? object) {}

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void writeln([Object? object = '']) {}

  @override
  void addUtf8Text(List<int> bytes) {}

  @override
  void addCredentials(HttpClientCredentials credentials, [bool invalid = false]) {}

  @override
  void addCookies(List<Cookie> cookies) {}

  @override
  Future<void> flush() async {}

  @override
  void setProxy(String host, int port) {}

  @override
  void setProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) {}

  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) => _responseFactory();
}

class _TestHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  _TestHttpClientResponse._(this.statusCode, this._bytes, this._headers);

  factory _TestHttpClientResponse.bytes(Uint8List bytes, {int statusCode = HttpStatus.ok, required String contentType}) {
    final headers = HttpHeaders();
    headers.contentLength = bytes.length;
    headers.contentType = ContentType.parse(contentType);
    return _TestHttpClientResponse._(statusCode, bytes, headers);
  }

  factory _TestHttpClientResponse.notFound() => _TestHttpClientResponse.bytes(
        Uint8List.fromList(utf8.encode('Not Found')),
        statusCode: HttpStatus.notFound,
        contentType: 'text/plain',
      );

  final Uint8List _bytes;

  @override
  final int statusCode;

  final HttpHeaders _headers;

  @override
  HttpHeaders get headers => _headers;

  @override
  int get contentLength => _bytes.length;

  @override
  CompressionState get compressionState => CompressionState.notCompressed;

  @override
  List<Cookie> get cookies => const <Cookie>[];

  @override
  Future<Socket> detachSocket() => Future<Socket>.error(UnsupportedError('Socket detachment is not supported'));

  @override
  HttpConnectionInfo? get connectionInfo => null;

  @override
  X509Certificate? get certificate => null;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => statusCode == HttpStatus.ok ? 'OK' : 'Not Found';

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) =>
      Future<HttpClientResponse>.error(UnsupportedError('Redirects are not supported'));

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

Future<void> runWithHttpOverrides(WidgetTester tester, Future<void> Function() body) {
  return HttpOverrides.runZoned(
    body,
    createHttpClient: (_) => TestHttpOverridesClient(),
  );
}
