part of '../main.dart';

const MethodChannel _shamellAndroidSystemChannel = MethodChannel(
  'shamell/android_system',
);

@visibleForTesting
Map<String, String>? shamellNormalizeDebugSessionSeed(
  Map<Object?, Object?>? raw, {
  bool isReleaseMode = kReleaseMode,
}) {
  if (isReleaseMode || raw == null || raw.isEmpty) {
    return null;
  }
  final token = (raw['token'] ?? '').toString().trim().toLowerCase();
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
    return null;
  }
  final base = normalizeSecureApiBaseUrl(
    (raw['base_url'] ?? raw['base'] ?? '').toString().trim(),
  );
  if (base == null || base.isEmpty) {
    return null;
  }
  return <String, String>{'token': token, 'base_url': base};
}

@visibleForTesting
Map<String, String>? shamellNormalizeDebugChatSeed(
  Map<Object?, Object?>? raw, {
  bool isReleaseMode = kReleaseMode,
}) {
  if (isReleaseMode || raw == null || raw.isEmpty) {
    return null;
  }
  final peerId = (raw['peer_id'] ?? raw['peer'] ?? '').toString().trim();
  if (!RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(peerId)) {
    return null;
  }
  final normalized = <String, String>{'peer_id': peerId};
  final autoSendText =
      (raw['autosend_text'] ?? raw['message'] ?? '').toString().trim();
  if (autoSendText.isNotEmpty) {
    normalized['autosend_text'] = autoSendText;
  }
  return normalized;
}

Future<Map<String, String>?> shamellConsumeDebugSessionSeed() async {
  if (kReleaseMode ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }
  try {
    final raw = await _shamellAndroidSystemChannel
        .invokeMapMethod<Object?, Object?>('consume_debug_session_seed');
    return shamellNormalizeDebugSessionSeed(raw);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

const String _debugSkipLoginPassword = 'ShamellDebugSkipLogin-2026';

String _debugSkipLoginUsernameFromDeviceId(String rawDeviceId) {
  final clean = rawDeviceId
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .padRight(20, '0');
  return 'dev${clean.substring(0, 20)}';
}

String _debugSkipLoginFallbackUsername() {
  final millis = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  return 'devlocal$millis';
}

Future<bool> _debugSkipLoginHasSession(String base) async {
  return (await getSessionCookieHeader(base) ?? '').trim().isNotEmpty;
}

Future<bool> _debugSkipLoginRefreshSnapshot({
  required String base,
  http.Client? client,
}) async {
  if (!await _debugSkipLoginHasSession(base)) {
    return false;
  }
  try {
    await refreshAndPersistAccountHomeSnapshot(
      baseUrl: base,
      client: client,
      ensureSession: false,
    );
  } catch (_) {}
  return await _debugSkipLoginHasSession(base);
}

Future<bool> _debugSkipLoginAuthenticateUsername({
  required String base,
  required String username,
  http.Client? client,
}) async {
  try {
    await shamellSignInWithUsernamePassword(
      baseUrl: base,
      username: username,
      password: _debugSkipLoginPassword,
      client: client,
    );
    return await _debugSkipLoginRefreshSnapshot(base: base, client: client);
  } catch (_) {}
  try {
    await shamellSignUpWithUsernamePassword(
      baseUrl: base,
      username: username,
      password: _debugSkipLoginPassword,
      walletCurrency: shamellDefaultWalletCurrency,
      client: client,
    );
    return await _debugSkipLoginRefreshSnapshot(base: base, client: client);
  } catch (e) {
    if (!e.toString().toLowerCase().contains('already taken')) {
      return false;
    }
  }
  try {
    await shamellSignInWithUsernamePassword(
      baseUrl: base,
      username: username,
      password: _debugSkipLoginPassword,
      client: client,
    );
    return await _debugSkipLoginRefreshSnapshot(base: base, client: client);
  } catch (_) {
    return false;
  }
}

Future<bool> shamellEnsureDebugSkipLoginSession({
  required String baseUrl,
  http.Client? client,
}) async {
  if (!_debugSkipLogin || kReleaseMode || kIsWeb) {
    return false;
  }
  final base = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (base == null || base.isEmpty) {
    return false;
  }
  final host = Uri.tryParse(base)?.host.toLowerCase() ?? '';
  if (!isLocalhostHost(host)) {
    return false;
  }
  if (await _debugSkipLoginHasSession(base)) {
    return true;
  }

  final seed = await shamellConsumeDebugSessionSeed();
  final seededToken = (seed?['token'] ?? '').trim();
  if (seededToken.isNotEmpty) {
    await setSessionTokenForBaseUrl(base, seededToken);
    if (await _debugSkipLoginRefreshSnapshot(base: base, client: client)) {
      return true;
    }
  }

  try {
    final deviceId = await getOrCreateStableDeviceId(baseUrlOverride: base);
    final usernames = <String>{
      _debugSkipLoginUsernameFromDeviceId(deviceId),
      _debugSkipLoginFallbackUsername(),
    };
    for (final username in usernames) {
      if (await _debugSkipLoginAuthenticateUsername(
        base: base,
        username: username,
        client: client,
      )) {
        debugPrint('DEBUG_SKIP_LOGIN_SESSION: ready for $base as $username');
        return true;
      }
    }
  } catch (e) {
    debugPrint('DEBUG_SKIP_LOGIN_SESSION: failed for $base: $e');
  }
  return await _debugSkipLoginHasSession(base);
}

Future<Map<String, String>?> shamellConsumeDebugChatSeed() async {
  if (kReleaseMode ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }
  try {
    final raw = await _shamellAndroidSystemChannel
        .invokeMapMethod<Object?, Object?>('consume_debug_chat_seed');
    return shamellNormalizeDebugChatSeed(raw);
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

@visibleForTesting
class ShamellGlobalBottomSafeZone extends StatelessWidget {
  const ShamellGlobalBottomSafeZone({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final rawBottomInset =
        mediaQuery.viewPadding.bottom > mediaQuery.padding.bottom
            ? mediaQuery.viewPadding.bottom
            : mediaQuery.padding.bottom;
    final maxReasonableBottomInset = mediaQuery.size.height * 0.20;
    final useAndroidPhoneFallback = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        mediaQuery.size.shortestSide > 0 &&
        mediaQuery.size.shortestSide < 600;
    final bottomInset = rawBottomInset > maxReasonableBottomInset
        ? (useAndroidPhoneFallback ? 48.0 : 0.0)
        : rawBottomInset <= 0 && useAndroidPhoneFallback
            ? 48.0
            : rawBottomInset;
    if (bottomInset <= 0) {
      return child;
    }
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: MediaQuery(
          data: mediaQuery.copyWith(
            padding: mediaQuery.padding.copyWith(bottom: 0),
          ),
          child: child,
        ),
      ),
    );
  }
}

@visibleForTesting
double shamellEffectiveTextScaleForLayout({
  required MediaQueryData mediaQuery,
  required double userTextScale,
}) {
  final shortestSide = mediaQuery.size.shortestSide;
  final maxScale = shortestSide > 0 && shortestSide < 430 ? 1.25 : 1.45;
  return (mediaQuery.textScaler.scale(1.0) * userTextScale)
      .clamp(0.85, maxScale)
      .toDouble();
}

class SuperApp extends StatelessWidget {
  final ShamellAppSurface appSurface;

  const SuperApp({super.key, this.appSurface = ShamellAppSurface.superapp});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // Debug log to verify HomePage from this repo is running on device.
    assert(() {
      debugPrint(
        'HOME_PAGE_BUILD: ${shamellSurfaceAppTitle(isArabic: false, surface: appSurface)}',
      );
      return true;
    }());
    const shamellGreen = Tokens.primary;
    const shamellLeaf = Tokens.accent;
    const lightScaffold = Tokens.lightScaffold;
    const lightSurface = Tokens.lightSurface;
    const lightOnSurface = Tokens.lightOnSurface;
    const darkScaffold = Tokens.darkScaffold;
    const darkSurface = Tokens.darkSurface;
    const darkOnSurface = Tokens.darkOnSurface;
    final baseBtnShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );

    final lightTextTheme = GoogleFonts.interTextTheme()
        .apply(bodyColor: lightOnSurface, displayColor: lightOnSurface)
        .copyWith(
          titleLarge: GoogleFonts.inter(
            color: lightOnSurface,
            fontSize: 25,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          headlineSmall: GoogleFonts.inter(
            color: lightOnSurface,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        );

    final darkTextTheme = GoogleFonts.interTextTheme(
      ThemeData(brightness: Brightness.dark).textTheme,
    ).apply(bodyColor: darkOnSurface, displayColor: darkOnSurface).copyWith(
          titleLarge: GoogleFonts.inter(
            color: darkOnSurface,
            fontSize: 25,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
          headlineSmall: GoogleFonts.inter(
            color: darkOnSurface,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        );

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: shamellGreen,
        secondary: shamellLeaf,
        surface: lightSurface,
        onSurface: lightOnSurface,
      ),
      scaffoldBackgroundColor: lightScaffold,
      dividerColor: Tokens.lightBorder,
      dividerTheme: const DividerThemeData(
        color: Tokens.lightBorder,
        thickness: 0.7,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: shamellGreen,
        unselectedItemColor: Tokens.lightOnSurfaceSecondary,
        elevation: 0,
      ),
      textTheme: lightTextTheme,
      iconTheme: const IconThemeData(color: lightOnSurface),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: shamellGreen,
          foregroundColor: Colors.white,
          shape: baseBtnShape,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: const WidgetStatePropertyAll(shamellGreen),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(baseBtnShape),
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(
            BorderSide(color: Tokens.lightInputBorder),
          ),
          foregroundColor: const WidgetStatePropertyAll(lightOnSurface),
          backgroundColor: const WidgetStatePropertyAll(Tokens.lightSurface),
          shape: WidgetStatePropertyAll(baseBtnShape),
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Tokens.lightSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Tokens.lightInputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Tokens.lightInputBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: shamellGreen, width: 1.4),
        ),
        labelStyle: const TextStyle(color: Tokens.lightOnSurfaceSecondary),
        hintStyle: const TextStyle(color: Tokens.lightOnSurfaceSecondary),
      ),
      cardTheme: CardThemeData(
        color: Tokens.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Tokens.lightBorder, width: .7),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Tokens.lightSnackSurface.withValues(alpha: .95),
        contentTextStyle: lightTextTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Tokens.lightScaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: lightOnSurface,
        ),
        foregroundColor: lightOnSurface,
        iconTheme: IconThemeData(color: lightOnSurface),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          statusBarColor: Colors.transparent,
        ),
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: shamellLeaf,
        secondary: shamellGreen,
        surface: darkSurface,
        onSurface: darkOnSurface,
      ),
      scaffoldBackgroundColor: darkScaffold,
      dividerColor: Tokens.darkBorder,
      dividerTheme: const DividerThemeData(
        color: Tokens.darkBorder,
        thickness: 0.7,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: shamellLeaf,
        unselectedItemColor: Tokens.darkOnSurfaceSecondary,
        elevation: 0,
      ),
      textTheme: darkTextTheme,
      iconTheme: const IconThemeData(color: darkOnSurface),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: shamellLeaf,
          foregroundColor: Colors.white,
          shape: baseBtnShape,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: const WidgetStatePropertyAll(shamellLeaf),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(baseBtnShape),
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(
            BorderSide(color: Tokens.darkInputBorder),
          ),
          foregroundColor: const WidgetStatePropertyAll(darkOnSurface),
          backgroundColor: const WidgetStatePropertyAll(Tokens.darkSurface),
          shape: WidgetStatePropertyAll(baseBtnShape),
          minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Tokens.darkSurfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Tokens.darkInputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Tokens.darkInputBorder),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: shamellLeaf, width: 1.4),
        ),
        labelStyle: const TextStyle(color: Tokens.darkOnSurfaceSecondary),
        hintStyle: const TextStyle(color: Tokens.darkOnSurfaceSecondary),
      ),
      cardTheme: CardThemeData(
        color: Tokens.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Tokens.darkBorder, width: .7),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Tokens.darkSnackSurface.withValues(alpha: .96),
        contentTextStyle: darkTextTheme.bodyMedium?.copyWith(
          color: darkOnSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Tokens.darkScaffold,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: darkOnSurface,
        ),
        foregroundColor: darkOnSurface,
        iconTheme: IconThemeData(color: darkOnSurface),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
          statusBarColor: Colors.transparent,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([uiLocale, uiTextScale, uiThemeMode]),
      builder: (context, _) {
        return MaterialApp(
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final effectiveScale = shamellEffectiveTextScaleForLayout(
              mediaQuery: mq,
              userTextScale: uiTextScale.value,
            );
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(effectiveScale)),
              child: ShamellGlobalBottomSafeZone(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          title: shamellSurfaceAppTitle(
            isArabic: l.isArabic,
            surface: appSurface,
          ),
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.supportedLocales,
          locale: uiLocale.value,
          localeResolutionCallback: (locale, supported) {
            if (locale != null) {
              for (final l in supported) {
                if (l.languageCode == locale.languageCode) {
                  return l;
                }
              }
            }
            return const Locale('en');
          },
          themeMode: uiThemeMode.value,
          theme: lightTheme,
          darkTheme: darkTheme,
          home: LoginGate(appSurface: appSurface),
        );
      },
    );
  }
}

