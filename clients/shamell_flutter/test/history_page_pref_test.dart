import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/history_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('history filter preferences stay isolated across API origins', () async {
    await saveHistoryFilterPreferences(
      baseUrl: 'https://api.alpha.example',
      dir: 'out',
      kind: 'bill',
      date: 'custom',
      fromDate: DateTime.utc(2026, 3, 1),
      toDate: DateTime.utc(2026, 3, 10),
    );

    final alpha = await loadHistoryFilterPreferences(
      baseUrl: 'https://api.alpha.example',
    );
    expect(alpha.dir, 'out');
    expect(alpha.kind, 'bill');
    expect(alpha.date, 'custom');
    expect(alpha.fromDate, DateTime.utc(2026, 3, 1));
    expect(alpha.toDate, DateTime.utc(2026, 3, 10));

    final betaBefore = await loadHistoryFilterPreferences(
      baseUrl: 'https://api.beta.example',
    );
    expect(betaBefore.dir, 'all');
    expect(betaBefore.kind, 'all');
    expect(betaBefore.date, 'all');
    expect(betaBefore.fromDate, isNull);
    expect(betaBefore.toDate, isNull);

    await saveHistoryFilterPreferences(
      baseUrl: 'https://api.beta.example',
      dir: 'in',
      kind: 'cash',
      date: '7d',
    );

    final beta = await loadHistoryFilterPreferences(
      baseUrl: 'https://api.beta.example',
    );
    expect(beta.dir, 'in');
    expect(beta.kind, 'cash');
    expect(beta.date, '7d');
    expect(beta.fromDate, isNull);
    expect(beta.toDate, isNull);

    final alphaAgain = await loadHistoryFilterPreferences(
      baseUrl: 'https://api.alpha.example',
    );
    expect(alphaAgain.dir, 'out');
    expect(alphaAgain.kind, 'bill');
    expect(alphaAgain.date, 'custom');
    expect(alphaAgain.fromDate, DateTime.utc(2026, 3, 1));
    expect(alphaAgain.toDate, DateTime.utc(2026, 3, 10));
  });

  test('legacy global history filters migrate only in unknown scope', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ph_dir': 'out',
      'ph_kind': 'transfer',
      'ph_date': 'custom',
      'ph_from': '2026-03-01T00:00:00.000Z',
      'ph_to': '2026-03-31T00:00:00.000Z',
    });

    final state = await loadHistoryFilterPreferences(baseUrl: '');
    expect(state.dir, 'out');
    expect(state.kind, 'transfer');
    expect(state.date, 'custom');
    expect(state.fromDate, DateTime.parse('2026-03-01T00:00:00.000Z'));
    expect(state.toDate, DateTime.parse('2026-03-31T00:00:00.000Z'));

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('ph_dir'), isNull);
    expect(sp.getString('ph_kind'), isNull);
    expect(sp.getString('ph_date'), isNull);
    expect(sp.getString('ph_from'), isNull);
    expect(sp.getString('ph_to'), isNull);
    expect(sp.getString('ph_dir.v2.unknown'), 'out');
    expect(sp.getString('ph_kind.v2.unknown'), 'transfer');
    expect(sp.getString('ph_date.v2.unknown'), 'custom');
  });

  test('legacy global history filters do not rebind into canonical origins',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'ph_dir': 'out',
      'ph_kind': 'transfer',
      'ph_date': 'custom',
      'ph_from': '2026-03-01T00:00:00.000Z',
      'ph_to': '2026-03-31T00:00:00.000Z',
    });

    final state = await loadHistoryFilterPreferences(
      baseUrl: 'https://api.example.com',
    );
    expect(state.dir, 'all');
    expect(state.kind, 'all');
    expect(state.date, 'all');
    expect(state.fromDate, isNull);
    expect(state.toDate, isNull);

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('ph_dir'), isNull);
    expect(sp.getString('ph_kind'), isNull);
    expect(sp.getString('ph_date'), isNull);
    expect(sp.getString('ph_from'), isNull);
    expect(sp.getString('ph_to'), isNull);
    expect(sp.getString('ph_dir.v2.https://api.example.com'), isNull);
    expect(sp.getString('ph_kind.v2.https://api.example.com'), isNull);
    expect(sp.getString('ph_date.v2.https://api.example.com'), isNull);
  });
}
