class AuthSession {
  final String userId;
  final String displayName;
  final String walletId;

  const AuthSession({
    required this.userId,
    required this.displayName,
    required this.walletId,
  });
}
