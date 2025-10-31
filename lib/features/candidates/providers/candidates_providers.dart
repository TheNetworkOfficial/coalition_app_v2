import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';
import '../../../services/api_client.dart';
import '../data/candidates_repository.dart';
import '../models/candidate.dart';
import '../models/candidate_update.dart';
import '../../../models/posts_page.dart';
import '../../../models/profile.dart';
import 'candidates_pager_provider.dart';

export 'candidates_pager_provider.dart';

final candidatesRepositoryProvider = Provider<CandidatesRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CandidatesRepository(apiClient: apiClient);
});

final myCandidateApplicationProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    return await api.getMyCandidateApplication();
  } catch (_) {
    return null;
  }
});

final myProfileProvider = FutureProvider<Profile?>((ref) async {
  final api = ref.read(apiClientProvider);
  try {
    final Profile? profile = await api.getMyProfile();
    return profile;
  } catch (_) {
    return null;
  }
});

final candidateIdentityLockedProvider = Provider<bool>((ref) {
  final appAsync = ref.watch(myCandidateApplicationProvider);
  final appIsLoading = appAsync.isLoading;
  final app = appAsync.asData?.value ?? appAsync.value;
  final appStatus = ((app?['status'] as String?) ?? '').trim().toLowerCase();
  final approvedByApp = appStatus == 'approved';

  final profAsync = ref.watch(myProfileProvider);
  final profIsLoading = profAsync.isLoading;
  final Profile? prof = profAsync.asData?.value ?? profAsync.value;
  final profStatus = ((prof?.candidateAccessStatus) ?? '').trim().toLowerCase();
  final approvedByProfile = profStatus == 'approved';

  // If either is loading, lock to prevent first-frame taps.
  if (appIsLoading || profIsLoading) return true;

  // If either source says approved, lock.
  if (approvedByApp || approvedByProfile) return true;

  // Otherwise unlock (not approved on either source).
  return false;
});

final candidateDetailProvider =
    FutureProvider.family<Candidate?, String>((ref, id) async {
  final apiClient = ref.watch(apiClientProvider);
  final trimmed = id.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  try {
    final response = await apiClient.getCandidate(trimmed);
    return response.candidate;
  } on ApiException catch (error) {
    if (error.statusCode == HttpStatus.notFound) {
      return null;
    }
    rethrow;
  }
});

final candidatePostsProvider =
    FutureProvider.family<PostsPage, String>((ref, id) {
  final repository = ref.watch(candidatesRepositoryProvider);
  return repository.getCandidatePosts(id);
});

final candidateUpdateControllerProvider =
    Provider<Future<Candidate> Function(String, CandidateUpdate)>((ref) {
  final repository = ref.watch(candidatesRepositoryProvider);
  return (String id, CandidateUpdate update) async {
    final updated = await repository.updateCandidate(id, update);
    ref.invalidate(candidateDetailProvider(id));
    ref.invalidate(candidatePostsProvider(id));
    ref.invalidate(candidatesPagerProvider);
    return updated;
  };
});