@visibleForTesting
Widget shamellBuildSignedInHome({
  required ShamellAppSurface appSurface,
  String? baseUrlOverride,
  String? initialRideId,
  String? initialChatPeerId,
  String? initialChatAutoSendText,
  bool runStartupTasks = true,
}) {
  if (shamellIsRideRiderSurface(appSurface)) {
    final normalizedRideId = (initialRideId ?? '').trim();
    return RideHailingPage(
      baseUrl: baseUrlOverride,
      initialRideId: normalizedRideId.isEmpty ? null : normalizedRideId,
      runStartupTasks: runStartupTasks,
      standaloneApp: true,
    );
  }
  if (shamellIsRideDriverSurface(appSurface)) {
    return RideDriverPage(baseUrl: baseUrlOverride);
  }
  if (shamellIsRideOperatorSurface(appSurface)) {
    if (kIsWeb) {
      if (!shamellAllowControlWebSessionBypass(appSurface: appSurface)) {
        return ShamellControlDashboardHubPage(baseUrl: baseUrlOverride ?? '');
      }
      final localhostDashboardOverride =
          shamellBuildLocalhostOperatorDashboardOverride(
        baseUrlOverride: baseUrlOverride,
      );
      if (localhostDashboardOverride != null) {
        return localhostDashboardOverride;
      }
      return ShamellControlDashboardHubPage(baseUrl: baseUrlOverride ?? '');
    }
    return ShamellControlDomainDashboardPage(
      baseUrl: baseUrlOverride ?? '',
      pathSegments: const <String>['admin', 'dashboards', 'rides'],
      title: 'Ride control',
      subtitle:
          'Ride trips, driver supply, dispatch offers, support pressure, payment failures, and live tracking authority.',
      icon: Icons.local_taxi_outlined,
      accent: const Color(0xFF2563EB),
    );
  }
  if (shamellIsTaxiOperatorSurface(appSurface)) {
    // Standalone Taxi Operator app — skip the superapp shell and land
    // straight in the ride-operations console. Same authoritative
    // surface as the legacy 'operator' flavor's mobile branch above,
    // but reachable as its own APK (online.shamell.taxioperator) so
    // taxi-fleet operators don't need to wade through Shamell Control's
    // multi-modal hub.
    return RideOperatorConsolePage(baseUrl: baseUrlOverride);
  }
  if (shamellIsBusOperatorSurface(appSurface)) {
    // Standalone Bus Operator app — same pattern as taxiOperator: land
    // straight in the coach operations console. RoleSignupGuard fronts
    // it with the coach.operator_admin self-service signup form when
    // the caller lacks the role, so a fresh applicant can apply and
    // an admin approves from the operator console's "Bus operators"
    // tab in the Signups workspace.
    return RoleSignupGuard(
      baseUrl: baseUrlOverride ?? '',
      roleId: RoleSignupRoleIds.busOperator,
      roleLabel: 'Bus operator',
      roleLabelArabic: 'مشغّل الحافلات',
      fields: RoleSignupFormFields.busOperator,
      builder: (_) =>
          CoachOperatorConsolePage(baseUrl: baseUrlOverride ?? ''),
    );
  }
  if (shamellIsHotelOperatorSurface(appSurface)) {
    // Standalone Hotel Operator app — Phase 9 bridge. The legacy
    // HotelAdminConsolePage uses its own service-side login flow
    // (hotel_operators table + HMAC bearer-token); platform-account
    // signup goes through the RoleSignupGuard wrap. Once the user has
    // hotels.operator on their platform session, the page renders and
    // can call /v1/hotels/me/grants to discover the hotels they're
    // attached to. Legacy operators (no Shamell session, just the
    // bearer-token flow) still work because HotelAdminConsolePage's
    // own bootstrap handles that path.
    return RoleSignupGuard(
      baseUrl: baseUrlOverride ?? '',
      roleId: RoleSignupRoleIds.hotelOperator,
      roleLabel: 'Hotel operator',
      roleLabelArabic: 'مشغّل الفندق',
      fields: RoleSignupFormFields.hotelOperator,
      builder: (_) => HotelAdminConsolePage(
        api: SuperappAPI.light(baseUrl: baseUrlOverride ?? ''),
      ),
    );
  }
  if (shamellIsCarrierSurface(appSurface)) {
    // Standalone Carrier (Spediteur-Disponent) app — SyrTrans Phase 2
    // scaffold. Lands in a minimal console that probes the freight
    // service health endpoint. Real fleet UI + carrier login flow
    // arrives with the BFF carrier endpoints in Phase 3.
    return CarrierConsolePage(baseUrl: baseUrlOverride);
  }
  if (shamellIsSyrComSurface(appSurface)) {
    return SyrComWorkbenchPage(baseUrl: baseUrlOverride);
  }
  return HomePage(
    lockedMode: AppMode.user,
    runStartupTasks: runStartupTasks,
    baseUrlOverride: baseUrlOverride,
    initialChatPeerId: initialChatPeerId,
    initialChatAutoSendText: initialChatAutoSendText,
  );
}

@visibleForTesting
String? shamellNormalizeLocalhostOperatorDashboardOverride({Uri? currentUri}) {
  final raw = (currentUri ?? Uri.base).queryParameters['dashboard'] ?? '';
  final normalized = raw.trim().toLowerCase().replaceAll('_', '-');
  if (normalized.isEmpty) {
    return null;
  }
  switch (normalized) {
    case 'ops':
    case 'workbench':
    case 'operator-workbench':
    case 'ops-workbench':
      return 'ops';
    case 'admin':
    case 'admin-dashboard':
      return 'admin';
    case 'superadmin':
    case 'superadmin-dashboard':
      return 'superadmin';
    case 'user-activity':
    case 'activity':
    case 'audit':
    case 'user-audit':
      return 'user-activity';
    case 'mini-program-review':
    case 'mini-programs-review':
    case 'mini-programs':
    case 'manifest-review':
      return 'mini-program-review';
    case 'moments':
    case 'moments-dashboard':
      return 'moments';
    case 'official':
    case 'official-accounts':
    case 'official-accounts-dashboard':
      return 'official-accounts';
    case 'discover':
    case 'discover-dashboard':
      return 'discover';
    case 'channels':
    case 'channels-discover':
      return 'channels';
    case 'contacts':
    case 'social-graph':
    case 'friends':
      return 'contacts';
    case 'friend-tags':
    case 'tags':
      return 'friend-tags';
    case 'cards-control':
      return 'cards';
    case 'cards':
    case 'offers':
    case 'cards-offers':
      return 'cards-offers';
    case 'stickers':
    case 'sticker-store':
      return 'stickers';
    case 'favorites':
    case 'saved':
    case 'saved-items':
      return 'favorites';
    case 'chat':
    case 'chat-preferences':
      return 'chat';
    case 'green-paket':
    case 'green-packet':
    case 'greenpaket':
    case 'commerce':
      return 'green-paket';
    case 'control-intelligence':
    case 'intelligence':
    case 'control-score':
      return 'control-intelligence';
    case 'control-inbox':
    case 'inbox':
    case 'action-inbox':
    case 'control-actions':
      return 'control-inbox';
    case 'daily-brief':
    case 'brief':
    case 'control-brief':
    case 'daily-control':
      return 'daily-brief';
    case 'escalations':
    case 'escalation':
    case 'control-escalations':
    case 'escalation-matrix':
      return 'escalations';
    case 'sla-board':
    case 'sla':
    case 'control-sla':
    case 'sla-queue':
      return 'sla-board';
    case 'evidence':
    case 'evidence-board':
    case 'control-evidence':
    case 'proof':
      return 'evidence';
    case 'sync':
    case 'sync-board':
    case 'control-sync':
    case 'freshness':
      return 'sync';
    case 'quality':
    case 'quality-board':
    case 'control-quality':
    case 'readiness-quality':
      return 'quality';
    case 'launch':
    case 'launch-board':
    case 'control-launch':
    case 'rollout':
      return 'launch';
    case 'growth':
    case 'growth-board':
    case 'control-growth':
    case 'growth-loops':
      return 'growth';
    case 'experiments':
    case 'experiment':
    case 'experiment-board':
    case 'control-experiments':
    case 'control-experiment':
      return 'experiments';
    case 'retention':
    case 'retention-board':
    case 'control-retention':
    case 'repeat-use':
    case 'habit-loops':
      return 'retention';
    case 'executive':
    case 'executive-board':
    case 'control-executive':
    case 'control-exec':
    case 'leadership':
      return 'executive';
    case 'risk':
    case 'risk-board':
    case 'control-risk':
    case 'risk-register':
      return 'risk';
    case 'incidents':
    case 'incident':
    case 'incident-board':
    case 'control-incidents':
    case 'incident-response':
      return 'incidents';
    case 'runbooks':
    case 'runbook':
    case 'control-runbooks':
      return 'runbooks';
    case 'owner-workload':
    case 'owners':
    case 'owner-actions':
    case 'control-owners':
      return 'owner-workload';
    case 'analytics':
    case 'analytics-authority':
    case 'platform-features':
    case 'platform-features-summary':
      return 'platform-features';
    case 'payments-credit':
    case 'payments':
    case 'payment':
    case 'pay':
    case 'credit':
    case 'guthaben':
    case 'guthaben-gutschreiben':
    case 'wallet-credit':
      return 'payments-credit';
    case 'ride-operator':
    case 'ride-ops':
    case 'rides':
      return 'ride-operator';
    case 'coach-operator':
    case 'coach-ops':
    case 'coach':
      return 'coach-operator';
    case 'coach-admin':
      return 'coach-admin';
    case 'coach-boarding':
      return 'coach-boarding';
    case 'control':
    case 'control-home':
    case 'home':
      return 'control-home';
  }
  return null;
}

