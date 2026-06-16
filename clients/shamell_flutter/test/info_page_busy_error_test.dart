import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/chat/shamell_chat_info_page.dart';
import 'package:shamell_flutter/core/l10n.dart';
import 'package:shamell_flutter/core/shamell_group_chat_info_page.dart';

Widget _wrapWithL10n(Widget home) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: L10n.supportedLocales,
    localizationsDelegates: const [
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
}

void main() {
  testWidgets('ShamellChatInfoPage surfaces busy-action failures safely',
      (tester) async {
    await tester.pumpWidget(
      _wrapWithL10n(
        ShamellChatInfoPage(
          myDisplayName: 'Me',
          displayName: 'Alice',
          peerId: 'AB12CD34',
          onCreateGroupChat: () async {},
          onToggleCloseFriend: (_) async => true,
          onToggleMuted: (_) async => throw Exception('boom'),
          onTogglePinned: (_) async {},
          onToggleHidden: (_) async {},
          onToggleBlocked: (_) async {},
          onOpenFavorites: () async {},
          onOpenMedia: () async {},
          onSearchInChat: () async {},
          onSaveRemarksTags: (_, __) async {},
          onSetTheme: (_) async {},
          onClearChatHistory: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mute notifications').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Could not complete action.'), findsOneWidget);
    final mutedSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(mutedSwitch.value, isFalse);
  });

  testWidgets('ShamellGroupChatInfoPage surfaces busy-action failures safely',
      (tester) async {
    await tester.pumpWidget(
      _wrapWithL10n(
        ShamellGroupChatInfoPage(
          groupId: 'group-1',
          groupName: 'Group',
          muted: false,
          pinned: false,
          onToggleMuted: (_) async => throw Exception('boom'),
          onTogglePinned: (_) async {},
          onSetTheme: (_) async {},
          onShowMembers: () async {},
          onInviteMembers: () async {},
          onEditGroup: () async {},
          onShowKeyEvents: () async {},
          onRotateKey: () async {},
          onClearChatHistory: () async {},
          onLeaveGroup: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mute notifications').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Could not complete action.'), findsOneWidget);
    final mutedSwitch = tester.widget<Switch>(find.byType(Switch).first);
    expect(mutedSwitch.value, isFalse);
  });
}
