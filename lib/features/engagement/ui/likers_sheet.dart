import 'package:coalition_app_v2/features/engagement/utils/ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/user_avatar.dart';
import '../models/liker.dart';
import '../providers/engagement_providers.dart';

Future<void> showLikersSheet(BuildContext context, String postId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => LikersSheet(postId: postId),
  );
}

class LikersSheet extends ConsumerStatefulWidget {
  const LikersSheet({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<LikersSheet> createState() => _LikersSheetState();
}

class _LikersSheetState extends ConsumerState<LikersSheet> {
  late final String _postId;

  @override
  void initState() {
    super.initState();
    _postId = normalizePostId(widget.postId);
    if (_postId.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _postId.isEmpty) {
        return;
      }
      ref.read(postLikersProvider(_postId).notifier).loadInitial();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_postId.isEmpty) {
      return SafeArea(
        top: false,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          child: const Center(child: Text('Likes unavailable for this post.')),
        ),
      );
    }

    final state = ref.watch(postLikersProvider(_postId));
    final notifier = ref.read(postLikersProvider(_postId).notifier);

    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Likes',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${state.items.length}${state.loading ? '+' : ''} people',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.pixels >=
                              notification.metrics.maxScrollExtent - 120 &&
                          !state.loading &&
                          (state.cursor ?? '').isNotEmpty) {
                        notifier.loadMore();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: state.items.length + (state.loading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= state.items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final liker = state.items[index];
                        return _LikerTile(liker: liker);
                      },
                    ),
                  ),
                ),
                if ((state.error ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      state.error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LikerTile extends StatelessWidget {
  const _LikerTile({required this.liker});

  final Liker liker;

  @override
  Widget build(BuildContext context) {
    final title = (liker.displayName ?? liker.userId).trim();
    final subtitle = liker.userId.isEmpty ? null : '@${liker.userId}';
    final timeLabel = _formatTimestamp(liker.createdAt);
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: UserAvatar(
        url: liker.avatarUrl,
        size: 48,
        backgroundColor: colorScheme.surfaceContainerHighest,
      ),
      title: Text(title.isEmpty ? 'Anonymous' : title),
      subtitle: subtitle == null || subtitle == '@'
          ? null
          : Text(subtitle),
      trailing: Text(
        timeLabel,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

String _formatTimestamp(DateTime? timestamp) {
  if (timestamp == null) {
    return '';
  }
  final now = DateTime.now().toUtc();
  final difference = now.difference(timestamp.toUtc());
  if (difference.inSeconds < 60) {
    return 'Just now';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m ago';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours}h ago';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d ago';
  }
  final weeks = (difference.inDays / 7).floor();
  return '${weeks}w ago';
}