@visibleForTesting
Widget? shamellBuildLocalhostOperatorDashboardOverride({
  required String? baseUrlOverride,
  Uri? currentUri,
}) {
  final dashboard = shamellNormalizeLocalhostOperatorDashboardOverride(
    currentUri: currentUri,
  );
  final baseUrl = baseUrlOverride ?? '';
  switch (dashboard) {
    case 'ops':
      return OpsPage(baseUrl);
    case 'admin':
      return AdminDashboardPage(baseUrl);
    case 'superadmin':
      return SuperadminDashboardPage(baseUrl);
    case 'user-activity':
      return SuperadminUserActivityPage(baseUrl: baseUrl);
    case 'control-intelligence':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'control-intelligence',
        ],
        title: 'Control intelligence',
        subtitle:
            'Operational score, gates, action plan, owner SLAs, and runbook evidence.',
        icon: Icons.psychology_alt_outlined,
        accent: const Color(0xFF334155),
      );
    case 'control-inbox':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'control-inbox',
        ],
        title: 'Control inbox',
        subtitle:
            'Prioritized owner queue with SLA, permissions, runbooks, and next dashboard routes.',
        icon: Icons.inbox_outlined,
        accent: const Color(0xFF0F766E),
      );
    case 'daily-brief':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'daily-brief',
        ],
        title: 'Daily brief',
        subtitle:
            "Today's Control posture, lead action, owner focus, gates, readiness, and native adoption.",
        icon: Icons.today_outlined,
        accent: const Color(0xFF334155),
      );
    case 'escalations':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'escalations',
        ],
        title: 'Escalations',
        subtitle:
            'High and medium Control signals with owner SLA, required permission, runbook, and target board.',
        icon: Icons.report_gmailerrorred_outlined,
        accent: const Color(0xFFDC2626),
      );
    case 'sla-board':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'sla-board',
        ],
        title: 'SLA board',
        subtitle:
            'Control actions grouped by due now, today, this week, and later watch buckets.',
        icon: Icons.timer_outlined,
        accent: const Color(0xFFC2410C),
      );
    case 'evidence':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'evidence',
        ],
        title: 'Evidence board',
        subtitle:
            'Runbook evidence, done-when criteria, first steps, escalation paths, and owner proof.',
        icon: Icons.fact_check_outlined,
        accent: const Color(0xFF2563EB),
      );
    case 'sync':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'sync',
        ],
        title: 'Sync board',
        subtitle:
            'Data freshness, source authority, native route coverage, and cross-surface sync health.',
        icon: Icons.sync_alt_outlined,
        accent: const Color(0xFF0F766E),
      );
    case 'quality':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'quality',
        ],
        title: 'Quality board',
        subtitle:
            'Surface readiness, operating gates, sync health, owners, and production-quality score.',
        icon: Icons.verified_outlined,
        accent: const Color(0xFF334155),
      );
    case 'launch':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'launch',
        ],
        title: 'Launch board',
        subtitle:
            'Rollout decisions for scale, limited rollout, pilots, and held WeChat surfaces.',
        icon: Icons.rocket_launch_outlined,
        accent: const Color(0xFF7C3AED),
      );
    case 'growth':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'growth',
        ],
        title: 'Growth board',
        subtitle:
            'Growth loops, adoption signals, experiments, instrumentation, and blocked surface follow-up.',
        icon: Icons.trending_up_outlined,
        accent: const Color(0xFF16A34A),
      );
    case 'experiments':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'experiments',
        ],
        title: 'Experiment board',
        subtitle:
            'Experiment hypotheses, primary metrics, success criteria, owners, and blocked growth follow-up.',
        icon: Icons.science_outlined,
        accent: const Color(0xFF0891B2),
      );
    case 'retention':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'retention',
        ],
        title: 'Retention board',
        subtitle:
            'Repeat-use loops, retention score, cohort proof, measurement gaps, owners, and next moves.',
        icon: Icons.repeat_outlined,
        accent: const Color(0xFF0F766E),
      );
    case 'executive':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'executive',
        ],
        title: 'Executive board',
        subtitle:
            'Top-level Control posture, attention, quality, rollout, growth, experiments, retention, and owner execution.',
        icon: Icons.space_dashboard_outlined,
        accent: const Color(0xFF334155),
      );
    case 'risk':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'risk',
        ],
        title: 'Risk board',
        subtitle:
            'Critical risks, mitigations, risk scores, owners, review cadence, and target control boards.',
        icon: Icons.shield_outlined,
        accent: const Color(0xFFDC2626),
      );
    case 'incidents':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'incidents',
        ],
        title: 'Incident board',
        subtitle:
            'Active incidents, commanders, containment, response SLAs, rollback gates, comms, and target boards.',
        icon: Icons.crisis_alert_outlined,
        accent: const Color(0xFFC2410C),
      );
    case 'runbooks':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'runbooks'],
        title: 'Control runbooks',
        subtitle:
            'Owner playbooks, evidence, done-when criteria, and escalation paths.',
        icon: Icons.rule_folder_outlined,
        accent: const Color(0xFF0F766E),
      );
    case 'owner-workload':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'owner-workload',
        ],
        title: 'Owner workload',
        subtitle:
            'Team ownership, action pressure, SLAs, permissions, and next owner boards.',
        icon: Icons.assignment_ind_outlined,
        accent: const Color(0xFF2563EB),
      );
    case 'mini-program-review':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'mini-programs'],
        title: 'Mini-program review',
        subtitle:
            'Mini Program registry, manifest authority, review queue, releases, shelf usage, and event quality.',
        icon: Icons.apps_outlined,
        accent: const Color(0xFF0F766E),
      );
    case 'moments':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'moments'],
        title: 'Moments control',
        subtitle:
            'Moments feed health, privacy scopes, reports, comments, likes, Mini Program embeds, and friend-tag sync.',
        icon: Icons.dynamic_feed_outlined,
        accent: const Color(0xFF16A34A),
      );
    case 'official-accounts':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'dashboards',
          'official-accounts',
        ],
        title: 'Official Accounts control',
        subtitle:
            'Official Account profile quality, follows, feed depth, template messages, notification modes, and Green Paket linkage.',
        icon: Icons.verified_outlined,
        accent: const Color(0xFF2563EB),
      );
    case 'channels':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'channels'],
        title: 'Channels control',
        subtitle:
            'Channels content, live depth, views, follows, engagement, creator quality, and discovery telemetry.',
        icon: Icons.play_circle_outline_rounded,
        accent: const Color(0xFFE11D48),
      );
    case 'discover':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'discover'],
        title: 'Discover control',
        subtitle:
            'Search, People Nearby, profile freshness, and discovery telemetry.',
        icon: Icons.explore_outlined,
        accent: const Color(0xFF2563EB),
      );
    case 'contacts':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'contacts'],
        title: 'Contacts control',
        subtitle:
            'Contacts graph quality, invitations, active edges, revocations, friend tags, and Moments privacy sync.',
        icon: Icons.groups_outlined,
        accent: const Color(0xFF0F766E),
      );
    case 'friend-tags':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'contacts'],
        title: 'Contacts control',
        subtitle:
            'Contacts graph quality, invitations, active edges, revocations, friend tags, and Moments privacy sync.',
        icon: Icons.groups_outlined,
        accent: const Color(0xFF0F766E),
      );
    case 'cards':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'cards'],
        title: 'Cards and offers control',
        subtitle:
            'Member cards, offer inventory, claims, redemptions, and commerce telemetry.',
        icon: Icons.style_outlined,
        accent: Tokens.colorPayments,
      );
    case 'cards-offers':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'cards'],
        title: 'Cards and offers control',
        subtitle:
            'Member cards, offer inventory, claims, redemptions, and commerce telemetry.',
        icon: Icons.style_outlined,
        accent: Tokens.colorPayments,
      );
    case 'stickers':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'stickers'],
        title: 'Sticker store control',
        subtitle:
            'Sticker inventory, official packs, chat usage, and Mini Program telemetry.',
        icon: Icons.emoji_emotions_outlined,
        accent: const Color(0xFF7C3AED),
      );
    case 'favorites':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'favorites'],
        title: 'Favorites control',
        subtitle:
            'Saved items, source modules, active accounts, and mutation telemetry.',
        icon: Icons.bookmark_border_rounded,
        accent: const Color(0xFF0F766E),
      );
    case 'chat':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'chat'],
        title: 'Chat preferences control',
        subtitle:
            'Pinned, muted, starred, group preferences, and chat telemetry.',
        icon: Icons.chat_bubble_outline_rounded,
        accent: const Color(0xFF334155),
      );
    case 'green-paket':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'green-paket'],
        title: 'Green Paket control',
        subtitle:
            'Campaigns, commerce surfaces, Moments sharing, and owner activity.',
        icon: Icons.redeem_outlined,
        accent: Tokens.colorPayments,
      );
    case 'platform-features':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>[
          'admin',
          'platform',
          'features',
          'summary',
        ],
        title: 'Analytics authority',
        subtitle:
            'Trusted platform events, source authority, and feature telemetry.',
        icon: Icons.query_stats_outlined,
        accent: const Color(0xFF334155),
      );
    case 'payments-credit':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'payments'],
        title: 'Payments control',
        subtitle:
            'Wallet authority, send safety, attestation hygiene, active challenges, and trusted payment telemetry.',
        icon: Icons.account_balance_wallet_outlined,
        accent: Tokens.colorPayments,
      );
    case 'ride-operator':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'rides'],
        title: 'Ride control',
        subtitle:
            'Ride trips, driver supply, dispatch offers, support pressure, payment failures, and live tracking authority.',
        icon: Icons.local_taxi_outlined,
        accent: const Color(0xFF2563EB),
      );
    case 'coach-operator':
    case 'coach-admin':
    case 'coach-boarding':
      return ShamellControlDomainDashboardPage(
        baseUrl: baseUrl,
        pathSegments: const <String>['admin', 'dashboards', 'coach'],
        title: 'Coach control',
        subtitle:
            'Coach bookings, tickets, boarding scans, feed health, refunds, and operator authority in one control board.',
        icon: Icons.directions_bus_outlined,
        accent: const Color(0xFF0F766E),
      );
    case 'control-home':
      return ShamellControlDashboardHubPage(baseUrl: baseUrl);
  }
  return null;
}

class ShamellControlDashboardHubPage extends StatelessWidget {
  final String baseUrl;

  const ShamellControlDashboardHubPage({super.key, required this.baseUrl});

