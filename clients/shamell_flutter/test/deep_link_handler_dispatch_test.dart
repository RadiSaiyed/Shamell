import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/deep_link_parsing.dart';

void main() {
  test(
      'dispatchOfficialDeepLink calls unavailable callback and blocks navigation',
      () {
    var unavailableCalls = 0;
    var openAccountCalls = 0;
    var openItemCalls = 0;

    dispatchOfficialDeepLink(
      Uri.parse('shamell://official/shop_123'),
      capabilityEnabled: false,
      onUnavailable: () => unavailableCalls += 1,
      onOpenAccount: (_) => openAccountCalls += 1,
      onOpenItem: (_, __) => openItemCalls += 1,
    );

    expect(unavailableCalls, 1);
    expect(openAccountCalls, 0);
    expect(openItemCalls, 0);
  });

  test('dispatchOfficialDeepLink opens account target when no item is present',
      () {
    var unavailableCalls = 0;
    String? openedAccountId;
    String? openedItemAccountId;
    String? openedItemId;

    dispatchOfficialDeepLink(
      Uri.parse('shamell://official/shop_123'),
      capabilityEnabled: true,
      onUnavailable: () => unavailableCalls += 1,
      onOpenAccount: (accountId) => openedAccountId = accountId,
      onOpenItem: (accountId, itemId) {
        openedItemAccountId = accountId;
        openedItemId = itemId;
      },
    );

    expect(unavailableCalls, 0);
    expect(openedAccountId, 'shop_123');
    expect(openedItemAccountId, isNull);
    expect(openedItemId, isNull);
  });

  test('dispatchOfficialDeepLink opens item target when item is present', () {
    var unavailableCalls = 0;
    String? openedAccountId;
    String? openedItemAccountId;
    String? openedItemId;

    dispatchOfficialDeepLink(
      Uri.parse('shamell://official/shop_123/item_9'),
      capabilityEnabled: true,
      onUnavailable: () => unavailableCalls += 1,
      onOpenAccount: (accountId) => openedAccountId = accountId,
      onOpenItem: (accountId, itemId) {
        openedItemAccountId = accountId;
        openedItemId = itemId;
      },
    );

    expect(unavailableCalls, 0);
    expect(openedAccountId, isNull);
    expect(openedItemAccountId, 'shop_123');
    expect(openedItemId, 'item_9');
  });

  test('dispatchOfficialDeepLink ignores malformed official links', () {
    var unavailableCalls = 0;
    var openAccountCalls = 0;
    var openItemCalls = 0;

    dispatchOfficialDeepLink(
      Uri.parse('shamell://official/'),
      capabilityEnabled: true,
      onUnavailable: () => unavailableCalls += 1,
      onOpenAccount: (_) => openAccountCalls += 1,
      onOpenItem: (_, __) => openItemCalls += 1,
    );

    expect(unavailableCalls, 0);
    expect(openAccountCalls, 0);
    expect(openItemCalls, 0);
  });
}
