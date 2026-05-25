import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/chat_message_highlight.dart';

void main() {
  test('flash applies and auto clears the highlight after the duration',
      () async {
    final controller = ChatMessageHighlightController(
      duration: const Duration(milliseconds: 15),
    );
    final changes = <String?>[];

    controller.flash(
      'm1',
      onChanged: changes.add,
    );

    expect(controller.highlightedMessageId, 'm1');
    expect(changes, <String?>['m1']);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(controller.highlightedMessageId, 'm1');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.highlightedMessageId, isNull);
    expect(changes, <String?>['m1', null]);
  });

  test('flash replaces a previous highlight and keeps the newer one', () async {
    final controller = ChatMessageHighlightController(
      duration: const Duration(milliseconds: 15),
    );
    final changes = <String?>[];

    controller.flash(
      'm1',
      onChanged: changes.add,
    );
    await Future<void>.delayed(const Duration(milliseconds: 8));
    controller.flash(
      'm2',
      onChanged: changes.add,
    );

    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(controller.highlightedMessageId, 'm2');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.highlightedMessageId, isNull);
    expect(changes, <String?>['m1', 'm2', null]);
  });

  test('clear cancels the timer and resets the active highlight', () async {
    final controller = ChatMessageHighlightController(
      duration: const Duration(milliseconds: 15),
    );
    final changes = <String?>[];

    controller.flash(
      'm1',
      onChanged: changes.add,
    );
    controller.clear(onChanged: changes.add);

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.highlightedMessageId, isNull);
    expect(changes, <String?>['m1', null]);
  });
}
