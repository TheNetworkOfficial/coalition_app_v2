import 'package:coalition_app_v2/core/navigation/account_link.dart';
import 'package:coalition_app_v2/features/engagement/utils/ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/post.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/post_view.dart';

class PostPlayerPage extends ConsumerWidget {
  const PostPlayerPage({super.key, required this.post});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void handleProfileTap() {
      AccountNavigator.navigateToAccount(
        context,
        AccountRef.fromPost(
          userId: post.userId ?? '',
          candidateId: post.candidateId,
        ),
      );
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
