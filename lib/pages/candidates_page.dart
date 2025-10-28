import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/candidates/models/candidate.dart';
import '../features/candidates/providers/candidates_providers.dart';
import '../widgets/user_avatar.dart';

class CandidatesPage extends ConsumerWidget {
  const CandidatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(candidatesPagerProvider);
    final pager = ref.watch(candidatesPagerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Candidates')),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load candidates: $error'),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No candidates yet.'));
          }

          final showLoader = pager.isLoading && pager.hasMore;
          final itemCount = items.length + (showLoader ? 1 : 0);

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
              onRefresh: () => pager.refresh(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: itemCount,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index >= items.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final candidate = items[index];
                  return CandidateCard(candidate: candidate);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class CandidateCard extends ConsumerWidget {
  const CandidateCard({super.key, required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  url: candidate.headshotUrl,
                  size: 56,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        candidate.name.isNotEmpty
                            ? candidate.name
                            : 'Unnamed candidate',
                        style: textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if ((candidate.level ?? '').isNotEmpty)
                            _InfoChip(label: candidate.level!),
                          if ((candidate.district ?? '').isNotEmpty)
                            _InfoChip(label: candidate.district!),
                          if (candidate.followersCount > 0)
                            _InfoChip(
                                label: '${candidate.followersCount} followers'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if ((candidate.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(candidate.description!, style: textTheme.bodyMedium),
            ],
            if (candidate.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in candidate.tags.take(5))
                    _TagChip(label: tag),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: () {
                    final candidateId = candidate.candidateId;
                    context.pushNamed(
                      'candidate_view',
                      pathParameters: {'id': candidateId},
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open profile'),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () async {
                    final notifier =
                        ref.read(candidatesPagerProvider.notifier);
                    final next = !candidate.isFollowing;
                    try {
                      await notifier.optimisticToggle(
                        candidate.candidateId,
                        next,
                      );
                    } catch (error) {
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content:
                                Text('Failed to update follow: $error'),
                          ),
                        );
                    }
                  },
                  icon: Icon(candidate.isFollowing
                      ? Icons.check
                      : Icons.person_add_alt),
                  label: Text(candidate.isFollowing ? 'Following' : 'Follow'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.primaryContainer,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.secondaryContainer,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
