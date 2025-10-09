class UploadOutcome {
  const UploadOutcome({
    required this.ok,
    this.postId,
    this.uploadId,
    this.message,
    this.statusCode,
  });

  final bool ok;
  final String? postId;
  final String? uploadId;
  final String? message;
  final int? statusCode;
}
