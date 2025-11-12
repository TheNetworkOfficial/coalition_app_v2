import 'package:coalition_app_v2/features/engagement/utils/ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/post.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/post_view.dart';

class PostPlayerPage extends ConsumerWidget {
  const PostPlayerPage({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void pushCandidateProfile(String? rawUserId) {
      final trimmed = (rawUserId ?? '').trim();
      if (trimmed.isEmpty) {
        return;
      }
      context.pushNamed('candidate_view', pathParameters: {'id': trimmed});
    }

    void handleProfileTap() {
      pushCandidateProfile(post.userId);
    }

    void handleCommentsTap() {
      final postId = normalizePostId(post.id);
      if (postId.isEmpty) {
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Comments unavailable for this post.')),
          );
        return;
      }
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Theme.of(context).colorScheme.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => CommentsSheet(
          postId: postId,
          onProfileTap: (userId) {
            pushCandidateProfile(userId);
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PostView(
          post: post,
          initiallyActive: true,
          onProfileTap: handleProfileTap,
          onCommentsTap: handleCommentsTap,
        ),
      ),
    );
  }
}
