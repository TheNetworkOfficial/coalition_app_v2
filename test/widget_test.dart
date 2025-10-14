// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:coalition_app_v2/features/feed/data/feed_repository.dart';
import 'package:coalition_app_v2/features/feed/models/post.dart';
import 'package:coalition_app_v2/features/feed/providers/feed_providers.dart';
import 'package:coalition_app_v2/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_http_overrides.dart';
import 'package:coalition_app_v2/providers/app_providers.dart';
import 'package:coalition_app_v2/services/auth_service.dart';
import 'package:coalition_app_v2/features/auth/models/user_summary.dart';

class FakeFeedRepository implements FeedRepository {
  const FakeFeedRepository();

  @override
  Future<List<Post>> getFeed() async {
    return const <Post>[
      Post(
        id: 'fake-1',
        userId: 'user-1',
        userDisplayName: 'Test User 1',
        description: 'First test post',
        mediaUrl: 'https://example.com/image1.jpg',
        thumbUrl: 'https://example.com/thumb1.jpg',
        isVideo: false,
      ),
      Post(
        id: 'fake-2',
        userId: 'user-2',
        userDisplayName: 'Test User 2',
        description: 'Second test post',
        mediaUrl: 'https://example.com/video1.mp4',
        thumbUrl: 'https://example.com/thumb2.jpg',
        isVideo: true,
      ),
    ];
  }
}

void main() {
  testWidgets(
    'Bottom navigation switches to candidates page',
    (WidgetTester tester) async {
      await runWithHttpOverrides(tester, () async {
        final fakeAuth = _FakeAuthService(
          user: const UserSummary(
            userId: 'u1',
            username: 'u1',
            displayName: 'Test User',
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              feedRepositoryProvider
                  .overrideWithValue(const FakeFeedRepository()),
              authServiceProvider.overrideWithValue(fakeAuth),
            ],
            child: const MyApp(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text('Feed'), findsWidgets);

        await tester.tap(find.byKey(const Key('tab_candidates')));
        await tester.pumpAndSettle();

        expect(find.text('TODO: Candidates page'), findsOneWidget);
      });
    },
  );
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
