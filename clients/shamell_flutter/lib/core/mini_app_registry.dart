import 'dart:async';

import 'package:flutter/material.dart';

import 'coach_miniprogram_page.dart';
import 'mini_app_contract.dart';
import 'mini_app_descriptor.dart';
import 'mini_apps/hotels_admin_page.dart';
import 'mini_apps/hotels_mini_app_page.dart';
import 'mini_games/mini_game_webview_page.dart';
import 'mini_program_models.dart';
import 'mini_program_runtime.dart';
import 'rides/ride_hailing_page.dart';
import 'superapp_api.dart';

class MiniAppRegistry {
  // Coach/Bus opens as a native mini-program so deep links do not fall back to
  // the older web surface.
  static const List<_MiniAppRegistration> _registrations = [
    _MiniAppRegistration(
      app: _RouteMiniApp(
        id: 'payments',
        modId: 'payments',
        manifestFallback: _paymentsManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'payments',
        icon: Icons.account_balance_wallet_outlined,
        titleEn: 'SyrChat Pay',
        titleAr: 'سرتشات باي',
        categoryEn: 'Wallet & commerce',
        categoryAr: 'المحفظة والتجارة',
        rating: 4.8,
        usageScore: 96,
        runtimeAppId: 'payments',
      ),
    ),
    _MiniAppRegistration(
      app: _RouteMiniApp(
        id: 'green_paket',
        modId: 'green_paket',
        manifestFallback: _greenPaketManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'green_paket',
        icon: Icons.card_giftcard_outlined,
        titleEn: 'Green Paket',
        titleAr: 'الحزمة الخضراء',
        categoryEn: 'Wallet & commerce',
        categoryAr: 'المحفظة والتجارة',
        rating: 4.7,
        usageScore: 88,
        runtimeAppId: 'green_paket',
        momentsShares: 24,
      ),
    ),
    _MiniAppRegistration(
      app: _RouteMiniApp(
        id: 'cards',
        modId: 'cards',
        manifestFallback: _cardsManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'cards',
        icon: Icons.local_offer_outlined,
        titleEn: 'Cards & Offers',
        titleAr: 'البطاقات والعروض',
        categoryEn: 'Wallet & commerce',
        categoryAr: 'المحفظة والتجارة',
        rating: 4.5,
        usageScore: 70,
        runtimeAppId: 'cards',
      ),
    ),
    _MiniAppRegistration(
      app: _RouteMiniApp(
        id: 'moments',
        modId: 'moments',
        manifestFallback: _momentsManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'moments',
        icon: Icons.camera_alt_outlined,
        titleEn: 'Moments',
        titleAr: 'اللحظات',
        categoryEn: 'Social',
        categoryAr: 'اجتماعي',
        rating: 4.7,
        usageScore: 92,
        runtimeAppId: 'moments',
      ),
    ),
    _MiniAppRegistration(
      app: _RouteMiniApp(
        id: 'favorites',
        modId: 'favorites',
        manifestFallback: _favoritesManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'favorites',
        icon: Icons.bookmark_added_outlined,
        titleEn: 'Favorites',
        titleAr: 'المفضلة',
        categoryEn: 'Personal tools',
        categoryAr: 'أدوات شخصية',
        rating: 4.7,
        usageScore: 90,
        runtimeAppId: 'favorites',
      ),
    ),
    _MiniAppRegistration(
      app: _RouteMiniApp(
        id: 'official_accounts',
        modId: 'official_accounts',
        manifestFallback: _officialAccountsManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'official_accounts',
        icon: Icons.verified_outlined,
        titleEn: 'Official Accounts',
        titleAr: 'الحسابات الرسمية',
        categoryEn: 'Services',
        categoryAr: 'الخدمات',
        rating: 4.6,
        usageScore: 84,
        runtimeAppId: 'official_accounts',
      ),
    ),
    _MiniAppRegistration(
      app: _RouteMiniApp(
        id: 'channels',
        modId: 'channels',
        manifestFallback: _channelsManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'channels',
        icon: Icons.play_circle_outline,
        titleEn: 'Channels',
        titleAr: 'القنوات',
        categoryEn: 'Media',
        categoryAr: 'الإعلام',
        rating: 4.5,
        usageScore: 78,
        runtimeAppId: 'channels',
      ),
    ),
    _MiniAppRegistration(
      app: _RouteMiniApp(
        id: 'people_nearby',
        modId: 'people_nearby',
        manifestFallback: _peopleNearbyManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'people_nearby',
        icon: Icons.near_me_outlined,
        titleEn: 'Nearby',
        titleAr: 'القريب مني',
        categoryEn: 'Local',
        categoryAr: 'محلي',
        rating: 4.4,
        usageScore: 68,
        runtimeAppId: 'people_nearby',
      ),
    ),
    // Sticker Store retired from the mini-program registry — the
    // surface had no runtime hookup left and was confusing operators
    // who saw the tile but found the screen empty. Deep-link entries
    // for "stickers" are no-op'd in both chat surfaces.
    _MiniAppRegistration(
      app: _CoachMiniApp(
        id: 'bus',
        manifestFallback: _busManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'bus',
        icon: Icons.directions_bus_filled_outlined,
        titleEn: 'Coach Bus',
        titleAr: 'الحافلات',
        categoryEn: 'Mobility',
        categoryAr: 'التنقل',
        rating: 4.6,
        usageScore: 60,
        runtimeAppId: 'bus',
      ),
    ),
    // Taxi (urban ride-hailing) registered as a Mobility mini-program
    // so the only entry point lives under Mini Programs — the
    // standalone Discover tile was removed alongside Coach Bus.
    _MiniAppRegistration(
      app: _RideMiniApp(
        id: 'ride',
        manifestFallback: _rideManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'ride',
        icon: Icons.local_taxi_outlined,
        titleEn: 'Taxi',
        titleAr: 'تاكسي',
        categoryEn: 'Mobility',
        categoryAr: 'التنقل',
        rating: 4.6,
        usageScore: 58,
        runtimeAppId: 'ride',
      ),
    ),
    // Gaming category — bundled HTML5 mini-games served inside a
    // sandboxed WebView. The Jump-Jump entry is the first member;
    // future games drop into `assets/mini_games/<id>/` and get a
    // sibling `_MiniAppRegistration` below.
    _MiniAppRegistration(
      app: _JumpJumpMiniApp(
        id: 'jump_jump',
        manifestFallback: _jumpJumpManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'jump_jump',
        icon: Icons.sports_esports_outlined,
        titleEn: 'Jump Jump',
        titleAr: 'القفز القفز',
        categoryEn: 'Gaming',
        categoryAr: 'الألعاب',
        rating: 4.5,
        usageScore: 55,
        runtimeAppId: 'jump_jump',
      ),
    ),
    // Three Men's Morris (Drei-Männer-Mühle) — 3x3 board game with
    // two phases (placement + movement) and Minimax AI at three
    // difficulty levels. The canonical id stays `tic_tac_toe` for
    // storage stability (persisted recent-modules state, deep-link
    // legacy aliases) even though the actual game is Morris-style.
    _MiniAppRegistration(
      app: _TicTacToeMiniApp(
        id: 'tic_tac_toe',
        manifestFallback: _ticTacToeManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'tic_tac_toe',
        icon: Icons.grid_3x3_outlined,
        titleEn: "Three Men's Morris",
        titleAr: 'طاحونة الثلاثة',
        categoryEn: 'Gaming',
        categoryAr: 'الألعاب',
        rating: 4.4,
        usageScore: 40,
        runtimeAppId: 'tic_tac_toe',
      ),
    ),
    // Travel & hospitality — generic Hotels mini-app. Currently
    // bundles a single partner (VENEZIA Hotel) and renders entirely
    // from `assets/mini_apps/hotels/`. New hotel partners join by
    // appending to that bundle's `hotels.json`; no Dart change needed.
    _MiniAppRegistration(
      app: _HotelsMiniApp(
        id: 'hotels',
        manifestFallback: _hotelsManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'hotels',
        icon: Icons.hotel_outlined,
        titleEn: 'Hotels',
        titleAr: 'الفنادق',
        categoryEn: 'Travel & hospitality',
        categoryAr: 'السفر والضيافة',
        rating: 4.8,
        usageScore: 64,
        runtimeAppId: 'hotels',
      ),
    ),
    // Hotel-staff admin console — paired surface to the public Hotels
    // mini-app. Reached from the `hotels` manifest via the
    // `open_hotels_admin` action; also registered standalone so deep
    // links work for partner accounts.
    //
    // `operatorOnly: true` keeps this out of the consumer Discover
    // directory and recent-modules chips — a consumer user opening
    // Discover should not even see that an admin surface exists. The
    // runtime still resolves `byId('hotels_admin')` so partner deep
    // links + the manifest `open_hotels_admin` action keep working;
    // the page itself enforces operator-token auth (see
    // `HotelAdminConsolePage._bootstrap` → `HotelsOperatorLoginPage`).
    _MiniAppRegistration(
      app: _HotelsAdminMiniApp(
        id: 'hotels_admin',
        manifestFallback: _hotelsAdminManifest,
      ),
      descriptor: MiniAppDescriptor(
        id: 'hotels_admin',
        icon: Icons.admin_panel_settings_outlined,
        titleEn: 'Hotels Admin',
        titleAr: 'إدارة الفنادق',
        categoryEn: 'Travel & hospitality',
        categoryAr: 'السفر والضيافة',
        rating: 4.6,
        usageScore: 22,
        runtimeAppId: 'hotels_admin',
        operatorOnly: true,
      ),
    ),
  ];

