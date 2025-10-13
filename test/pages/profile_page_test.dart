import 'dart:async';
import 'dart:collection';

import 'package:background_downloader/background_downloader.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:coalition_app_v2/features/auth/models/user_summary.dart';
import 'package:coalition_app_v2/features/feed/models/post.dart';
import 'package:coalition_app_v2/models/post_draft.dart';
import 'package:coalition_app_v2/models/profile.dart';
import 'package:coalition_app_v2/models/upload_outcome.dart';
import 'package:coalition_app_v2/pages/profile_page.dart';
import 'package:coalition_app_v2/providers/app_providers.dart';
import 'package:coalition_app_v2/providers/upload_manager.dart';
import 'package:coalition_app_v2/services/api_client.dart';
import 'package:coalition_app_v2/services/auth_service.dart';

import '../test_http_overrides.dart';

void main() {
  testWidgets(
    'profile refresh fetches latest posts after upload completes',
    (WidgetTester tester) async {
      await runWithHttpOverrides(tester, () async {
        final fakeApiClient = _FakeApiClient(
          initialProfile: Profile(
            userId: 'user-123',
            displayName: 'Test User',
            username: 'testuser',
          ),
          postResponses: Queue<List<Post>>.from(<List<Post>>[
            const <Post>[],
            const <Post>[
              Post(
                id: 'post-1',
                userId: 'user-123',
                userDisplayName: 'Test User',
                mediaUrl: 'https://example.com/media.jpg',
                thumbUrl: 'https://example.com/thumb.jpg',
                isVideo: false,
              ),
            ],
          ]),
        );
        final fakeAuthService = _FakeAuthService(
          user: const UserSummary(
            userId: 'user-123',
            username: 'testuser',
            displayName: 'Test User',
          ),
        );
        final fakeUploadManager = _FakeUploadManager();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authServiceProvider.overrideWithValue(fakeAuthService),
              apiClientProvider.overrideWithValue(fakeApiClient),
              uploadManagerProvider.overrideWith((ref) => fakeUploadManager),
            ],
            child: const MaterialApp(home: ProfilePage()),
          ),
        );

        // Allow the initial profile/posts load to complete.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(fakeApiClient.myPostsCallCount, 1);
        expect(find.text('No posts yet.'), findsOneWidget);

        // Simulate an upload finishing which should trigger a profile refresh.
        fakeUploadManager.updateStatus(TaskStatus.running);
        await tester.pump();
        fakeUploadManager.updateStatus(TaskStatus.complete);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(fakeApiClient.myPostsCallCount, greaterThanOrEqualTo(2));
        expect(find.text('No posts yet.'), findsNothing);
        expect(find.byType(CachedNetworkImage), findsWidgets);
      });
    },
  );
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({
    required Profile initialProfile,
    Queue<List<Post>>? postResponses,
  })  : _profile = initialProfile,
        _postResponses = postResponses ?? Queue<List<Post>>(),
        super(httpClient: _NoopHttpClient(), baseUrl: 'https://example.com');

  Profile _profile;
  final Queue<List<Post>> _postResponses;
  List<Post> _lastPosts = const <Post>[];
  int _myPostsCallCount = 0;

  int get myPostsCallCount => _myPostsCallCount;

  @override
  Future<Profile> getMyProfile() async => _profile;

  @override
  Future<List<Post>> getMyPosts({bool includePending = false}) async {
    _myPostsCallCount += 1;
    if (_postResponses.isNotEmpty) {
      _lastPosts = _postResponses.removeFirst();
    }
    return _lastPosts;
  }

  @override
  Future<Profile> upsertMyProfile(ProfileUpdate update) async {
    _profile = _profile.copyWith(
      displayName: update.displayName ?? _profile.displayName,
      username: update.username ?? _profile.username,
      avatarUrl: update.avatarUrl ?? _profile.avatarUrl,
      bio: update.bio ?? _profile.bio,
    );
    return _profile;
  }

  @override
  void close() {}
}

class _FakeAuthService extends AuthService {
  _FakeAuthService({UserSummary? user})
      : _user = user,
        super();

  final UserSummary? _user;

  @override
  Future<void> configureIfNeeded() async {}

  @override
  Future<bool> isSignedIn() async => _user != null;

  @override
  Future<UserSummary?> currentUser() async => _user;

  @override
  Future<void> signOut() async {}
}

class _FakeUploadManager extends ChangeNotifier implements UploadManager {
  _FakeUploadManager({UploadOutcome? outcome})
      : _outcome = outcome ?? const UploadOutcome(ok: true);

  bool _hasActiveUpload = false;
  double? _progress;
  TaskStatus? _currentStatus;
  String? _currentTaskId;
  UploadOutcome _outcome;
  final Queue<TaskStatus?> _statusNotifications = Queue<TaskStatus?>();

  @override
  bool get hasActiveUpload => _hasActiveUpload;

  @override
  double? get progress => _progress;

  @override
  TaskStatus? get status {
    if (_statusNotifications.isNotEmpty) {
      _currentStatus = _statusNotifications.removeFirst();
    }
    return _currentStatus;
  }

  @override
  String? get currentTaskId => _currentTaskId;

  @override
  Future<UploadOutcome> startUpload({
    required PostDraft draft,
    required String description,
  }) async {
    _hasActiveUpload = true;
    _currentTaskId = 'fake-task';
    updateStatus(TaskStatus.running);
    return _outcome;
  }

  void updateStatus(TaskStatus? status) {
    _statusNotifications
      ..clear()
      ..add(_currentStatus)
      ..add(status);
    _currentStatus = status;
    if (status?.isFinalState == true) {
      _hasActiveUpload = false;
      _currentTaskId = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _hasActiveUpload = false;
    _currentStatus = null;
    _progress = null;
    _currentTaskId = null;
    _statusNotifications.clear();
    super.dispose();
  }
}

class _NoopHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw UnimplementedError(
      'Network calls are not expected in FakeApiClient tests',
    );
  }
}
