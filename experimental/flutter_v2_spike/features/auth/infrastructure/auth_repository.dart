import '../domain/auth_session.dart';

abstract class AuthRepository {
  Future<AuthSession> restoreSession();
}