  List<_ControlDashboardHubEntry> _entries() {
    return <_ControlDashboardHubEntry>[
      _ControlDashboardHubEntry(
        title: 'Ops',
        description: 'Live operations workbench and frontline queues.',
        icon: Icons.layers_outlined,
        color: const Color(0xFF0F766E),
        builder: (_) => OpsPage(baseUrl),
      ),
      _ControlDashboardHubEntry(
        title: 'Admin',
        description: 'Platform admin overview, exports, and web controls.',
        icon: Icons.admin_panel_settings_outlined,
        color: const Color(0xFF334155),
        builder: (_) => AdminDashboardPage(baseUrl),
      ),
      _ControlDashboardHubEntry(
        title: 'Superadmin',
        description: 'Access provisioning, finance review, and owner tools.',
        icon: Icons.verified_user_outlined,
        color: const Color(0xFF7C3AED),
        builder: (_) => SuperadminDashboardPage(baseUrl),
      ),
      _ControlDashboardHubEntry(
        title: 'User activity',
        description: 'Username signups and per-account app action audit.',
        icon: Icons.manage_search_outlined,
        color: const Color(0xFF2563EB),
        builder: (_) => SuperadminUserActivityPage(baseUrl: baseUrl),
      ),
      _ControlDashboardHubEntry(
        title: 'Control runbooks',
        description:
            'Owner playbooks, evidence, done-when criteria, and escalation paths.',
        icon: Icons.rule_folder_outlined,
        color: const Color(0xFF0F766E),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'runbooks'],
          title: 'Control runbooks',
          subtitle:
              'Owner playbooks, evidence, done-when criteria, and escalation paths.',
          icon: Icons.rule_folder_outlined,
          accent: const Color(0xFF0F766E),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Control intelligence',
        description:
            'Operational score, gates, action plan, owner SLAs, and runbook evidence.',
        icon: Icons.psychology_alt_outlined,
        color: const Color(0xFF334155),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'control-intelligence',
          ],
          title: 'Control intelligence',
          subtitle:
              'Operational score, gates, action plan, owner SLAs, and runbook evidence.',
          icon: Icons.psychology_alt_outlined,
          accent: const Color(0xFF334155),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Daily brief',
        description:
            "Today's Control posture, lead action, owner focus, gates, readiness, and native adoption.",
        icon: Icons.today_outlined,
        color: const Color(0xFF334155),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'daily-brief',
          ],
          title: 'Daily brief',
          subtitle:
              "Today's Control posture, lead action, owner focus, gates, readiness, and native adoption.",
          icon: Icons.today_outlined,
          accent: const Color(0xFF334155),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Control inbox',
        description:
            'Prioritized owner queue with SLA, permissions, runbooks, and next dashboard routes.',
        icon: Icons.inbox_outlined,
        color: const Color(0xFF0F766E),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'control-inbox',
          ],
          title: 'Control inbox',
          subtitle:
              'Prioritized owner queue with SLA, permissions, runbooks, and next dashboard routes.',
          icon: Icons.inbox_outlined,
          accent: const Color(0xFF0F766E),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Escalations',
        description:
            'High and medium Control signals with owner SLA, required permission, runbook, and target board.',
        icon: Icons.report_gmailerrorred_outlined,
        color: const Color(0xFFDC2626),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'escalations',
          ],
          title: 'Escalations',
          subtitle:
              'High and medium Control signals with owner SLA, required permission, runbook, and target board.',
          icon: Icons.report_gmailerrorred_outlined,
          accent: const Color(0xFFDC2626),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'SLA board',
        description:
            'Control actions grouped by due now, today, this week, and later watch buckets.',
        icon: Icons.timer_outlined,
        color: const Color(0xFFC2410C),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'sla-board',
          ],
          title: 'SLA board',
          subtitle:
              'Control actions grouped by due now, today, this week, and later watch buckets.',
          icon: Icons.timer_outlined,
          accent: const Color(0xFFC2410C),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Evidence board',
        description:
            'Runbook evidence, done-when criteria, first steps, escalation paths, and owner proof.',
        icon: Icons.fact_check_outlined,
        color: const Color(0xFF2563EB),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'evidence',
          ],
          title: 'Evidence board',
          subtitle:
              'Runbook evidence, done-when criteria, first steps, escalation paths, and owner proof.',
          icon: Icons.fact_check_outlined,
          accent: const Color(0xFF2563EB),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Sync board',
        description:
            'Data freshness, source authority, native route coverage, and cross-surface sync health.',
        icon: Icons.sync_alt_outlined,
        color: const Color(0xFF0F766E),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'sync',
          ],
          title: 'Sync board',
          subtitle:
              'Data freshness, source authority, native route coverage, and cross-surface sync health.',
          icon: Icons.sync_alt_outlined,
          accent: const Color(0xFF0F766E),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Quality board',
        description:
            'Surface readiness, operating gates, sync health, owners, and production-quality score.',
        icon: Icons.verified_outlined,
        color: const Color(0xFF334155),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'quality',
          ],
          title: 'Quality board',
          subtitle:
              'Surface readiness, operating gates, sync health, owners, and production-quality score.',
          icon: Icons.verified_outlined,
          accent: const Color(0xFF334155),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Launch board',
        description:
            'Rollout decisions for scale, limited rollout, pilots, and held WeChat surfaces.',
        icon: Icons.rocket_launch_outlined,
        color: const Color(0xFF7C3AED),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'launch',
          ],
          title: 'Launch board',
          subtitle:
              'Rollout decisions for scale, limited rollout, pilots, and held WeChat surfaces.',
          icon: Icons.rocket_launch_outlined,
          accent: const Color(0xFF7C3AED),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Growth board',
        description:
            'Growth loops, adoption signals, experiments, instrumentation, and blocked surface follow-up.',
        icon: Icons.trending_up_outlined,
        color: const Color(0xFF16A34A),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'growth',
          ],
          title: 'Growth board',
          subtitle:
              'Growth loops, adoption signals, experiments, instrumentation, and blocked surface follow-up.',
          icon: Icons.trending_up_outlined,
          accent: const Color(0xFF16A34A),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Experiment board',
        description:
            'Experiment hypotheses, primary metrics, success criteria, owners, and blocked growth follow-up.',
        icon: Icons.science_outlined,
        color: const Color(0xFF0891B2),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'experiments',
          ],
          title: 'Experiment board',
          subtitle:
              'Experiment hypotheses, primary metrics, success criteria, owners, and blocked growth follow-up.',
          icon: Icons.science_outlined,
          accent: const Color(0xFF0891B2),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Retention board',
        description:
            'Repeat-use loops, retention score, cohort proof, measurement gaps, owners, and next moves.',
        icon: Icons.repeat_outlined,
        color: const Color(0xFF0F766E),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'retention',
          ],
          title: 'Retention board',
          subtitle:
              'Repeat-use loops, retention score, cohort proof, measurement gaps, owners, and next moves.',
          icon: Icons.repeat_outlined,
          accent: const Color(0xFF0F766E),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Executive board',
        description:
            'Top-level Control posture, attention, quality, rollout, growth, experiments, retention, and owner execution.',
        icon: Icons.space_dashboard_outlined,
        color: const Color(0xFF334155),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'executive',
          ],
          title: 'Executive board',
          subtitle:
              'Top-level Control posture, attention, quality, rollout, growth, experiments, retention, and owner execution.',
          icon: Icons.space_dashboard_outlined,
          accent: const Color(0xFF334155),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Risk board',
        description:
            'Critical risks, mitigations, risk scores, owners, review cadence, and target control boards.',
        icon: Icons.shield_outlined,
        color: const Color(0xFFDC2626),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'risk',
          ],
          title: 'Risk board',
          subtitle:
              'Critical risks, mitigations, risk scores, owners, review cadence, and target control boards.',
          icon: Icons.shield_outlined,
          accent: const Color(0xFFDC2626),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Incident board',
        description:
            'Active incidents, commanders, containment, response SLAs, rollback gates, comms, and target boards.',
        icon: Icons.crisis_alert_outlined,
        color: const Color(0xFFC2410C),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'incidents',
          ],
          title: 'Incident board',
          subtitle:
              'Active incidents, commanders, containment, response SLAs, rollback gates, comms, and target boards.',
          icon: Icons.crisis_alert_outlined,
          accent: const Color(0xFFC2410C),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Owner workload',
        description:
            'Team ownership, action pressure, SLAs, permissions, and next owner boards.',
        icon: Icons.assignment_ind_outlined,
        color: const Color(0xFF2563EB),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'owner-workload',
          ],
          title: 'Owner workload',
          subtitle:
              'Team ownership, action pressure, SLAs, permissions, and next owner boards.',
          icon: Icons.assignment_ind_outlined,
          accent: const Color(0xFF2563EB),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Command worklist',
        description:
            'Executive command, owner response, dispatch steps, and next response windows.',
        icon: Icons.outbound_outlined,
        color: const Color(0xFFDC2626),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'command-worklist',
          ],
          title: 'Command worklist',
          subtitle:
              'Executive command, owner response, dispatch steps, next response windows, and target boards.',
          icon: Icons.outbound_outlined,
          accent: const Color(0xFFDC2626),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Mini-program review',
        description: 'Registry approvals, publishing state, and suspensions.',
        icon: Icons.widgets_outlined,
        color: const Color(0xFF16A34A),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'mini-programs'],
          title: 'Mini-program review',
          subtitle:
              'Mini Program registry, manifest authority, review queue, releases, shelf usage, and event quality.',
          icon: Icons.apps_outlined,
          accent: const Color(0xFF0F766E),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Moments control',
        description:
            'Native social feed, privacy scopes, comments, and Mini Program embeds.',
        icon: Icons.auto_awesome_outlined,
        color: const Color(0xFF0F766E),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'moments'],
          title: 'Moments control',
          subtitle:
              'Moments feed health, privacy scopes, reports, comments, likes, Mini Program embeds, and friend-tag sync.',
          icon: Icons.dynamic_feed_outlined,
          accent: const Color(0xFF16A34A),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Official Accounts control',
        description:
            'Follow flows, account feeds, owner surfaces, and template messages.',
        icon: Icons.verified_outlined,
        color: const Color(0xFF2563EB),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'dashboards',
            'official-accounts',
          ],
          title: 'Official Accounts control',
          subtitle:
              'Official Account profile quality, follows, feed depth, template messages, notification modes, and Green Paket linkage.',
          icon: Icons.verified_outlined,
          accent: const Color(0xFF2563EB),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Channels control',
        description:
            'Discoverable videos, hot content, live hooks, and creator surfaces.',
        icon: Icons.play_circle_outline_rounded,
        color: const Color(0xFFC2410C),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'channels'],
          title: 'Channels control',
          subtitle:
              'Channels content, live depth, views, follows, engagement, creator quality, and discovery telemetry.',
          icon: Icons.play_circle_outline_rounded,
          accent: const Color(0xFFE11D48),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Discover control',
        description:
            'Search, People Nearby, profile freshness, and discovery telemetry.',
        icon: Icons.explore_outlined,
        color: const Color(0xFF2563EB),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'discover'],
          title: 'Discover control',
          subtitle:
              'Search, People Nearby, profile freshness, and discovery telemetry.',
          icon: Icons.explore_outlined,
          accent: const Color(0xFF2563EB),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Contacts control',
        description:
            'Friend requests, social graph follow-up, and contact growth loops.',
        icon: Icons.people_alt_outlined,
        color: const Color(0xFF7C3AED),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'contacts'],
          title: 'Contacts control',
          subtitle:
              'Contacts graph quality, invitations, active edges, revocations, friend tags, and Moments privacy sync.',
          icon: Icons.groups_outlined,
          accent: const Color(0xFF0F766E),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Cards and offers control',
        description:
            'Native commerce offer list connected to Official Accounts and Mini Programs.',
        icon: Icons.style_outlined,
        color: Tokens.colorPayments,
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'cards'],
          title: 'Cards and offers control',
          subtitle:
              'Member cards, offer inventory, claims, redemptions, and commerce telemetry.',
          icon: Icons.style_outlined,
          accent: Tokens.colorPayments,
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Cards control',
        description:
            'Offer inventory, member cards, claims, redemptions, and commerce telemetry.',
        icon: Icons.credit_card_outlined,
        color: Tokens.colorPayments,
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'cards'],
          title: 'Cards and offers control',
          subtitle:
              'Member cards, offer inventory, claims, redemptions, and commerce telemetry.',
          icon: Icons.style_outlined,
          accent: Tokens.colorPayments,
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Sticker store control',
        description:
            'Sticker inventory, official packs, chat usage, and Mini Program telemetry.',
        icon: Icons.emoji_emotions_outlined,
        color: const Color(0xFF7C3AED),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'stickers'],
          title: 'Sticker store control',
          subtitle:
              'Sticker inventory, official packs, chat usage, and Mini Program telemetry.',
          icon: Icons.emoji_emotions_outlined,
          accent: const Color(0xFF7C3AED),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Green Paket control',
        description:
            'Campaign authority, commerce telemetry, and Moments sharing signals.',
        icon: Icons.redeem_outlined,
        color: Tokens.colorPayments,
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'green-paket'],
          title: 'Green Paket control',
          subtitle:
              'Campaigns, commerce surfaces, Moments sharing, and owner activity.',
          icon: Icons.redeem_outlined,
          accent: Tokens.colorPayments,
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Favorites control',
        description:
            'Saved items, source modules, active accounts, and mutation telemetry.',
        icon: Icons.bookmark_border_rounded,
        color: const Color(0xFF0F766E),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'favorites'],
          title: 'Favorites control',
          subtitle:
              'Saved items, source modules, active accounts, and mutation telemetry.',
          icon: Icons.bookmark_border_rounded,
          accent: const Color(0xFF0F766E),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Chat preferences control',
        description:
            'Pinned, muted, starred, group preferences, and chat telemetry.',
        icon: Icons.chat_bubble_outline_rounded,
        color: const Color(0xFF334155),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'chat'],
          title: 'Chat preferences control',
          subtitle:
              'Pinned, muted, starred, group preferences, and chat telemetry.',
          icon: Icons.chat_bubble_outline_rounded,
          accent: const Color(0xFF334155),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Payments control',
        description:
            'Wallet authority, send safety, attestation hygiene, and trusted payment telemetry.',
        icon: Icons.account_balance_wallet_outlined,
        color: Tokens.colorPayments,
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'payments'],
          title: 'Payments control',
          subtitle:
              'Wallet authority, send safety, attestation hygiene, active challenges, and trusted payment telemetry.',
          icon: Icons.account_balance_wallet_outlined,
          accent: Tokens.colorPayments,
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Ride control',
        description:
            'Ride trips, driver supply, dispatch offers, support pressure, payment failures, and live tracking authority.',
        icon: Icons.local_taxi_outlined,
        color: const Color(0xFF2563EB),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'rides'],
          title: 'Ride control',
          subtitle:
              'Ride trips, driver supply, dispatch offers, support pressure, payment failures, and live tracking authority.',
          icon: Icons.local_taxi_outlined,
          accent: const Color(0xFF2563EB),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Coach control',
        description:
            'Coach bookings, tickets, boarding scans, feed health, refunds, and operator authority.',
        icon: Icons.directions_bus_outlined,
        color: const Color(0xFF0F766E),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>['admin', 'dashboards', 'coach'],
          title: 'Coach control',
          subtitle:
              'Coach bookings, tickets, boarding scans, feed health, refunds, and operator authority in one control board.',
          icon: Icons.directions_bus_outlined,
          accent: const Color(0xFF0F766E),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Analytics authority',
        description:
            'Source authority, trusted event telemetry, and platform feature controls.',
        icon: Icons.query_stats_outlined,
        color: const Color(0xFF334155),
        builder: (_) => ShamellControlDomainDashboardPage(
          baseUrl: baseUrl,
          pathSegments: const <String>[
            'admin',
            'platform',
            'features',
            'summary',
          ],
          title: 'Analytics authority',
          subtitle:
              'Trusted platform events, source authority, and feature telemetry.',
          icon: Icons.query_stats_outlined,
          accent: const Color(0xFF334155),
        ),
      ),
      _ControlDashboardHubEntry(
        title: 'Control Home',
        description: 'This dashboard index for monitoring every control area.',
        icon: Icons.home_work_outlined,
        color: const Color(0xFF475569),
        builder: (_) => ShamellControlDashboardHubPage(baseUrl: baseUrl),
        current: true,
      ),
    ];
  }

  void _openDashboard(BuildContext context, _ControlDashboardHubEntry entry) {
    if (entry.current) {
      return;
    }
    _recordControlDashboardOpen(
      baseUrl: baseUrl,
      dashboardTitle: entry.title,
      nativeSurface: true,
      openContext: 'control_dashboard_hub',
    );
    Navigator.of(context).push(MaterialPageRoute(builder: entry.builder));
  }

  bool _isPriorityEntry(_ControlDashboardHubEntry entry) {
    return const <String>{
      'Daily brief',
      'Control inbox',
      'Command worklist',
      'Owner workload',
    }.contains(entry.title);
  }

  String _sectionKeyForEntry(_ControlDashboardHubEntry entry) {
    if (const <String>{
      'Ops',
      'Admin',
      'Superadmin',
      'User activity',
      'Control Home',
      'Analytics authority',
    }.contains(entry.title)) {
      return 'admin';
    }
    if (const <String>{
      'Control runbooks',
      'Control intelligence',
      'Escalations',
      'SLA board',
      'Evidence board',
      'Sync board',
      'Quality board',
      'Launch board',
      'Growth board',
      'Incident board',
    }.contains(entry.title)) {
      return 'operating';
    }
    if (const <String>{
      'Experiment board',
      'Retention board',
      'Executive board',
      'Risk board',
    }.contains(entry.title)) {
      return 'strategy';
    }
    if (const <String>{
      'Mini-program review',
      'Moments',
      'Official Accounts',
      'Channels',
      'Discover control',
      'Contacts',
      'Favorites control',
      'Chat preferences control',
    }.contains(entry.title)) {
      return 'wechat';
    }
    if (const <String>{
      'Card offers',
      'Cards control',
      'Sticker store control',
      'Green Paket control',
      'Guthaben gutschreiben',
    }.contains(entry.title)) {
      return 'commerce';
    }
    return 'mobility';
  }

  List<_ControlDashboardHubSection> _sections(
    List<_ControlDashboardHubEntry> entries,
  ) {
    const order = <String>[
      'operating',
      'strategy',
      'wechat',
      'commerce',
      'mobility',
      'admin',
    ];
    return order
        .map(
          (key) => _ControlDashboardHubSection(
            key: key,
            title: _sectionTitle(key),
            detail: _sectionDetail(key),
            icon: _sectionIcon(key),
            color: _sectionColor(key),
            entries: entries
                .where((entry) => _sectionKeyForEntry(entry) == key)
                .toList(growable: false),
          ),
        )
        .where((section) => section.entries.isNotEmpty)
        .toList(growable: false);
  }

  String _sectionTitle(String key) {
    switch (key) {
      case 'operating':
        return 'Operating Control';
      case 'strategy':
        return 'Strategy And Risk';
      case 'wechat':
        return 'WeChat Surfaces';
      case 'commerce':
        return 'Commerce';
      case 'mobility':
        return 'Mobility';
      default:
        return 'Admin Tools';
    }
  }

  String _sectionDetail(String key) {
    switch (key) {
      case 'operating':
        return 'Native boards for SLA, evidence, sync, quality, launch, growth, incidents, and runbooks.';
      case 'strategy':
        return 'Executive posture, experiments, retention loops, and risk decisions.';
      case 'wechat':
        return 'Mini Programs, Moments, Official Accounts, Channels, Discover, contacts, and chat surfaces.';
      case 'commerce':
        return 'Green Paket, cards, offers, stickers, and payment operations.';
      case 'mobility':
        return 'Ride and Coach operator control rooms.';
      default:
        return 'Admin, superadmin, audit, analytics authority, and legacy owner tools.';
    }
  }

  IconData _sectionIcon(String key) {
    switch (key) {
      case 'operating':
        return Icons.dashboard_customize_outlined;
      case 'strategy':
        return Icons.space_dashboard_outlined;
      case 'wechat':
        return Icons.apps_outlined;
      case 'commerce':
        return Icons.account_balance_wallet_outlined;
      case 'mobility':
        return Icons.route_outlined;
      default:
        return Icons.admin_panel_settings_outlined;
    }
  }

  Color _sectionColor(String key) {
    switch (key) {
      case 'operating':
        return const Color(0xFF0F766E);
      case 'strategy':
        return const Color(0xFF334155);
      case 'wechat':
        return const Color(0xFF2563EB);
      case 'commerce':
        return Tokens.colorPayments;
      case 'mobility':
        return const Color(0xFFC2410C);
      default:
        return const Color(0xFF475569);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = _entries();
    final priorityEntries =
        entries.where(_isPriorityEntry).toList(growable: false);
    final groupedSections = _sections(
      entries
          .where((entry) => !_isPriorityEntry(entry))
          .toList(growable: false),
    );
    return AppScaffold(
      appBar: AppBar(
        title: const Text('SyrChat Control'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Center(
              child: Text(
                'Owner monitoring',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .62),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final maxTileWidth = width >= 1240
              ? 320.0
              : width >= 820
                  ? 300.0
                  : 420.0;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                sliver: SliverToBoxAdapter(
                  child: _ControlDashboardHubHero(
                    totalCount: entries.length,
                    priorityCount: priorityEntries.length,
                  ),
                ),
              ),
              if (priorityEntries.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
                  sliver: SliverToBoxAdapter(
                    child: _ControlDashboardHubSectionHeader(
                      icon: Icons.push_pin_outlined,
                      color: const Color(0xFF0F766E),
                      title: 'Command Center',
                      detail:
                          'Start here for today, owner pressure, command dispatch, and the live inbox.',
                      count: priorityEntries.length,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: maxTileWidth,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 172,
                    ),
                    itemCount: priorityEntries.length,
                    itemBuilder: (context, index) {
                      final entry = priorityEntries[index];
                      return _ControlDashboardHubTile(
                        entry: entry,
                        onTap: () => _openDashboard(context, entry),
                        priority: true,
                      );
                    },
                  ),
                ),
              ],
              ...groupedSections.expand(
                (section) => <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                    sliver: SliverToBoxAdapter(
                      child: _ControlDashboardHubSectionHeader(
                        icon: section.icon,
                        color: section.color,
                        title: section.title,
                        detail: section.detail,
                        count: section.entries.length,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: maxTileWidth,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 156,
                      ),
                      itemCount: section.entries.length,
                      itemBuilder: (context, index) {
                        final entry = section.entries[index];
                        return _ControlDashboardHubTile(
                          entry: entry,
                          onTap: () => _openDashboard(context, entry),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          );
        },
      ),
    );
  }
}

class _ControlDashboardHubSection {
  final String key;
  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final List<_ControlDashboardHubEntry> entries;

  const _ControlDashboardHubSection({
    required this.key,
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.entries,
  });
}

class _ControlDashboardHubEntry {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
  final bool current;

  const _ControlDashboardHubEntry({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.builder,
    this.current = false,
  });
}

class _ControlDashboardHubHero extends StatelessWidget {
  final int totalCount;
  final int priorityCount;

  const _ControlDashboardHubHero({
    required this.totalCount,
    required this.priorityCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const color = Color(0xFF0F766E);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: .14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.space_dashboard_outlined, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Control Command Center',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF17362B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Native owner access for SyrChat operations, WeChat-style surfaces, commerce, mobility, and admin controls.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF5A6F66),
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ControlDashboardHubPill(
                      icon: Icons.dashboard_customize_outlined,
                      label: 'Dashboards',
                      value: totalCount,
                      color: color,
                    ),
                    _ControlDashboardHubPill(
                      icon: Icons.push_pin_outlined,
                      label: 'Priority',
                      value: priorityCount,
                      color: const Color(0xFF2563EB),
                    ),
                    const _ControlDashboardHubPill(
                      icon: Icons.phone_android_outlined,
                      label: 'Surface',
                      value: 'Native',
                      color: Color(0xFF334155),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlDashboardHubSectionHeader extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final int count;

  const _ControlDashboardHubSectionHeader({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$title · $count',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF17362B),
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F66),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ControlDashboardHubPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Object value;
  final Color color;

  const _ControlDashboardHubPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label · $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlDashboardHubTile extends StatelessWidget {
  final _ControlDashboardHubEntry entry;
  final VoidCallback onTap;
  final bool priority;

  const _ControlDashboardHubTile({
    required this.entry,
    required this.onTap,
    this.priority = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: .72),
        ),
      ),
      child: InkWell(
        onTap: entry.current ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: priority ? 46 : 40,
                    height: priority ? 46 : 40,
                    decoration: BoxDecoration(
                      color: entry.color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      entry.icon,
                      color: entry.color,
                      size: priority ? 24 : 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Icon(
                    entry.current
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward_outlined,
                    color: entry.current
                        ? ShamellPalette.green
                        : theme.colorScheme.onSurface.withValues(alpha: .46),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Text(
                  entry.description,
                  maxLines: priority ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .68),
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  entry.current ? 'Current page' : 'Open dashboard',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: entry.current ? ShamellPalette.green : entry.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Optional wrapper to reduce background duplication (gradual adoption)
class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final bool extendBehindAppBar;
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.extendBehindAppBar = true,
  });
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      extendBodyBehindAppBar: extendBehindAppBar,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AppBG(),
          SafeArea(child: body),
        ],
      ),
    );
  }
}

Future<String?> _getCookie({String? baseUrlOverride}) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final base = configuredApiBaseUrlOrFallbackIfUnset(
          storedBaseUrl: baseUrlOverride ?? (sp.getString('base_url') ?? ''),
          fallbackBaseUrl: const String.fromEnvironment(
            'BASE_URL',
            defaultValue: 'https://api.shamell.online',
          ),
        ) ??
        '';
    if (base.isNotEmpty) {
      return await getSessionCookieHeader(base);
    }
  } catch (_) {}
  return null;
}

@visibleForTesting
Future<String?> shamellGetCookieForBaseUrl({String? baseUrlOverride}) async {
  return await _getCookie(baseUrlOverride: baseUrlOverride);
}

bool _isPublicAccountAuthBoundaryDetail(String detail) {
  return detail.contains('internal auth required') ||
      detail.contains('auth session required') ||
      detail.contains('authentication required') ||
      detail.contains('unauthorized') ||
      detail.contains('forbidden');
}

@visibleForTesting
Future<Map<String, String>> shamellBuildHeaders({
  bool json = false,
  String? baseUrl,
  bool includeSessionCookie = true,
}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final rawBase = (baseUrl ?? '').trim();
  // Many callers intentionally omit `baseUrl`; fall back to the active
  // runtime origin so authenticated API calls still attach the scoped cookie.
  final resolvedBase =
      rawBase.isNotEmpty ? rawBase : (shamellGetActiveRuntimeBaseUrl() ?? '');
  final normalizedBase = normalizeSecureApiBaseUrl(resolvedBase);
  final host = Uri.tryParse(normalizedBase ?? '')?.host.toLowerCase();
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
    // Local dev shortcut: edge-attested client IP is normally injected by
    // reverse proxy; direct localhost calls provide an explicit loopback IP.
    h['x-shamell-client-ip'] = '127.0.0.1';
  }
  if (includeSessionCookie && normalizedBase != null) {
    final c = await getSessionCookieHeader(normalizedBase);
    if (c != null && c.isNotEmpty) {
      // Best practice: use real Cookie header so prod/staging can disable
      // header-based session auth without breaking native clients.
      h['cookie'] = c;
    }
  }
  return h;
}

