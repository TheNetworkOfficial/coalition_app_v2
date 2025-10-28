import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/candidates/models/candidate.dart';
import '../features/candidates/providers/candidates_providers.dart';
import '../providers/app_providers.dart';
import '../widgets/user_avatar.dart';

class CandidateViewerPage extends ConsumerStatefulWidget {
  const CandidateViewerPage({super.key, required this.candidateId});

  final String candidateId;

  @override
  ConsumerState<CandidateViewerPage> createState() =>
      _CandidateViewerPageState();
}

class _CandidateViewerPageState extends ConsumerState<CandidateViewerPage> {
  AsyncValue<Candidate> _state = const AsyncValue.loading();

  @override
  void initState() {
    super.initState();
    _loadCandidate();
  }

  Future<void> _loadCandidate() async {
    setState(() => _state = const AsyncValue.loading());
    final apiClient = ref.read(apiClientProvider);
    try {
      final response = await apiClient.getCandidate(widget.candidateId);
      if (!mounted) {
        return;
      }
      setState(() => _state = AsyncValue.data(response.candidate));
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }
      setState(() => _state = AsyncValue.error(error, stackTrace));
    }
  }

  Future<void> _toggleFollow(Candidate candidate) async {
    final next = !candidate.isFollowing;
    final delta = next ? 1 : -1;
    final optimistic = candidate.copyWith(
      isFollowing: next,
      followersCount: max(0, candidate.followersCount + delta),
    );

    setState(() => _state = AsyncValue.data(optimistic));

    try {
      await ref.read(candidatesPagerProvider.notifier).optimisticToggle(
            candidate.candidateId,
            next,
          );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _state = AsyncValue.data(candidate));
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Failed to update follow: $error')),
        );
      return;
    }

    try {
      final refreshed =
          await ref.read(apiClientProvider).getCandidate(candidate.candidateId);
      if (!mounted) {
        return;
      }
      setState(() => _state = AsyncValue.data(refreshed.candidate));
    } catch (_) {
      // Keep optimistic state if refresh fails.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Candidate'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadCandidate,
          ),
        ],
      ),
      body: _state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load candidate: $error'),
          ),
        ),
        data: (candidate) => RefreshIndicator(
          onRefresh: _loadCandidate,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  UserAvatar(
                    url: candidate.headshotUrl,
                    size: 72,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.name.isNotEmpty
                              ? candidate.name
                              : 'Unnamed candidate',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if ((candidate.level ?? '').isNotEmpty)
                              Chip(label: Text(candidate.level!)),
                            if ((candidate.district ?? '').isNotEmpty)
                              Chip(label: Text(candidate.district!)),
                            Chip(
                                label: Text(
                                    '${candidate.followersCount} followers')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((candidate.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  candidate.description!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
              if (candidate.tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in candidate.tags.take(5))
                      Chip(label: Text(tag)),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _toggleFollow(candidate),
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
            ],
          ),
        ),
      ),
    );
  }
}
