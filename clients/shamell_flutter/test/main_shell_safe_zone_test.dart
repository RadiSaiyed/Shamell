import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/main.dart'
    show ShamellGlobalBottomSafeZone, shamellEffectiveTextScaleForLayout;

void main() {
  testWidgets(
      'global bottom safe zone reserves navigation inset without double padding',
      (tester) async {
    const screenSize = Size(390, 844);
    const bottomInset = 34.0;
    const markerKey = Key('bottom-marker');

    await tester.binding.setSurfaceSize(screenSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: screenSize,
            padding: EdgeInsets.only(bottom: bottomInset),
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: ShamellGlobalBottomSafeZone(
            child: const SafeArea(
              top: false,
              child: SizedBox.expand(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    key: markerKey,
                    width: 20,
                    height: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getBottomLeft(find.byKey(markerKey)).dy,
      screenSize.height - bottomInset,
    );
  });

  testWidgets('global bottom safe zone also honors view padding only',
      (tester) async {
    const screenSize = Size(390, 844);
    const bottomInset = 34.0;
    const markerKey = Key('view-padding-bottom-marker');

    await tester.binding.setSurfaceSize(screenSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: screenSize,
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: ShamellGlobalBottomSafeZone(
            child: const SizedBox.expand(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  key: markerKey,
                  width: 20,
                  height: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getBottomLeft(find.byKey(markerKey)).dy,
      screenSize.height - bottomInset,
    );
  });

  test('effective text scale is tighter on phone layouts', () {
    final phone = shamellEffectiveTextScaleForLayout(
      mediaQuery: const MediaQueryData(
        size: Size(390, 844),
        textScaler: TextScaler.linear(1.45),
      ),
      userTextScale: 1,
    );
    final tablet = shamellEffectiveTextScaleForLayout(
      mediaQuery: const MediaQueryData(
        size: Size(768, 1024),
        textScaler: TextScaler.linear(1.45),
      ),
      userTextScale: 1,
    );

    expect(phone, 1.25);
    expect(tablet, 1.45);
  });
}
