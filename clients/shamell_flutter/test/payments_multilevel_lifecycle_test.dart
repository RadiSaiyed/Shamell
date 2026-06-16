import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shamell_flutter/core/superapp_api.dart';
import 'package:shamell_flutter/mini_apps/payments/payments_multilevel.dart';

class _FakeDelayedApi extends SuperappAPI {
  final Duration delay = const Duration(milliseconds: 60);

  _FakeDelayedApi()
      : super(
          baseUrl: 'https://api.example.com',
          walletId: 'wallet_demo',
          deviceId: 'device_demo',
          openMod: (_) {},
          pushPage: (_) {},
          ensureServiceOfficialFollow: ({
            required String officialId,
            required String chatPeerId,
          }) async {},
          recordModuleUse: (_) async {},
        );

  @override
  Future<Map<String, String>> sessionHeaders({
    bool json = false,
    Map<String, String>? extra,
  }) async {
    return <String, String>{};
  }

  @override
  Future<http.Response> getUri(Uri uri, {Map<String, String>? headers}) async {
    await Future<void>.delayed(delay);
    return http.Response('{"detail":"unavailable"}', 503);
  }
}

void main() {
  testWidgets('PaymentsMultiLevelPage does not throw when disposed mid-load',
      (tester) async {
    final api = _FakeDelayedApi();
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
      MaterialApp(
        home: PaymentsMultiLevelPage(api: api),
      ),
    );

    // Dispose the page while the async load is still in flight.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump(api.delay + const Duration(milliseconds: 40));

    expect(nonOverflowErrors, isEmpty);
  });
}