  static MiniApp? byId(String id) {
    final normalized = _normalizeId(id);
    for (final r in _registrations) {
      if (r.app.id == normalized) return r.app;
    }
    return null;
  }

  static List<MiniAppDescriptor> get descriptors =>
      _registrations.map((r) => r.descriptor).toList(growable: false);

  static MiniProgramManifest? localManifestById(String id) =>
      byId(id)?.manifest();

  static String _normalizeId(String id) {
    final clean = id.trim().toLowerCase();
    if (clean == 'coach') return 'bus';
    if (clean == 'taxi' || clean == 'ride_hailing' || clean == 'ridehailing') {
      return 'ride';
    }
    if (clean == 'wallet' || clean == 'pay') return 'payments';
    if (clean == 'saved' || clean == 'saved_items' || clean == 'bookmarks') {
      return 'favorites';
    }
    if (clean == 'redpacket' || clean == 'red_packet' || clean == 'hongbao') {
      return 'green_paket';
    }
    if (clean == 'official' || clean == 'officials') {
      return 'official_accounts';
    }
    if (clean == 'nearby') return 'people_nearby';
    if (clean == 'sticker_store') return 'stickers';
    if (clean == 'hotel' ||
        clean == 'venezia' ||
        clean == 'venezia_hotel' ||
        clean == 'hospitality') {
      return 'hotels';
    }
    // Canonical id stays 'tic_tac_toe' for persisted-state stability.
    // First group: legacy aliases from the original classic Tic-Tac-Toe
    // implementation — still routed for back-compat with saved deep
    // links, even though the actual game is now Three Men's Morris.
    // Second group: aliases for the current game's real names.
    if (clean == 'tictactoe' ||
        clean == 'tic-tac-toe' ||
        clean == 'xo' ||
        clean == 'x_o' ||
        clean == 'noughts_and_crosses' ||
        clean == 'morris' ||
        clean == 'three_mens_morris' ||
        clean == 'three-mens-morris' ||
        clean == 'threemensmorris' ||
        clean == 'drei_maenner_muehle' ||
        clean == 'drei-maenner-muehle' ||
        clean == 'dreimaennermuehle') {
      return 'tic_tac_toe';
    }
    return clean;
  }
}

