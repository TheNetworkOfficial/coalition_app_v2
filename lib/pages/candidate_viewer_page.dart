import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/candidates/models/candidate.dart';
import '../features/candidates/providers/candidates_providers.dart';
import '../features/candidates/ui/candidate_views.dart';
import '../models/posts_page.dart';
import '../widgets/post_grid_tile.dart';

class CandidateViewerPage extends ConsumerStatefulWidget {
  const CandidateViewerPage({super.key, required this.candidateId});

  final String candidateId;

  @override
  ConsumerState<CandidateViewerPage> createState() =>
      _CandidateViewerPageState();
}

class _CandidateViewerPageState extends ConsumerState<CandidateViewerPage> {
  bool _isTogglingFollow = false;

  @override
  Widget build(BuildContext context) {
    final candidateAsync =
        ref.watch(candidateDetailProvider(widget.candidateId));

    return candidateAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Candidate')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load candidate: $error'),
          ),
        ),
      ),
      data: (candidate) {
        if (candidate == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Candidate')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Your candidate page is not created yet.'),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => context.pushNamed('candidate_edit'),
                    child: const Text('Create / Edit Candidate Page'),
                  ),
                ],
              ),
            ),
          );
        }

        final postsAsync =
            ref.watch(candidatePostsProvider(widget.candidateId));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Candidate'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: _refresh,
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                CandidateHeaderView(
                  avatarUrl: candidate.avatarUrl ?? candidate.headshotUrl,
                  displayName: candidate.name,
                  levelOfOffice: candidate.level,
                  district: candidate.district,
                  extraChips: [
                    Chip(label: Text('${candidate.followersCount} followers')),
                  ],
                ),
                if ((candidate.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 16),
                  CandidateBioView(bio: candidate.description),
                ],
                if (candidate.tags.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  CandidateTagsView(
                    priorityTags:
                        candidate.tags.take(5).toList(growable: false),
                  ),
                ],
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _isTogglingFollow
                        ? null
                        : () => _toggleFollow(candidate),
                    icon: Icon(candidate.isFollowing
                        ? Icons.check
                        : Icons.person_add_alt),
                    label: Text(
                      candidate.isFollowing
                          ? 'Following • ${candidate.followersCount}'
                          : 'Follow • ${candidate.followersCount}',
                    ),
                  ),
                ),
                CandidateSocialsView(
                  socials: candidate.socials ?? const {},
                  title: const CandidateSectionTitle(text: 'Connect'),
                ),
                const SizedBox(height: 24),
                const CandidateSectionTitle(text: 'Posts'),
                const SizedBox(height: 12),
                _buildPostsSection(postsAsync),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(candidateDetailProvider(widget.candidateId));
    ref.invalidate(candidatePostsProvider(widget.candidateId));
    try {
      await Future.wait([
        ref.read(candidateDetailProvider(widget.candidateId).future),
        ref.read(candidatePostsProvider(widget.candidateId).future),
      ]);
    } catch (_) {
      // Ignore refresh errors; UI will display latest AsyncValue state.
    }
  }

  Future<void> _toggleFollow(Candidate candidate) async {
    if (_isTogglingFollow) {
      return;
    }
    setState(() => _isTogglingFollow = true);

    try {
      await ref.read(candidatesPagerProvider.notifier).optimisticToggle(
            candidate.candidateId,
            !candidate.isFollowing,
          );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to update follow: $error')),
        );
    } finally {
      ref.invalidate(candidateDetailProvider(candidate.candidateId));
      try {
        await ref
            .read(candidateDetailProvider(candidate.candidateId).future);
      } catch (_) {}
      if (mounted) {
        setState(() => _isTogglingFollow = false);
      }
    }
  }

  Widget _buildPostsSection(AsyncValue<PostsPage> postsAsync) {
    return postsAsync.when(
      loading: () => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 1,
        ),
        itemBuilder: (context, index) => const PostGridShimmerTile(),
      ),
      error: (error, _) => Text(
        'Failed to load posts: $error',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.error),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const Text('No posts yet.');
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: page.items.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 1,
          ),
          itemBuilder: (context, index) {
            final item = page.items[index];
            return PostGridTile(
              item: item,
              onTap: () {},
            );
          },
        );
      },
    );
  }
}
