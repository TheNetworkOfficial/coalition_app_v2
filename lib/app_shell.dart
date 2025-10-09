import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
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

Widget lazyNavigationContainerBuilder(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  List<Widget> children,
) {
  return _LazyNavigationContainer(
    navigationShell: navigationShell,
    children: children,
  );
}

class _LazyNavigationContainer extends StatelessWidget {
  const _LazyNavigationContainer({
    required this.navigationShell,
    required this.children,
  });

  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final int activeIndex = navigationShell.currentIndex;
    return IndexedStack(
      index: activeIndex,
      children: [
        for (int i = 0; i < children.length; i++)
          _Lazy(
            active: i == activeIndex,
            builder: () => children[i],
          ),
      ],
    );
  }
}

class _Lazy extends StatefulWidget {
  const _Lazy({required this.active, required this.builder});

  final bool active;
  final Widget Function() builder;

  @override
  State<_Lazy> createState() => _LazyState();
}

class _LazyState extends State<_Lazy> with AutomaticKeepAliveClientMixin {
  Widget? _child;

  @override
  void didUpdateWidget(covariant _Lazy oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && _child == null) {
      _child = widget.builder();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final shouldInstantiate = widget.active && _child == null;
    if (shouldInstantiate) {
      _child = widget.builder();
    }

    final child = _child;
    if (child == null) {
      return const SizedBox.shrink();
    }

    return Offstage(
      offstage: !widget.active,
      child: TickerMode(
        enabled: widget.active,
        child: child,
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
