import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final location = GoRouterState.of(context).uri.toString();
        final currentIndex = location.startsWith('/admin/tags') ? 1 : 0;
        final useRail = constraints.maxWidth >= 720;
        if (useRail) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Admin dashboard'),
            ),
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NavigationRail(
                  selectedIndex: currentIndex,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.inbox_outlined),
                      selectedIcon: Icon(Icons.inbox),
                      label: Text('Applications'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.label_outline),
                      selectedIcon: Icon(Icons.label),
                      label: Text('Candidate Tags'),
                    ),
                  ],
                  onDestinationSelected: (index) {
                    if (index == 0) {
                      context.go('/admin/applications');
                    } else if (index == 1) {
                      context.go('/admin/tags');
                    }
                  },
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          );
        }

        return DefaultTabController(
          length: 2,
          initialIndex: currentIndex,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Admin dashboard'),
              bottom: TabBar(
                onTap: (index) {
                  if (index == currentIndex) {
                    return;
                  }
                  if (index == 0) {
                    context.go('/admin/applications');
                  } else {
                    context.go('/admin/tags');
                  }
                },
                tabs: const [
                  Tab(text: 'Applications'),
                  Tab(text: 'Candidate Tags'),
                ],
              ),
            ),
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                currentIndex == 0 ? child : const SizedBox.shrink(),
                currentIndex == 1 ? child : const SizedBox.shrink(),
              ],
            ),
          ),
        );
      },
    );
  }
}
