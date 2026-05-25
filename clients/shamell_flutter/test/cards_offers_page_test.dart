import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/cards_offers_page.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

void main() {
  const baseUrl = 'http://localhost:8080';
  const sessionToken = 'abcdefabcdefabcdefabcdefabcdef12';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await clearSessionCookie();
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
  });

  tearDown(() async {
    await clearSessionCookie();
  });

  testWidgets('cards offers page lists offers and claims one', (tester) async {
    final requests = <http.Request>[];
    var claimed = false;
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/cards/offers') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'offers': <Object?>[
              <String, Object?>{
                'id': 'cards_welcome_coupon',
                'title_en': 'Welcome coupon',
                'description_en': 'Introductory service coupon.',
                'kind': 'coupon',
                'discount_text': '10% service bonus',
                'official_name': 'Market Official',
                'featured': true,
                'owned': claimed,
                'status': claimed ? 'claimed' : null,
                'claimed_count': claimed ? 10 : 9,
                'redeemed_count': 4,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/cards/offers/cards_welcome_coupon/claim') {
        claimed = true;
        return http.Response(
          jsonEncode(<String, Object?>{
            'offer_id': 'cards_welcome_coupon',
            'owned': true,
            'status': 'claimed',
          }),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CardsOffersPage(baseUrl: baseUrl, httpClient: client),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cards & Offers'), findsOneWidget);
    expect(find.text('Welcome coupon'), findsOneWidget);
    expect(find.text('Market Official · coupon · 10% service bonus'),
        findsOneWidget);
    expect(find.text('Claim'), findsOneWidget);

    await tester.tap(find.text('Claim'));
    await tester.pumpAndSettle();

    expect(find.text('Redeem'), findsOneWidget);
    expect(
      requests.any(
        (request) =>
            request.url.path == '/cards/offers/cards_welcome_coupon/claim' &&
            (request.headers['cookie'] ?? '').contains(sessionToken),
      ),
      isTrue,
    );
  });

  testWidgets('cards offers page forwards contextual filters', (tester) async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/cards/offers') {
        return http.Response(
          jsonEncode(<String, Object?>{'offers': <Object?>[]}),
          200,
        );
      }
      return http.Response('not found', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CardsOffersPage(
          baseUrl: baseUrl,
          httpClient: client,
          officialAccountId: 'official_market',
          miniProgramId: 'cards',
          kind: 'coupon',
          mineOnly: true,
          title: 'Market Cards',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Market Cards'), findsOneWidget);
    expect(find.text('No offers in this section.'), findsOneWidget);
    final offersRequest = requests.singleWhere(
      (request) => request.url.path == '/cards/offers',
    );
    expect(offersRequest.url.queryParameters['official_account_id'],
        'official_market');
    expect(offersRequest.url.queryParameters['mini_program_id'], 'cards');
    expect(offersRequest.url.queryParameters['kind'], 'coupon');
    expect(offersRequest.url.queryParameters['mine'], 'true');
    expect(
        (offersRequest.headers['cookie'] ?? '').contains(sessionToken), isTrue);
  });
}