Future<Map<String, String>> _hdr({bool json = false, String? baseUrl}) {
  return shamellBuildHeaders(json: json, baseUrl: baseUrl);
}

const bool _allowLocalhostControlWebBypassInRelease = bool.fromEnvironment(
  'ALLOW_LOCALHOST_CONTROL_WEB_BYPASS_IN_RELEASE',
  defaultValue: true,
);
const String _controlWebDirectDashboardHostsRaw = String.fromEnvironment(
  'SHAMELL_CONTROL_WEB_DIRECT_DASHBOARD_HOSTS',
  defaultValue: '',
);
const String _webDirectAppHostsRaw = String.fromEnvironment(
  'SHAMELL_WEB_DIRECT_APP_HOSTS',
  defaultValue: '',
);

const List<String> _localhostControlWebBypassRoles = <String>[
  'ops',
  'admin',
  'operator_dispatch',
  'operator_support',
  'operator_finance',
  'operator_pricing',
  'operator_compliance',
];

Set<String> _controlWebDirectDashboardHosts({String? hostsRaw}) {
  final raw = (hostsRaw ?? _controlWebDirectDashboardHostsRaw).trim();
  if (raw.isEmpty) {
    return const <String>{};
  }
  return raw
      .split(RegExp(r'[\s,]+'))
      .map((host) => host.trim().toLowerCase())
      .where((host) => host.isNotEmpty)
      .toSet();
}

Set<String> _webDirectAppHosts({String? hostsRaw}) {
  final raw = (hostsRaw ?? _webDirectAppHostsRaw).trim();
  if (raw.isEmpty) {
    return const <String>{};
  }
  return raw
      .split(RegExp(r'[\s,]+'))
      .map((host) => host.trim().toLowerCase())
      .where((host) => host.isNotEmpty)
      .toSet();
}

@visibleForTesting
bool shamellAllowLocalhostControlWebDirectDashboards({
  required ShamellAppSurface appSurface,
  Uri? currentUri,
  bool isWeb = kIsWeb,
  bool isReleaseMode = kReleaseMode,
  bool? allowLocalhostBypassInRelease,
  String? directDashboardHostsRaw,
  String? directAppHostsRaw,
}) {
  if (!isWeb) {
    return false;
  }
  final uri = currentUri ?? Uri.base;
  final scheme = uri.scheme.trim().toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    return false;
  }
  final host = uri.host.trim().toLowerCase();
  if (_webDirectAppHosts(hostsRaw: directAppHostsRaw).contains(host)) {
    return true;
  }
  if (!shamellIsRideOperatorSurface(appSurface)) {
    return false;
  }
  if (isLocalhostHost(host)) {
    if (!isReleaseMode) {
      return true;
    }
    return allowLocalhostBypassInRelease ??
        _allowLocalhostControlWebBypassInRelease;
  }
  return _controlWebDirectDashboardHosts(
    hostsRaw: directDashboardHostsRaw,
  ).contains(host);
}

