import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/providers/theme_mode_provider.dart';

class SettingsArgs {
  const SettingsArgs({
    required this.onEditProfile,
    required this.onSignOut,
    this.onOpenAdminDashboard,
    required this.showCandidateAccess,
    required this.showAdminDashboard,
    required this.adminDashboardEnabled,
  });

  final VoidCallback onEditProfile;
  final VoidCallback onSignOut;
  final VoidCallback? onOpenAdminDashboard;
  final bool showCandidateAccess;
  final bool showAdminDashboard;
  final bool adminDashboardEnabled;
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key, required this.args});

  final SettingsArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeControllerProvider);
    final themeCtl = ref.read(themeModeControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.phone_android),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: <ThemeMode>{themeMode},
              onSelectionChanged: (selection) {
                final sel = selection.first;
                themeCtl.set(sel);
              },
            ),
          ),
          const Divider(),
          const _SectionHeader('Account & Admin'),
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Edit profile'),
            onTap: args.onEditProfile,
          ),
          if (args.showCandidateAccess)
            ListTile(
              leading: const Icon(Icons.how_to_vote),
              title: const Text('Apply for candidate access'),
              onTap: () => context.push('/settings/candidate-access'),
            ),
          if (args.showAdminDashboard)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Admin dashboard'),
              enabled: args.adminDashboardEnabled,
              onTap: args.onOpenAdminDashboard,
            ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: args.onSignOut,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
