import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/home_routes.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
  });

  testWidgets('Finance hub wallet/history tiles dispatch correct callbacks',
      (tester) async {
    int walletTapped = 0;
    int historyTapped = 0;

    final actions = HomeActions(
      onScanPay: () {},
      onTopup: () {},
      onSonic: () {},
      onP2P: () {},
      onChat: () {},
      onVouchers: () {},
      onRequests: () {},
      onBills: () {},
      onWallet: () {
        walletTapped++;
      },
      onHistory: () {
        historyTapped++;
      },
      onRide: () {},
      onOps: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeRouteGrid(
            actions: actions,
            showVouchers: true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Finance & Wallet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Wallet'));
    await tester.pump();
    expect(walletTapped, 1);
    expect(historyTapped, 0);

    await tester.tap(find.text('Wallet history'));
    await tester.pump();
    expect(walletTapped, 1);
    expect(historyTapped, 1);
  });

  testWidgets('Quick-action buttons call the expected handlers',
      (tester) async {
    int scanTapped = 0;
    int p2pTapped = 0;
    int topupTapped = 0;
    int sonicTapped = 0;

    final actions = HomeActions(
      onScanPay: () {
        scanTapped++;
      },
      onTopup: () {
        topupTapped++;
      },
      onSonic: () {
        sonicTapped++;
      },
      onP2P: () {
        p2pTapped++;
      },
      onChat: () {},
      onVouchers: () {},
      onRequests: () {},
      onBills: () {},
      onWallet: () {},
      onHistory: () {},
      onRide: () {},
      onOps: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeRouteGrid(
            actions: actions,
            showSonic: true,
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Scan & pay'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'P2P'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Topup'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Sonic'));
    await tester.pump();

    expect(scanTapped, 1);
    expect(p2pTapped, 1);
    expect(topupTapped, 1);
    expect(sonicTapped, 1);
  });

  testWidgets('unfinished sonic and vouchers actions stay hidden by default',
      (tester) async {
    final actions = HomeActions(
      onScanPay: () {},
      onTopup: () {},
      onSonic: () {},
      onP2P: () {},
      onChat: () {},
      onVouchers: () {},
      onRequests: () {},
      onBills: () {},
      onWallet: () {},
      onHistory: () {},
      onRide: () {},
      onOps: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeRouteGrid(actions: actions),
        ),
      ),
    );

    expect(find.widgetWithText(FilledButton, 'Sonic'), findsNothing);

    await tester.tap(find.text('Finance & Wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Bills'), findsNothing);
    expect(find.text('Vouchers'), findsNothing);
  });

  testWidgets('Mobility tile dispatches ride callback', (tester) async {
    var rideTapped = 0;
    final actions = HomeActions(
      onScanPay: () {},
      onTopup: () {},
      onSonic: () {},
      onP2P: () {},
      onChat: () {},
      onVouchers: () {},
      onRequests: () {},
      onBills: () {},
      onWallet: () {},
      onHistory: () {},
      onRide: () {
        rideTapped++;
      },
      onOps: () {},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeRouteGrid(actions: actions),
        ),
      ),
    );

    await tester.tap(find.text('Mobility'));
    await tester.pump();

    expect(rideTapped, 1);
  });
}
