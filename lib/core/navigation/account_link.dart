import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:coalition_app_v2/router/app_router.dart';

/// Describes a user or candidate target for navigation.
class AccountRef {
  const AccountRef({
    required this.userId,
    this.candidateId,
    this.isCandidateHint,
  });

  final String userId;
  final String? candidateId;
  final bool? isCandidateHint;

  factory AccountRef.fromPost({
    required String userId,
    String? candidateId,
    bool? isCandidateHint,
  }) {
    return AccountRef(
      userId: userId,
      candidateId: candidateId,
      isCandidateHint: isCandidateHint,
    );
  }

  factory AccountRef.fromComment({
    required String userId,
    String? candidateId,
  }) {
    return AccountRef(
      userId: userId,
      candidateId: candidateId,
    );
  }
}

/// Debounced, route-aware navigation utility for profile/candidate taps.
class AccountNavigator {
  static DateTime? _lastNavAt;
  static bool _inFlight = false;

  static bool _shouldDebounce() {
    final now = DateTime.now();
    if (_lastNavAt != null &&
        now.difference(_lastNavAt!) < const Duration(milliseconds: 350)) {
      return true;
    }
    _lastNavAt = now;
    return false;
  }

  static Future<void> navigateToAccount(
    BuildContext context,
    AccountRef? ref,
  ) async {
    if (ref == null) {
      return;
    }
    final trimmedUserId = ref.userId.trim();
    if (trimmedUserId.isEmpty || _inFlight || _shouldDebounce()) {
      return;
    }
    _inFlight = true;
    try {
      final rootContext = rootNavigatorKey.currentContext ?? context;
      final router = GoRouter.of(rootContext);
      final routeInfo = router.routeInformationProvider.value;
      final uri = routeInfo.uri;
      final path = uri.path;
      final segments = uri.pathSegments;

      String segmentValue(String segment) {
        final delimiterIndex = segment.indexOf(';');
        if (delimiterIndex == -1) {
          return segment;
        }
        return segment.substring(0, delimiterIndex);
      }

      final candidateId = (ref.candidateId ?? trimmedUserId).trim();
      final isCandidate = (ref.candidateId?.trim().isNotEmpty ?? false) ||
          (ref.isCandidateHint ?? false);
      final bool alreadyOnCandidate = isCandidate &&
          segments.length >= 2 &&
          segmentValue(segments[0]) == 'candidates' &&
          segmentValue(segments[1]) == candidateId;
      final bool alreadyOnProfile =
          !isCandidate && (path == '/profile' || path == '/profile-tab');

      if (isCandidate && candidateId.isNotEmpty) {
        if (alreadyOnCandidate) {
          return;
        }
        await router.pushNamed(
          'candidate_view',
          pathParameters: {'id': candidateId},
        );
        return;
      }

      if (alreadyOnProfile) {
        return;
      }
      await router.pushNamed('profile', extra: trimmedUserId);
    } finally {
      _inFlight = false;
    }
  }
}
