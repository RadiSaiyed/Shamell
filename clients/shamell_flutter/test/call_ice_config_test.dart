import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/call_ice_config.dart';

void main() {
  test('falls back to default STUN when no config is provided', () {
    final servers = shamellCallIceServers(
      rawIceServersJson: '',
      rawStunUrls: '',
      rawTurnUrls: '',
      rawTurnUsername: '',
      rawTurnCredential: '',
    );
    expect(servers, hasLength(1));
    expect(
      servers.first['urls'],
      orderedEquals(const <String>['stun:stun.l.google.com:19302']),
    );
  });

  test('builds stun+turn list from explicit env-style values', () {
    final servers = shamellCallIceServers(
      rawIceServersJson: '',
      rawStunUrls: 'stun:91.107.221.147:3478',
      rawTurnUrls:
          'turn:91.107.221.147:3478?transport=udp,turn:91.107.221.147:3478?transport=tcp',
      rawTurnUsername: 'turn_user',
      rawTurnCredential: 'turn_secret',
    );
    expect(servers, hasLength(2));
    expect(
      servers[0]['urls'],
      orderedEquals(const <String>['stun:91.107.221.147:3478']),
    );
    expect(
      servers[1]['urls'],
      orderedEquals(const <String>[
        'turn:91.107.221.147:3478?transport=udp',
        'turn:91.107.221.147:3478?transport=tcp',
      ]),
    );
    expect(servers[1]['username'], 'turn_user');
    expect(servers[1]['credential'], 'turn_secret');
  });

  test('valid JSON ice list overrides fallback parsing', () {
    final servers = shamellCallIceServers(
      rawIceServersJson:
          '[{"urls":["stun:stun1.example:3478","turn:turn.example:3478?transport=udp"],"username":"u","credential":"p"}]',
      rawStunUrls: 'stun:ignored.example:3478',
      rawTurnUrls: 'turn:ignored.example:3478?transport=udp',
      rawTurnUsername: 'ignored',
      rawTurnCredential: 'ignored',
    );
    expect(servers, hasLength(1));
    expect(
      servers[0]['urls'],
      orderedEquals(const <String>[
        'stun:stun1.example:3478',
        'turn:turn.example:3478?transport=udp',
      ]),
    );
    expect(servers[0]['username'], 'u');
    expect(servers[0]['credential'], 'p');
  });

  test('invalid JSON falls back to explicit stun values', () {
    final servers = shamellCallIceServers(
      rawIceServersJson: '{not valid json}',
      rawStunUrls: 'stun:stun2.example:3478',
      rawTurnUrls: '',
      rawTurnUsername: '',
      rawTurnCredential: '',
    );
    expect(servers, hasLength(1));
    expect(
      servers.first['urls'],
      orderedEquals(const <String>['stun:stun2.example:3478']),
    );
  });
}