class _MiniAppRegistration {
  final MiniApp app;
  final MiniAppDescriptor descriptor;

  const _MiniAppRegistration({
    required this.app,
    required this.descriptor,
  });
}

class _RuntimeMiniApp implements MiniApp {
  @override
  final String id;
  final MiniProgramManifest? manifestFallback;

  const _RuntimeMiniApp({
    required this.id,
    this.manifestFallback,
  });

  @override
  MiniProgramManifest? manifest() => manifestFallback;

  @override
  Widget entry(BuildContext context, SuperappAPI api) {
    unawaited(api.recordModuleUse(id));
    return MiniProgramPage(
      id: id,
      baseUrl: api.baseUrl,
      walletId: api.walletId,
      deviceId: api.deviceId,
      onOpenMod: api.openMod,
    );
  }
}

class _CoachMiniApp extends _RuntimeMiniApp {
  const _CoachMiniApp({
    required super.id,
    super.manifestFallback,
  });

  @override
  Widget entry(BuildContext context, SuperappAPI api) {
    unawaited(api.recordModuleUse(id));
    return CoachMiniProgramPage(
      baseUrl: api.baseUrl,
      walletId: api.walletId,
      deviceId: api.deviceId,
    );
  }
}

/// Urban ride-hailing mini-program — hosts [RideHailingPage] inside the
/// Mini Programs runtime. Mirrors [_CoachMiniApp]: opens the same
/// native page the legacy Discover tile used so existing deep links
/// (`ride`, `taxi`) keep landing on the unchanged surface.
class _RideMiniApp extends _RuntimeMiniApp {
  const _RideMiniApp({
    required super.id,
    super.manifestFallback,
  });

