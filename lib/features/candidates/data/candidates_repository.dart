import 'package:coalition_app_v2/features/candidates/models/candidate.dart';
import 'package:coalition_app_v2/features/candidates/models/candidate_update.dart';
import 'package:coalition_app_v2/features/candidates/models/candidates_filter.dart';
import 'package:coalition_app_v2/models/posts_page.dart';
import 'package:coalition_app_v2/services/api_client.dart';

class CandidatesRepository {
  CandidatesRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<({List<Candidate> items, String? cursor})> list({
    int limit = 20,
    String? cursor,
    CandidatesFilter? filter,
  }) {
    final tags = filter?.tags ?? const <String>{};
    return apiClient.getCandidates(
      limit: limit,
      cursor: cursor,
      level: filter?.level,
      district: filter?.district,
      tags: tags.isEmpty ? null : tags.join(','),
      query: filter?.query,
    );
  }

  Future<void> toggleFollow(String id) {
    return apiClient.toggleCandidateFollow(id);
  }

  Future<Candidate> updateCandidate(String id, CandidateUpdate update) {
    return apiClient.updateCandidate(id, update);
  }

  Future<PostsPage> getCandidatePosts(
    String id, {
    int limit = 30,
    String? cursor,
  }) {
    return apiClient.getCandidatePosts(
      id,
      limit: limit,
      cursor: cursor,
    );
  }
}
