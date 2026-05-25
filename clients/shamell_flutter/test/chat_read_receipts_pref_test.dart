import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_read_receipts_pref.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ChatReadReceiptsPref.resetForTesting();
  });

  group('ChatReadReceiptsPref', () {
    test('defaults to enabled before hydrate', () {
      // The hot-path getter must be safe to call before hydrate
      // completes — a brief window of extra acks is preferable to a
      // crash on first message arrival.
      expect(ChatReadReceiptsPref.enabled, isTrue);
    });

    test('hydrate reads the persisted false value', () async {
      SharedPreferences.setMockInitialValues({
        'shamell.chat.read_receipts.v1': false,
      });
      await ChatReadReceiptsPref.hydrate();
      expect(ChatReadReceiptsPref.enabled, isFalse);
    });

    test('hydrate is idempotent', () async {
      SharedPreferences.setMockInitialValues({
        'shamell.chat.read_receipts.v1': false,
      });
      await ChatReadReceiptsPref.hydrate();
      // After hydration the cache should not be re-read from prefs.
      // We simulate that by changing the underlying mock and
      // confirming hydrate doesn't pick up the change.
      SharedPreferences.setMockInitialValues({
        'shamell.chat.read_receipts.v1': true,
      });
      await ChatReadReceiptsPref.hydrate();
      expect(ChatReadReceiptsPref.enabled, isFalse);
    });

    test('setEnabled updates cache + persists', () async {
      await ChatReadReceiptsPref.setEnabled(false);
      expect(ChatReadReceiptsPref.enabled, isFalse);
      // Verify persistence by reading the underlying prefs.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('shamell.chat.read_receipts.v1'), isFalse);
    });

    test('setEnabled cache update is synchronous-feeling', () async {
      // The cache must update BEFORE the disk write completes —
      // otherwise the user could toggle, send a message in the same
      // tick, and have the old value still gating the ack.
      final future = ChatReadReceiptsPref.setEnabled(false);
      // The getter reads `_cached` immediately, no await.
      expect(ChatReadReceiptsPref.enabled, isFalse);
      await future;
      expect(ChatReadReceiptsPref.enabled, isFalse);
    });

    test('toggle round-trip', () async {
      await ChatReadReceiptsPref.setEnabled(false);
      await ChatReadReceiptsPref.setEnabled(true);
      await ChatReadReceiptsPref.setEnabled(false);
      expect(ChatReadReceiptsPref.enabled, isFalse);
    });

    test('resetForTesting clears cache + hydration state', () async {
      await ChatReadReceiptsPref.setEnabled(false);
      expect(ChatReadReceiptsPref.enabled, isFalse);
      ChatReadReceiptsPref.resetForTesting();
      expect(ChatReadReceiptsPref.enabled, isTrue);
      // Hydration state should also reset — a follow-on hydrate call
      // should pick up whatever's currently in the mock prefs.
      SharedPreferences.setMockInitialValues({
        'shamell.chat.read_receipts.v1': false,
      });
      await ChatReadReceiptsPref.hydrate();
      expect(ChatReadReceiptsPref.enabled, isFalse);
    });
  });
}