@visibleForTesting
bool shamellAllowControlWebSessionBypass({
  required ShamellAppSurface appSurface,
  Uri? currentUri,
  bool isWeb = kIsWeb,
  bool isReleaseMode = kReleaseMode,
  bool? allowLocalhostBypassInRelease,
}) {
  if (!shamellIsRideOperatorSurface(appSurface)) {
    return false;
  }
  final uri = currentUri ?? Uri.base;
  final host = uri.host.trim().toLowerCase();
  if (!isLocalhostHost(host)) {
    return false;
  }
  return shamellAllowLocalhostControlWebDirectDashboards(
    appSurface: appSurface,
    currentUri: uri,
    isWeb: isWeb,
    isReleaseMode: isReleaseMode,
    allowLocalhostBypassInRelease: allowLocalhostBypassInRelease,
  );
}

Future<void> _primeLocalhostControlWebDashboardAccess(String baseUrl) async {
  final normalizedBase = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (normalizedBase == null || normalizedBase.isEmpty) {
    return;
  }
  await saveAccountPrivilegeSnapshot(
    roles: _localhostControlWebBypassRoles,
    isSuperadmin: true,
    baseUrlOverride: normalizedBase,
  );
}

@visibleForTesting
bool shamellAllowsDebugAndroidEmulatorSignInBypass({
  required ShamellAppSurface appSurface,
  bool isWeb = kIsWeb,
  bool isReleaseMode = kReleaseMode,
  bool? platformIsAndroid,
}) {
  final isAndroid =
      platformIsAndroid ?? defaultTargetPlatform == TargetPlatform.android;
  if (isWeb || isReleaseMode || !isAndroid) {
    return false;
  }
  if (shamellIsRideOperatorSurface(appSurface)) {
    return false;
  }
  return appSurface == ShamellAppSurface.superapp;
}

class LoginGate extends StatefulWidget {
  final ShamellAppSurface appSurface;
  @visibleForTesting
  final Widget Function(String? baseUrlOverride)? debugHomeBuilder;
  @visibleForTesting
  final Widget Function(String? baseUrlOverride)? debugLoginBuilder;
  @visibleForTesting
  final bool? debugAllowLocalhostControlWebBypassOverride;
  @visibleForTesting
  final bool? debugAllowAndroidEmulatorSignInBypassOverride;

  const LoginGate({
    super.key,
    this.appSurface = ShamellAppSurface.superapp,
    this.debugHomeBuilder,
    this.debugLoginBuilder,
    this.debugAllowLocalhostControlWebBypassOverride,
    this.debugAllowAndroidEmulatorSignInBypassOverride,
  });
  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> with WidgetsBindingObserver {
  bool _loading = true;
  bool _hasSession = false;
  bool _skipSignedInStartupTasks = false;
  String _baseUrl = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_bootstrapGate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !mounted) {
      return;
    }
    final baseUrlOverride = _baseUrl.trim().isEmpty ? null : _baseUrl.trim();
    unawaited(
      _reconcilePushBindingOnForeground(baseUrlOverride: baseUrlOverride),
    );
  }

  Future<void> _bootstrapGate() async {
    final baseUrl = await _resolveBootstrapBaseUrl();
    final allowSessionBypass =
        widget.debugAllowLocalhostControlWebBypassOverride ??
            shamellAllowControlWebSessionBypass(appSurface: widget.appSurface);
    final allowAndroidEmulatorBypass =
        widget.debugAllowAndroidEmulatorSignInBypassOverride ??
            (shamellAllowsDebugAndroidEmulatorSignInBypass(
                  appSurface: widget.appSurface,
                ) &&
                _debugSkipLogin &&
                await HardwareAttestation.isProbablyAndroidEmulator());
    if (allowSessionBypass) {
      await _primeLocalhostControlWebDashboardAccess(baseUrl);
    }
    var hasStoredSession =
        (await getSessionCookieHeader(baseUrl) ?? '').isNotEmpty;
    if (!hasStoredSession && allowAndroidEmulatorBypass && _debugSkipLogin) {
      hasStoredSession = await shamellEnsureDebugSkipLoginSession(
        baseUrl: baseUrl,
      );
    }
    final hasSession =
        allowSessionBypass || allowAndroidEmulatorBypass || hasStoredSession;
    if (!mounted) return;
    setState(() {
      _baseUrl = baseUrl;
      _hasSession = hasSession;
      _skipSignedInStartupTasks =
          allowAndroidEmulatorBypass && !hasStoredSession;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
        ),
      );
    }

    if (_hasSession) {
      final baseUrlOverride = _baseUrl.trim().isEmpty ? null : _baseUrl.trim();
      if (widget.debugHomeBuilder != null) {
        return widget.debugHomeBuilder!(baseUrlOverride);
      }
      return shamellBuildSignedInHome(
        appSurface: widget.appSurface,
        baseUrlOverride: baseUrlOverride,
        runStartupTasks: !_skipSignedInStartupTasks,
      );
    }

    final baseUrlOverride = _baseUrl.trim().isEmpty ? null : _baseUrl.trim();
    if (widget.debugLoginBuilder != null) {
      return widget.debugLoginBuilder!(baseUrlOverride);
    }
    return LoginPage(
      hasSession: false,
      baseUrlOverride: baseUrlOverride,
      appSurface: widget.appSurface,
    );
  }
}

class LoginPage extends StatefulWidget {
  final bool hasSession;
  final String? baseUrlOverride;
  final ShamellAppSurface appSurface;
  @visibleForTesting
  final bool? debugIsWebOverride;
  @visibleForTesting
  final Widget Function(String? baseUrlOverride)? debugSignedInHomeBuilder;

  const LoginPage({
    super.key,
    this.hasSession = false,
    this.baseUrlOverride,
    this.appSurface = ShamellAppSurface.superapp,
    this.debugIsWebOverride,
    this.debugSignedInHomeBuilder,
  });
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SafeSetStateMixin<LoginPage> {
  static const Duration _prefsIoTimeout = Duration(seconds: 3);
  final baseCtrl = TextEditingController(
    text: const String.fromEnvironment(
      'BASE_URL',
      defaultValue: 'https://api.shamell.online',
    ),
  );
  final usernameCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final confirmPasswordCtrl = TextEditingController();
  String out = '';
  bool _busy = false;
  bool _hasSessionCookie = false;
  bool _canBiometricSignIn = false;
  bool _signUpMode = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool get _isWebEnvironment => widget.debugIsWebOverride ?? kIsWeb;
  bool get _usesUsernamePasswordAuth =>
      shamellSurfaceUsesUsernamePasswordAuth(widget.appSurface) ||
      (_isWebEnvironment && shamellIsRideOperatorSurface(widget.appSurface));

  @override
  void initState() {
    super.initState();
    unawaited(_loadBase());
  }

  @override
  void dispose() {
    baseCtrl.dispose();
    usernameCtrl.dispose();
    passwordCtrl.dispose();
    confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    final fallbackBase = normalizeSecureApiBaseUrl(
          const String.fromEnvironment(
            'BASE_URL',
            defaultValue: 'https://api.shamell.online',
          ),
        ) ??
        'https://api.shamell.online';
    final fallbackHost = Uri.tryParse(fallbackBase)?.host ?? '';
    final hasReachableFallback =
        fallbackBase.isNotEmpty && !isLocalhostHost(fallbackHost);
    final explicitBaseOverride = (widget.baseUrlOverride ?? '').trim();

    try {
      final sp = await SharedPreferences.getInstance();
      final rawStored = sp.getString('base_url') ?? '';
      final stored = explicitBaseOverride.isNotEmpty
          ? normalizeSecureApiBaseUrl(explicitBaseOverride)
          : preferredConfiguredApiBaseUrl(
              storedBaseUrl: rawStored,
              fallbackBaseUrl: fallbackBase,
            );
      final normalizedStored = normalizeSecureApiBaseUrl(rawStored.trim());
      if (stored != null && stored.isNotEmpty) {
        baseCtrl.text = stored;
      }
      if (hasReachableFallback &&
          stored != null &&
          stored.isNotEmpty &&
          stored != normalizedStored &&
          explicitBaseOverride.isEmpty) {
        try {
          await sp.setString('base_url', stored);
        } catch (_) {}
      }
    } catch (_) {}
    if (await _maybeImportDebugSessionSeed()) {
      return;
    }
    await _refreshAvailableSignInOptions();
  }

  Future<bool> _maybeImportDebugSessionSeed() async {
    final seed = await shamellConsumeDebugSessionSeed();
    if (seed == null) {
      return false;
    }
    final base = seed['base_url']!;
    final token = seed['token']!;
    baseCtrl.text = base;
    await _persistSelectedBaseUrl();
    await setSessionTokenForBaseUrl(base, token);
    try {
      final snapshot = await refreshAndPersistAccountHomeSnapshot(
        baseUrl: base,
        ensureSession: false,
      );
      if (!mounted) {
        return true;
      }
      setState(() {
        _hasSessionCookie = true;
        out = snapshot.shamellId.isNotEmpty
            ? shamellSurfaceAccountCreateSuccessLabel(
                isArabic: L10n.of(context).isArabic,
                shamellId: snapshot.shamellId,
                surface: widget.appSurface,
              )
            : 'Session restored.';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_handlePostLoginNavigation());
      });
      return true;
    } catch (e) {
      await clearSessionCookie();
      if (!mounted) {
        return false;
      }
      setState(() {
        _hasSessionCookie = false;
        out = _sanitizeLoginException(
          error: e,
          isArabic: L10n.of(context).isArabic,
          baseUrl: base,
        );
      });
      return false;
    }
  }

  Future<void> _persistSelectedBaseUrl() async {
    final explicitBaseOverride = (widget.baseUrlOverride ?? '').trim();
    if (explicitBaseOverride.isNotEmpty) return;
    final raw = baseCtrl.text.trim();
    if (raw.isEmpty) return;
    final base = normalizeSecureApiBaseUrl(raw);
    if (base == null || base.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance().timeout(_prefsIoTimeout);
      await sp.setString('base_url', base).timeout(_prefsIoTimeout);
    } catch (_) {}
  }

  Future<void> _refreshAvailableSignInOptions() async {
    final base = normalizeSecureApiBaseUrl(baseCtrl.text.trim());
    if (base == null || base.isEmpty) {
      if (!mounted) return;
      setState(() => _canBiometricSignIn = false);
      return;
    }
    final token = (await getBiometricLoginTokenForBaseUrl(base) ?? '').trim();
    if (!mounted) return;
    setState(() => _canBiometricSignIn = token.isNotEmpty);
  }

  Future<void> _signInWithBiometrics() async {
    void setOutSafe(String message) {
      if (!mounted) return;
      setState(() => out = message);
    }

    final l = L10n.of(context);
    if (_busy) return;
    final rawBase = baseCtrl.text.trim();
    if (rawBase.isEmpty) {
      setOutSafe(
        l.isArabic ? 'عنوان الخادم مطلوب.' : 'Server URL is required.',
      );
      return;
    }
    final base = normalizeSecureApiBaseUrl(rawBase);
    if (base == null) {
      setOutSafe(
        l.isArabic
            ? 'يجب استخدام HTTPS (وفي وضع التطوير يُسمح بـ HTTP على localhost أو الشبكة المحلية).'
            : 'HTTPS is required (non-release builds also allow HTTP for localhost/LAN).',
      );
      return;
    }
    if (_isWebEnvironment) {
      setOutSafe(l.loginBiometricWebUnavailable);
      return;
    }

    await _persistSelectedBaseUrl();
    await _refreshAvailableSignInOptions();
    if (!_canBiometricSignIn) {
      setOutSafe(l.loginDeviceNotEnrolled);
      return;
    }

    setState(() {
      _busy = true;
      out = l.loginAuthenticating;
    });

    final stopwatch = Stopwatch()..start();
    var authAttemptSuccess = false;
    try {
      final result = await biometricSignInDetailed(base);
      if (result != BiometricFlowResult.success) {
        await _refreshAvailableSignInOptions();
        switch (result) {
          case BiometricFlowResult.reauthRequired:
            setOutSafe(l.loginBiometricReauthRequired);
            break;
          case BiometricFlowResult.failed:
            setOutSafe(
              _canBiometricSignIn
                  ? l.loginBiometricFailed
                  : l.loginDeviceNotEnrolled,
            );
            break;
          case BiometricFlowResult.success:
            break;
        }
        if (mounted) setState(() => _busy = false);
        return;
      }

      authAttemptSuccess = true;
      await _handlePostLoginNavigation();
      if (!mounted) return;
      setState(() {
        _hasSessionCookie = true;
        _busy = false;
      });
    } catch (e) {
      setOutSafe(
        _sanitizeLoginException(error: e, isArabic: l.isArabic, baseUrl: base),
      );
      if (mounted) setState(() => _busy = false);
    } finally {
      stopwatch.stop();
      await V2AuthStranglerStore.recordAuthAttempt(
        variant: AuthFlowVariant.legacy,
        elapsedMs: stopwatch.elapsedMilliseconds,
        success: authAttemptSuccess,
        baseUrlOverride: base,
      );
    }
  }

