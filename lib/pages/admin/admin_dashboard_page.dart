import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
                  selectedIndex: 0,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.inbox_outlined),
                      selectedIcon: Icon(Icons.inbox),
                      label: Text('Applications'),
                    ),
                  ],
                  onDestinationSelected: (index) {
                    if (index == 0) {
                      context.go('/admin/applications');
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
          length: 1,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Admin dashboard'),
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Applications'),
                ],
              ),
            ),
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                child,
              ],
            ),
          ),
        );
      },
    );
  }
}
