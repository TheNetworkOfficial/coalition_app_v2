import 'package:coalition_app_v2/features/auth/ui/auth_gate_page.dart';
import 'package:coalition_app_v2/features/auth/ui/confirm_code_page.dart';
import 'package:coalition_app_v2/features/feed/ui/feed_page.dart';
import 'package:coalition_app_v2/pages/candidate_access_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_shell.dart';
import '../pages/admin/admin_application_detail_page.dart';
import '../pages/admin/admin_applications_page.dart';
import '../pages/admin/admin_dashboard_page.dart';
import '../pages/bootstrap_page.dart';
import '../pages/candidate_viewer_page.dart';
import '../pages/candidates_page.dart';
import '../pages/create_entry_page.dart';
import '../pages/events_page.dart';
import '../pages/edit_candidate_page.dart';
import '../pages/profile_page.dart';

/// Root navigator for pages rendered above the shell/tabs.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/bootstrap',
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
          child: ProfilePage(targetUserId: targetUserId),
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
      ],
    ),
    StatefulShellRoute(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      navigatorContainerBuilder: lazyNavigationContainerBuilder,
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
            ),
            GoRoute(
              path: '/candidates/:id',
              name: 'candidate_view',
              pageBuilder: (context, state) {
                final candidateId = state.pathParameters['id'];
                if (candidateId == null || candidateId.isEmpty) {
                  return const NoTransitionPage(child: CandidatesPage());
                }
                return MaterialPage<void>(
                  child: CandidateViewerPage(candidateId: candidateId),
                );
              },
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
