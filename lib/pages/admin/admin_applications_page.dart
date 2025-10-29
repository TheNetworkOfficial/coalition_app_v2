import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/models/admin_application.dart';
import '../../features/admin/providers/admin_providers.dart';
import '../../widgets/user_avatar.dart';

class AdminApplicationsPage extends ConsumerWidget {
  const AdminApplicationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pendingApplicationsProvider);
    final pager = ref.watch(pendingApplicationsProvider.notifier);

    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _AdminApplicationsError(
        error: error,
        onRetry: pager.refresh,
      ),
      data: (applications) {
        if (applications.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No pending applications right now.'),
            ),
          );
        }

        final showLoader = pager.isLoading && pager.hasMore;
        final itemCount = applications.length + (showLoader ? 1 : 0);

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.pixels >=
                    notification.metrics.maxScrollExtent - 400 &&
                pager.hasMore &&
                !pager.isLoading) {
              pager.loadMore();
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: pager.refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: itemCount,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (index >= applications.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final application = applications[index];
                return _AdminApplicationCard(
                  application: application,
                  onTap: () => context.push(
                    '/admin/applications/${application.id}',
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _AdminApplicationCard extends StatelessWidget {
  const _AdminApplicationCard({
    required this.application,
    required this.onTap,
  });

  final AdminApplication application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(
                    url: application.avatarUrl,
                    size: 56,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          application.fullName,
                          style: textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          application.summary ??
                              'Tap to review full details.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Chip(
                        label: Text(application.status.toUpperCase()),
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        application.submittedLabel,
                        style: textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
              if (application.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in application.tags.take(4))
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminApplicationsError extends StatelessWidget {
  const _AdminApplicationsError({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Failed to load applications: $error',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
