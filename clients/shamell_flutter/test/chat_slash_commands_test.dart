import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_slash_commands.dart';

void main() {
  group('parseSlashCommand', () {
    test('plain text returns null', () {
      expect(parseSlashCommand('hello world'), isNull);
    });

    test('bare slash returns null', () {
      expect(parseSlashCommand('/'), isNull);
    });

    test('slash followed by non-letter returns null', () {
      expect(parseSlashCommand('/1234'), isNull);
      expect(parseSlashCommand('/-foo'), isNull);
    });

    test('extracts simple command name', () {
      final c = parseSlashCommand('/poll')!;
      expect(c.name, 'poll');
      expect(c.rest, '');
    });

    test('extracts command + args', () {
      final c = parseSlashCommand('/poll Lunch? | Pizza | Sushi')!;
      expect(c.name, 'poll');
      expect(c.rest, 'Lunch? | Pizza | Sushi');
    });

    test('command name is lowercased', () {
      expect(parseSlashCommand('/POLL')!.name, 'poll');
    });

    test('leading whitespace is trimmed', () {
      expect(parseSlashCommand('  /me danced')!.name, 'me');
    });

    test('command names may include digits + underscores', () {
      expect(parseSlashCommand('/poll_2 question')!.name, 'poll_2');
    });
  });

  group('suggestSlashCommands', () {
    test('empty partial returns the full set', () {
      expect(suggestSlashCommands(partial: ''), equals(slashCommands));
    });

    test('prefix filter (`po` matches `poll`)', () {
      final r = suggestSlashCommands(partial: 'po');
      expect(r.length, 1);
      expect(r.first.name, 'poll');
    });

    test('no-match returns empty', () {
      expect(suggestSlashCommands(partial: 'xyz'), isEmpty);
    });
  });

  group('parsePollArgs', () {
    test('empty rest returns null', () {
      expect(parsePollArgs(''), isNull);
      expect(parsePollArgs('   '), isNull);
    });

    test('question only (no options) returns question + empty list', () {
      final r = parsePollArgs('Lunch?')!;
      expect(r.question, 'Lunch?');
      expect(r.options, isEmpty);
    });

    test('question + options', () {
      final r = parsePollArgs('Lunch? | Pizza | Sushi')!;
      expect(r.question, 'Lunch?');
      expect(r.options, <String>['Pizza', 'Sushi']);
    });

    test('trims whitespace + drops empty options', () {
      final r = parsePollArgs('  Q  |  A  |  | B ')!;
      expect(r.question, 'Q');
      expect(r.options, <String>['A', 'B']);
    });
  });

  group('buildMeMessage', () {
    test('formats as * name verb *', () {
      expect(
        buildMeMessage(senderName: 'Alice', rest: 'danced wildly'),
        '* Alice danced wildly *',
      );
    });

    test('empty rest still wraps the name', () {
      expect(buildMeMessage(senderName: 'Alice', rest: ''), '* Alice *');
    });

    test('falls back to "?" when sender is blank', () {
      expect(buildMeMessage(senderName: '   ', rest: 'waved'), '* ? waved *');
    });
  });
}
