import 'package:flutter/foundation.dart';

import '../../../../core/account_session_bootstrap.dart';
import '../../../../core/base_url.dart';
import '../../../../core/device_binding_guard.dart';
import '../../../../core/logout_wipe.dart';
import '../../../../core/session_cookie_store.dart';
import '../../../../core/v2_auth_strangler.dart';
import '../domain/auth_session.dart';
import 'auth_repository.dart';

typedef SessionBootstrapBaseUrlResolver = Future<String> Function();
typedef SessionBootstrapEnsureSession = Future<AccountSessionBootstrapResult>
    Function(String baseUrl);
typedef SessionBootstrapEnsureSessionAttempt
    = Future<AccountSessionBootstrapAttemptOutcome> Function(String baseUrl);
typedef SessionBootstrapSnapshotLoader = Future<AccountHomeSnapshot> Function(
  String baseUrl,
);

@visibleForTesting
bool shamellIsCriticalSessionBootstrapFailure(Object error) =>
    shamellIsCriticalAccountSessionError(error);

class SessionBootstrapAuthRepository implements AuthRepository {
  final SessionBootstrapBaseUrlResolver? baseUrlResolver;
  final SessionBootstrapEnsureSession? ensureSessionCookie;
  final SessionBootstrapEnsureSessionAttempt? ensureSessionAttempt;
  final SessionBootstrapSnapshotLoader? snapshotLoader;

  SessionBootstrapAuthRepository({
    this.baseUrlResolver,
    this.ensureSessionCookie,
    this.ensureSessionAttempt,
    this.snapshotLoader,
  });

  @override
  Future<AuthSession> restoreSession() async {
    String? baseUrl;
    try {
      baseUrl = await (baseUrlResolver?.call() ??
          V2AuthStranglerStore.resolveBaseUrl());
      if (!isSecureApiBaseUrl(baseUrl)) {
        throw Exception('Invalid API base URL. Configure HTTPS base_url.');
      }
      final resolvedBaseUrl = baseUrl;

      final cookie =
          (await getSessionCookieHeader(resolvedBaseUrl) ?? '').trim();
      if (cookie.isEmpty) {
        throw Exception('Authentication required.');
      }

      final sessionAttempt = await (() async {
        if (ensureSessionAttempt != null) {
          return ensureSessionAttempt!(resolvedBaseUrl);
        }
        if (ensureSessionCookie != null) {
          return AccountSessionBootstrapAttemptOutcome(
            result: await ensureSessionCookie!(resolvedBaseUrl),
          );
        }
        return const AccountSessionBootstrapAttemptOutcome(
          result: AccountSessionBootstrapResult.success,
        );
      })();
      if (sessionAttempt.result ==
          AccountSessionBootstrapResult.reauthRequired) {
        await wipeLocalAccountData(
          preserveDevicePrefs: true,
          baseUrlOverride: baseUrl,
        );
        throw Exception(
          'This Shamell session no longer matches this device. Sign in again.',
        );
      }
      if (sessionAttempt.result != AccountSessionBootstrapResult.success) {
        throw shamellAccountSessionBootstrapFailureException(sessionAttempt);
      }

      late final AccountHomeSnapshot snapshot;
      if (snapshotLoader != null) {
        snapshot = await snapshotLoader!(baseUrl);
      } else {
        final client = shamellHttpClient();
        try {
          snapshot = await refreshAndPersistAccountHomeSnapshot(
            baseUrl: baseUrl,
            client: client,
            ensureSession: false,
          );
        } finally {
          client.close();
        }
      }

      final displayName = snapshot.shamellId;
      final userId = snapshot.shamellId;
      return AuthSession(
        userId: userId,
        displayName: displayName,
        walletId: snapshot.walletId,
      );
    } catch (e) {
      if (shamellIsCriticalSessionBootstrapFailure(e)) {
        await wipeLocalAccountData(
          preserveDevicePrefs: true,
          baseUrlOverride: baseUrl,
        );
        throw Exception(
          'This Shamell session no longer matches this device. Sign in again.',
        );
      }
      rethrow;
    }
  }
}
