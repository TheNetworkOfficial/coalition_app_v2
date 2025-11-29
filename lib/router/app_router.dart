import 'package:coalition_app_v2/features/auth/ui/auth_gate_page.dart';
import 'package:coalition_app_v2/features/auth/ui/confirm_code_page.dart';
import 'package:coalition_app_v2/features/feed/models/post.dart';
import 'package:coalition_app_v2/features/feed/ui/feed_page.dart';
import 'package:coalition_app_v2/features/feed/ui/pages/post_player_page.dart';
import 'package:coalition_app_v2/features/events/models/event.dart';
import 'package:coalition_app_v2/pages/candidate_access_page.dart';
import 'package:coalition_app_v2/pages/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_shell.dart';
import '../pages/admin/admin_application_detail_page.dart';
import '../pages/admin/admin_applications_page.dart';
import '../pages/admin/admin_dashboard_page.dart';
import '../pages/admin/admin_event_tags_page.dart';
import '../pages/admin/admin_tags_page.dart';
import '../pages/bootstrap_page.dart';
import '../pages/candidate_viewer_page.dart';
import '../pages/candidates_page.dart';
import '../pages/create_entry_page.dart';
import '../pages/events_page.dart';
import '../pages/event_viewer_page.dart';
import '../pages/edit_candidate_page.dart';
import '../pages/events/event_edit_page.dart';
import '../pages/events/manage_events_page.dart';
import '../pages/profile_page.dart';
import 'route_observers.dart';

/// Root navigator for pages rendered above the shell/tabs.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/bootstrap',
  observers: [appRouteObserver],
  routes: [
    GoRoute(
      path: '/bootstrap',
      name: 'bootstrap',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: BootstrapPage(),
      ),
    ),
    GoRoute(
      path: '/auth',
      name: 'auth',
      pageBuilder: (context, state) => const NoTransitionPage(
        child: AuthGatePage(),
      ),
    ),
    GoRoute(
      path: '/auth/confirm-code',
      name: 'confirm-code',
      pageBuilder: (context, state) => const MaterialPage(
        child: ConfirmCodePage(),
      ),
    ),
    // Top-level profile route so any branch can display it above the shell.
    GoRoute(
      path: '/profile',
      name: 'profile',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) {
        debugPrint(
          '[ROUTER] building /profile | extra=${state.extra.runtimeType}:${state.extra}',
        );
        final targetUserId =
            state.extra is String ? state.extra as String : null;
        return NoTransitionPage(
          key: state.pageKey,
          child: ProfilePage(targetUserId: targetUserId),
        );
      },
    ),
    GoRoute(
      path: '/posts/view',
      name: 'post_view',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) {
        final extra = state.extra;
        assert(
          extra is Post,
          'post_view route expects a Post instance via state.extra',
        );
        final post = extra is Post ? extra : null;
        if (post == null) {
          return const MaterialPage<void>(
            child: Scaffold(
              body: Center(child: Text('Post unavailable')),
            ),
          );
        }
        return MaterialPage<void>(
          key: state.pageKey,
          child: PostPlayerPage(post: post),
        );
      },
    ),
    GoRoute(
      path: '/settings',
      name: 'settings',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) {
        final args = state.extra is SettingsArgs
            ? state.extra as SettingsArgs
            : null;

        return MaterialPage<void>(
          key: state.pageKey,
          child: SettingsPage(
            args: args ??
                SettingsArgs(
                  onEditProfile: () {},
                  onSignOut: () {},
                  onOpenAdminDashboard: null,
                  showCandidateAccess: false,
                  showAdminDashboard: false,
                  adminDashboardEnabled: false,
                ),
          ),
        );
      },
    ),
    GoRoute(
      path: '/settings/candidate-access',
      name: 'candidate_access_apply',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => const NoTransitionPage(
        child: CandidateAccessPage(),
      ),
    ),
    GoRoute(
      path: '/settings/candidate-edit',
      name: 'candidate_edit',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) {
        final candidateId =
            state.extra is String ? state.extra as String : null;
        return MaterialPage<void>(
          key: state.pageKey,
          child: EditCandidatePage(candidateId: candidateId),
        );
      },
    ),
    GoRoute(
      path: '/manage-events',
      name: 'manage_events',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => const MaterialPage<void>(
        child: ManageEventsPage(),
      ),
    ),
    GoRoute(
      path: '/manage-events/new',
      name: 'event_create',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) => MaterialPage<void>(
        key: state.pageKey,
        child: const EventEditPage(),
      ),
    ),
    GoRoute(
      path: '/manage-events/:id/edit',
      name: 'event_edit',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (context, state) {
        final eventId = state.pathParameters['id'] ?? '';
        final event = state.extra is Event ? state.extra as Event : null;
        return MaterialPage<void>(
          key: state.pageKey,
          child: EventEditPage(
            eventId: eventId,
            event: event,
          ),
        );
      },
    ),
    GoRoute(
      path: '/admin',
      parentNavigatorKey: rootNavigatorKey,
      redirect: (context, state) => '/admin/applications',
    ),
    ShellRoute(
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state, child) => AdminDashboardPage(child: child),
      routes: [
        GoRoute(
          path: '/admin/applications',
          name: 'admin_applications',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AdminApplicationsPage(),
          ),
          routes: [
            GoRoute(
              path: ':id',
              name: 'admin_application_detail',
              pageBuilder: (context, state) {
                final applicationId = state.pathParameters['id'] ?? '';
                return MaterialPage<void>(
                  key: state.pageKey,
                  child: AdminApplicationDetailPage(
                    applicationId: applicationId,
                  ),
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/admin/tags',
          name: 'admin_tags',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AdminTagsPage(),
          ),
        ),
        GoRoute(
          path: '/admin/event-tags',
          name: 'admin_event_tags',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: AdminEventTagsPage(),
          ),
        ),
      ],
    ),
    StatefulShellRoute(
      builder: (context, state, navigationShell) => navigationShell,
      // go_router 16.x base constructor requires this *three-parameter* builder:
      // (BuildContext context, StatefulNavigationShell navigationShell, List<Widget> children)
      navigatorContainerBuilder: (
        BuildContext context,
        StatefulNavigationShell navigationShell,
        List<Widget> children,
      ) {
        // Wrap the shell in AppShell AND hand it the branch navigators (children).
        return AppShell(
          navigationShell: navigationShell,
          branches: children,
        );
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/feed',
              name: 'feed',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: FeedPage(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/candidates',
              name: 'candidates',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: CandidatesPage(),
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  name: 'candidate_view',
                  pageBuilder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return MaterialPage<void>(
                      key: state.pageKey,
                      child: CandidateViewerPage(candidateId: id),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/create',
              name: 'create',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: CreateEntryPage(),
              ),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/events',
              name: 'events',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: EventsPage(),
              ),
              routes: [
                GoRoute(
                  path: ':id',
                  name: 'event_view',
                  pageBuilder: (context, state) {
                    final id = state.pathParameters['id']!;
                    return MaterialPage<void>(
                      key: state.pageKey,
                      child: EventViewerPage(eventId: id),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile-tab',
              name: 'profile-tab',
              pageBuilder: (context, state) => const NoTransitionPage(
                child: ProfilePage(),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