  @override
  Widget entry(BuildContext context, SuperappAPI api) {
    unawaited(api.recordModuleUse(id));
    return RideHailingPage(baseUrl: api.baseUrl);
  }
}

/// HTML5 mini-game host for Jump-Jump. Opens [MiniGameWebViewPage]
/// with the `jump_jump` asset bundle. Doesn't need
/// wallet/baseUrl/deviceId since the game runs entirely client-side
/// with no platform bridge.
class _JumpJumpMiniApp extends _RuntimeMiniApp {
  const _JumpJumpMiniApp({
    required super.id,
    super.manifestFallback,
  });

  @override
  Widget entry(BuildContext context, SuperappAPI api) {
    unawaited(api.recordModuleUse(id));
    return const MiniGameWebViewPage(
      gameId: 'jump_jump',
      title: 'Jump Jump',
    );
  }
}

/// HTML5 mini-game host for Three Men's Morris (Drei-Männer-Mühle).
/// Same WebView pattern as Jump-Jump — the game is fully client-side:
/// 2-player pass-and-play and single-player vs Minimax AI (easy /
/// medium / hard, alpha-beta search) both run inside the page. Online
/// play is stubbed in the menu and will land once the chat-transport
/// design is settled (see project notes).
class _TicTacToeMiniApp extends _RuntimeMiniApp {
  const _TicTacToeMiniApp({
    required super.id,
    super.manifestFallback,
  });

  @override
  Widget entry(BuildContext context, SuperappAPI api) {
    unawaited(api.recordModuleUse(id));
    return const MiniGameWebViewPage(
      gameId: 'tic_tac_toe',
      title: "Three Men's Morris",
      appBarColor: Color(0xFF1F2A44),
      backgroundColor: Color(0xFFF7F4EE),
      spinnerColor: Color(0xFF4F8EF7),
    );
  }
}

/// HTML5 mini-app host for the Hotels mini-program. Unlike Jump-Jump
/// (no host bridge), this WebView wires a `ShamellHost` JavaScript
/// channel through to [SuperappAPI.openMod] so the hotel screens can
/// hand off to SyrChat Pay (for bookings + room-service checkout) and
/// the chat mod (for concierge hand-off).
class _HotelsMiniApp extends _RuntimeMiniApp {
  const _HotelsMiniApp({
    required super.id,
    super.manifestFallback,
  });

  @override
  Widget entry(BuildContext context, SuperappAPI api) {
    unawaited(api.recordModuleUse(id));
    return HotelsMiniAppPage(api: api);
  }
}

