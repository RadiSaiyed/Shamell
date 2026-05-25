import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_models.dart' show ChatContact;
import 'package:shamell_flutter/main.dart';

ChatContact _contact(String id, {String? name}) => ChatContact(
      id: id,
      publicKeyB64: 'pk',
      fingerprint: 'fp',
      name: name,
    );

void main() {
  const baseUrl = 'https://api.example';
  const peer = 'dev_caller_001';

  test('returns null when no alias and no contact match', () {
    final out = shamellResolveCallerDisplayName(
      fromDeviceId: peer,
      baseUrl: baseUrl,
    );
    expect(out, isNull);
  });

  test('friend alias wins over contact name', () {
    final out = shamellResolveCallerDisplayName(
      fromDeviceId: peer,
      baseUrl: baseUrl,
      aliases: const {peer: 'Anna (Work)'},
      contacts: [_contact(peer, name: 'Anna Müller')],
    );
    expect(out, 'Anna (Work)');
  });

  test('falls back to contact name when alias absent', () {
    final out = shamellResolveCallerDisplayName(
      fromDeviceId: peer,
      baseUrl: baseUrl,
      contacts: [_contact(peer, name: 'Anna Müller')],
    );
    expect(out, 'Anna Müller');
  });

  test('blank alias treated as absent — falls through to contact name', () {
    final out = shamellResolveCallerDisplayName(
      fromDeviceId: peer,
      baseUrl: baseUrl,
      aliases: const {peer: '   '},
      contacts: [_contact(peer, name: 'Anna Müller')],
    );
    expect(out, 'Anna Müller');
  });

  test('contact match requires id equality after trim', () {
    final out = shamellResolveCallerDisplayName(
      fromDeviceId: '  $peer  ',
      baseUrl: baseUrl,
      contacts: [_contact(peer, name: 'Anna')],
    );
    expect(out, 'Anna');
  });

  test('empty fromDeviceId yields null without scanning', () {
    final out = shamellResolveCallerDisplayName(
      fromDeviceId: '   ',
      baseUrl: baseUrl,
      aliases: const {'   ': 'should-not-match'},
      contacts: [_contact('   ', name: 'should-not-match')],
    );
    expect(out, isNull);
  });

  test('contact with blank/null name is skipped', () {
    final out = shamellResolveCallerDisplayName(
      fromDeviceId: peer,
      baseUrl: baseUrl,
      contacts: [
        _contact(peer, name: '   '),
        _contact(peer, name: 'Anna'),
      ],
    );
    expect(out, 'Anna');
  });
}
