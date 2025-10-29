import 'package:flutter/foundation.dart';

@immutable
class AdminApplication {
  const AdminApplication({
    required this.id,
    required this.fullName,
    required this.status,
    required this.submittedAt,
    this.avatarUrl,
    this.summary,
    this.details = const <String, Object?>{},
    this.tags = const <String>[],
  })  : assert(id != ''),
        assert(fullName != '');

  final String id;
  final String fullName;
  final String status;
  final DateTime submittedAt;
  final String? avatarUrl;
  final String? summary;
  final Map<String, Object?> details;
  final List<String> tags;

  String get submittedLabel => submittedAt.toLocal().toIso8601String();

  AdminApplication copyWith({
    String? fullName,
    String? status,
    DateTime? submittedAt,
    String? avatarUrl,
    String? summary,
    Map<String, Object?>? details,
    List<String>? tags,
  }) {
    return AdminApplication(
      id: id,
      fullName: fullName ?? this.fullName,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      summary: summary ?? this.summary,
      details: details ?? this.details,
      tags: tags ?? this.tags,
    );
  }
}

@immutable
class AdminApplicationsPage {
  const AdminApplicationsPage({
    required this.items,
    required this.nextCursor,
  });

  final List<AdminApplication> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}

@immutable
class ApprovalResult {
  const ApprovalResult({
    required this.applicationId,
    required this.status,
    this.reason,
  });

  final String applicationId;
  final String status;
  final String? reason;
}
