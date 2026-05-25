import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_page.dart';

void main() {
  test('chat scanned shamell uri guard allows only safe authority shape', () {
    expect(
      shamellChatAllowsScannedCustomSchemeUri(
        Uri.parse(
          'shamell://invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      isTrue,
    );
    expect(
      shamellChatAllowsScannedCustomSchemeUri(
        Uri.parse(
          'SHAMELL://invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      isTrue,
    );

    expect(
      shamellChatAllowsScannedCustomSchemeUri(
        Uri.parse(
          'shamell://user:pass@invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      isFalse,
    );

    expect(
      shamellChatAllowsScannedCustomSchemeUri(
        Uri.parse(
          'shamell://invite:444?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        ),
      ),
      isFalse,
    );

    expect(
      shamellChatAllowsScannedCustomSchemeUri(
        Uri.parse('shamell:/invite?token=aaaaaaaa'),
      ),
      isFalse,
    );

    expect(
      shamellChatAllowsScannedCustomSchemeUri(
        Uri.parse('https://online.shamell.online/app/invite?token=abc'),
      ),
      isFalse,
    );

    expect(
      shamellChatAllowsScannedCustomSchemeUri(
        Uri.parse('shamell://chat?peer=p1'),
      ),
      isFalse,
    );

    expect(
      shamellChatAllowsScannedCustomSchemeUri(
        Uri.parse(
          'shamell://invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa#hidden',
        ),
      ),
      isFalse,
    );
  });

  test('chat scan normalization accepts hosted app-link invite fragments', () {
    final normalized = normalizeShamellChatScannedInboundUri(
      Uri.parse(
        'https://online.shamell.online/app/invite?token=queryToken#token=fragmentToken',
      ),
    );
    expect(
      normalized.toString(),
      'shamell://invite?token=fragmentToken',
    );
    expect(
      shamellChatAllowsScannedCustomSchemeUri(normalized),
      isTrue,
    );
  });

  test('chat scan normalization rejects hosted query-only bearer links', () {
    final invite = normalizeShamellChatScannedInboundUri(
      Uri.parse(
        'https://online.shamell.online/app/invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
    );
    expect(
      invite.toString(),
      'https://online.shamell.online/app/invite?token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    expect(shamellChatAllowsScannedCustomSchemeUri(invite), isFalse);

    final deviceLogin = normalizeShamellChatScannedInboundUri(
      Uri.parse(
          'https://online.shamell.online/app/device_login?token=queryToken'),
    );
    expect(
      deviceLogin.toString(),
      'https://online.shamell.online/app/device_login?token=queryToken',
    );
    expect(shamellChatAllowsScannedCustomSchemeUri(deviceLogin), isFalse);
  });

  test('chat scan normalization keeps unknown hosts non-actionable', () {
    final normalized = normalizeShamellChatScannedInboundUri(
      Uri.parse('https://online.shamell.online/app/chat?peer=p1'),
    );
    expect(normalized.toString(), 'shamell://chat?peer=p1');
    expect(shamellChatAllowsScannedCustomSchemeUri(normalized), isFalse);
  });
}