/// Native Flutter admin surface for hotel partners. Lists bookings +
/// room-service orders and lets staff change status — talks directly
/// to `shamell_hotels_service` over the API base URL exposed via
/// [SuperappAPI]. Today it defaults to the VENEZIA hotel id; a future
/// onboarding flow will let operators pick the partner from a list.
class _HotelsAdminMiniApp extends _RuntimeMiniApp {
  const _HotelsAdminMiniApp({
    required super.id,
    super.manifestFallback,
  });

  @override
  Widget entry(BuildContext context, SuperappAPI api) {
    unawaited(api.recordModuleUse(id));
    return HotelAdminConsolePage(api: api);
  }
}

class _RouteMiniApp extends _RuntimeMiniApp {
  final String modId;

  const _RouteMiniApp({
    required super.id,
    required this.modId,
    super.manifestFallback,
  });

  @override
  Widget entry(BuildContext context, SuperappAPI api) {
    unawaited(api.recordModuleUse(id));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      api.openMod(modId);
    });
    return _MiniAppRedirectSurface(title: manifestFallback?.titleEn ?? id);
  }
}

class _MiniAppRedirectSurface extends StatelessWidget {
  final String title;

  const _MiniAppRedirectSurface({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

const MiniProgramManifest _paymentsManifest = MiniProgramManifest(
  id: 'payments',
  titleEn: 'SyrChat Pay',
  titleAr: 'سرتشات باي',
  descriptionEn: 'Wallet, transfers, QR payments and payment requests.',
  descriptionAr: 'المحفظة والتحويلات والدفع عبر QR وطلبات الدفع.',
  actions: [
    MiniProgramAction(
      id: 'open_payments',
      labelEn: 'Open wallet',
      labelAr: 'فتح المحفظة',
      kind: MiniProgramActionKind.openMod,
      modId: 'payments',
    ),
  ],
);

const MiniProgramManifest _greenPaketManifest = MiniProgramManifest(
  id: 'green_paket',
  titleEn: 'Green Paket',
  titleAr: 'الحزمة الخضراء',
  descriptionEn: 'Send social payment gifts to chats and campaigns.',
  descriptionAr: 'أرسل هدايا دفع اجتماعية في الدردشات والحملات.',
  actions: [
    MiniProgramAction(
      id: 'open_green_paket',
      labelEn: 'Open Green Paket',
      labelAr: 'فتح الحزمة الخضراء',
      kind: MiniProgramActionKind.openMod,
      modId: 'green_paket',
    ),
  ],
);

const MiniProgramManifest _cardsManifest = MiniProgramManifest(
  id: 'cards',
  titleEn: 'Cards & Offers',
  titleAr: 'البطاقات والعروض',
  descriptionEn: 'Coupons, member cards and saved service offers.',
  descriptionAr: 'قسائم وبطاقات عضوية وعروض خدمات محفوظة.',
  actions: [
    MiniProgramAction(
      id: 'open_cards',
      labelEn: 'Open Cards & Offers',
      labelAr: 'فتح البطاقات والعروض',
      kind: MiniProgramActionKind.openMod,
      modId: 'cards',
    ),
  ],
);

const MiniProgramManifest _momentsManifest = MiniProgramManifest(
  id: 'moments',
  titleEn: 'Moments',
  titleAr: 'اللحظات',
  descriptionEn: 'Share updates with friends and official accounts.',
  descriptionAr: 'شارك التحديثات مع الأصدقاء والحسابات الرسمية.',
  actions: [
    MiniProgramAction(
      id: 'open_moments',
      labelEn: 'Open Moments',
      labelAr: 'فتح اللحظات',
      kind: MiniProgramActionKind.openMod,
      modId: 'moments',
    ),
  ],
);

const MiniProgramManifest _favoritesManifest = MiniProgramManifest(
  id: 'favorites',
  titleEn: 'Favorites',
  titleAr: 'المفضلة',
  descriptionEn: 'Saved messages, links, notes and locations.',
  descriptionAr: 'الرسائل والروابط والملاحظات والمواقع المحفوظة.',
  actions: [
    MiniProgramAction(
      id: 'open_favorites',
      labelEn: 'Open Favorites',
      labelAr: 'فتح المفضلة',
      kind: MiniProgramActionKind.openMod,
      modId: 'favorites',
    ),
  ],
);

const MiniProgramManifest _officialAccountsManifest = MiniProgramManifest(
  id: 'official_accounts',
  titleEn: 'Official Accounts',
  titleAr: 'الحسابات الرسمية',
  descriptionEn: 'Follow verified merchants and service accounts.',
  descriptionAr: 'تابع التجار والخدمات الموثقة.',
  actions: [
    MiniProgramAction(
      id: 'open_official_accounts',
      labelEn: 'Open Official Accounts',
      labelAr: 'فتح الحسابات الرسمية',
      kind: MiniProgramActionKind.openMod,
      modId: 'official_accounts',
    ),
  ],
);

const MiniProgramManifest _channelsManifest = MiniProgramManifest(
  id: 'channels',
  titleEn: 'Channels',
  titleAr: 'القنوات',
  descriptionEn: 'Short updates, live clips and merchant campaigns.',
  descriptionAr: 'تحديثات قصيرة وبث مباشر وحملات التجار.',
  actions: [
    MiniProgramAction(
      id: 'open_channels',
      labelEn: 'Open Channels',
      labelAr: 'فتح القنوات',
      kind: MiniProgramActionKind.openMod,
      modId: 'channels',
    ),
  ],
);

const MiniProgramManifest _peopleNearbyManifest = MiniProgramManifest(
  id: 'people_nearby',
  titleEn: 'Nearby',
  titleAr: 'القريب مني',
  descriptionEn:
      'Find nearby restaurants, bars, pharmacies, fuel stations and more.',
  descriptionAr:
      'اعثر على المطاعم والحانات والصيدليات ومحطات الوقود والمزيد بالقرب منك.',
  actions: [
    MiniProgramAction(
      id: 'open_people_nearby',
      labelEn: 'Open Nearby',
      labelAr: 'فتح القريب مني',
      kind: MiniProgramActionKind.openMod,
      modId: 'people_nearby',
    ),
  ],
);

// `_stickersManifest` removed — Sticker Store registration is gone
// (see the registry list above). The deep-link id 'stickers' is now
// no-op'd in chat surfaces; no manifest needs to be served.

const MiniProgramManifest _rideManifest = MiniProgramManifest(
  id: 'ride',
  titleEn: 'SyrChat Taxi',
  titleAr: 'سرتشات تاكسي',
  descriptionEn: 'Hail urban rides inside SyrChat.',
  descriptionAr: 'احجز رحلات حضرية داخل سرتشات.',
  actions: [
    MiniProgramAction(
      id: 'open_ride',
      labelEn: 'Open Taxi',
      labelAr: 'فتح تاكسي',
      kind: MiniProgramActionKind.openMod,
      modId: 'ride',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _busManifest = MiniProgramManifest(
  id: 'bus',
  titleEn: 'SyrChat Coach Bus',
  titleAr: 'سرتشات باص',
  descriptionEn: 'Search and manage intercity coach trips with SyrChat.',
  descriptionAr: 'خطط وأدر رحلات الحافلات بين المدن عبر سرتشات.',
  actions: [
    MiniProgramAction(
      id: 'open_bus',
      labelEn: 'Open Coach',
      labelAr: 'فتح خدمة الحافلات',
      kind: MiniProgramActionKind.openMod,
      modId: 'bus',
    ),
    MiniProgramAction(
      id: 'open_bus_admin',
      labelEn: 'Bus admin',
      labelAr: 'إدارة الحافلات',
      kind: MiniProgramActionKind.openUrl,
      url: '/bus/admin',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

/// Manifest for the **Hotels** mini-app. Mirrors the runtime
/// `assets/mini_apps/hotels/manifest.json` so the directory page can
/// show the description before the WebView has booted. The
/// `view_venezia` action is a partner-specific deep-link example;
/// future partners get their own action ids without code changes (the
/// HTML5 bundle routes by the URL fragment).
const MiniProgramManifest _hotelsManifest = MiniProgramManifest(
  id: 'hotels',
  titleEn: 'Hotels',
  titleAr: 'الفنادق',
  descriptionEn:
      'Browse partner hotels, book rooms, order room-service, and '
      'chat with the concierge — first partner: VENEZIA Hotel.',
  descriptionAr:
      'تصفح الفنادق الشريكة، احجز الغرف، اطلب خدمة الغرف، وتحدث مع '
      'الكونسيرج — الشريك الأول: فندق فينيتسيا.',
  actions: [
    MiniProgramAction(
      id: 'open_hotels',
      labelEn: 'Open Hotels',
      labelAr: 'فتح الفنادق',
      kind: MiniProgramActionKind.openMod,
      modId: 'hotels',
    ),
    MiniProgramAction(
      id: 'open_hotels_admin',
      labelEn: 'Partner admin',
      labelAr: 'إدارة الشريك',
      kind: MiniProgramActionKind.openMod,
      modId: 'hotels_admin',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

/// Manifest for the Hotels admin console. Surfaces booking and
/// room-service queues for hotel staff; reachable as a standalone
/// mini-app or via the `open_hotels_admin` action on the public
/// `hotels` manifest above.
const MiniProgramManifest _hotelsAdminManifest = MiniProgramManifest(
  id: 'hotels_admin',
  titleEn: 'Hotels Admin',
  titleAr: 'إدارة الفنادق',
  descriptionEn:
      'Partner console: review bookings and room-service orders, '
      'update status, and respond to guest requests.',
  descriptionAr:
      'لوحة الشريك: راجع الحجوزات وطلبات خدمة الغرف، حدّث الحالة، '
      'واستجب لطلبات الضيوف.',
  actions: [
    MiniProgramAction(
      id: 'open_hotels_admin',
      labelEn: 'Open admin',
      labelAr: 'فتح الإدارة',
      kind: MiniProgramActionKind.openMod,
      modId: 'hotels_admin',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

/// Manifest for the **Three Men's Morris** (Drei-Männer-Mühle)
/// HTML5 mini-game. Mirrors the `manifest.json` shipped under
/// `assets/mini_games/tic_tac_toe/` (folder name retained for
/// storage/deep-link stability — see registration comment above).
const MiniProgramManifest _ticTacToeManifest = MiniProgramManifest(
  id: 'tic_tac_toe',
  titleEn: "Three Men's Morris",
  titleAr: 'طاحونة الثلاثة',
  descriptionEn:
      "Three Men's Morris: each player places three pieces, then moves "
      'them across the 3×3 board. First to line up three wins. Play '
      'pass-and-play or face the Minimax AI at three difficulty levels.',
  descriptionAr:
      'طاحونة الثلاثة: يضع كل لاعب ثلاث قطع ثم يحرّكها على رقعة 3×3. أول '
      'من يصطف ثلاث قطع في خط واحد يفوز. العب مع صديق على نفس الجهاز أو '
      'واجه الذكاء الاصطناعي بثلاث مستويات صعوبة.',
  actions: [
    MiniProgramAction(
      id: 'open_tic_tac_toe',
      labelEn: "Play Three Men's Morris",
      labelAr: 'العب طاحونة الثلاثة',
      kind: MiniProgramActionKind.openMod,
      modId: 'tic_tac_toe',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

/// Manifest for the **Jump-Jump** HTML5 mini-game. Mirrors the
/// `manifest.json` shipped under `assets/mini_games/jump_jump/` so
/// the directory page can show the description before the WebView
/// has loaded the live manifest from inside the game bundle.
const MiniProgramManifest _jumpJumpManifest = MiniProgramManifest(
  id: 'jump_jump',
  titleEn: 'Jump Jump',
  titleAr: 'القفز القفز',
  descriptionEn:
      'Tap-and-hold mini-game — charge a jump, release to leap, land centered for a combo bonus.',
  descriptionAr:
      'لعبة صغيرة بنقرة مطوّلة — اشحن القفزة، اتركها للقفز، الهبوط في المنتصف يمنحك مكافأة كومبو.',
  actions: [
    MiniProgramAction(
      id: 'open_jump_jump',
      labelEn: 'Play Jump Jump',
      labelAr: 'العب القفز القفز',
      kind: MiniProgramActionKind.openMod,
      modId: 'jump_jump',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);