  String _sanitizeLoginException({
    required Object error,
    required bool isArabic,
    String? baseUrl,
  }) {
    final fallback = sanitizeExceptionForUi(error: error, isArabic: isArabic);
    final raw = error.toString().trim().toLowerCase();
    if (_isPublicAccountAuthBoundaryDetail(raw)) {
      return isArabic
          ? 'هذا الخادم لا يسمح بإنشاء حسابات عامة.'
          : 'This server does not allow public account creation.';
    }
    final isLikelyNetwork = raw.contains('socket') ||
        raw.contains('network') ||
        raw.contains('connection') ||
        raw.contains('timeout');
    final isMobilePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    if (!isLikelyNetwork || !isMobilePlatform) return fallback;

    final base = (baseUrl ?? baseCtrl.text).trim();
    final host = Uri.tryParse(base)?.host ?? '';
    if (!isLocalhostHost(host)) return fallback;

    return isArabic
        ? 'خطأ في الشبكة. على الهاتف يشير localhost إلى نفس الجهاز. استخدم رابط خادم قابل للوصول (ويُفضَّل HTTPS).'
        : 'Network error. On a phone, localhost points to the phone itself. Use a reachable server URL (HTTPS preferred).';
  }

  String? _validateUsernamePasswordInput(L10n l, {required bool signUp}) {
    final username = usernameCtrl.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z][a-z0-9._-]{2,31}$').hasMatch(username)) {
      return l.isArabic
          ? 'استخدم اسم مستخدم من 3 إلى 32 حرفاً يبدأ بحرف إنجليزي ويحتوي فقط على أحرف صغيرة أو أرقام أو . أو _ أو -'
          : 'Use a 3-32 character username starting with a letter and containing only lowercase letters, numbers, ., _, or -.';
    }
    final password = passwordCtrl.text;
    if (password.length < 8) {
      return l.isArabic
          ? 'يجب أن تتكون كلمة المرور من 8 أحرف على الأقل.'
          : 'Password must be at least 8 characters.';
    }
    if (signUp && password != confirmPasswordCtrl.text) {
      return l.isArabic
          ? 'كلمتا المرور غير متطابقتين.'
          : 'Passwords do not match.';
    }
    return null;
  }

  Future<void> _submitUsernamePasswordAuth({required bool signUp}) async {
    void setOutSafe(String message) {
      if (!mounted) return;
      setState(() => out = message);
    }

    final l = L10n.of(context);
    if (_busy) return;
    final allowSignUp = shamellSurfaceAllowsPublicAccountCreate(
      widget.appSurface,
    );
    if (signUp && !allowSignUp) {
      setOutSafe(
        l.isArabic
            ? 'إنشاء الحساب غير متاح لهذه الواجهة.'
            : 'Account creation is not available for this control surface.',
      );
      return;
    }

    final rawBase = baseCtrl.text.trim();
    if (rawBase.isEmpty) {
      setOutSafe(
        l.isArabic ? 'عنوان الخادم مطلوب.' : 'Server URL is required.',
      );
      return;
    }
    final base = normalizeSecureApiBaseUrl(rawBase);
    if (base == null) {
      setOutSafe(
        l.isArabic
            ? 'يجب استخدام HTTPS (وفي وضع التطوير يُسمح بـ HTTP على localhost أو الشبكة المحلية).'
            : 'HTTPS is required (non-release builds also allow HTTP for localhost/LAN).',
      );
      return;
    }

    final validationError = _validateUsernamePasswordInput(l, signUp: signUp);
    if (validationError != null) {
      setOutSafe(validationError);
      return;
    }

    await _persistSelectedBaseUrl();

    setState(() {
      _busy = true;
      out = signUp
          ? (l.isArabic ? 'جارٍ إنشاء الحساب…' : 'Creating account…')
          : (l.isArabic ? 'جارٍ تسجيل الدخول…' : 'Signing in…');
    });

    final stopwatch = Stopwatch()..start();
    var authAttemptSuccess = false;
    try {
      if (signUp) {
        await shamellSignUpWithUsernamePassword(
          baseUrl: base,
          username: usernameCtrl.text,
          password: passwordCtrl.text,
        );
      } else {
        await shamellSignInWithUsernamePassword(
          baseUrl: base,
          username: usernameCtrl.text,
          password: passwordCtrl.text,
        );
      }

      // Persist the freshly-authenticated handle so the Profile / Me
      // hero can show "@username" under the display name. We mirror
      // `usernameCtrl.text` rather than the server response so the
      // handle the user typed is what they see surfaced back — the
      // sign-in API normalises to lowercase, which makes a mixed-case
      // handle silently mutate on each round-trip.
      unawaited(
        saveProfileUsername(usernameCtrl.text).catchError((_) {}),
      );

      final snapshot = await refreshAndPersistAccountHomeSnapshot(
        baseUrl: base,
        ensureSession: false,
      );
      authAttemptSuccess = true;
      if (!mounted) return;
      setState(() {
        _hasSessionCookie = true;
        _busy = false;
        out = signUp
            ? (snapshot.shamellId.isNotEmpty
                ? shamellSurfaceAccountCreateSuccessLabel(
                    isArabic: l.isArabic,
                    shamellId: snapshot.shamellId,
                    surface: widget.appSurface,
                  )
                : (l.isArabic ? 'تم إنشاء الحساب.' : 'Account created.'))
            : (snapshot.shamellId.isNotEmpty
                ? (l.isArabic
                    ? 'تم تسجيل الدخول: ${snapshot.shamellId}'
                    : 'Signed in: ${snapshot.shamellId}')
                : (l.isArabic ? 'تم تسجيل الدخول.' : 'Signed in.'));
      });
      passwordCtrl.clear();
      confirmPasswordCtrl.clear();
      await _handlePostLoginNavigation();
    } catch (e) {
      setOutSafe(
        _sanitizeLoginException(error: e, isArabic: l.isArabic, baseUrl: base),
      );
      if (mounted) {
        setState(() => _busy = false);
      }
    } finally {
      stopwatch.stop();
      await V2AuthStranglerStore.recordAuthAttempt(
        variant: AuthFlowVariant.legacy,
        elapsedMs: stopwatch.elapsedMilliseconds,
        success: authAttemptSuccess,
        baseUrlOverride: base,
      );
    }
  }

  Future<void> _handlePostLoginNavigation() async {
    // Replace the auth route so the back arrow does not return to login.
    if (!mounted) return;
    final baseUrlOverride = normalizeSecureApiBaseUrl(baseCtrl.text.trim());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            widget.debugSignedInHomeBuilder?.call(baseUrlOverride) ??
            shamellBuildSignedInHome(
              appSurface: widget.appSurface,
              baseUrlOverride: baseUrlOverride,
            ),
      ),
    );
  }

  @visibleForTesting
  String debugCurrentBaseUrl() => baseCtrl.text.trim();

  @visibleForTesting
  Future<void> debugHandlePostLoginNavigation() => _handlePostLoginNavigation();

  @visibleForTesting
  Future<void> debugPersistSelectedBaseUrl() async {
    await _persistSelectedBaseUrl();
  }

  @visibleForTesting
  Future<void> debugRecordAuthAttempt({
    required AuthFlowVariant variant,
    required int elapsedMs,
    required bool success,
  }) async {
    await V2AuthStranglerStore.recordAuthAttempt(
      variant: variant,
      elapsedMs: elapsedMs,
      success: success,
      baseUrlOverride: widget.baseUrlOverride,
    );
  }

  Future<void> _checkBrowserSession() async {
    final l = L10n.of(context);
    if (_busy) return;
    final rawBase = baseCtrl.text.trim();
    if (rawBase.isEmpty) {
      setState(() {
        out = l.isArabic ? 'عنوان الخادم مطلوب.' : 'Server URL is required.';
      });
      return;
    }
    final base = normalizeSecureApiBaseUrl(rawBase);
    if (base == null) {
      setState(() {
        out = l.isArabic
            ? 'رابط الخادم غير صالح.'
            : 'The configured server URL is invalid.';
      });
      return;
    }

    setState(() {
      _busy = true;
      out = l.isArabic
          ? 'جارٍ التحقق من جلسة المتصفح…'
          : 'Checking browser session…';
    });
    await _persistSelectedBaseUrl();

    try {
      if (kIsWeb) {
        await refreshAndPersistAccountHomeSnapshot(
          baseUrl: base,
          ensureSession: false,
        );
        if (!mounted) return;
        setState(() {
          _hasSessionCookie = true;
          out = l.isArabic
              ? 'تم العثور على الجلسة. جارٍ فتح وحدة التشغيل…'
              : 'Session detected. Opening SyrChat Control…';
        });
        await _handlePostLoginNavigation();
        return;
      }

      final cookie = (await getSessionCookieHeader(base) ?? '').trim();
      if (cookie.isEmpty) {
        if (!mounted) return;
        setState(() {
          _hasSessionCookie = false;
          out = l.isArabic
              ? 'لا توجد جلسة صالحة في هذا المتصفح بعد. اطلب من Superadmin منحك الوصول ثم سجّل الدخول من تدفق معتمد.'
              : 'No active SyrChat Control session was found in this browser. Ask a superadmin to grant access, then sign in through an approved flow.';
        });
        return;
      }

      await refreshAndPersistAccountHomeSnapshot(
        baseUrl: base,
        ensureSession: false,
      );
      if (!mounted) return;
      setState(() {
        _hasSessionCookie = true;
        out = l.isArabic
            ? 'تم العثور على الجلسة. جارٍ فتح وحدة التشغيل…'
            : 'Session detected. Opening SyrChat Control…';
      });
      await _handlePostLoginNavigation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasSessionCookie = false;
        out = _sanitizeLoginException(
          error: e,
          isArabic: l.isArabic,
          baseUrl: base,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openSupportUri(Uri uri) async {
    final l = L10n.of(context);
    try {
      final launched = await launchUrl(
        uri,
        mode: shamellExternalLaunchMode(uri),
      );
      if (!launched && mounted) {
        setState(() {
          out = l.isArabic
              ? 'تعذر فتح رابط الدعم.'
              : 'Could not open the support link.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        out = _sanitizeLoginException(
          error: e,
          isArabic: l.isArabic,
          baseUrl: baseCtrl.text.trim(),
        );
      });
    }
  }

  Future<void> _openDeviceLoginUri(Uri uri) async {
    final l = L10n.of(context);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
      if (!launched && mounted) {
        setState(() {
          out = l.isArabic
              ? 'تعذر فتح صفحة تسجيل دخول الجهاز.'
              : 'Could not open the device-login page.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        out = _sanitizeLoginException(
          error: e,
          isArabic: l.isArabic,
          baseUrl: baseCtrl.text.trim(),
        );
      });
    }
  }

  Widget _buildUsernamePasswordAuthCard({
    required L10n l,
    required ThemeData theme,
  }) {
    final allowSignUp = shamellSurfaceAllowsPublicAccountCreate(
      widget.appSurface,
    );
    final signUpMode = allowSignUp && _signUpMode;
    final title = shamellSurfaceBiometricActionLabel(
      isArabic: l.isArabic,
      surface: widget.appSurface,
    );
    final description = allowSignUp
        ? (l.isArabic
            ? 'أنشئ حسابك أو سجّل الدخول باستخدام اسم المستخدم وكلمة المرور فقط.'
            : 'Create your account or sign in using only a username and password.')
        : (l.isArabic
            ? 'سجّل الدخول باستخدام حساب تشغيل مصرح به.'
            : 'Sign in with an authorized operations account.');

    InputDecoration decoration({
      required String label,
      IconData? icon,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            if (allowSignUp) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l.isArabic ? 'تسجيل الدخول' : 'Sign in'),
                    selected: !signUpMode,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _signUpMode = false),
                  ),
                  ChoiceChip(
                    label: Text(l.isArabic ? 'إنشاء حساب' : 'Sign up'),
                    selected: signUpMode,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _signUpMode = true),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: usernameCtrl,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const <String>[AutofillHints.username],
              decoration: decoration(
                label: l.isArabic ? 'اسم المستخدم' : 'Username',
                icon: Icons.alternate_email_outlined,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              enabled: !_busy,
              obscureText: _obscurePassword,
              textInputAction:
                  signUpMode ? TextInputAction.next : TextInputAction.done,
              autofillHints: const <String>[AutofillHints.password],
              onSubmitted: signUpMode
                  ? null
                  : (_) =>
                      unawaited(_submitUsernamePasswordAuth(signUp: false)),
              decoration: decoration(
                label: l.isArabic ? 'كلمة المرور' : 'Password',
                icon: Icons.lock_outline,
                suffixIcon: IconButton(
                  onPressed: _busy
                      ? null
                      : () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (signUpMode) ...[
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordCtrl,
                enabled: !_busy,
                obscureText: _obscureConfirmPassword,
                textInputAction: TextInputAction.done,
                autofillHints: const <String>[AutofillHints.newPassword],
                onSubmitted: (_) =>
                    unawaited(_submitUsernamePasswordAuth(signUp: true)),
                decoration: decoration(
                  label: l.isArabic ? 'تأكيد كلمة المرور' : 'Confirm password',
                  icon: Icons.verified_user_outlined,
                  suffixIcon: IconButton(
                    onPressed: _busy
                        ? null
                        : () => setState(
                              () => _obscureConfirmPassword =
                                  !_obscureConfirmPassword,
                            ),
                    icon: Icon(
                      _obscureConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _submitUsernamePasswordAuth(signUp: signUpMode),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Icon(
                      signUpMode
                          ? Icons.person_add_alt_1_outlined
                          : Icons.login_outlined,
                    ),
              label: Text(
                signUpMode
                    ? (l.isArabic ? 'إنشاء حساب' : 'Create account')
                    : (l.isArabic ? 'تسجيل الدخول' : 'Sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNativeSurfaceAuthCard({
    required BuildContext context,
    required L10n l,
    required ThemeData theme,
  }) {
    final origin = normalizeSecureApiBaseUrl(baseCtrl.text.trim()) ??
        'https://api.shamell.online';
    if (_usesUsernamePasswordAuth) {
      return _buildUsernamePasswordAuthCard(l: l, theme: theme);
    }
    final signInLabel = shamellSurfaceBiometricActionLabel(
      isArabic: l.isArabic,
      surface: widget.appSurface,
    );
    final managedSignInLabel = shamellSurfaceManagedSignInActionLabel(
      isArabic: l.isArabic,
      surface: widget.appSurface,
    );

    late final String title;
    late final String description;
    late final String primaryLabel;
    late final IconData primaryIcon;
    late final Future<void> Function() onPrimaryPressed;
    String? helperText;
    Widget? secondaryAction;

    if (_canBiometricSignIn) {
      title = signInLabel;
      description = shamellSurfaceManagedSignInDescription(
        isArabic: l.isArabic,
        surface: widget.appSurface,
      );
      primaryLabel = signInLabel;
      primaryIcon = Icons.fingerprint;
      onPrimaryPressed = _signInWithBiometrics;
      secondaryAction = OutlinedButton.icon(
        onPressed: _busy
            ? null
            : () => _openDeviceLoginUri(Uri.parse('$origin/auth/device_login')),
        icon: const Icon(Icons.qr_code_2_outlined),
        label: Text(managedSignInLabel),
      );
    } else {
      title = managedSignInLabel;
      description = shamellSurfaceManagedSignInDescription(
        isArabic: l.isArabic,
        surface: widget.appSurface,
      );
      primaryLabel = managedSignInLabel;
      primaryIcon = Icons.qr_code_2_outlined;
      onPrimaryPressed =
          () => _openDeviceLoginUri(Uri.parse('$origin/auth/device_login'));
      helperText = l.isArabic
          ? 'إذا سبق اعتماد هذا الجهاز، سيظهر تسجيل الدخول بالبصمة هنا لاحقاً.'
          : 'If this device is approved later, biometric sign-in will appear here.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .70),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : onPrimaryPressed,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Icon(primaryIcon),
              label: Text(primaryLabel),
            ),
            if (secondaryAction != null) ...[
              const SizedBox(height: 10),
              secondaryAction,
            ],
            if (helperText != null) ...[
              const SizedBox(height: 8),
              Text(
                helperText,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .68),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControlWebLogin({
    required BuildContext context,
    required L10n l,
    required ThemeData theme,
    required bool hasSession,
  }) {
    final origin = normalizeSecureApiBaseUrl(baseCtrl.text.trim()) ??
        'https://api.shamell.online';
    final statusColor = hasSession ? ShamellPalette.green : Tokens.warning;
    final heroGlass = Tokens.lightSurface.withValues(alpha: .84);
    final heroBorder = Tokens.lightBorder;
    final heroShadow = Tokens.primary.withValues(alpha: .08);
    final heroTitle = Tokens.lightOnSurface;
    final heroBody = Tokens.lightOnSurfaceSecondary;
    final heroDeepPanel = Tokens.lightSnackSurface;
    final statusLabel = hasSession
        ? (l.isArabic ? 'الجلسة جاهزة' : 'Session detected')
        : (l.isArabic ? 'بانتظار التفويض' : 'Awaiting authorized session');
    final intro = l.isArabic
        ? 'لوحة تشغيل سطح مكتب لإدارة الرحلات، الأسطول، الحوادث، والمدفوعات من واجهة واحدة.'
        : 'A desktop operations desk for live rides, fleet control, case handling, and payment exceptions.';
    final accessText = l.isArabic
        ? 'تتطلب هذه الواجهة حساب تشغيل مصرحاً به. يتم منح الوصول من خلال Superadmin داخل SyrChat Control.'
        : 'This console requires an authorized operations account. Access is provisioned by a superadmin inside SyrChat Control.';
    final featureItems = <String>[
      l.isArabic
          ? 'لوحة حية للرحلات والسائقين'
          : 'Live board for rides and drivers',
      l.isArabic
          ? 'إعادة الإسناد، الإلغاء، والمتابعة التشغيلية'
          : 'Reassign, cancel, and intervene in active trips',
      l.isArabic
          ? 'مراجعة المدفوعات ووصول الإدارة'
          : 'Finance review and admin-access management',
    ];

    Widget statusPill() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: statusColor.withValues(alpha: .35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasSession
                  ? Icons.verified_user_outlined
                  : Icons.pending_outlined,
              size: 16,
              color: statusColor,
            ),
            const SizedBox(width: 8),
            Text(
              statusLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    Widget heroPanel() {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Tokens.lightSurface,
              Tokens.lightSurfaceAlt,
              Tokens.lightScaffold,
            ],
          ),
          border: Border.all(color: heroBorder),
          boxShadow: <BoxShadow>[
            BoxShadow(color: heroShadow, blurRadius: 34, offset: Offset(0, 18)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: heroGlass,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: heroBorder),
              ),
              child: Text(
                'SyrChat Control Web',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: ShamellPalette.green,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              shamellSurfaceAppTitle(
                isArabic: l.isArabic,
                surface: widget.appSurface,
              ),
              style: GoogleFonts.dmSerifDisplay(
                fontSize: 54,
                height: .95,
                color: heroTitle,
              ),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                intro,
                style: theme.textTheme.titleMedium?.copyWith(
                  height: 1.45,
                  color: heroBody,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: featureItems
                  .map(
                    (item) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: heroGlass,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: heroBorder),
                      ),
                      child: Text(
                        item,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: heroTitle,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: heroDeepPanel,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.monitor_heart_outlined,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.isArabic
                              ? 'استخدم superadmin للوصول والإسناد'
                              : 'Use superadmin for access provisioning',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.isArabic
                              ? 'يمكن لـ Superadmin إنشاء حسابات admin وops مباشرة من داخل Control.'
                              : 'Superadmins can grant admin and ops access directly from inside Control.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: .78),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget detailsRow({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: ShamellPalette.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: ShamellPalette.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                  ),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ShamellPalette.textPrimary,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    Widget actionPanel() {
      return Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Tokens.lightSurface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: heroBorder),
          boxShadow: <BoxShadow>[
            BoxShadow(color: heroShadow, blurRadius: 28, offset: Offset(0, 16)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            statusPill(),
            const SizedBox(height: 20),
            Text(
              l.isArabic ? 'وصول المشغل' : 'Operator access',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: ShamellPalette.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              accessText,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: ShamellPalette.textSecondary,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      if (hasSession) {
                        await _handlePostLoginNavigation();
                        return;
                      }
                      await _checkBrowserSession();
                    },
              style: FilledButton.styleFrom(
                backgroundColor: ShamellPalette.green,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      hasSession
                          ? Icons.login_outlined
                          : Icons.verified_user_outlined,
                    ),
              label: Text(
                hasSession
                    ? (l.isArabic
                        ? 'متابعة إلى Control'
                        : 'Continue to Control')
                    : (l.isArabic
                        ? 'التحقق من الجلسة'
                        : 'Check browser session'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (!hasSession) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _openDeviceLoginUri(
                          Uri.parse('$origin/auth/device_login'),
                        ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  side: const BorderSide(color: Tokens.lightInputBorder),
                ),
                icon: const Icon(Icons.qr_code_2_outlined),
                label: Text(
                  l.isArabic ? 'فتح QR لتسجيل الدخول' : 'Open QR sign-in',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openSupportUri(
                      shamellSupportEmailUri(subject: 'SyrChat Control access'),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: const BorderSide(color: Tokens.lightInputBorder),
                    ),
                    icon: const Icon(Icons.mail_outline),
                    label: Text(
                      l.isArabic ? 'مراسلة الدعم' : 'Email support',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openSupportUri(shamellSupportPhoneUri()),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      side: const BorderSide(color: Tokens.lightInputBorder),
                    ),
                    icon: const Icon(Icons.call_outlined),
                    label: Text(
                      l.isArabic ? 'اتصال الدعم' : 'Call support',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            if (out.isNotEmpty) ...[
              const SizedBox(height: 18),
              StatusBanner.info(out, dense: true),
            ],
            const SizedBox(height: 22),
            const Divider(height: 1),
            const SizedBox(height: 18),
            detailsRow(
              icon: Icons.hub_outlined,
              label: l.isArabic ? 'خادم الـ API' : 'API origin',
              value: origin,
            ),
            const SizedBox(height: 16),
            detailsRow(
              icon: Icons.admin_panel_settings_outlined,
              label: l.isArabic ? 'التفويض' : 'Provisioning',
              value: l.isArabic
                  ? 'Superadmin فقط يمنح admin / ops / superadmin'
                  : 'Superadmin grants admin / ops / superadmin access',
            ),
            const SizedBox(height: 16),
            detailsRow(
              icon: Icons.support_agent_outlined,
              label: l.isArabic ? 'الدعم' : 'Support',
              value: '${kShamellSupportEmail}  •  ${kShamellSupportPhone}',
            ),
            const SizedBox(height: 18),
            Text(
              l.loginTerms,
              style: theme.textTheme.bodySmall?.copyWith(
                color: ShamellPalette.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Tokens.lightScaffold,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Tokens.lightSurfaceAlt, Tokens.lightScaffold],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1080;
              final shell = wide
                  ? Row(
                      children: [
                        Expanded(flex: 12, child: heroPanel()),
                        const SizedBox(width: 24),
                        Expanded(flex: 10, child: actionPanel()),
                      ],
                    )
                  : Column(
                      children: [
                        heroPanel(),
                        const SizedBox(height: 20),
                        actionPanel(),
                      ],
                    );
              return SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    child: shell,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final hasSession = widget.hasSession || _hasSessionCookie;
    final needsAuthAction =
        !hasSession && (!_isWebEnvironment || _usesUsernamePasswordAuth);

    if (_isWebEnvironment &&
        shamellIsRideOperatorSurface(widget.appSurface) &&
        !_usesUsernamePasswordAuth) {
      return _buildControlWebLogin(
        context: context,
        l: l,
        theme: theme,
        hasSession: hasSession,
      );
    }

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 12),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    shamellSurfaceAppTitle(
                      isArabic: l.isArabic,
                      surface: widget.appSurface,
                    ),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ShamellPalette.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    shamellSurfaceBrandIcon(widget.appSurface),
                    size: 32,
                    color: ShamellPalette.green,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l.loginTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .75),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (needsAuthAction) ...[
          _buildNativeSurfaceAuthCard(context: context, l: l, theme: theme),
          const SizedBox(height: 12),
        ],
        if (out.isNotEmpty) ...[
          const SizedBox(height: 12),
          StatusBanner.info(out, dense: true),
        ],
        const SizedBox(height: 16),
        Text(
          l.loginTerms,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .60),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const SizedBox.shrink(),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: content,
          ),
        ),
      ),
    );
  }
}
