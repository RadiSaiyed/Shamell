import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/friends_page.dart';

void main() {
  test('friends invite extraction accepts fragment-only hosted app links', () {
    expect(
      extractInviteTokenFromRaw(
        'https://online.shamell.online/app/invite#token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  });

  test('friends invite extraction rejects query-only hosted app links', () {
    expect(
      extractInviteTokenFromRaw(
        'https://online.shamell.online/app/invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      isEmpty,
    );
  });

  test('friends invite extraction still accepts custom-scheme qr payloads', () {
    expect(
      extractInviteTokenFromRaw(
        'shamell://invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  });
}
