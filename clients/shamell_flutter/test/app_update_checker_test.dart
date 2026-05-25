import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/app_update_checker.dart';

void main() {
  group('ShamellAppUpdateInfo.isUpdateAvailable', () {
    test('returns false when current and latest are identical', () {
      final info = ShamellAppUpdateInfo(
        currentReleaseId: 'android-apk-0.1.0-20260513T100000Z',
        latestReleaseId: 'android-apk-0.1.0-20260513T100000Z',
        latestVersionName: '0.1.0',
      );
      expect(info.isUpdateAvailable, isFalse);
    });

    test('returns true when latest differs from current', () {
      final info = ShamellAppUpdateInfo(
        currentReleaseId: 'android-apk-0.1.0-20260512T100000Z',
        latestReleaseId: 'android-apk-0.1.0-20260513T100000Z',
        latestVersionName: '0.1.0',
      );
      expect(info.isUpdateAvailable, isTrue);
    });

    test('returns false when current is empty (dev / unpinned build)', () {
      final info = ShamellAppUpdateInfo(
        currentReleaseId: '',
        latestReleaseId: 'android-apk-0.1.0-20260513T100000Z',
        latestVersionName: '0.1.0',
      );
      expect(info.isUpdateAvailable, isFalse);
    });

    test('returns false when latest is empty (manifest missing release_id)', () {
      final info = ShamellAppUpdateInfo(
        currentReleaseId: 'android-apk-0.1.0-20260513T100000Z',
        latestReleaseId: '',
        latestVersionName: '0.1.0',
      );
      expect(info.isUpdateAvailable, isFalse);
    });
  });
}
