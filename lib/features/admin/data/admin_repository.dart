import '../../../services/api_client.dart';
import '../models/admin_application.dart';

class AdminRepository {
  AdminRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<AdminApplicationsPage> listApplications({
    String status = 'pending',
    int limit = 20,
    String? cursor,
  }) {
    return apiClient.listAdminApplications(
      status: status,
      limit: limit,
      cursor: cursor,
    );
  }

  Future<AdminApplication> getApplication(String id) {
    return apiClient.getAdminApplication(id);
  }

  Future<ApprovalResult> approve(
    String id, {
    String? reason,
  }) {
    return apiClient.approveAdminApplication(id, reason: reason);
  }

  Future<ApprovalResult> reject(
    String id, {
    String? reason,
  }) {
    return apiClient.rejectAdminApplication(id, reason: reason);
  }
}
