import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'base_url.dart';
import 'l10n.dart';

/// Build-time identifier for this APK's release. Injected by the build
/// script via `--dart-define=APP_RELEASE_ID=...` so the running app can
/// compare itself against the latest published manifest on the static
/// download page. Empty when running a dev build that wasn't built via the
/// release pipeline — in that case the update check silently skips.
const String _kAppReleaseId = String.fromEnvironment('APP_RELEASE_ID');

const String _kDownloadsUrl = 'https://shamell.online/downloads/android/';
const String _kManifestUrl =
    'https://shamell.online/downloads/android/release-manifest.json';
const String _kLastShownReleaseIdKey = 'shamell.app_update.last_shown_release_id';
const String _kLastCheckEpochKey = 'shamell.app_update.last_check_epoch';
const Duration _kCheckInterval = Duration(hours: 6);

class ShamellAppUpdateInfo {
  ShamellAppUpdateInfo({
    required this.currentReleaseId,
    required this.latestReleaseId,
    required this.latestVersionName,
  });
  final String currentReleaseId;
  final String latestReleaseId;
  final String latestVersionName;
  bool get isUpdateAvailable =>
      currentReleaseId.isNotEmpty &&
      latestReleaseId.isNotEmpty &&
      currentReleaseId != latestReleaseId;
}

/// Best-effort fetch of the published release manifest. Returns `null` when
/// the request fails or returns malformed JSON — callers treat that as "no
/// update info available".
Future<ShamellAppUpdateInfo?> fetchShamellAppUpdateInfo() async {
  if (_kAppReleaseId.isEmpty) return null;
  final client = shamellHttpClient();
  try {
    final response = await client
        .get(Uri.parse(_kManifestUrl))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;
    final body = jsonDecode(response.body);
    if (body is! Map<String, Object?>) return null;
    final releaseId = (body['release_id'] ?? '').toString().trim();
    final versionName = (body['version_name'] ?? '').toString().trim();
    if (releaseId.isEmpty) return null;
    return ShamellAppUpdateInfo(
      currentReleaseId: _kAppReleaseId,
      latestReleaseId: releaseId,
      latestVersionName: versionName,
    );
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Foreground-only update check. Schedules itself to run on app foreground
/// after a brief delay so it doesn't fight with login / push / route bootstrap.
/// Shows a non-blocking SnackBar with an "Open" action that launches the
/// downloads page, and stashes the shown release_id so the same banner does
/// not nag on every cold start.
Future<void> maybeShowAppUpdateBanner(BuildContext context) async {
  if (_kAppReleaseId.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final lastCheck = prefs.getInt(_kLastCheckEpochKey) ?? 0;
    if (now - lastCheck < _kCheckInterval.inSeconds) return;
    await prefs.setInt(_kLastCheckEpochKey, now);

    final info = await fetchShamellAppUpdateInfo();
    if (info == null || !info.isUpdateAvailable) return;

    final lastShown = prefs.getString(_kLastShownReleaseIdKey) ?? '';
    if (lastShown == info.latestReleaseId) return;
    if (!context.mounted) return;

    final l = L10n.of(context);
    final isArabic = l.isArabic;
    final message = isArabic
        ? 'يتوفر تحديث جديد لتطبيق سرتشات (${info.latestVersionName}).'
        : 'A new SyrChat update is available (${info.latestVersionName}).';
    final actionLabel = isArabic ? 'تحديث' : 'Update';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: actionLabel,
          onPressed: () {
            unawaited(launchUrl(
              Uri.parse(_kDownloadsUrl),
              mode: LaunchMode.externalApplication,
            ));
          },
        ),
        duration: const Duration(seconds: 8),
      ),
    );

    await prefs.setString(_kLastShownReleaseIdKey, info.latestReleaseId);
  } catch (e) {
    assert(() {
      debugPrint('APP_UPDATE_CHECK_FAIL: $e');
      return true;
    }());
  }
}
