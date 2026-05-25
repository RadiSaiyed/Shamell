import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/main.dart';

void main() {
  test('debug session seed normalizes valid debug payload', () {
    final seed = shamellNormalizeDebugSessionSeed(
      <Object?, Object?>{
        'token': 'ABCDEF0123456789ABCDEF0123456789',
        'base_url': 'https://api.shamell.online/',
      },
      isReleaseMode: false,
    );

    expect(seed, isNotNull);
    expect(seed!['token'], 'abcdef0123456789abcdef0123456789');
    expect(seed['base_url'], 'https://api.shamell.online');
  });

  test('debug session seed rejects invalid payloads in release mode', () {
    final seed = shamellNormalizeDebugSessionSeed(
      <Object?, Object?>{
        'token': 'abcdef0123456789abcdef0123456789',
        'base_url': 'https://api.shamell.online',
      },
      isReleaseMode: true,
    );

    expect(seed, isNull);
  });

  test('debug session seed rejects insecure or malformed inputs', () {
    expect(
      shamellNormalizeDebugSessionSeed(
        <Object?, Object?>{
          'token': 'bad',
          'base_url': 'https://api.shamell.online',
        },
        isReleaseMode: false,
      ),
      isNull,
    );
    expect(
      shamellNormalizeDebugSessionSeed(
        <Object?, Object?>{
          'token': 'abcdef0123456789abcdef0123456789',
          'base_url': 'http://api.shamell.online',
        },
        isReleaseMode: false,
      ),
      isNull,
    );
    expect(
      shamellNormalizeDebugSessionSeed(
        <Object?, Object?>{
          'token': 'abcdef0123456789abcdef0123456789',
          'base_url': 'https://api.shamell.online/path',
        },
        isReleaseMode: false,
      ),
      isNull,
    );
  });

  test('debug chat seed normalizes valid debug payload', () {
    final seed = shamellNormalizeDebugChatSeed(
      <Object?, Object?>{
        'peer_id': 'CWXN6Q2WAFTP7ZNTSCLWXT9P',
        'autosend_text': 'hello from debug',
      },
      isReleaseMode: false,
    );

    expect(seed, isNotNull);
    expect(seed!['peer_id'], 'CWXN6Q2WAFTP7ZNTSCLWXT9P');
    expect(seed['autosend_text'], 'hello from debug');
  });

  test('debug chat seed rejects malformed payloads and release-mode use', () {
    expect(
      shamellNormalizeDebugChatSeed(
        <Object?, Object?>{
          'peer_id': 'bad peer id',
        },
        isReleaseMode: false,
      ),
      isNull,
    );
    expect(
      shamellNormalizeDebugChatSeed(
        <Object?, Object?>{
          'peer_id': 'CWXN6Q2WAFTP7ZNTSCLWXT9P',
        },
        isReleaseMode: true,
      ),
      isNull,
    );
  });
}
