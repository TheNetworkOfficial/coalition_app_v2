import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ids.dart';
import '../../features/auth/providers/auth_state.dart';
import '../../features/comments/providers/comments_providers.dart';
import '../../features/engagement/providers/engagement_providers.dart';
import 'realtime_events.dart';

abstract class RealtimeService {
  void subscribePost(String postId);
  void unsubscribePost(String postId);
  Stream<RealtimeEvent> get stream;
  void dispose();
}

class PollingRealtimeService implements RealtimeService {
  PollingRealtimeService({
    required Future<Map<String, dynamic>?> Function(String postId)
        fetchSummary,
    this.interval = const Duration(seconds: 25),
  }) : _fetchSummary = fetchSummary;

  final Future<Map<String, dynamic>?> Function(String postId) _fetchSummary;
  final Duration interval;

  final _subscribed = <String>{};
  Timer? _timer;
  final StreamController<RealtimeEvent> _controller =
      StreamController<RealtimeEvent>.broadcast();

  @override
  Stream<RealtimeEvent> get stream => _controller.stream;

  @override
  void subscribePost(String postId) {
    final normalized = normalizePostId(postId);
    if (!isValidPostId(normalized)) {
      return;
    }
    final added = _subscribed.add(normalized);
    if (added && _timer == null) {
      _timer = Timer.periodic(interval, (_) => _tick());
    }
  }

  @override
  void unsubscribePost(String postId) {
    final normalized = normalizePostId(postId);
    if (!isValidPostId(normalized)) {
      _subscribed.remove(normalized);
      if (_subscribed.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
      return;
    }
    _subscribed.remove(normalized);
    if (_subscribed.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _tick() async {
    for (final id in _subscribed.toList()) {
      // Double-guard against legacy synthetic IDs.
      if (!isValidPostId(id)) {
        continue;
      }
      try {
        final summary = await _fetchSummary(id);
        if (summary == null) {
          continue;
        }
        _controller.add(
          RealtimeEvent(
            'post.engagement.updated',
            <String, dynamic>{'postId': id, ...summary},
          ),
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[PollingRealtimeService] fetchSummary failed for post $id: $error\n$stackTrace',
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}

class RealtimeReducer {
  RealtimeReducer(this.ref, Stream<RealtimeEvent> stream) {
    _subscription = stream.listen(_handleEvent);
  }

  final Ref ref;
  StreamSubscription<RealtimeEvent>? _subscription;

  void _handleEvent(RealtimeEvent event) {
    switch (event.type) {
      case 'post.engagement.updated':
        _onPostEngagementUpdated(event.payload);
        break;
      case 'comment.created':
        _onCommentCreated(event.payload);
        break;
      case 'comment.likes.updated':
        _onCommentLikesUpdated(event.payload);
        break;
      case 'comment.engagement.user':
        _onCommentEngagementUser(event.payload);
        break;
      default:
        break;
    }
  }

  void _onPostEngagementUpdated(Map<String, dynamic> payload) {
    final update = PostEngagementUpdated.fromJson(payload);
    if (update.postId.isEmpty) {
      return;
    }
    final controller =
        ref.read(postEngagementProvider(update.postId).notifier);
    controller.applyServerSummary(
      likeCount: update.likesCount,
      commentCount: update.commentsCount,
      overrideLikedStatus: false,
    );
  }

  void _onCommentCreated(Map<String, dynamic> payload) {
    final update = CommentCreated.fromJson(payload);
    if (update.postId.isEmpty) {
      return;
    }
    final active = ref.read(activeCommentsRegistryProvider);
    if (!active.contains(update.postId)) {
      return;
    }
    ref
        .read(commentsControllerProvider(update.postId).notifier)
        .insertFromServer(update.commentJson);
  }

  void _onCommentLikesUpdated(Map<String, dynamic> payload) {
    final update = CommentLikesUpdated.fromJson(payload);
    if (update.commentId.isEmpty) {
      return;
    }
    final active = ref.read(activeCommentsRegistryProvider);
    if (active.isEmpty) {
      return;
    }
    for (final postId in active) {
      ref
          .read(commentsControllerProvider(postId).notifier)
          .applyServerLikeCount(update.commentId, update.likeCount);
    }
    final authState = ref.read(authStateProvider);
    final myUserId = authState.user?.userId.trim() ?? '';
    if (myUserId.isEmpty ||
        update.userId.isEmpty ||
        update.userId != myUserId) {
      return;
    }
    for (final postId in active) {
      ref
          .read(commentsControllerProvider(postId).notifier)
          .applyUserLikedStatus(update.commentId, update.likedByMe);
    }
  }

  void _onCommentEngagementUser(Map<String, dynamic> payload) {
    final evt = CommentEngagementUser.fromJson(payload);
    if (evt.commentId.isEmpty) {
      return;
    }
    final authState = ref.read(authStateProvider);
    final myUserId = authState.user?.userId.trim() ?? '';
    if (myUserId.isEmpty || evt.userId.isEmpty || evt.userId != myUserId) {
      return;
    }
    final active = ref.read(activeCommentsRegistryProvider);
    if (active.isEmpty) {
      return;
    }
    for (final postId in active) {
      ref
          .read(commentsControllerProvider(postId).notifier)
          .applyUserLikedStatus(evt.commentId, evt.likedByMe);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
