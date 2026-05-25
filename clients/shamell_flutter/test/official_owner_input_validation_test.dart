import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/official_owner_input_validation.dart';

void main() {
  test('official owner account id validation accepts 64-hex only', () {
    expect(
      isValidOfficialOwnerAccountId(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      isTrue,
    );
    expect(
      isValidOfficialOwnerAccountId(
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ),
      isTrue,
    );
    expect(isValidOfficialOwnerAccountId('abc123'), isFalse);
    expect(
      isValidOfficialOwnerAccountId(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/',
      ),
      isFalse,
    );
  });

  test('official owner phone validation accepts E.164 only', () {
    expect(isValidOfficialOwnerPhoneE164('+963944444444'), isTrue);
    expect(isValidOfficialOwnerPhoneE164('+11234567890'), isTrue);
    expect(isValidOfficialOwnerPhoneE164('963944444444'), isFalse);
    expect(isValidOfficialOwnerPhoneE164('+0123456789'), isFalse);
    expect(isValidOfficialOwnerPhoneE164('+963 944444444'), isFalse);
  });

  test('official owner account id normalization lowercases and trims', () {
    expect(
      normalizeOfficialOwnerAccountId(
        '  AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA  ',
      ),
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
  });
}
