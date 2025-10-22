import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../debug/logging.dart';
import '../../../../env.dart';
import '../../../comments/models/comment.dart';
import '../../../comments/providers/comments_providers.dart';
import '../../../../widgets/user_avatar.dart';

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({
    super.key,
    required this.postId,
    this.onProfileTap,
  });

  final String postId;
  final void Function(String userId)? onProfileTap;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final base = normalizedApiBaseUrl.isEmpty ? 'unset' : normalizedApiBaseUrl;
      logDebug(
        'COMMENTS',
        'sheet open',
        extra: <String, Object?>{
          'postId': widget.postId,
          'apiBase': base,
        },
      );
      ref
          .read(commentsControllerProvider(widget.postId).notifier)
          .loadInitial();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(commentsControllerProvider(widget.postId));
    final controller =
        ref.read(commentsControllerProvider(widget.postId).notifier);
    final Map<String, Comment> commentById = {
      for (final comment in state.items) comment.commentId: comment,
    };

    Comment? replyTarget;
    final replyingId = state.replyingTo;
    if (replyingId != null) {
      replyTarget = commentById[replyingId];
    }

    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.5,
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
                'Comments',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Divider(height: 1),
              Expanded(
                child: _buildCommentsList(
                  context,
                  state,
                  controller,
                  scrollController,
                  commentById,
                ),
              ),
              _Composer(
                replyingTo: replyTarget,
                controller: _textController,
                focusNode: _focusNode,
                onCancelReply: () => controller.setReplyingTo(null),
                onSend: (text) async {
                  final replyTo = state.replyingTo;
                  logDebug(
                    'COMMENTS',
                    'send start',
                    extra: <String, Object?>{
                      'postId': widget.postId,
                      'textLength': text.length,
                      if (replyTo != null) 'replyTo': replyTo,
                    },
                  );
                  try {
                    await controller.addComment(text, replyTo: replyTo);
                    logDebug(
                      'COMMENTS',
                      'send success',
                      extra: <String, Object?>{
                        'postId': widget.postId,
                        if (replyTo != null) 'replyTo': replyTo,
                      },
                    );
                    if (!mounted) {
                      return;
                    }
                    _textController.clear();
                    controller.setReplyingTo(null);
                    _focusNode.unfocus();
                  } catch (error, stackTrace) {
                    logDebug(
                      'COMMENTS',
                      'send error: $error',
                      extra: stackTrace.toString(),
                    );
                    rethrow;
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCommentsList(
    BuildContext context,
    CommentsState state,
    CommentsController controller,
    ScrollController scrollController,
    Map<String, Comment> commentById,
  ) {
    if (state.items.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: [
          if (state.loading)
            const Center(child: CircularProgressIndicator())
          else
            Center(
              child: Text(
                'Be the first to comment.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 120 &&
            !state.loading) {
          controller.loadMore();
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
          final comment = state.items[index];
          final parent =
              comment.replyTo == null ? null : commentById[comment.replyTo!];
          return _CommentTile(
            comment: comment,
            parent: parent,
            onLike: () => controller.toggleLike(comment.commentId),
            onReply: () {
              controller.setReplyingTo(comment.commentId);
              _focusNode.requestFocus();
            },
            onProfileTap: widget.onProfileTap,
          );
        },
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.parent,
    required this.onLike,
    required this.onReply,
    required this.onProfileTap,
  });

  final Comment comment;
  final Comment? parent;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final void Function(String userId)? onProfileTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final displayName = comment.displayName ?? comment.username ?? 'Unknown';
    final username = comment.username;
    final timeLabel = _formatTimestamp(comment.createdAt);
    final likeColor = comment.likedByMe ? theme.colorScheme.secondary : null;

    final contentPadding = EdgeInsets.only(
      left: comment.replyTo == null ? 16 : 32,
      right: 16,
      top: 4,
      bottom: 4,
    );

    return Padding(
      padding: EdgeInsets.only(
        left: comment.replyTo == null ? 0 : 8,
        right: 0,
      ),
      child: ListTile(
        contentPadding: contentPadding,
        leading: GestureDetector(
          onTap: comment.userId.isNotEmpty
              ? () => onProfileTap?.call(comment.userId)
              : null,
          child: UserAvatar(
            url: comment.avatarUrl,
            size: 40,
            backgroundColor: theme.colorScheme.surfaceVariant.withOpacity(0.2),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: comment.userId.isNotEmpty
                        ? () => onProfileTap?.call(comment.userId)
                        : null,
                    child: Text(
                      displayName,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (timeLabel != null)
                  Text(
                    timeLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: textTheme.bodySmall?.color?.withOpacity(0.7),
                    ),
                  ),
              ],
            ),
            if (username != null && username.isNotEmpty)
              Text(
                '@$username',
                style: textTheme.bodySmall?.copyWith(
                  color: textTheme.bodySmall?.color?.withOpacity(0.7),
                ),
              ),
            if (parent != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Replying to ${parent!.displayName ?? parent!.username ?? 'comment'}',
                  style: textTheme.bodySmall?.copyWith(
                    color: textTheme.bodySmall?.color?.withOpacity(0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                comment.text,
                style: textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onLike,
                  icon: Icon(
                    comment.likedByMe ? Icons.favorite : Icons.favorite_border,
                  ),
                  color: likeColor,
                  tooltip: 'Like',
                ),
                Text(
                  '${comment.likeCount}',
                  style: textTheme.bodySmall,
                ),
                TextButton(
                  onPressed: onReply,
                  child: const Text('Reply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.replyingTo,
    required this.controller,
    required this.focusNode,
    required this.onCancelReply,
    required this.onSend,
  });

  final Comment? replyingTo;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onCancelReply;
  final Future<void> Function(String text) onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replyName = replyingTo?.displayName ?? replyingTo?.username;
    final replyLabel =
        replyName == null ? 'Replying' : 'Replying to $replyName';
    final hintText = replyingTo == null ? 'Add a comment…' : 'Write a reply…';

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
        top: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (replyingTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      replyLabel,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: onCancelReply,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  final trimmed = controller.text.trim();
                  logDebug(
                    'COMMENTS',
                    'send tapped',
                    extra: <String, Object?>{'textLength': trimmed.length},
                  );
                  if (trimmed.isEmpty) {
                    return;
                  }
                  onSend(trimmed).catchError((error, stackTrace) {
                    logDebug(
                      'COMMENTS',
                      'send failed: $error',
                      extra: stackTrace.toString(),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to post comment: $error'),
                      ),
                    );
                  });
                },
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12),
                ),
                child: const Icon(Icons.send, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _formatTimestamp(int timestamp) {
  if (timestamp <= 0) {
    return null;
  }

  var milliseconds = timestamp;
  if (milliseconds < 1000000000000) {
    milliseconds *= 1000;
  }

  DateTime created;
  try {
    created = DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true)
        .toLocal();
  } catch (_) {
    return null;
  }

  final now = DateTime.now();
  final difference = now.difference(created);
  if (difference.inSeconds < 60) {
    return 'just now';
  }
  if (difference.inMinutes < 60) {
    return '${difference.inMinutes}m';
  }
  if (difference.inHours < 24) {
    return '${difference.inHours}h';
  }
  if (difference.inDays < 7) {
    return '${difference.inDays}d';
  }

  return '${created.month}/${created.day}/${created.year}';
}
