import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/feed/playback/feed_activity_provider.dart';

class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.branches,
  });

  final StatefulNavigationShell navigationShell;
  final List<Widget> branches; // Branch navigators supplied by the router.

  void _setFeedActive(BuildContext context, WidgetRef ref, int index) {
    final isFeedActive = index == kFeedBranchIndex;
    final notifier = ref.read(feedActiveProvider.notifier);
    if (notifier.state == isFeedActive) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      final controller = ref.read(feedActiveProvider.notifier);
      if (controller.state != isFeedActive) {
        controller.state = isFeedActive;
      }
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeIndex = navigationShell.currentIndex;
    _setFeedActive(context, ref, activeIndex);

    return Scaffold(
      // Base StatefulShellRoute asks the shell to render the branch navigators.
      // IndexedStack keeps each branch's navigation stack alive.
      body: IndexedStack(
        index: activeIndex,
        children: branches,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: activeIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
          _setFeedActive(context, ref, index);
        },
        destinations: const [
          NavigationDestination(
            key: Key('tab_feed'),
            icon: Icon(Icons.dynamic_feed_outlined),
            selectedIcon: Icon(Icons.dynamic_feed),
            label: 'Feed',
          ),
          NavigationDestination(
            key: Key('tab_candidates'),
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Candidates',
          ),
          NavigationDestination(
            key: Key('tab_create'),
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Create',
          ),
          NavigationDestination(
            key: Key('tab_events'),
            icon: Icon(Icons.event_outlined),
            selectedIcon: Icon(Icons.event),
            label: 'Events',
          ),
          NavigationDestination(
            key: Key('tab_profile'),
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
