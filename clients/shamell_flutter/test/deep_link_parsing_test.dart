import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/deep_link_parsing.dart';

void main() {
  test('parseOfficialDeepLink extracts account and optional item', () {
    final accountOnly = parseOfficialDeepLink(
      Uri.parse('shamell://official/shop_123'),
    );
    expect(accountOnly, isNotNull);
    expect(accountOnly!.accountId, 'shop_123');
    expect(accountOnly.itemId, isNull);

    final withItem = parseOfficialDeepLink(
      Uri.parse('shamell://official/shop_123/item_9'),
    );
    expect(withItem, isNotNull);
    expect(withItem!.accountId, 'shop_123');
    expect(withItem.itemId, 'item_9');
  });

  test('parseOfficialDeepLinkFromText extracts embedded official links', () {
    final target = parseOfficialDeepLinkFromText(
      'New menu today\nshamell://official/shop_123/item_9\n#Lunch',
    );

    expect(target, isNotNull);
    expect(target!.accountId, 'shop_123');
    expect(target.itemId, 'item_9');
    expect(parseOfficialDeepLinkFromText('no official link here'), isNull);
  });

  test('officialTargetFromExplicitOrText preserves matching item links', () {
    final matching = officialTargetFromExplicitOrText(
      explicitAccountId: 'shop_123',
      explicitItemId: '',
      text: 'New menu\nshamell://official/shop_123/item_9',
    );

    expect(matching, isNotNull);
    expect(matching!.accountId, 'shop_123');
    expect(matching.itemId, 'item_9');

    final explicitWins = officialTargetFromExplicitOrText(
      explicitAccountId: 'shop_123',
      explicitItemId: 'item_7',
      text: 'New menu\nshamell://official/shop_123/item_9',
    );
    expect(explicitWins, isNotNull);
    expect(explicitWins!.accountId, 'shop_123');
    expect(explicitWins.itemId, 'item_7');
  });

  test('parseOfficialDeepLink rejects invalid host or empty account id', () {
    expect(
      parseOfficialDeepLink(Uri.parse('https://official/shop_123')),
      isNull,
    );
    expect(
      parseOfficialDeepLink(Uri.parse('shamell://moments/shop_123')),
      isNull,
    );
    expect(parseOfficialDeepLink(Uri.parse('shamell://official')), isNull);
    expect(parseOfficialDeepLink(Uri.parse('shamell://official/')), isNull);
  });

  test('parseOfficialDeepLink rejects malformed identifiers and extra segments',
      () {
    expect(
      parseOfficialDeepLink(Uri.parse('shamell://official/.shop_123')),
      isNull,
    );
    expect(
      parseOfficialDeepLink(Uri.parse('shamell://official/shop_123/item 9')),
      isNull,
    );
    expect(
      parseOfficialDeepLink(Uri.parse('shamell://official/shop_123/item_9/x')),
      isNull,
    );
    final tooLong = 'a' * 65;
    expect(
      parseOfficialDeepLink(Uri.parse('shamell://official/$tooLong')),
      isNull,
    );
  });

  test('parseMiniProgramDeepLink accepts uri and pipe QR payloads', () {
    final uriTarget = parseMiniProgramDeepLink(
      Uri.parse('shamell://mini_program/wallet'),
    );
    expect(uriTarget, isNotNull);
    expect(uriTarget!.id, 'payments');
    expect(uriTarget.resourceId, isNull);

    final pipeTarget = parseMiniProgramPipePayload(
      'MINIPROGRAM|id=green_paket|packet_id=packet_123',
    );
    expect(pipeTarget, isNotNull);
    expect(pipeTarget!.id, 'green_paket');
    expect(pipeTarget.resourceId, 'packet_123');

    final textTarget = parseMiniProgramDeepLinkFromText(
      'Open this app\nMINIPROGRAM|id=coach',
    );
    expect(textTarget, isNotNull);
    expect(textTarget!.id, 'bus');
  });

  test('stripMiniProgramDeepLinksFromText removes uri and pipe payloads', () {
    expect(
      stripMiniProgramDeepLinksFromText(
        'SyrChat Pay\nMINIPROGRAM|id=payments\nready',
      ),
      'SyrChat Pay\nready',
    );
    expect(
      stripMiniProgramDeepLinksFromText(
        'Green Paket\nshamell://green_paket/packet_123',
      ),
      'Green Paket',
    );
  });

  test('stripOfficialDeepLinksFromText removes embedded official links', () {
    expect(
      stripOfficialDeepLinksFromText(
        'New menu\nshamell://official/shop_123/item_9\n#Lunch',
      ),
      'New menu\n#Lunch',
    );
  });

  test('miniProgramTargetFromExplicitOrText preserves matching resource links',
      () {
    final matching = miniProgramTargetFromExplicitOrText(
      explicitId: 'green_paket',
      text: 'Gift\nshamell://green_paket/packet_123',
    );
    expect(matching, isNotNull);
    expect(matching!.id, 'green_paket');
    expect(matching.resourceId, 'packet_123');

    final explicitWins = miniProgramTargetFromExplicitOrText(
      explicitId: 'payments',
      text: 'Gift\nshamell://green_paket/packet_123',
    );
    expect(explicitWins, isNotNull);
    expect(explicitWins!.id, 'payments');
    expect(explicitWins.resourceId, isNull);
  });
}
