import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../features/candidates/models/candidate.dart';
import '../features/candidates/providers/candidates_providers.dart';
import '../features/candidates/ui/candidate_views.dart' show kCandidateSocialIcons;
import '../features/candidates/ui/candidates_filter_sheet.dart';

class CandidatesPage extends ConsumerWidget {
  const CandidatesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCandidates = ref.watch(candidatesPagerProvider);
    final pager = ref.watch(candidatesPagerProvider.notifier);

    final Widget mainChild = asyncCandidates.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Failed to load candidates: $error'),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => pager.refresh(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 48, bottom: 24),
              children: const [
                Center(child: Text('No candidates yet.')),
              ],
            ),
          );
        }

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (metrics.maxScrollExtent == double.infinity) {
              return false;
            }
            final threshold =
                (metrics.viewportDimension * 1.2).clamp(300.0, 800.0) as double;
            final remaining = metrics.extentAfter;
            final bool atVirtualEnd =
                metrics.maxScrollExtent == 0 &&
                    notification is OverscrollNotification &&
                    notification.overscroll > 0;
            final bool nearEnd = metrics.pixels > 0 && remaining <= threshold;
            if ((atVirtualEnd || nearEnd) &&
                pager.hasMore &&
                !pager.isLoading) {
              unawaited(pager.loadMore());
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: () => pager.refresh(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                var viewportHeight = constraints.maxHeight;
                if (!viewportHeight.isFinite || viewportHeight <= 0) {
                  final media = MediaQuery.of(context);
                  viewportHeight = media.size.height -
                      media.padding.top -
                      media.padding.bottom;
                }

                final showLoader = pager.isLoading && pager.hasMore;
                final itemCount = items.length + (showLoader ? 1 : 0);

                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    if (index >= items.length) {
                      return SizedBox(
                        height: viewportHeight,
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final candidate = items[index];
                    return SizedBox(
                      height: viewportHeight,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: CandidateListCard(
                          candidate: candidate,
                          fillHeight: true,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );

    return Scaffold(
      body: SafeArea(
        top: true,
        child: Stack(
          children: [
            Positioned.fill(child: mainChild),
            Positioned(
              top: 8,
              right: 12,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.search),
                tooltip: 'Browse by focus area',
                onPressed: () => showCandidatesFilterSheet(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CandidateListCard extends ConsumerWidget {
  const CandidateListCard({
    super.key,
    required this.candidate,
    this.fillHeight = false,
  });

  final Candidate candidate;
  final bool fillHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void handleToggleFollow() {
      final notifier = ref.read(candidatesPagerProvider.notifier);
      final next = !candidate.isFollowing;
      unawaited(() async {
        try {
          await notifier.optimisticToggle(candidate.candidateId, next);
        } catch (error) {
          if (!context.mounted) {
            return;
          }
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('Failed to update follow: $error'),
              ),
            );
        }
      }());
    }

    return _CandidateListCard(
      candidate: candidate,
      onOpen: () {
        final id = candidate.candidateId.trim();
        if (id.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Profile unavailable: missing candidate id',
              ),
            ),
          );
          return;
        }
        assert(() {
          debugPrint('Open profile → $id');
          return true;
        }());
        context.pushNamed(
          'candidate_view',
          pathParameters: {'id': id},
        );
      },
      onToggleFollow: handleToggleFollow,
      fullHeight: fillHeight,
    );
  }
}

class _CandidateListCard extends StatelessWidget {
  const _CandidateListCard({
    required this.candidate,
    required this.onOpen,
    required this.onToggleFollow,
    this.fullHeight = false,
  });

  final Candidate candidate;
  final VoidCallback onOpen;
  final VoidCallback onToggleFollow;
  final bool fullHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = candidate.name.isEmpty ? 'Unnamed candidate' : candidate.name;
    final desc = candidate.description;
    final tags = candidate.tags.take(5).toList();
    final socials = (candidate.socials ?? {})
        .map((k, v) => MapEntry(k.toLowerCase(), v));

    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundImage: (candidate.avatarUrl ?? candidate.headshotUrl) != null
                    ? NetworkImage(candidate.avatarUrl ?? candidate.headshotUrl!)
                    : null,
                child: (candidate.avatarUrl ?? candidate.headshotUrl) == null
                    ? const Icon(Icons.person, size: 36)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if ((candidate.level ?? '').isNotEmpty)
                          _InfoChip(
                            label: _displayLevel(candidate.level!),
                            large: true,
                          ),
                        if ((candidate.district ?? '').isNotEmpty)
                          _InfoChip(
                            label: candidate.district!,
                            large: true,
                          ),
                        _InfoChip(
                          icon: Icons.people_alt_outlined,
                          label: '${candidate.followersCount}',
                          large: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (desc != null && desc.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              desc.trim(),
              style: theme.textTheme.bodyLarge,
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: tags
                  .map((t) => _TagChip(label: t, large: true))
                  .toList(),
            ),
          ],
          const Spacer(),
          if (socials.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              children: socials.entries
                  .where((e) => e.value != null && e.value!.isNotEmpty)
                  .map(
                    (e) => IconButton(
                      tooltip: e.key,
                      icon: Icon(
                        kCandidateSocialIcons[e.key] ?? Icons.link_outlined,
                        size: 24,
                      ),
                      onPressed: () => _launchSocial(e.key, e.value!),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open profile'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    textStyle: theme.textTheme.labelLarge,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onToggleFollow,
                  icon:
                      Icon(candidate.isFollowing ? Icons.check : Icons.person_add),
                  label: Text(candidate.isFollowing ? 'Following' : 'Follow'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    textStyle: theme.textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: fullHeight ? SizedBox.expand(child: content) : content,
    );
  }

  String _displayLevel(String raw) {
    switch (raw.toLowerCase()) {
      case 'federal':
        return 'Federal';
      case 'state':
        return 'State';
      case 'county':
        return 'County';
      case 'city':
        return 'City/Township';
    }
    return raw;
  }

  Future<void> _launchSocial(String key, String value) async {
    String url = value;
    if (key == 'email') url = 'mailto:$value';
    if (key == 'phone') url = 'tel:$value';
    if (key == 'facebook') {
      url = value.startsWith('http') ? value : 'https://facebook.com/$value';
    }
    if (key == 'instagram') {
      url = value.startsWith('http') ? value : 'https://instagram.com/$value';
    }
    if (key == 'tiktok') {
      url = value.startsWith('http') ? value : 'https://tiktok.com/@$value';
    }
    if (key == 'x' || key == 'twitter') {
      url = value.startsWith('http') ? value : 'https://x.com/$value';
    }
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, this.icon, this.large = false});
  final String label;
  final IconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = (large
            ? Theme.of(context).textTheme.labelLarge
            : Theme.of(context).textTheme.labelMedium)
        ?.copyWith(fontWeight: FontWeight.w600);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 10,
        vertical: large ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: large ? 18 : 16),
          const SizedBox(width: 6),
        ],
        Text(label, style: style),
      ]),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, this.large = false});
  final String label;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = large
        ? Theme.of(context).textTheme.labelLarge
        : Theme.of(context).textTheme.labelMedium;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 10,
        vertical: large ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(label, style: style),
    );
  }
}
