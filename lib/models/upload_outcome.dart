class UploadOutcome {
  const UploadOutcome({
    required this.ok,
    this.postId,
    this.cfUid,
    this.message,
    this.statusCode,
  });

  final bool ok;
  final String? postId;
  final String? cfUid;
  final String? message;
  final int? statusCode;
}
