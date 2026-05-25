import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shamell_flutter/core/payments/currency_symbol_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stored currency symbol stays isolated across API origins', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.alpha.example',
    });

    expect(
      await saveStoredCurrencySymbol(
        'USD',
        baseUrl: 'https://api.alpha.example',
      ),
      isTrue,
    );
    expect(
      await loadStoredCurrencySymbol(baseUrl: 'https://api.alpha.example'),
      'USD',
    );
    expect(
      await loadStoredCurrencySymbol(baseUrl: 'https://api.beta.example'),
      isNull,
    );

    expect(
      await saveStoredCurrencySymbol(
        'EUR',
        baseUrl: 'https://api.beta.example',
      ),
      isTrue,
    );
    expect(
      await loadStoredCurrencySymbol(baseUrl: 'https://api.beta.example'),
      'EUR',
    );
    expect(
      await loadStoredCurrencySymbol(baseUrl: 'https://api.alpha.example'),
      'USD',
    );
  });

  test('legacy global currency symbol migrates only in unknown scope',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'currency_symbol': 'USD',
    });

    expect(await loadStoredCurrencySymbol(baseUrl: ''), 'USD');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('currency_symbol'), isNull);
    expect(sp.getString('currency_symbol.v2.unknown'), 'USD');
  });

  test('legacy global currency symbol does not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'base_url': 'https://api.example.com',
      'currency_symbol': 'USD',
    });

    expect(
      await loadStoredCurrencySymbol(baseUrl: 'https://api.example.com'),
      isNull,
    );

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('currency_symbol'), isNull);
    expect(sp.getString('currency_symbol.v2.https://api.example.com'), isNull);
  });
}
