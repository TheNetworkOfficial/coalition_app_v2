import 'package:coalition_app_v2/features/auth/ui/auth_gate_page.dart';
import 'package:coalition_app_v2/features/feed/ui/feed_page.dart';
import 'package:go_router/go_router.dart';

import '../app_shell.dart';
import '../pages/bootstrap_page.dart';
import '../pages/candidates_page.dart';
import '../pages/create_entry_page.dart';
import '../pages/events_page.dart';
import '../pages/profile_page.dart';

final GoRouter appRouter = GoRouter(
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
              path: '/profile',
              name: 'profile',
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
