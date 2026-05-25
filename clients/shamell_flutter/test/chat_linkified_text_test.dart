import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_linkified_text.dart';

void main() {
  group('normalizeUrlForLaunch', () {
    test('http/https pass through', () {
      expect(ChatLinkifiedText.normalizeUrlForLaunch('https://x.com'),
          'https://x.com');
      expect(ChatLinkifiedText.normalizeUrlForLaunch('http://x.com'),
          'http://x.com');
    });

    test('bare www gets https:// prefix', () {
      expect(ChatLinkifiedText.normalizeUrlForLaunch('www.example.com'),
          'https://www.example.com');
    });

    test('tel: / mailto: pass through', () {
      expect(ChatLinkifiedText.normalizeUrlForLaunch('tel:+12025550100'),
          'tel:+12025550100');
      expect(ChatLinkifiedText.normalizeUrlForLaunch('mailto:foo@bar.com'),
          'mailto:foo@bar.com');
    });
  });

  group('urlRegex', () {
    test('matches http + https URLs', () {
      expect(
        ChatLinkifiedText.urlRegex.firstMatch('see http://example.com here')?.group(0),
        'http://example.com',
      );
      expect(
        ChatLinkifiedText.urlRegex.firstMatch('see HTTPS://Example.COM here')?.group(0),
        'HTTPS://Example.COM',
      );
    });

    test('does not match ftp:// or other schemes', () {
      expect(ChatLinkifiedText.urlRegex.hasMatch('ftp://x'), isFalse);
      expect(ChatLinkifiedText.urlRegex.hasMatch('x@y.com'), isFalse);
    });

    test('matches tel: + mailto: + bare www.', () {
      expect(
        ChatLinkifiedText.urlRegex
            .firstMatch('call tel:+12025550100 today')
            ?.group(0),
        'tel:+12025550100',
      );
      expect(
        ChatLinkifiedText.urlRegex
            .firstMatch('email mailto:foo@bar.com please')
            ?.group(0),
        'mailto:foo@bar.com',
      );
      expect(
        ChatLinkifiedText.urlRegex.firstMatch('go to www.example.com now')?.group(0),
        'www.example.com',
      );
    });

    test('stops at whitespace', () {
      final m = ChatLinkifiedText.urlRegex
          .firstMatch('hello https://a.b/c then more')
          ?.group(0);
      expect(m, 'https://a.b/c');
    });
  });

  group('trimTrailingPunctuation', () {
    test('strips a trailing period', () {
      expect(
        ChatLinkifiedText.trimTrailingPunctuation('https://example.com.'),
        'https://example.com',
      );
    });

    test('strips multiple trailing punctuation chars', () {
      expect(
        ChatLinkifiedText.trimTrailingPunctuation('https://x.com).'),
        'https://x.com',
      );
    });

    test('leaves punctuation INSIDE the URL alone', () {
      expect(
        ChatLinkifiedText.trimTrailingPunctuation('https://en.wikipedia.org/wiki/Cat'),
        'https://en.wikipedia.org/wiki/Cat',
      );
    });
  });

  group('tokenizeMarkdown', () {
    test('plain text -> single plain segment', () {
      expect(
        ChatLinkifiedText.tokenizeMarkdown('hello world'),
        const <ChatTextSegment>[
          ChatTextSegment('hello world', ChatTextStyle.plain),
        ],
      );
    });

    test('bold delimiter -> bold segment', () {
      expect(
        ChatLinkifiedText.tokenizeMarkdown('say **hi** there'),
        const <ChatTextSegment>[
          ChatTextSegment('say ', ChatTextStyle.plain),
          ChatTextSegment('hi', ChatTextStyle.bold),
          ChatTextSegment(' there', ChatTextStyle.plain),
        ],
      );
    });

    test('italic delimiter -> italic segment', () {
      expect(
        ChatLinkifiedText.tokenizeMarkdown('say __hi__ there'),
        const <ChatTextSegment>[
          ChatTextSegment('say ', ChatTextStyle.plain),
          ChatTextSegment('hi', ChatTextStyle.italic),
          ChatTextSegment(' there', ChatTextStyle.plain),
        ],
      );
    });

    test('mono delimiter -> mono segment', () {
      expect(
        ChatLinkifiedText.tokenizeMarkdown('run `cargo test` now'),
        const <ChatTextSegment>[
          ChatTextSegment('run ', ChatTextStyle.plain),
          ChatTextSegment('cargo test', ChatTextStyle.mono),
          ChatTextSegment(' now', ChatTextStyle.plain),
        ],
      );
    });

    test('mixed bold + mono + plain', () {
      expect(
        ChatLinkifiedText.tokenizeMarkdown('the **CLI** uses `grep`'),
        const <ChatTextSegment>[
          ChatTextSegment('the ', ChatTextStyle.plain),
          ChatTextSegment('CLI', ChatTextStyle.bold),
          ChatTextSegment(' uses ', ChatTextStyle.plain),
          ChatTextSegment('grep', ChatTextStyle.mono),
        ],
      );
    });

    test('lonely delimiter stays literal', () {
      // `**` opener with no closer should NOT consume the rest.
      final result = ChatLinkifiedText.tokenizeMarkdown('say **hi');
      // Implementation collapses to plain segments when no closer
      // exists — exact split doesn't matter, only that no bold span
      // was emitted.
      final hasBold = result.any((s) => s.style == ChatTextStyle.bold);
      expect(hasBold, isFalse);
      // The concatenated text matches the input.
      expect(result.map((s) => s.text).join(), 'say **hi');
    });

    test('newline-bounded: bold does not span across lines', () {
      final result =
          ChatLinkifiedText.tokenizeMarkdown('say **hi\n**there**');
      expect(result.any((s) => s.text == 'hi'), isFalse);
      // Should find the `there` bolded since its delimiters are
      // both on the same line.
      expect(result.any((s) => s.style == ChatTextStyle.bold && s.text == 'there'), isTrue);
    });
  });

  group('ChatLinkifiedText rendering', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    }

    testWidgets('no URLs renders plain Text', (tester) async {
      await pump(tester, const ChatLinkifiedText(text: 'no urls here'));
      expect(find.byType(Text), findsOneWidget);
      expect(find.byType(RichText), findsWidgets); // any RichText (Text uses it internally)
    });

    testWidgets('one URL wraps as Text.rich with separate spans',
        (tester) async {
      await pump(
        tester,
        const ChatLinkifiedText(text: 'see https://example.com today'),
      );
      // No plain Text widget directly — Text.rich is used (which builds RichText).
      // We assert the visible text content matches by walking the RichText.
      final rich = tester.widget<RichText>(find.byType(RichText));
      final flat = rich.text.toPlainText();
      expect(flat, 'see https://example.com today');
    });

    testWidgets('tap on URL span fires launchOverride with parsed URI',
        (tester) async {
      Uri? launched;
      await pump(
        tester,
        ChatLinkifiedText(
          text: 'visit https://example.com end',
          launchOverride: (uri) async {
            launched = uri;
            return true;
          },
        ),
      );
      // Find the painted text. We need to compute the offset of the
      // URL substring + tap there.
      await tester.tap(find.textContaining('example.com'));
      await tester.pumpAndSettle();
      expect(launched, isNotNull);
      expect(launched!.scheme, 'https');
      expect(launched!.host, 'example.com');
    });

    testWidgets('trailing punctuation is excluded from the launch URL',
        (tester) async {
      Uri? launched;
      await pump(
        tester,
        ChatLinkifiedText(
          text: 'check https://example.com.',
          launchOverride: (uri) async {
            launched = uri;
            return true;
          },
        ),
      );
      await tester.tap(find.textContaining('example.com'));
      await tester.pumpAndSettle();
      expect(launched, isNotNull);
      // The trailing '.' must NOT be in the host.
      expect(launched!.host, 'example.com');
      // And the URL string itself shouldn't end with a period.
      expect(launched.toString().endsWith('.'), isFalse);
    });
  });
}
