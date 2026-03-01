import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/safe_set_state.dart';

class _DelayedSetStateWidget extends StatefulWidget {
  final Duration delay;

  const _DelayedSetStateWidget({required this.delay});

  @override
  State<_DelayedSetStateWidget> createState() => _DelayedSetStateWidgetState();
}

class _DelayedSetStateWidgetState extends State<_DelayedSetStateWidget>
    with SafeSetStateMixin<_DelayedSetStateWidget> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    await Future<void>.delayed(widget.delay);
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Text(_done ? 'done' : 'pending'),
    );
  }
}

void main() {
  testWidgets('SafeSetStateMixin does not raise errors after dispose',
      (tester) async {
    final nonOverflowErrors = <FlutterErrorDetails>[];
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('A RenderFlex overflowed')) {
        return;
      }
      nonOverflowErrors.add(details);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    await tester.pumpWidget(
      const _DelayedSetStateWidget(delay: Duration(milliseconds: 60)),
    );

    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 80));

    expect(nonOverflowErrors, isEmpty);
  });
}
