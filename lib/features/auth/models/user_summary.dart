class UserSummary {
  const UserSummary({
    required this.userId,
    required this.username,
    this.displayName,
  });

  final String userId;
  final String username;
  final String? displayName;
}
