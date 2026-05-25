import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';
import 'package:shamell_flutter/core/superadmin_user_activity_page.dart';

void main() {
  const baseUrl = 'http://localhost:8080';
  const sessionToken = '0123456789abcdef0123456789abcdef';

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await clearSessionCookie();
    await setSessionTokenForBaseUrl(baseUrl, sessionToken);
  });

  tearDown(() async {
    await clearSessionCookie();
  });

  testWidgets('superadmin user activity page lists signups and actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 11400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/admin/platform/features/summary') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'total_events': 3,
            'active_users': 2,
            'mini_program_events': 2,
            'modules': <Object?>[
              <String, Object?>{'module_id': 'mini_programs', 'event_count': 2},
              <String, Object?>{'module_id': 'payments', 'event_count': 1},
            ],
            'features': <Object?>[],
            'mini_programs': <Object?>[],
            'recent_events': <Object?>[],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/overview') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'official_accounts': 2,
            'green_paket_campaigns_active': 1,
            'official_follows': 5,
            'official_template_unread': 1,
            'sticker_packs': 5,
            'sticker_packs_enabled': 5,
            'sticker_items': 14,
            'sticker_installs': 8,
            'sticker_events_30d': 6,
            'card_offers': 3,
            'card_offers_active': 2,
            'cards_claimed': 9,
            'cards_redeemed': 4,
            'cards_events_30d': 5,
            'moments_engagement_events_30d': 4,
            'moments_reports': 1,
            'channels_items': 3,
            'channels_follows': 6,
            'dashboards': <Object?>[
              <String, Object?>{
                'id': 'moments_dashboard',
                'title': 'Moments Dashboard',
                'status': 'connected',
              },
              <String, Object?>{
                'id': 'channels_dashboard',
                'title': 'Channels Dashboard',
                'status': 'connected',
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/official-accounts') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'accounts_total': 4,
              'verified_accounts': 2,
              'featured_accounts': 1,
              'accounts_30d': 1,
              'follows_total': 18,
              'active_followers_30d': 6,
              'feed_items_total': 12,
              'feed_items_30d': 7,
              'template_messages_total': 20,
              'template_unread_total': 3,
              'muted_follows': 2,
              'green_paket_campaigns_total': 3,
              'active_campaigns': 2,
            },
            'top_accounts': <Object?>[
              <String, Object?>{
                'official_account_id': 'official_market',
                'official_name': 'Market Official',
                'kind': 'merchant',
                'category': 'market',
                'verified': true,
                'featured': true,
                'followers': 18,
                'feed_items': 9,
                'active_campaigns': 2,
                'locations': 1,
              },
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'feature_key': 'official_follow',
                'action': 'follow',
                'event_count': 8,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'accounts': 1,
                'feed_items': 2,
                'follows': 5,
                'template_messages': 3,
                'profile_view_events': 11,
                'feed_view_events': 13,
                'follow_events': 5,
                'template_events': 3,
                'notification_events': 1,
                'campaign_admin_events': 2,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/mini-programs') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'programs_total': 8,
              'enabled_programs': 8,
              'published_programs': 6,
              'official_programs': 5,
              'beta_programs': 1,
              'review_queue': 2,
              'versions_total': 11,
              'approved_versions': 7,
              'pending_versions': 2,
              'versions_reviewed_30d': 4,
              'shelf_items': 15,
              'pinned_shelf_items': 4,
              'seen_releases': 10,
              'seen_releases_30d': 3,
              'open_events_30d': 24,
              'review_events_30d': 5,
              'shelf_events_30d': 6,
              'release_seen_events_30d': 3,
            },
            'top_programs': <Object?>[
              <String, Object?>{
                'app_id': 'green_paket',
                'title_en': 'Green Paket',
                'category_en': 'Pay',
                'status': 'published',
                'review_status': 'approved',
                'official': true,
                'enabled': true,
                'beta': false,
                'usage_score': 88,
                'rating': '4.70',
                'rating_count': 88,
                'moments_shares': 12,
                'shelf_users': 13,
                'pinned_users': 4,
                'shelf_opens': 31,
                'versions': 2,
                'pending_versions': 0,
              },
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'mini_program_id': 'green_paket',
                'feature_key': 'mini_program_open',
                'action': 'open',
                'event_count': 12,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'programs': 1,
                'versions': 2,
                'pending_versions': 1,
                'reviewed_versions': 1,
                'shelf_items': 2,
                'pinned_items': 1,
                'seen_releases': 1,
                'open_events': 12,
                'review_events': 2,
                'shelf_events': 2,
                'release_seen_events': 1,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/stickers') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'packs_total': 5,
              'enabled_packs': 5,
              'featured_packs': 3,
              'official_packs': 5,
              'paid_packs': 0,
              'items_total': 14,
              'installs_total': 8,
              'installed_accounts': 4,
              'active_users_30d': 3,
              'usage_count_total': 21,
              'store_events_30d': 6,
              'purchase_events_30d': 2,
              'mini_program_events_30d': 4,
            },
            'top_packs': <Object?>[
              <String, Object?>{
                'pack_id': 'classic_smileys',
                'title_en': 'Classic smileys',
                'official': true,
                'enabled': true,
                'featured': true,
                'price_cents': 0,
                'currency': 'SYP',
                'usage_score': 86,
                'install_count': 5,
                'item_count': 7,
                'install_users': 5,
                'usage_count': 12,
                'active_users_30d': 3,
              },
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'module_id': 'stickers',
                'feature_key': 'sticker_store',
                'action': 'purchase',
                'event_count': 2,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'packs': 1,
                'items': 3,
                'installs': 2,
                'active_users': 3,
                'open_events': 4,
                'purchase_events': 2,
                'use_events': 1,
                'mini_program_events': 4,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/cards') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'offers_total': 3,
              'active_offers': 2,
              'featured_offers': 1,
              'official_offers': 1,
              'expired_offers': 0,
              'claimed_total': 9,
              'claimed_30d': 4,
              'redeemed_total': 4,
              'redeemed_30d': 2,
              'cardholder_accounts': 5,
              'card_events_30d': 5,
              'claim_events_30d': 3,
              'redeem_events_30d': 2,
              'mini_program_events_30d': 1,
            },
            'top_offers': <Object?>[
              <String, Object?>{
                'offer_id': 'cards_welcome_coupon',
                'title_en': 'Welcome coupon',
                'official_name': 'Market Official',
                'kind': 'coupon',
                'discount_text': '10% service bonus',
                'active': true,
                'featured': true,
                'inventory_total': 10000,
                'claimed_count': 9,
                'redeemed_count': 4,
                'holder_count': 5,
                'redeemed_holders': 4,
              },
            ],
            'kinds': <Object?>[
              <String, Object?>{'kind': 'coupon', 'offer_count': 2},
              <String, Object?>{'kind': 'member_card', 'offer_count': 1},
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'module_id': 'cards',
                'feature_key': 'card_offer',
                'action': 'claim',
                'event_count': 3,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'offers': 1,
                'claims': 3,
                'redeems': 2,
                'open_events': 1,
                'claim_events': 3,
                'redeem_events': 2,
                'mini_program_events': 1,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/green-paket') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'campaigns_total': 3,
              'campaigns_active': 2,
              'active_officials': 2,
              'campaigns_30d': 1,
              'campaign_packets_total': 9,
              'campaign_packets_30d': 4,
              'claims_total': 14,
              'claims_30d': 6,
              'amount_cents_total': 9000,
              'claimed_amount_cents_total': 4600,
              'admin_events_30d': 5,
              'mini_program_events_30d': 12,
              'moments_shares_30d': 3,
            },
            'top_campaigns': <Object?>[
              <String, Object?>{
                'id': 'gp_market_default',
                'campaign_id': 'gp_market_default',
                'official_account_id': 'official_market',
                'title': 'Market Green Paket',
                'description': 'Campaign',
                'default_amount_cents': 1000,
                'default_count': 10,
                'active': true,
                'packets_issued': 7,
                'packets_claimed': 11,
                'amount_cents': 7000,
                'claimed_amount_cents': 3300,
                'moments_shares': 4,
                'moments_shares_30d': 3,
              },
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'module_id': 'official_accounts',
                'feature_key': 'green_paket_campaign_admin',
                'action': 'patch',
                'event_count': 5,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'campaigns': 1,
                'packets': 4,
                'amount_cents': 4000,
                'claimed_amount_cents': 1800,
                'claims': 6,
                'moments_shares': 3,
                'admin_events': 5,
                'mini_program_events': 12,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/discover') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'nearby_profiles_total': 8,
              'nearby_visible_profiles': 5,
              'nearby_hidden_profiles': 3,
              'nearby_located_profiles': 4,
              'nearby_profiles_updated_30d': 6,
              'discover_events_30d': 19,
              'global_search_events_30d': 12,
              'nearby_search_events_30d': 7,
              'nearby_profile_events_30d': 3,
            },
            'profile_segments': <Object?>[
              <String, Object?>{'segment': 'visible', 'profile_count': 5},
              <String, Object?>{'segment': 'located', 'profile_count': 4},
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'feature_key': 'global_search',
                'action': 'search',
                'event_count': 12,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'profile_updates': 3,
                'global_search_events': 12,
                'nearby_search_events': 7,
                'nearby_profile_events': 3,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/favorites') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'favorites_total': 10,
              'favorites_updated_30d': 7,
              'saving_accounts': 4,
              'active_saving_accounts_30d': 3,
              'sourced_items': 8,
              'favorites_events_30d': 11,
              'open_events_30d': 5,
              'save_events_30d': 4,
              'delete_events_30d': 2,
            },
            'kinds': <Object?>[
              <String, Object?>{'kind': 'moment', 'item_count': 4},
              <String, Object?>{'kind': 'mini_program', 'item_count': 3},
            ],
            'sources': <Object?>[
              <String, Object?>{'source_module': 'moments', 'item_count': 4},
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'feature_key': 'saved_item',
                'action': 'upsert',
                'event_count': 4,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'created_items': 2,
                'updated_items': 3,
                'open_events': 5,
                'save_events': 4,
                'delete_events': 2,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/chat') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'conversation_prefs_total': 9,
              'group_prefs_total': 6,
              'pinned_conversations': 3,
              'muted_conversations': 2,
              'starred_conversations': 1,
              'pinned_groups': 2,
              'muted_groups': 1,
              'conversation_pref_accounts': 4,
              'group_pref_accounts': 3,
              'conversation_prefs_updated_30d': 5,
              'group_prefs_updated_30d': 4,
              'chat_pref_events_30d': 8,
            },
            'segments': <Object?>[
              <String, Object?>{
                'segment': 'pinned_conversations',
                'item_count': 3,
              },
              <String, Object?>{'segment': 'pinned_groups', 'item_count': 2},
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'feature_key': 'conversation_prefs',
                'action': 'set',
                'event_count': 5,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'conversation_updates': 5,
                'pinned_conversations': 3,
                'muted_conversations': 2,
                'group_updates': 4,
                'pinned_groups': 2,
                'muted_groups': 1,
                'conversation_events': 5,
                'group_events': 3,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/contacts') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'contact_edges_total': 18,
              'active_contact_edges': 15,
              'revoked_contact_edges': 3,
              'contact_edges_30d': 5,
              'active_contact_edges_30d': 4,
              'contact_owner_accounts': 6,
              'contact_peer_devices': 9,
              'invites_total': 7,
              'active_invites': 3,
              'revoked_invites': 1,
              'expired_invites': 2,
              'invite_uses_total': 8,
              'invites_created_30d': 4,
              'invites_redeemed_30d': 2,
              'friend_tags_total': 11,
              'tag_owner_accounts': 4,
              'tagged_friend_pairs': 6,
              'friend_tags_sync_events_30d': 5,
            },
            'tags': <Object?>[
              <String, Object?>{'tag': 'family', 'pair_count': 4},
              <String, Object?>{'tag': 'work', 'pair_count': 2},
            ],
            'segments': <Object?>[
              <String, Object?>{
                'segment': 'active_contacts',
                'item_count': 15,
              },
              <String, Object?>{'segment': 'active_invites', 'item_count': 3},
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'module_id': 'moments',
                'feature_key': 'friend_tags_sync',
                'action': 'sync',
                'event_count': 5,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'contact_edges': 2,
                'active_contact_edges': 2,
                'invites_created': 1,
                'invites_redeemed': 1,
                'tag_updates': 3,
                'friend_tags_events': 5,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/moments') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'posts_total': 8,
              'posts_30d': 6,
              'public_posts': 5,
              'protected_posts': 3,
              'tag_scoped_posts': 2,
              'friends_except_posts': 1,
              'mini_program_posts': 3,
              'mini_program_posts_30d': 2,
              'likes_total': 12,
              'comments_total': 4,
              'reports_total': 1,
              'active_authors_30d': 3,
            },
            'features_30d': <Object?>[
              <String, Object?>{
                'feature_key': 'moments_engagement',
                'action': 'like',
                'event_count': 7,
              },
            ],
            'visibility_breakdown': <Object?>[
              <String, Object?>{
                'visibility_scope': 'public',
                'event_count': 5,
              },
              <String, Object?>{
                'visibility_scope': 'tag',
                'event_count': 2,
              },
              <String, Object?>{
                'visibility_scope': 'friends_except',
                'event_count': 1,
              },
            ],
            'mini_program_embeds': <Object?>[
              <String, Object?>{
                'mini_program_id': 'payments',
                'title_en': 'SyrChat Pay',
                'category_en': 'Wallet',
                'embeds_total': 3,
                'embeds_30d': 2,
                'unique_authors_30d': 2,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'posts': 2,
                'mini_program_posts': 2,
                'engagement_events': 7,
                'privacy_events': 1,
                'safety_events': 0,
                'friend_tags_events': 1,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/admin/dashboards/channels') {
        return http.Response(
          jsonEncode(<String, Object?>{
            'summary': <String, Object?>{
              'items_total': 9,
              'items_30d': 5,
              'live_items': 2,
              'active_officials_30d': 2,
              'follows_total': 14,
              'comments_total': 3,
              'gift_coins_total': 90,
              'views_total': 150,
              'likes_total': 20,
            },
            'top_accounts': <Object?>[
              <String, Object?>{
                'official_account_id': 'official_daily',
                'official_name': 'Daily Official',
                'items': 3,
                'views': 120,
                'likes': 15,
                'gifts': 4,
                'followers': 11,
                'comments': 2,
              },
            ],
            'features_30d': <Object?>[
              <String, Object?>{
                'feature_key': 'channel_view',
                'action': 'view',
                'event_count': 20,
              },
            ],
            'series_30d': <Object?>[
              <String, Object?>{
                'day': '2026-05-05',
                'items': 1,
                'publish_events': 2,
                'view_events': 20,
                'follow_events': 3,
                'engagement_events': 5,
                'live_events': 1,
              },
            ],
          }),
          200,
        );
      }
      final eventType = request.url.queryParameters['event_type'];
      final signup = <String, Object?>{
        'id': 7,
        'account_id': 'a' * 64,
        'shamell_user_id': '1234567890',
        'username': 'alice',
        'event_type': 'signup',
        'action': 'username_password_signup',
        'route': '/auth/signup',
        'metadata': <String, Object?>{'wallet_currency': 'SYP'},
        'created_at': '2026-04-29T10:00:00.000Z',
      };
      final action = <String, Object?>{
        'id': 8,
        'account_id': 'b' * 64,
        'shamell_user_id': '1234567891',
        'username': 'bob',
        'event_type': 'module_open',
        'module_id': 'payments',
        'action': 'open',
        'metadata': <String, Object?>{},
        'created_at': '2026-04-29T10:01:00.000Z',
      };
      final items =
          eventType == 'signup' ? <Object?>[signup] : <Object?>[signup, action];
      return http.Response(jsonEncode(<String, Object?>{'items': items}), 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SuperadminUserActivityPage(
          baseUrl: baseUrl,
          httpClient: client,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final activityRequest = requests
        .firstWhere((request) => request.url.path == '/admin/user-activity');
    expect(activityRequest.headers['cookie'], contains(sessionToken));
    expect(
      requests.any(
        (request) => request.url.path == '/admin/platform/features/summary',
      ),
      isTrue,
    );
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);
    expect(find.text('Signups'), findsWidgets);
    expect(find.text('Actions'), findsWidgets);
    expect(find.text('Platform'), findsOneWidget);
    expect(find.text('Mini programs'), findsWidgets);
    expect(find.text('Official accounts control'), findsOneWidget);
    expect(find.text('Mini programs control'), findsOneWidget);
    expect(find.text('Stickers control'), findsOneWidget);
    expect(find.text('Cards control'), findsOneWidget);
    expect(find.text('Green Paket control'), findsOneWidget);
    expect(find.text('Discover control'), findsOneWidget);
    expect(find.text('Favorites control'), findsOneWidget);
    expect(find.text('Chat control'), findsOneWidget);
    expect(find.text('Contacts control'), findsOneWidget);
    expect(find.text('Moments control'), findsOneWidget);
    expect(find.text('Channels control'), findsOneWidget);
    expect(find.text('SyrChat Pay · 2 embeds · 2 authors'), findsOneWidget);
    expect(find.text('Market Official · 18 follows · 9 posts'), findsOneWidget);
    expect(find.text('Green Paket · 31 opens · 13 users'), findsOneWidget);
    expect(find.text('Classic smileys · 5 installs · 7 items'), findsOneWidget);
    expect(
      find.text('Welcome coupon · 5 holders · 4 redeemed'),
      findsOneWidget,
    );
    expect(
      find.text('Market Green Paket · 7 issued · 11 claimed'),
      findsOneWidget,
    );
    expect(
        find.text('Daily Official · 120 views · 11 follows'), findsOneWidget);
    expect(
      requests.any(
        (request) => request.url.path == '/admin/dashboards/official-accounts',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (request) => request.url.path == '/admin/dashboards/mini-programs',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (request) => request.url.path == '/admin/dashboards/stickers',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (request) => request.url.path == '/admin/dashboards/cards',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (request) => request.url.path == '/admin/dashboards/green-paket',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (request) => request.url.path == '/admin/dashboards/discover',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (request) => request.url.path == '/admin/dashboards/favorites',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (request) => request.url.path == '/admin/dashboards/chat',
      ),
      isTrue,
    );
    expect(
      requests.any(
        (request) => request.url.path == '/admin/dashboards/contacts',
      ),
      isTrue,
    );
    expect(
      requests
          .any((request) => request.url.path == '/admin/dashboards/moments'),
      isTrue,
    );
    expect(
      requests
          .any((request) => request.url.path == '/admin/dashboards/channels'),
      isTrue,
    );

    await tester.tap(find.text('Signups').last);
    await tester.pumpAndSettle();

    expect(requests.last.url.queryParameters['event_type'], 'signup');
    expect(find.text('alice'), findsOneWidget);
  });
}
