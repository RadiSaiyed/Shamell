import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
// Offline features removed: no connectivity/offline queue
// import 'package:connectivity_plus/connectivity_plus.dart';
// import 'core/offline_queue.dart';
import 'package:app_links/app_links.dart';
// import 'package:workmanager/workmanager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/notification_service.dart';
import 'core/config.dart';
import 'core/gotify_client.dart';
import 'core/glass.dart';
import 'core/home_routes.dart';
import 'core/chat/threema_chat_page.dart';
import 'core/payments_multilevel.dart';
import 'core/taxi_multilevel.dart';
import 'core/food_multilevel.dart';
import 'core/stays_multilevel.dart';
import 'core/realestate_multilevel.dart';
import 'core/realestate_zillow.dart';
import 'core/bus_multilevel.dart';
import 'core/building_multilevel.dart';
import 'core/building_cubotoo.dart';
import 'core/carrental_modern.dart';
import 'core/equipment_rental.dart';
import 'core/equipment_ops_dashboard.dart';
import 'core/equipment_catalog.dart';
import 'core/driver_pod.dart';
import 'core/livestock_sellmylivestock.dart';
import 'core/pms_cloudbeds.dart';
import 'core/pos_glass.dart';
import 'core/courier_live.dart';
import 'core/courier_multilevel.dart';
import 'core/agriculture_multilevel.dart';
import 'core/cars_multilevel.dart';
import 'core/agri_fullharvest.dart';
import 'core/design_tokens.dart';
import 'core/offline_queue.dart';
import 'core/perf.dart';
import 'core/status_banner.dart';
import 'core/ui_kit.dart';
import 'core/l10n.dart';
import 'core/food_orders.dart';
import 'core/scan_page.dart';
import 'core/history_page.dart';
import 'core/format.dart';
import 'core/journey_page.dart';
import 'core/skeleton.dart';
import 'core/taxi/taxi_operator.dart';
import 'core/taxi/taxi_driver.dart';
import 'core/taxi/taxi_rider.dart';
import 'core/taxi/taxi_settings.dart';
import 'core/taxi/taxi_history.dart';
import 'core/onboarding.dart';
import 'core/payments_send.dart';
import 'core/payments_shell.dart';
import 'core/payments_requests.dart';
import 'core/doctors_doctolib.dart';
import 'core/doctors_admin.dart';
// no webviews; pure native app

// Offline background worker removed

enum AppMode { auto, user, operator, admin }

const String _appModeRaw =
    String.fromEnvironment('APP_MODE', defaultValue: 'auto');
const bool _envSkipLogin =
    bool.fromEnvironment('SKIP_LOGIN', defaultValue: false);
const String kSuperadminPhone = '+963996428955';

AppMode get currentAppMode {
  switch (_appModeRaw.toLowerCase()) {
    case 'auto':
      return AppMode.auto;
    case 'operator':
      return AppMode.operator;
    case 'admin':
      return AppMode.admin;
    default:
      return AppMode.user;
  }
}

String appModeLabel(AppMode mode) {
  switch (mode) {
    case AppMode.operator:
      return 'Operator';
    case AppMode.admin:
      return 'Admin';
    case AppMode.auto:
      return 'Hybrid';
    case AppMode.user:
      return 'User';
  }
}

IconData appModeIcon(AppMode mode) {
  switch (mode) {
    case AppMode.operator:
      return Icons.support_agent;
    case AppMode.admin:
      return Icons.admin_panel_settings;
    case AppMode.user:
      return Icons.person_outline;
    case AppMode.auto:
      return Icons.all_inclusive;
  }
}

class _RoleChip extends StatelessWidget {
  final AppMode mode;
  final AppMode current;
  final VoidCallback onTap;
  final bool enabled;
  const _RoleChip(
      {required this.mode,
      required this.current,
      required this.onTap,
      this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isSelected = mode == current;
    String label;
    if (l.isArabic) {
      switch (mode) {
        case AppMode.user:
          label = 'مستخدم';
          break;
        case AppMode.operator:
          label = 'مشغل';
          break;
        case AppMode.admin:
          label = 'مسؤول';
          break;
        case AppMode.auto:
          label = 'هجين';
          break;
      }
    } else {
      label = appModeLabel(mode);
    }
    final icon = appModeIcon(mode);
    final theme = Theme.of(context);
    final isDisabled = !enabled;
    // Distinct tint per mode when selected
    Color tint;
    switch (mode) {
      case AppMode.user:
        tint = Tokens.colorPayments; // green
        break;
      case AppMode.operator:
        tint = Tokens.colorBuildingMaterials; // brown for operators
        break;
      case AppMode.admin:
        tint = Tokens.colorHotelsStays; // indigo
        break;
      case AppMode.auto:
        tint = theme.colorScheme.primary;
        break;
    }
    final bg = isSelected
        ? tint.withValues(alpha: .18)
        : theme.colorScheme.surface.withValues(alpha: isDisabled ? .4 : .9);
    Color fg;
    if (isDisabled) {
      fg = theme.colorScheme.onSurface.withValues(alpha: .40);
    } else {
      fg = theme.brightness == Brightness.dark ? Colors.white : Colors.black87;
    }
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: isSelected ? tint : Colors.white24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
                Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: fg))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuperadminChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  const _SuperadminChip(
      {required this.selected, required this.onTap, this.enabled = true});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final label = l.isArabic ? 'سوبر مسؤول' : 'Superadmin';
    final isDisabled = !enabled;
    final Color tint = Tokens.accent;
    final bg = selected
        ? tint.withValues(alpha: .18)
        : (isDisabled ? Colors.white10.withValues(alpha: .4) : Colors.white10);
    final fg = isDisabled
        ? theme.colorScheme.onSurface.withValues(alpha: .40)
        : (theme.brightness == Brightness.dark ? Colors.white : Colors.black87);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? tint : Colors.white24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.security, size: 16),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverChip extends StatelessWidget {
  final VoidCallback onTap;
  final bool enabled;
  final bool selected;
  const _DriverChip(
      {required this.onTap, this.enabled = true, this.selected = false});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final label = l.isArabic ? 'سائق' : 'Driver';
    final icon = Icons.local_taxi;
    final isDisabled = !enabled;
    final bg = selected
        ? Tokens.colorTaxi.withValues(alpha: .18)
        : (isDisabled
            ? theme.colorScheme.surface.withValues(alpha: .4)
            : theme.colorScheme.surface.withValues(alpha: .9));
    final fg = isDisabled
        ? theme.colorScheme.onSurface.withValues(alpha: .40)
        : (theme.brightness == Brightness.dark ? Colors.white : Colors.black87);
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected ? Tokens.colorTaxi : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialised in background isolates
  try {
    await Firebase.initializeApp();
  } catch (_) {}
}

Future<void> _initPush() async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  try {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (_) {}
  try {
    final perm = await FirebaseMessaging.instance.requestPermission();
    if (perm.authorizationStatus == AuthorizationStatus.authorized ||
        perm.authorizationStatus == AuthorizationStatus.provisional) {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('fcm_token', token);
      }
    }
  } catch (_) {}
}

/// Launches a web URL and, for HTTP(S) endpoints, appends the current
/// Shamell session (`sa_session`) as query parameter when available.
///
/// This allows admin / superadmin web consoles to reuse the OTP login
/// from the Flutter app without relying on browser cookies.
Future<void> launchWithSession(Uri uri) async {
  try {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final cookie = await _getCookie();
      if (cookie != null && cookie.isNotEmpty) {
        String token = cookie;
        final m = RegExp(r'sa_session=([^;]+)').firstMatch(token);
        if (m != null && m.group(1) != null) {
          token = m.group(1)!;
        }
        if (token.isNotEmpty) {
          final qp = Map<String, String>.from(uri.queryParameters);
          qp.putIfAbsent('sa_session', () => token);
          uri = uri.replace(queryParameters: qp);
        }
      }
    }
  } catch (_) {
    // Fallback: ignore session wiring failures and just open the URL.
  }
  await launchUrl(uri);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initPush();
  // Offline background sync disabled
  try {
    await NotificationService.initialize();
    await NotificationService.requestAndroidPermission();
  } catch (_) {}
  try {
    await OfflineQueue.init();
  } catch (_) {}
  Perf.init();
  if (kPushProvider.toLowerCase() == 'gotify' ||
      kPushProvider.toLowerCase() == 'both') {
    try {
      await GotifyClient.start();
    } catch (_) {}
  }
  runApp(const SuperApp());
}

void showBackoff(BuildContext context, http.Response resp) {
  try {
    final j = jsonDecode(resp.body);
    final ms = (j['retry_after_ms'] ?? 0) as int;
    final reasons = (j['reasons'] ?? []).toString();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Backoff: ${(ms / 1000).toStringAsFixed(0)}s  reasons: $reasons')));
  } catch (_) {
    final ra = resp.headers['retry-after'] ?? '?';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Backoff: Retry-After=$ra')));
  }
}

bool _hasOpsRole(List<String> roles) {
  // Treat any operator_* role as ops-capable plus classic admin/seller/ops.
  if (roles.any((r) => r == 'admin' || r == 'seller' || r == 'ops')) {
    return true;
  }
  return roles.any((r) => r.startsWith('operator_'));
}

bool _hasSuperadminRole(List<String> roles) {
  // Treat high‑risk / platform‑level roles as superadmin
  const superRoles = ['seller', 'ops'];
  return roles.any((r) => superRoles.contains(r));
}

bool _hasAdminRole(List<String> roles) {
  // Admins plus all superadmins
  if (_hasSuperadminRole(roles)) return true;
  return roles.contains('admin');
}

bool _computeShowOps(List<String> roles, AppMode mode) {
  final hasOps = _hasOpsRole(roles);
  switch (mode) {
    case AppMode.auto:
      return hasOps;
    case AppMode.user:
      return false;
    case AppMode.operator:
    case AppMode.admin:
      return hasOps;
  }
}

bool _computeTaxiOnly(AppMode mode, List<String> operatorDomains) {
  if (mode != AppMode.operator) return false;
  if (operatorDomains.isEmpty) return false;
  // Taxi-only homescreen is only enabled when Taxi is the sole operator domain.
  return operatorDomains.contains('taxi') && operatorDomains.length == 1;
}

class SuperApp extends StatelessWidget {
  const SuperApp({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // Debug log to verify HomePage from this repo is running on device.
    debugPrint('HOME_PAGE_BUILD: Shamell');
    // Global pill-shaped buttons to match liquid glass UI.
    final baseBtnShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: Colors.white.withValues(alpha: .30)));
    const accentActive = Colors.white; // global text/icon color (pure white)
    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Tokens.primary,
        secondary: Tokens.accent,
        surface: Tokens.surface,
        onSurface: accentActive,
      ),
      textTheme: GoogleFonts.interTextTheme()
          .apply(bodyColor: accentActive, displayColor: accentActive),
      iconTheme: const IconThemeData(color: accentActive),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        elevation: 6,
        shadowColor: Colors.black87,
        backgroundColor: Tokens.primary,
        foregroundColor: accentActive,
        shape: baseBtnShape,
        minimumSize: const Size.fromHeight(48),
      )),
      filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor:
            WidgetStatePropertyAll(Colors.white.withValues(alpha: .10)),
        foregroundColor: const WidgetStatePropertyAll(accentActive),
        shape: WidgetStatePropertyAll(baseBtnShape),
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
        side: WidgetStatePropertyAll(
            BorderSide(color: Colors.white.withValues(alpha: .22))),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
        side: WidgetStatePropertyAll(
            BorderSide(color: Colors.white.withValues(alpha: .22))),
        foregroundColor: const WidgetStatePropertyAll(accentActive),
        backgroundColor:
            WidgetStatePropertyAll(Colors.white.withValues(alpha: .06)),
        shape: WidgetStatePropertyAll(baseBtnShape),
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Tokens.primary, width: 1.4)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Tokens.primary, width: 1.4)),
        focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: Tokens.primary, width: 2.0)),
        labelStyle: TextStyle(color: Tokens.onSurface.withValues(alpha: .92)),
        hintStyle: TextStyle(color: Tokens.onSurface.withValues(alpha: .72)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: .08),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Tokens.border)),
        elevation: 8,
        shadowColor: Colors.black87,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 18, color: accentActive),
        foregroundColor: accentActive,
        iconTheme: IconThemeData(color: accentActive),
        systemOverlayStyle: SystemUiOverlayStyle(
            statusBarBrightness: Brightness.dark,
            statusBarIconBrightness: Brightness.light,
            statusBarColor: Colors.transparent),
      ),
    );

    return MaterialApp(
      title: l.appTitle,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
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
      themeMode: ThemeMode.dark,
      theme: darkTheme,
      darkTheme: darkTheme,
      home: const LoginGate(),
    );
  }
}

// Optional wrapper to reduce background duplication (gradual adoption)
class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final bool extendBehindAppBar;
  const AppScaffold(
      {super.key,
      this.appBar,
      required this.body,
      this.extendBehindAppBar = true});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      extendBodyBehindAppBar: extendBehindAppBar,
      backgroundColor: Colors.transparent,
      body: Stack(children: [const AppBG(), SafeArea(child: body)]),
    );
  }
}

Future<String?> _getCookie() async {
  final sp = await SharedPreferences.getInstance();
  return sp.getString('sa_cookie');
}

Future<void> _setCookie(String v) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setString('sa_cookie', v);
}

Future<void> _clearCookie() async {
  final sp = await SharedPreferences.getInstance();
  await sp.remove('sa_cookie');
}

Future<Map<String, String>> _hdr({bool json = false}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final c = await _getCookie();
  if (c != null && c.isNotEmpty) {
    // Custom Header statt Cookie-Header, damit Web-Clients nicht
    // an Browser-Restriktionen scheitern.
    h['sa_cookie'] = c;
  }
  return h;
}

class LoginGate extends StatefulWidget {
  const LoginGate({super.key});
  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  String? _c;
  bool _skip = false;
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _c = await _getCookie();
    // In Hybrid (APP_MODE=auto), always show login; never skip.
    final defSkip = _envSkipLogin ||
        (currentAppMode != AppMode.auto &&
            (currentAppMode == AppMode.operator ||
                currentAppMode == AppMode.admin));
    bool skip = defSkip;
    bool requireBiometrics = false;
    try {
      final sp = await SharedPreferences.getInstance();
      skip = sp.getBool('skip_login') ?? defSkip;
      requireBiometrics = sp.getBool('require_biometrics') ?? false;
    } catch (_) {
      skip = defSkip;
    }
    // When a session cookie exists and the user has previously
    // completed OTP login on this device, optionally gate access
    // behind biometrics instead of auto-skipping the login screen.
    if (!kIsWeb &&
        requireBiometrics &&
        _c != null &&
        _c!.isNotEmpty &&
        (currentAppMode == AppMode.user ||
            currentAppMode == AppMode.operator ||
            currentAppMode == AppMode.admin)) {
      final ok = await _authenticateWithBiometrics();
      skip = ok;
    }
    if (!mounted) return;
    setState(() {
      _skip = skip;
    });
  }

  Future<bool> _authenticateWithBiometrics() async {
    try {
      final auth = LocalAuthentication();
      final canCheck =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canCheck) {
        // If the device no longer supports biometrics, fall back to
        // normal cookie-based auto-login.
        return true;
      }
      const reason = 'Authenticate to unlock Shamell';
      final didAuth = await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
        ),
      );
      return didAuth;
    } catch (_) {
      // Never hard-block login because of biometric errors.
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // In Hybrid mode always force explicit login first.
    if (currentAppMode == AppMode.auto) {
      return const LoginPage();
    }
    return (_skip || (_c != null && _c!.isNotEmpty))
        ? const HomePage()
        : const LoginPage();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final baseCtrl = TextEditingController(
    text: const String.fromEnvironment(
      'BASE_URL',
      defaultValue: 'http://localhost:8080',
    ),
  );
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String out = '';
  AppMode _loginMode = AppMode.user;
  bool _superadminLogin = false;
  bool _driverLogin = false;
  bool _canBiometricLogin = false;
  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  Future<void> _loadBase() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final b = sp.getString('base_url');
      if (b != null && b.isNotEmpty) {
        final v = b.trim();
        // Ignore legacy dev defaults so the new
        // monolith port (8080) is used automatically.
        if (!(v.contains('localhost:5003') || v.contains('127.0.0.1:5003'))) {
          baseCtrl.text = v;
        }
      }
      final lastPhone = sp.getString('last_login_phone');
      if (lastPhone != null && lastPhone.isNotEmpty) {
        phoneCtrl.text = lastPhone;
      }
      final lastName = sp.getString('last_login_name');
      if (lastName != null && lastName.isNotEmpty) {
        nameCtrl.text = lastName;
      }
      final requireBiometrics = sp.getBool('require_biometrics') ?? false;
      final cookie = await _getCookie();
      final hasCookie = cookie != null && cookie.isNotEmpty;
      final canBio = !kIsWeb && requireBiometrics && hasCookie;
      if (mounted) {
        setState(() {
          _canBiometricLogin = canBio;
        });
      }
    } catch (_) {}
  }

  Future<void> _request() async {
    setState(() => out = 'Requesting code…');
    final uri = Uri.parse('${baseCtrl.text.trim()}/auth/request_code');
    final resp = await http.post(uri,
        headers: await _hdr(json: true),
        body: jsonEncode({'phone': phoneCtrl.text.trim()}));
    try {
      final j = jsonDecode(resp.body);
      final code = (j['code'] ?? '').toString();
      codeCtrl.text = code;
      if (resp.statusCode == 200) {
        final ttl = j['ttl'];
        final ttlText = ttl is int ? 'Valid for ${(ttl / 60).round()} min' : '';
        setState(
            () => out = ttlText.isEmpty ? 'Code sent.' : 'Code sent. $ttlText');
        if (code.isNotEmpty && mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Demo OTP'),
              content: SelectableText(code,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('OTP copied')));
                  },
                  child: const Text('Copy'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _verify();
                  },
                  child: const Text('Auto verify'),
                ),
              ],
            ),
          );
        }
      } else if (resp.statusCode == 429) {
        // Freundliche Backoff-Anzeige (z.B. bei Rate-Limiting)
        showBackoff(context, resp);
        setState(() => out = 'Too many attempts. Please wait a moment.');
      } else {
        setState(() => out = 'Could not send code (${resp.statusCode}).');
      }
    } catch (_) {
      setState(() => out = 'Unexpected response (${resp.statusCode}).');
    }
  }

  Future<void> _verify() async {
    setState(() => out = 'Verifying…');
    final uri = Uri.parse('${baseCtrl.text.trim()}/auth/verify');
    final resp = await http.post(uri,
        headers: await _hdr(json: true),
        body: jsonEncode({
          'phone': phoneCtrl.text.trim(),
          'code': codeCtrl.text.trim(),
          'name': nameCtrl.text.trim(),
        }));
    // Prefer reading session ID from JSON body (for web):
    try {
      final j = jsonDecode(resp.body);
      final sess = (j['session'] ?? '').toString();
      if (sess.isNotEmpty) {
        await _setCookie('sa_session=$sess');
      }
    } catch (_) {
      // Fallback: Set-Cookie header (only works outside the browser)
      try {
        final sc = resp.headers['set-cookie'];
        if (sc != null) {
          final m = RegExp(r'sa_session=([^;]+)').firstMatch(sc);
          if (m != null) {
            await _setCookie('sa_session=${m.group(1)}');
          }
        }
      } catch (_) {}
    }
    if (resp.statusCode == 200) {
      setState(() => out = 'Signed in successfully.');
    } else if (resp.statusCode == 400) {
      setState(() => out = 'Invalid code. Please try again.');
    } else if (resp.statusCode == 429) {
      setState(() => out = 'Too many attempts. Please wait a moment.');
    } else {
      setState(() => out = 'Login failed (${resp.statusCode}).');
    }
    if (!mounted) return;
    if (resp.statusCode == 200) {
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('base_url', baseCtrl.text.trim());
        await sp.setString('last_login_phone', phoneCtrl.text.trim());
        await sp.setString('last_login_name', nameCtrl.text.trim());
        // Mark this device as eligible for biometric login
        // after the first successful OTP sign-in.
        await sp.setBool('require_biometrics', true);
      } catch (_) {}
      // Decide post-login destination based on selected login mode.
      await _handlePostLoginNavigation();
    }
  }

  Future<void> _loginWithBiometrics() async {
    if (kIsWeb) {
      setState(() => out = 'Biometric login is not available on web.');
      return;
    }
    setState(() => out = 'Authenticating…');
    try {
      final auth = LocalAuthentication();
      final canCheck =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canCheck) {
        setState(() =>
            out = 'Biometric authentication is not available on this device.');
        return;
      }
      const reason = 'Authenticate to unlock Shamell';
      final didAuth = await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
        ),
      );
      if (!didAuth) {
        setState(() => out = 'Authentication cancelled.');
        return;
      }
    } catch (e) {
      setState(() => out = 'Biometric authentication failed: $e');
      return;
    }
    // Reuse stored base URL and phone (if any) and continue
    // with the same post-login navigation as after OTP login.
    try {
      final sp = await SharedPreferences.getInstance();
      final b = sp.getString('base_url');
      final lastPhone = sp.getString('last_login_phone');
      if (b != null && b.isNotEmpty) {
        baseCtrl.text = b.trim();
      }
      if (lastPhone != null && lastPhone.isNotEmpty) {
        phoneCtrl.text = lastPhone;
      }
    } catch (_) {}
    await _handlePostLoginNavigation();
  }

  Future<void> _handlePostLoginNavigation() async {
    final base = baseCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    Map<String, dynamic>? snapshot;
    List<String> roles = const <String>[];
    List<String> opDomains = const <String>[];
    bool isSuper = false;
    bool isAdmin = false;

    Future<bool> _loadSnapshot() async {
      if (snapshot != null) return true;
      try {
        final uri = Uri.parse('$base/me/home_snapshot');
        final r = await http.get(uri, headers: await _hdr());
        if (r.statusCode == 404) {
          // Legacy BFF without /me/home_snapshot.
          return false;
        }
        if (r.statusCode != 200) {
          setState(() => out = 'Could not load profile (${r.statusCode}).');
          await _clearCookie();
          return false;
        }
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        snapshot = body;
        roles = (body['roles'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
        opDomains = (body['operator_domains'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        isSuper = (body['is_superadmin'] ?? false) == true ||
            (body['phone'] ?? '') == kSuperadminPhone;
        isAdmin = (body['is_admin'] ?? false) == true ||
            isSuper ||
            roles.contains('admin');
        return true;
      } catch (e) {
        setState(() => out = 'Error during profile lookup: $e');
        await _clearCookie();
        return false;
      }
    }

    // Superadmin phone: always allow direct Superadmin dashboard
    // (except in explicit driver login, where we honour driver mode).
    if (!_driverLogin &&
        phone == kSuperadminPhone &&
        _loginMode != AppMode.operator) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SuperadminDashboardPage(base)),
      );
      return;
    }

    // Driver login: require explicit driver role
    if (_driverLogin) {
      final ok = await _loadSnapshot();
      if (!ok) {
        // If snapshot unsupported, treat as error for driver login.
        return;
      }
      const driverRole = 'driver';
      if (!roles.contains(driverRole)) {
        setState(() => out =
            'This phone is not registered as a driver. Please contact an admin.');
        await _clearCookie();
        return;
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => TaxiDriverPage(base)),
      );
      return;
    }

    // For operator/admin modes, enforce that the phone has corresponding roles.
    if (_loginMode == AppMode.operator || _loginMode == AppMode.admin) {
      final ok = await _loadSnapshot();
      if (!ok) {
        // Legacy BFF without /me/home_snapshot: skip strict gating but still
        // route into the respective dashboards. Server-side guards remain.
        if (_loginMode == AppMode.operator) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => OperatorDashboardPage(base)),
          );
          return;
        }
        if (_loginMode == AppMode.admin) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => AdminDashboardPage(base)),
          );
          return;
        }
      }
      if (_loginMode == AppMode.operator) {
        if (opDomains.isEmpty && !isAdmin) {
          setState(() => out =
              'This phone is not registered as an operator. Please contact an admin.');
          await _clearCookie();
          return;
        }
        if (!mounted) return;
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  OperatorDashboardPage(base, operatorDomains: opDomains),
            ));
        return;
      }

      if (_loginMode == AppMode.admin) {
        if (!isAdmin) {
          setState(() => out =
              'This phone is not registered as an admin. Please contact a superadmin.');
          await _clearCookie();
          return;
        }
        if (!mounted) return;
        Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AdminDashboardPage(base),
            ));
        return;
      }
    }

    // Default: end-user app home.
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => HomePage(
          lockedMode: _loginMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.appTitle,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF4D7C0F), // olive green
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.all_inclusive,
                size: 36,
                color: Color(0xFF4D7C0F), // olive green
              ),
            ],
          ),
        ),
        Text(
          l.loginTitle,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: baseCtrl,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: l.isArabic ? 'عنوان الخادم' : 'Server URL',
            prefixIcon: const Icon(Icons.dns_outlined),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _RoleChip(
              mode: AppMode.user,
              current: _driverLogin ? AppMode.operator : _loginMode,
              onTap: () {
                setState(() {
                  _loginMode = AppMode.user;
                  _superadminLogin = false;
                  _driverLogin = false;
                });
              },
            ),
            const SizedBox(width: 8),
            _DriverChip(
              onTap: () {
                setState(() {
                  _loginMode = AppMode.user;
                  _superadminLogin = false;
                  _driverLogin = true;
                });
              },
              selected: _driverLogin,
            ),
            const SizedBox(width: 8),
            _RoleChip(
              mode: AppMode.operator,
              current: _loginMode,
              onTap: () {
                setState(() {
                  _loginMode = AppMode.operator;
                  _superadminLogin = false;
                  _driverLogin = false;
                });
              },
            ),
            const SizedBox(width: 8),
            _RoleChip(
              mode: AppMode.admin,
              current: _superadminLogin ? AppMode.user : _loginMode,
              onTap: () {
                setState(() {
                  _loginMode = AppMode.admin;
                  _superadminLogin = false;
                  _driverLogin = false;
                });
              },
            ),
            const SizedBox(width: 8),
            _SuperadminChip(
              selected: _superadminLogin,
              onTap: () {
                setState(() {
                  _loginMode = AppMode.admin;
                  _superadminLogin = true;
                  _driverLogin = false;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: nameCtrl,
          keyboardType: TextInputType.name,
          decoration: InputDecoration(
            labelText: l.loginFullName,
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: l.loginPhone,
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 12),
        WaterButton(
          icon: Icons.lock_open_outlined,
          label: l.loginRequestCode,
          onTap: _request,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: codeCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: l.loginCodeLabel,
            prefixIcon: const Icon(Icons.verified_user_outlined),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _verify,
          icon: const Icon(Icons.login),
          label: Text(l.loginVerify),
        ),
        if (_canBiometricLogin) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _loginWithBiometrics,
            icon: const Icon(Icons.fingerprint),
            label: Text(
              l.isArabic ? 'تسجيل الدخول بالبصمة' : 'Login with biometrics',
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (out.isNotEmpty) StatusBanner.info(out, dense: true),
        const SizedBox(height: 16),
        Text(
          l.loginNoteDemo,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .70),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
    const bg = AppBG();
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const SizedBox.shrink(),
      ),
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          bg,
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: GlassPanel(
                    padding: const EdgeInsets.all(16),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final AppMode lockedMode;
  const HomePage({super.key, this.lockedMode = AppMode.auto});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _baseUrl = const String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  String _walletId = '';
  int? _walletBalanceCents;
  String _walletCurrency = 'SYP';
  bool _walletHidden = false;
  bool _walletLoading = false;
  final deviceId = _randId();
  String _uiRoute = const String.fromEnvironment('UI_ROUTE', defaultValue: 'A');
  Timer? _flushTimer;
  bool _showOps = false;
  bool _showSuperadmin = false;
  List<String> _roles = const [];
  List<String> _operatorDomains = const [];
  bool _taxiOnly = false; // Show all apps by default
  AppMode _appMode = currentAppMode;
  // Bus admin summary for quick dashboard
  int? _busTripsToday;
  int? _busBookingsToday;
  int? _busRevenueTodayCents;
  // Taxi admin summary for quick dashboard
  int? _taxiRidesToday;
  int? _taxiCompletedToday;
  int? _taxiRevenueTodayCents;

  static String _randId() {
    const chars = 'abcdef0123456789';
    final r = Random();
    return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.appTitle),
            const SizedBox(width: 8),
            _ModePill(mode: _appMode),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _openOnboarding,
            tooltip: l.isArabic ? 'مساعدة' : 'Help & onboarding',
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            onPressed: _openUserMenu,
            tooltip: l.menuProfile,
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: Stack(
        children: [
          const AppBG(),
          SafeArea(
            child: Column(
              children: [
                if (_showSuperadmin)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Builder(builder: (context) {
                      final hasOps = _hasOpsRole(_roles);
                      final hasAdmin = _hasAdminRole(_roles);
                      final isSuper = _showSuperadmin;
                      final allowSwitch = isSuper;
                      return Row(
                        children: [
                          _RoleChip(
                            mode: AppMode.user,
                            current: _appMode,
                            onTap: () => _changeAppMode(AppMode.user),
                            enabled: allowSwitch || _appMode == AppMode.user,
                          ),
                          const SizedBox(width: 8),
                          _DriverChip(
                            onTap: () {
                              _navPush(TaxiDriverPage(_baseUrl));
                            },
                            enabled: allowSwitch,
                          ),
                          const SizedBox(width: 8),
                          _RoleChip(
                            mode: AppMode.operator,
                            current: _appMode,
                            onTap: () => _changeAppMode(AppMode.operator),
                            enabled: allowSwitch && hasOps,
                          ),
                          const SizedBox(width: 8),
                          _RoleChip(
                            mode: AppMode.admin,
                            current: _appMode,
                            onTap: () => _changeAppMode(AppMode.admin),
                            enabled: allowSwitch && hasAdmin,
                          ),
                          const SizedBox(width: 8),
                          _SuperadminChip(
                            selected: isSuper && _appMode == AppMode.admin,
                            enabled: allowSwitch && isSuper,
                            onTap: () {
                              if (!isSuper || !allowSwitch) return;
                              _changeAppMode(AppMode.admin);
                            },
                          ),
                        ],
                      );
                    }),
                  ),
                if ((_appMode == AppMode.operator ||
                        _appMode == AppMode.admin) &&
                    _taxiRidesToday != null &&
                    _taxiRevenueTodayCents != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: GlassPanel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.local_taxi_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(L10n.of(context).taxiTodayTitle,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                  '${_taxiRidesToday ?? 0} ${L10n.of(context).ridesLabel} · ${_taxiCompletedToday ?? 0} ${L10n.of(context).completedLabel} · ${fmtCents(_taxiRevenueTodayCents!)} SYP',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Open Taxi Admin',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () {
                              launchWithSession(
                                  Uri.parse('$_baseUrl/taxi/admin'));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                if ((_appMode == AppMode.operator ||
                        _appMode == AppMode.admin) &&
                    _busTripsToday != null &&
                    _busRevenueTodayCents != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: GlassPanel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.directions_bus_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(L10n.of(context).busTodayTitle,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                  '${_busTripsToday ?? 0} ${L10n.of(context).tripsLabel} · ${_busBookingsToday ?? 0} ${L10n.of(context).bookingsLabel} · ${fmtCents(_busRevenueTodayCents!)} SYP',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Open Bus Control',
                            icon: const Icon(Icons.open_in_new),
                            onPressed: () {
                              _navPush(BusControlPage(_baseUrl));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_walletId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: GlassPanel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_wallet_outlined),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _appMode == AppMode.operator
                                      ? (L10n.of(context).isArabic
                                          ? 'محفظة المشغل'
                                          : 'Operator wallet')
                                      : L10n.of(context).homeWallet,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _walletHidden
                                      ? '••••••'
                                      : (_walletBalanceCents == null
                                          ? (_walletLoading
                                              ? (L10n.of(context).isArabic
                                                  ? 'جارٍ التحميل…'
                                                  : 'Loading…')
                                              : (L10n.of(context).isArabic
                                                  ? 'الرصيد غير متاح'
                                                  : 'Balance unavailable'))
                                          : '${fmtCents(_walletBalanceCents!)} $_walletCurrency'),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip:
                                _walletHidden ? 'Show balance' : 'Hide balance',
                            icon: Icon(_walletHidden
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () {
                              setState(() => _walletHidden = !_walletHidden);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(child: _buildHomeRoute()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openOnboarding() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OnboardingPage()),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // offline sync timer disabled
    _setupLinks();
    _flushTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      await OfflineQueue.flush();
    });
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    final storedRoles = sp.getStringList('roles') ?? const [];
    final storedOpDomains = sp.getStringList('operator_domains') ?? const [];
    final storedMode = sp.getString('app_mode');
    final storedPhone = sp.getString('phone') ?? '';
    final storedIsSuper = sp.getBool('is_superadmin') ?? false;
    // Start from lockedMode when provided; otherwise from currentAppMode and prefs.
    AppMode appMode =
        widget.lockedMode == AppMode.auto ? currentAppMode : widget.lockedMode;
    if (widget.lockedMode == AppMode.auto &&
        storedMode != null &&
        storedMode.isNotEmpty) {
      switch (storedMode.toLowerCase()) {
        case 'user':
          appMode = AppMode.user;
          break;
        case 'operator':
          appMode = AppMode.operator;
          break;
        case 'admin':
          appMode = AppMode.admin;
          break;
        case 'auto':
        default:
          appMode = AppMode.auto;
      }
    }
    final baseShowOps = _computeShowOps(storedRoles, appMode);
    final showSuper = storedIsSuper || storedPhone == kSuperadminPhone;
    final showOps = baseShowOps || showSuper;
    setState(() {
      _baseUrl = sp.getString('base_url') ?? _baseUrl;
      _walletId = sp.getString('wallet_id') ?? _walletId;
      _uiRoute = sp.getString('ui_route') ?? _uiRoute;
      _roles = storedRoles;
      _operatorDomains = storedOpDomains;
      _appMode = appMode;
      _showOps = showOps;
      _showSuperadmin = showSuper;
      _taxiOnly = _computeTaxiOnly(appMode, storedOpDomains);
    });
    // Configure remote metrics after loading prefs
    final metricsRemote = sp.getBool('metrics_remote') ?? false;
    Perf.configure(
        baseUrl: _baseUrl, deviceId: deviceId, remote: metricsRemote);
    // 1) Optional: Cached Snapshot aus vorheriger Session anwenden, damit Home
    //    sofort etwas sinnvolles anzeigt, auch bevor das Netz greift.
    try {
      final cachedRaw = sp.getString('home_snapshot');
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        final cached = jsonDecode(cachedRaw) as Map<String, dynamic>;
        await _applyHomeSnapshot(cached, sp, appMode, persist: false);
      }
    } catch (_) {}
    // ensure Wallet/Rollen + erste KPIs via Aggregat-Endpunkt (idempotent)
    try {
      final r = await http.get(Uri.parse('$_baseUrl/me/home_snapshot'),
          headers: await _hdr());
      if (r.statusCode == 200) {
        Perf.action('home_snapshot_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        await sp.setString('home_snapshot', r.body);
        await _applyHomeSnapshot(j, sp, appMode, persist: true);
      } else {
        Perf.action('home_snapshot_fail');
      }
    } catch (_) {
      Perf.action('home_snapshot_error');
    }
    // Fallback: explizit Rollen laden, falls Aggregat leer war
    if (_roles.isEmpty) {
      await _loadRoles();
    }
    if (_walletId.isNotEmpty) {
      await _loadWalletSummary();
    }
    // Load KPIs for dashboard when in operator/admin mode
    if (_appMode == AppMode.operator || _appMode == AppMode.admin) {
      unawaited(_loadBusSummary());
      unawaited(_loadTaxiSummary());
    }
  }

  Future<void> _applyHomeSnapshot(
    Map<String, dynamic> j,
    SharedPreferences sp,
    AppMode appMode, {
    required bool persist,
  }) async {
    final phone = (j['phone'] ?? '').toString();
    final isSuperFlag = (j['is_superadmin'] ?? false) == true;
    if (persist) {
      if (phone.isNotEmpty) {
        await sp.setString('phone', phone);
      }
      await sp.setBool('is_superadmin', isSuperFlag);
    }
    final w = (j['wallet_id'] ?? '').toString();
    final rolesFromOverview =
        (j['roles'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final opDomainsFromOverview =
        (j['operator_domains'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    if (w.isNotEmpty) {
      if (persist) {
        await sp.setString('wallet_id', w);
      }
      if (mounted) {
        setState(() {
          _walletId = w;
        });
      }
    }
    if (rolesFromOverview.isNotEmpty) {
      if (persist) {
        await sp.setStringList('roles', rolesFromOverview);
        await sp.setStringList('operator_domains', opDomainsFromOverview);
      }
      final baseShowOps = _computeShowOps(rolesFromOverview, appMode);
      final showSuper = isSuperFlag || phone == kSuperadminPhone;
      final showOps = baseShowOps || showSuper;
      if (mounted) {
        setState(() {
          _roles = rolesFromOverview;
          _operatorDomains = opDomainsFromOverview;
          _showOps = showOps;
          _showSuperadmin = showSuper;
          _taxiOnly = _computeTaxiOnly(appMode, opDomainsFromOverview);
        });
      }
    } else {
      // Even without explicit roles, a flagged Superadmin should see Ops/Superadmin UI.
      final showSuper = isSuperFlag || phone == kSuperadminPhone;
      final showOps = showSuper;
      if (mounted) {
        setState(() {
          _showOps = showOps;
          _showSuperadmin = showSuper;
        });
      }
    }
    // Optional: hydrate initial Bus/Taxi KPIs from the snapshot
    try {
      final bs = j['bus_admin_summary'];
      if (bs is Map<String, dynamic>) {
        final trips = bs['trips_today'] ?? 0;
        final bookings = bs['bookings_today'] ?? 0;
        final revenueC = bs['revenue_cents_today'] ?? 0;
        final revInt =
            revenueC is int ? revenueC : int.tryParse(revenueC.toString()) ?? 0;
        if (mounted) {
          setState(() {
            _busTripsToday =
                trips is int ? trips : int.tryParse(trips.toString()) ?? 0;
            _busBookingsToday = bookings is int
                ? bookings
                : int.tryParse(bookings.toString()) ?? 0;
            _busRevenueTodayCents = revInt;
          });
        }
      }
    } catch (_) {}
    try {
      final ts = j['taxi_admin_summary'];
      if (ts is Map<String, dynamic>) {
        final ridesToday = ts['rides_today'] ?? 0;
        final completed = ts['rides_completed_today'] ?? 0;
        final fareC = ts['total_fare_cents_today'] ?? 0;
        final fareInt =
            fareC is int ? fareC : int.tryParse(fareC.toString()) ?? 0;
        if (mounted) {
          setState(() {
            _taxiRidesToday = ridesToday is int
                ? ridesToday
                : int.tryParse(ridesToday.toString()) ?? 0;
            _taxiCompletedToday = completed is int
                ? completed
                : int.tryParse(completed.toString()) ?? 0;
            _taxiRevenueTodayCents = fareInt;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _linksSub?.cancel();
    _flushTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadWalletSummary() async {
    if (_walletId.isEmpty) return;
    setState(() => _walletLoading = true);
    try {
      // Konsistente Nutzung des Wallet-Snapshots wie in den
      // Payments-Ansichten, um Serverlogik zentral zu halten.
      final uri = Uri.parse('$_baseUrl/wallets/' +
              Uri.encodeComponent(_walletId) +
              '/snapshot')
          .replace(queryParameters: const {'limit': '1'});
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        Perf.action('wallet_snapshot_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final w = j['wallet'];
        if (w is Map<String, dynamic>) {
          final cents = (w['balance_cents'] ?? 0) as int;
          final cur = (w['currency'] ?? 'SYP').toString();
          if (mounted) {
            setState(() {
              _walletBalanceCents = cents;
              _walletCurrency = cur;
            });
          }
        }
      } else {
        Perf.action('wallet_snapshot_fail');
      }
    } catch (_) {
      Perf.action('wallet_snapshot_error');
    }
    if (mounted) {
      setState(() => _walletLoading = false);
    }
  }

  Future<void> _loadBusSummary() async {
    try {
      final uri = Uri.parse('$_baseUrl/bus/admin/summary');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final trips = j['trips_today'] ?? 0;
        final bookings = j['bookings_today'] ?? 0;
        final revenueC = j['revenue_cents_today'] ?? 0;
        final revInt =
            revenueC is int ? revenueC : int.tryParse(revenueC.toString()) ?? 0;
        if (mounted) {
          setState(() {
            _busTripsToday =
                trips is int ? trips : int.tryParse(trips.toString()) ?? 0;
            _busBookingsToday = bookings is int
                ? bookings
                : int.tryParse(bookings.toString()) ?? 0;
            _busRevenueTodayCents = revInt;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadTaxiSummary() async {
    try {
      final uri = Uri.parse('$_baseUrl/taxi/admin/summary_cached');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final ridesToday = j['rides_today'] ?? 0;
        final completed = j['rides_completed_today'] ?? 0;
        final fareC = j['total_fare_cents_today'] ?? 0;
        final fareInt =
            fareC is int ? fareC : int.tryParse(fareC.toString()) ?? 0;
        if (mounted) {
          setState(() {
            _taxiRidesToday = ridesToday is int
                ? ridesToday
                : int.tryParse(ridesToday.toString()) ?? 0;
            _taxiCompletedToday = completed is int
                ? completed
                : int.tryParse(completed.toString()) ?? 0;
            _taxiRevenueTodayCents = fareInt;
          });
        }
      }
    } catch (_) {}
  }

  Widget _buildHomeRoute() {
    final actions = HomeActions(
      onScanPay: _quickScanPay,
      onTopup: _quickTopup,
      onSonic: () => _navPush(SonicPayPage(_baseUrl)),
      onP2P: _quickP2P,
      onMobility: () => _navPush(JourneyPage(_baseUrl)),
      onTaxiRider: () => _navPush(TaxiRiderPage(_baseUrl)),
      onTaxiDriver: () => _navPush(TaxiDriverPage(_baseUrl)),
      onTaxiOperator: () => _navPush(TaxiOperatorPage(_baseUrl)),
      onBusOperator: () => _navPush(BusOperatorPage(_baseUrl)),
      onBusControl: () => _navPush(BusControlPage(_baseUrl)),
      onOps: () => _navPush(OpsPage(_baseUrl)),
      onFood: () => _navPush(FoodPage(_baseUrl)),
      onBills: () => _navPush(PaymentsPage(_baseUrl, _walletId, deviceId)),
      onWallet: () =>
          _navPush(HistoryPage(baseUrl: _baseUrl, walletId: _walletId)),
      onHistory: () =>
          _navPush(HistoryPage(baseUrl: _baseUrl, walletId: _walletId)),
      onStays: () => _navPush(StaysPage(_baseUrl)),
      onStaysHotel: () => _navPush(PmsGlassPage(_baseUrl)),
      onStaysPro: () => _navPush(PmsGlassPage(_baseUrl)),
      onCarmarket: () => _navPush(CarmarketPage(_baseUrl)),
      onCarrental: () => _navPush(CarrentalModernPage(_baseUrl)),
      onEquipment: () => _navPush(EquipmentCatalogPage(baseUrl: _baseUrl, walletId: _walletId)),
      onRealestate: () => _navPush(RealEstateEnduser(baseUrl: _baseUrl)),
      onCourier: () => _navPush(CourierMultiLevelPage(baseUrl: _baseUrl)),
      onFreight: () => _navPush(FreightPage(_baseUrl)),
      onBus: () => _navPush(BusBookPage(_baseUrl)),
      onChat: () => _navPush(ThreemaChatPage(baseUrl: _baseUrl)),
      onDoctors: () => _navPush(DoctorsDoctolibPage(baseUrl: _baseUrl)),
      onFlights: () =>
          _navPush(ModuleHealthPage(_baseUrl, 'Flights', '/flights/health')),
      onJobs: () =>
          _navPush(ModuleHealthPage(_baseUrl, 'Jobs', '/jobs/health')),
      onAgriculture: () =>
          _navPush(AgriMarketplacePage(baseUrl: _baseUrl)),
      onLivestock: () =>
          _navPush(LivestockMarketplacePage(baseUrl: _baseUrl)),
      onCommerce: () =>
          _navPush(ModuleHealthPage(_baseUrl, 'Commerce', '/commerce/health')),
      onMerchantPOS: () => _navPush(PosGlassPage(_baseUrl)),
      onTira: () => _navPush(CourierLivePage(_baseUrl)),
      // Inventory view
      onVouchers: () => _navPush(CashMandatePage(_baseUrl)),
      onRequests: () =>
          _navPush(RequestsPage(baseUrl: _baseUrl, walletId: _walletId)),
      onFoodOrders: () => _navPush(FoodOrdersPage(_baseUrl)),
      onBuildingMaterials: () =>
          _navPush(BuildingCubotooPage(baseUrl: _baseUrl)),
    );
    final child = switch (_uiRoute.toUpperCase()) {
      'GRID' => HomeRouteGrid(
          actions: actions,
          showOps: _showOps,
          showSuperadmin: _showSuperadmin,
          taxiOnly: _taxiOnly,
          operatorDomains: _operatorDomains),
      'A' => HomeRouteGrid(
          actions: actions,
          showOps: _showOps,
          showSuperadmin: _showSuperadmin,
          taxiOnly: _taxiOnly,
          operatorDomains: _operatorDomains),
      'B' => HomeRoutePalette(
          actions: actions,
          showTaxiOperator:
              _operatorDomains.contains('taxi') && _appMode != AppMode.user,
        ),
      'C' => HomeRouteSheets(
          actions: actions,
          showTaxiOperator:
              _operatorDomains.contains('taxi') && _appMode != AppMode.user,
        ),
      'HUB' => HomeRouteHub(
          actions: actions,
          showOps: _showOps,
          showSuperadmin: _showSuperadmin,
          taxiOnly: _taxiOnly),
      _ => HomeRouteGrid(
          actions: actions,
          showOps: _showOps,
          showSuperadmin: _showSuperadmin,
          taxiOnly: _taxiOnly,
          operatorDomains: _operatorDomains),
    };
    return AnimatedSwitcher(
        duration: Tokens.motionBase,
        child: KeyedSubtree(key: ValueKey(_uiRoute), child: child));
  }

  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linksSub;
  Future<void> _setupLinks() async {
    try {
      _appLinks = AppLinks();
      final uri = await _appLinks!.getInitialLink();
      if (uri != null) {
        _handleUri(uri);
      }
      _linksSub = _appLinks!.uriLinkStream.listen((uri) {
        if (uri != null) {
          _handleUri(uri);
        }
      });
    } catch (_) {}
  }

  void _handleUri(Uri uri) {
    try {
      String? mod = uri.queryParameters['mod'];
      if (mod == null) {
        final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) mod = segs.last;
      }
      // offline sync removed; ignore syncnow
      if (mod == null) return;
      _openMod(mod.toLowerCase());
    } catch (_) {}
  }

  void _openUserMenu() {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final l = L10n.of(context);
          final items = <_MenuItem>[
            _MenuItem(
              icon: Icons.person_outline,
              label: l.menuProfile,
              onTap: () {
                Navigator.pop(ctx);
                _navPush(ProfilePage(_baseUrl));
              },
            ),
            _MenuItem(
              icon: Icons.local_taxi,
              label: l.menuTrips,
              onTap: () {
                Navigator.pop(ctx);
                _navPush(TaxiHistoryPage(_baseUrl));
              },
            ),
            _MenuItem(
              icon: Icons.account_tree_outlined,
              label: l.menuRoles,
              onTap: () {
                Navigator.pop(ctx);
                _navPush(const RolesInfoPage());
              },
            ),
            _MenuItem(
              icon: Icons.shield_outlined,
              label: l.menuEmergency,
              onTap: () {
                Navigator.pop(ctx);
                _showEmergency();
              },
            ),
            _MenuItem(
              icon: Icons.report_problem_outlined,
              label: l.menuComplaints,
              onTap: () {
                Navigator.pop(ctx);
                _showComplaints();
              },
            ),
            _MenuItem(
              icon: Icons.call_outlined,
              label: l.menuCallUs,
              onTap: () {
                Navigator.pop(ctx);
                _callUs();
              },
            ),
            if (_hasOpsRole(_roles))
              _MenuItem(
                icon: Icons.layers_outlined,
                label: l.menuSwitchMode,
                onTap: () {
                  Navigator.pop(ctx);
                  _showModeSheet();
                },
              ),
            if (_hasOpsRole(_roles))
              _MenuItem(
                icon: Icons.dashboard_customize_outlined,
                label: l.menuOperatorConsole,
                onTap: () {
                  Navigator.pop(ctx);
                  _navPush(OperatorDashboardPage(_baseUrl));
                },
              ),
            if (_hasAdminRole(_roles))
              _MenuItem(
                icon: Icons.admin_panel_settings_outlined,
                label: l.menuAdminConsole,
                onTap: () {
                  Navigator.pop(ctx);
                  _navPush(AdminDashboardPage(_baseUrl));
                },
              ),
            if (_showSuperadmin)
              _MenuItem(
                icon: Icons.security,
                label: l.menuSuperadminConsole,
                onTap: () {
                  Navigator.pop(ctx);
                  _navPush(SuperadminDashboardPage(_baseUrl));
                },
              ),
          ];
          return GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                  color: Colors.black54,
                  child: GestureDetector(
                      onTap: () {},
                      child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                              decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surface
                                      .withValues(alpha: .98),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(16))),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 16),
                              child: SafeArea(
                                  top: false,
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                            height: 4,
                                            width: 44,
                                            margin: const EdgeInsets.only(
                                                bottom: 8),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                                color: Colors.white24,
                                                borderRadius:
                                                    BorderRadius.circular(4))),
                                        ...items
                                            .map((m) => ListTile(
                                                leading: Icon(m.icon),
                                                title: Text(m.label),
                                                onTap: m.onTap))
                                            .toList(),
                                        const Divider(height: 12),
                                        ListTile(
                                          leading: const Icon(Icons.logout),
                                          title: Text(l.menuLogout),
                                          onTap: () {
                                            Navigator.pop(ctx);
                                            _logout();
                                          },
                                        ),
                                      ])))))));
        });
  }

  void _showEmergency() {
    showDialog(
        context: context,
        builder: (_) {
          final l = L10n.of(context);
          return AlertDialog(
            title: Text(l.emergencyTitle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                  leading: const Icon(Icons.local_police_outlined),
                  title: Text(l.emergencyPolice),
                  subtitle: const Text('112'),
                  onTap: () {
                    launchUrl(Uri.parse('tel:112'));
                    Navigator.pop(context);
                  }),
              ListTile(
                  leading: const Icon(Icons.local_hospital_outlined),
                  title: Text(l.emergencyAmbulance),
                  subtitle: const Text('110'),
                  onTap: () {
                    launchUrl(Uri.parse('tel:110'));
                    Navigator.pop(context);
                  }),
              ListTile(
                  leading: const Icon(Icons.local_fire_department_outlined),
                  title: Text(l.emergencyFire),
                  subtitle: const Text('113'),
                  onTap: () {
                    launchUrl(Uri.parse('tel:113'));
                    Navigator.pop(context);
                  }),
            ]),
          );
        });
  }

  void _showComplaints() {
    showDialog(
        context: context,
        builder: (_) {
          final l = L10n.of(context);
          return AlertDialog(
            title: Text(l.complaintsTitle),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Email: radisaiyed@icloud.com'),
              const SizedBox(height: 8),
              FilledButton(
                  onPressed: () {
                    launchUrl(Uri.parse(
                        'mailto:radisaiyed@icloud.com?subject=Complaint'));
                    Navigator.pop(context);
                  },
                  child: Text(l.complaintsEmailUs)),
            ]),
          );
        });
  }

  void _callUs() {
    try {
      launchUrl(Uri.parse('tel:+963996428955'));
    } catch (_) {}
  }
  // NOTE: support call number aligned with current superadmin phone.

  Future<void> _loadRoles() async {
    try {
      final r = await http.get(Uri.parse('$_baseUrl/me/roles'),
          headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final phone = (j['phone'] ?? '').toString();
        final roles =
            (j['roles'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        final sp = await SharedPreferences.getInstance();
        await sp.setStringList('roles', roles);
        if (phone.isNotEmpty) {
          await sp.setString('phone', phone);
        }
        final storedIsSuper = sp.getBool('is_superadmin') ?? false;
        if (mounted) {
          final baseShowOps = _computeShowOps(roles, _appMode);
          final showSuper = storedIsSuper || phone == kSuperadminPhone;
          final showOps = baseShowOps || showSuper;
          setState(() {
            _roles = roles;
            _showOps = showOps;
            _showSuperadmin = showSuper;
          });
        }
      }
    } catch (_) {}
  }

  void _openMod(String mod) {
    switch (mod) {
      case 'payments':
      case 'alias':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PaymentsPage(_baseUrl, _walletId, deviceId)));
        break;
      case 'merchant':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PaymentsPage(_baseUrl, _walletId, deviceId)));
        break;
      case 'taxi_driver':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TaxiDriverPage(_baseUrl)));
        break;
      case 'taxi_rider':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TaxiRiderPage(_baseUrl)));
        break;
      case 'food':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => FoodPage(_baseUrl)));
        break;
      case 'carmarket':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => CarmarketPage(_baseUrl)));
        break;
      case 'carrental':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => CarrentalModernPage(_baseUrl)));
        break;
      case 'realestate':
        Navigator.push(context,
            MaterialPageRoute(
                builder: (_) => RealEstateEnduser(baseUrl: _baseUrl)));
        break;
      case 'stays':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => StaysPage(_baseUrl)));
        break;
      case 'stays_hotel':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => PmsGlassPage(_baseUrl)));
        break;
      case 'freight':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => FreightPage(_baseUrl)));
        break;
      case 'chat':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => ThreemaChatPage(baseUrl: _baseUrl)));
        break;
      case 'doctors':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    DoctorsDoctolibPage(baseUrl: _baseUrl)));
        break;
      case 'flights':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    ModuleHealthPage(_baseUrl, 'Flights', '/flights/health')));
        break;
      case 'jobs':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    ModuleHealthPage(_baseUrl, 'Jobs', '/jobs/health')));
        break;
      case 'bus':
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => BusBookPage(_baseUrl)));
        break;
      case 'agriculture':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ModuleHealthPage(
                    _baseUrl, 'Agri Marketplace', '/agriculture/health')));
        break;
      case 'commerce':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ModuleHealthPage(
                    _baseUrl, 'Commerce', '/commerce/health')));
        break;
      case 'livestock':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ModuleHealthPage(
                    _baseUrl, 'Livestock', '/livestock/health')));
        break;
      default:
        break;
    }
  }

  void _quickScanPay() {
    _navPush(
        PaymentsPage(_baseUrl, _walletId, deviceId, triggerScanOnOpen: true));
  }

  void _quickTopup() {
    _navPush(TopupPage(_baseUrl, triggerScanOnOpen: true));
  }

  void _quickP2P() {
    _navPush(PaymentsPage(_baseUrl, _walletId, deviceId));
  }

  void _navPush(Widget page) {
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
            child: page),
      ),
    ));
  }

  Future<void> _logout() async {
    try {
      final cookie = await _getCookie();
      await _clearCookie();
      final uri = Uri.parse('$_baseUrl/auth/logout');
      await http.post(uri, headers: {'Cookie': cookie ?? ''});
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const LoginPage()));
  }

  // removed duplicate dispose; handled earlier for timers

  Future<void> _changeAppMode(AppMode mode) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        'app_mode',
        switch (mode) {
          AppMode.user => 'user',
          AppMode.operator => 'operator',
          AppMode.admin => 'admin',
          AppMode.auto => 'auto',
        });
    if (!mounted) return;
    setState(() {
      _appMode = mode;
      _taxiOnly = _computeTaxiOnly(_appMode, _operatorDomains);
      _showOps = _computeShowOps(_roles, _appMode);
    });
  }

  void _showModeSheet() {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final modes = <AppMode>[
            AppMode.user,
            AppMode.operator,
            AppMode.admin
          ];
          return GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                  color: Colors.black54,
                  child: GestureDetector(
                      onTap: () {},
                      child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                              decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surface
                                      .withValues(alpha: .98),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(16))),
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 16),
                              child: SafeArea(
                                  top: false,
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                            height: 4,
                                            width: 44,
                                            margin: const EdgeInsets.only(
                                                bottom: 8),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                                color: Colors.white24,
                                                borderRadius:
                                                    BorderRadius.circular(4))),
                                        const Text('App mode',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 8),
                                        ...modes.map((m) {
                                          final selectedMode =
                                              _appMode == AppMode.auto
                                                  ? AppMode.user
                                                  : _appMode;
                                          final isSelected =
                                              selectedMode == m;
                                          return ListTile(
                                            leading: Icon(
                                              appModeIcon(m),
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurface,
                                            ),
                                            title: Text(appModeLabel(m)),
                                            trailing: isSelected
                                                ? const Icon(Icons.check_circle)
                                                : const SizedBox.shrink(),
                                            onTap: () {
                                              Navigator.pop(ctx);
                                              _changeAppMode(m);
                                            },
                                          );
                                        }),
                                      ])))))));
        });
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem(
      {required this.icon, required this.label, required this.onTap});
}

class _ModePill extends StatelessWidget {
  final AppMode mode;
  const _ModePill({required this.mode});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = appModeLabel(mode);
    Color bg;
    switch (mode) {
      case AppMode.operator:
        bg = Colors.amber.withValues(alpha: isDark ? .30 : .20);
        break;
      case AppMode.admin:
        bg = Colors.redAccent.withValues(alpha: isDark ? .30 : .18);
        break;
      case AppMode.user:
        bg = Colors.greenAccent.withValues(alpha: isDark ? .30 : .20);
        break;
      case AppMode.auto:
      default:
        bg = Colors.blueAccent.withValues(alpha: isDark ? .30 : .20);
        break;
    }
    final fg = isDark ? Colors.white : Colors.black87;
    final icon = appModeIcon(mode);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

class ProfilePage extends StatefulWidget {
  final String baseUrl;
  const ProfilePage(this.baseUrl, {super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String phone = '';
  String walletId = '';
  String name = '';
  bool loading = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      try {
        final sp = await SharedPreferences.getInstance();
        name = sp.getString('last_login_name') ?? '';
      } catch (_) {}
      final r = await http.get(Uri.parse('${widget.baseUrl}/me/overview'),
          headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        phone = (j['phone'] ?? '').toString();
        walletId = (j['wallet_id'] ?? '').toString();
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final content = loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(16), children: [
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(l.labelWalletId),
              subtitle: Text(walletId.isEmpty ? '-' : walletId),
              trailing: walletId.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: walletId));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.msgWalletCopied)));
                        }
                      },
                    ),
            ),
            const SizedBox(height: 8),
            ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(l.labelName),
                subtitle: Text(name.isEmpty ? '-' : name)),
            const SizedBox(height: 8),
            ListTile(
                leading: const Icon(Icons.phone_iphone),
                title: Text(l.labelPhone),
                subtitle: Text(phone.isEmpty ? '-' : phone)),
          ]);
    return Scaffold(
        appBar: AppBar(
            title: Text(l.profileTitle), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          bg,
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }
}

class RolesInfoPage extends StatelessWidget {
  const RolesInfoPage({super.key});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    const bg = AppBG();
    final tiles = <Map<String, dynamic>>[
      {
        'mode': AppMode.user,
        'title': l.isArabic ? 'مستخدم' : 'User',
        'desc': l.isArabic
            ? 'المستخدم الافتراضي للتطبيق – يدفع ويتلقى المدفوعات ويستخدم خدمات التنقل والخدمات الأخرى.'
            : 'Default app user – pays, receives payments and uses mobility and other services.'
      },
      {
        'mode': AppMode.operator,
        'title': l.isArabic ? 'مشغل' : 'Operator',
        'desc': l.isArabic
            ? 'يستخدم أدوات تشغيل احترافية (مثل التاكسي، الحافلات، الفنادق) ويدير الحجوزات الحية.'
            : 'Uses professional operator tools (e.g. taxi, bus, hotels) and manages live bookings.'
      },
      {
        'mode': AppMode.admin,
        'title': l.isArabic ? 'مسؤول' : 'Admin',
        'desc': l.isArabic
            ? 'لديه صلاحيات واسعة في المكتب الخلفي وإدارة المخاطر (معظمها عبر واجهة الويب).'
            : 'Has extended backoffice and risk administration capabilities (mostly via web admin).'
      },
    ];
    return Scaffold(
      appBar: AppBar(
          title: Text(l.rolesOverviewTitle),
          backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          bg,
          Positioned.fill(
            child: SafeArea(
              child: GlassPanel(
                padding: const EdgeInsets.all(16),
                child: ListView.separated(
                  itemCount: tiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final t = tiles[index];
                    final AppMode mode = t['mode'] as AppMode;
                    final ColorScheme c = Theme.of(context).colorScheme;
                    Color chipBg;
                    switch (mode) {
                      case AppMode.operator:
                        chipBg = Colors.amber.withValues(alpha: .20);
                        break;
                      case AppMode.admin:
                        chipBg = Colors.redAccent.withValues(alpha: .18);
                        break;
                      case AppMode.user:
                        chipBg = Colors.greenAccent.withValues(alpha: .20);
                        break;
                      case AppMode.auto:
                      default:
                        chipBg = c.primary.withValues(alpha: .18);
                        break;
                    }
                    final icon = appModeIcon(mode);
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? c.surface.withValues(alpha: .92)
                            : c.surface.withValues(alpha: .96),
                        borderRadius: Tokens.radiusLg,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: chipBg,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  t['title'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t['desc'] as String,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MerchantPosPage extends StatefulWidget {
  final String baseUrl;
  const MerchantPosPage(this.baseUrl, {super.key});
  @override
  State<MerchantPosPage> createState() => _MerchantPosPageState();
}

class TopupPage extends StatefulWidget {
  final String baseUrl;
  final bool triggerScanOnOpen;
  const TopupPage(this.baseUrl, {super.key, this.triggerScanOnOpen = false});
  @override
  State<TopupPage> createState() => _TopupPageState();
}

class _TopupPageState extends State<TopupPage> {
  final amtCtrl = TextEditingController(text: '10000');
  final walletCtrl = TextEditingController();
  String out = '';
  String topupPayload = '';
  String _curSym = 'SYP';
  @override
  void initState() {
    super.initState();
    _load();
    if (widget.triggerScanOnOpen) {
      Future.microtask(_scanTopupAndDo);
    }
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    walletCtrl.text = sp.getString('wallet_id') ?? '';
    final cs = sp.getString('currency_symbol');
    if (cs != null && cs.isNotEmpty) {
      _curSym = cs;
    }
    setState(() {});
  }

  Future<void> _doTopup() async {
    setState(() => out = '...');
    try {
      final w = walletCtrl.text.trim();
      final amt =
          double.tryParse(amtCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      if (w.isEmpty || amt <= 0) {
        setState(() => out = 'Please check wallet and amount');
        return;
      }
      final uri = Uri.parse('${widget.baseUrl}/payments/wallets/' +
          Uri.encodeComponent(w) +
          '/topup');
      final headers = (await _hdr(json: true))
        ..addAll({
          'Idempotency-Key': 'top-${DateTime.now().millisecondsSinceEpoch}'
        });
      final body = jsonEncode({'amount': double.parse(amt.toStringAsFixed(2))});
      final r = await http.post(uri, headers: headers, body: body);
      setState(() => out = '${r.statusCode}: ${r.body}');
      if (r.statusCode >= 500) {
        await OfflineQueue.enqueue(OfflineTask(
            id: 'top-${DateTime.now().millisecondsSinceEpoch}',
            method: 'POST',
            url: uri.toString(),
            headers: headers,
            body: body,
            tag: 'payments_topup',
            createdAt: DateTime.now().millisecondsSinceEpoch));
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Offline: queued top‑up')));
      }
    } catch (e) {
      final w = walletCtrl.text.trim();
      final amt =
          double.tryParse(amtCtrl.text.trim().replaceAll(',', '.')) ?? 0;
      final uri = Uri.parse('${widget.baseUrl}/payments/wallets/' +
          Uri.encodeComponent(w) +
          '/topup');
      final headers = (await _hdr(json: true))
        ..addAll({
          'Idempotency-Key': 'top-${DateTime.now().millisecondsSinceEpoch}'
        });
      final body = jsonEncode({'amount': double.parse(amt.toStringAsFixed(2))});
      await OfflineQueue.enqueue(OfflineTask(
          id: 'top-${DateTime.now().millisecondsSinceEpoch}',
          method: 'POST',
          url: uri.toString(),
          headers: headers,
          body: body,
          tag: 'payments_topup',
          createdAt: DateTime.now().millisecondsSinceEpoch));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offline saved: Top‑up')));
      setState(() => out = 'Queued (offline)');
    }
  }

  void _genTopupQR() {
    final w = walletCtrl.text.trim();
    final a = int.tryParse(amtCtrl.text.trim()) ?? 0;
    if (w.isEmpty) {
      setState(() => out = 'Wallet required');
      return;
    }
    setState(() => topupPayload =
        'TOPUP|wallet=' + Uri.encodeComponent(w) + (a > 0 ? '|amount=$a' : ''));
  }

  Future<void> _scanTopupAndDo() async {
    final res = await Navigator.push<String?>(
        context, MaterialPageRoute(builder: (_) => const ScanPage()));
    if (res == null) return;
    try {
      final parts = res.split('|');
      if (parts.isEmpty) return;
      final kind = parts.first.toUpperCase();
      if (kind != 'TOPUP') return;
      final map = <String, String>{};
      for (final p in parts.skip(1)) {
        final kv = p.split('=');
        if (kv.length == 2) map[kv[0]] = Uri.decodeComponent(kv[1]);
      }
      final amount = int.tryParse(map['amount'] ?? '0') ?? 0;
      if (map['code'] != null && map['sig'] != null) {
        // Voucher redeem flow
        final sp = await SharedPreferences.getInstance();
        final toWallet = sp.getString('wallet_id') ?? '';
        if (toWallet.isEmpty) {
          if (mounted) setState(() => out = 'No wallet in session');
          return;
        }
        final uri = Uri.parse('${widget.baseUrl}/topup/redeem');
        final headers = await _hdr(json: true);
        final body = jsonEncode({
          'code': map['code'],
          'amount_cents': amount,
          'sig': map['sig'],
          'to_wallet_id': toWallet
        });
        final r = await http.post(uri, headers: headers, body: body);
        setState(() => out = '${r.statusCode}: ${r.body}');
        return;
      }
      if (map['wallet'] != null) {
        walletCtrl.text = map['wallet']!;
      }
      if (amount > 0) {
        amtCtrl.text = amount.toString();
      }
      setState(() {});
      await _doTopup();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
          controller: walletCtrl,
          decoration: const InputDecoration(labelText: 'Wallet ID')),
      const SizedBox(height: 8),
      TextField(
          controller: amtCtrl,
          decoration: const InputDecoration(labelText: 'Amount (SYP)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 4),
      Builder(builder: (_) {
        final c = int.tryParse(amtCtrl.text.trim()) ?? 0;
        final s = c > 0 ? '≈ ${fmtCents(c)} ${_curSym}' : '';
        return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(s,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white70))));
      }),
      Wrap(spacing: 8, runSpacing: 8, children: [
        PayActionButton(
            icon: Icons.qr_code_scanner,
            label: 'Scan & Topup',
            onTap: _scanTopupAndDo),
        PayActionButton(
            icon: Icons.qr_code_2,
            label: 'Generate Topup QR',
            onTap: _genTopupQR)
      ]),
      const SizedBox(height: 12),
      if (topupPayload.isNotEmpty)
        Center(
            child: Column(children: [
          Text(topupPayload, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          QrImageView(data: topupPayload, size: 220)
        ])),
      SelectableText(out),
    ]);
    const bg = AppBG();
    return Scaffold(
      appBar:
          AppBar(title: Text(l.homeTopup), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        Positioned.fill(
            child: SafeArea(
                child: GlassPanel(
                    padding: const EdgeInsets.all(16), child: content)))
      ]),
    );
  }
}

class _MerchantPosPageState extends State<MerchantPosPage> {
  final walletCtrl = TextEditingController();
  final amountCtrl = TextEditingController(text: '10000');
  String payload = '';
  StatusKind _bannerKind = StatusKind.info;
  String _bannerMsg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    walletCtrl.text = sp.getString('merchant_wallet') ?? '';
    setState(() {});
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('merchant_wallet', walletCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
  }

  void _genPay() {
    final w = walletCtrl.text.trim();
    final a = double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    if (w.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Wallet required')));
      return;
    }
    setState(() => payload = 'PAY|wallet=' +
        Uri.encodeComponent(w) +
        (a > 0 ? '|amount=' + Uri.encodeComponent(a.toStringAsFixed(2)) : ''));
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      if (_bannerMsg.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child:
              StatusBanner(kind: _bannerKind, message: _bannerMsg, dense: true),
        ),
      TextField(
          controller: walletCtrl,
          decoration: const InputDecoration(labelText: 'Merchant Wallet ID')),
      const SizedBox(height: 8),
      TextField(
          controller: amountCtrl,
          decoration: const InputDecoration(labelText: 'Amount (SYP)'),
          keyboardType: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: PayActionButton(
                icon: Icons.save_outlined,
                label: L10n.of(context).isArabic ? 'حفظ' : 'Save',
                onTap: _save)),
        const SizedBox(width: 8),
        Expanded(
            child: PayActionButton(
                icon: Icons.qr_code_2, label: 'PAY QR', onTap: _genPay))
      ]),
      const SizedBox(height: 12),
      PayActionButton(
          icon: Icons.local_printshop_outlined,
          label: L10n.of(context).isArabic ? 'كشك شحن' : 'Topup Kiosk',
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => TopupKioskPage(widget.baseUrl)));
          }),
      const SizedBox(height: 16),
      if (payload.isNotEmpty)
        Center(
            child: Column(children: [
          Text(payload, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          QrImageView(data: payload, version: QrVersions.auto, size: 220)
        ])),
    ]);
    return Scaffold(
        appBar: AppBar(
            title: Text(L10n.of(context).homeMerchantPos),
            backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          bg,
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }
}

// Topup Kiosk: create and print batches of topup vouchers
class TopupKioskPage extends StatefulWidget {
  final String baseUrl;
  const TopupKioskPage(this.baseUrl, {super.key});
  @override
  State<TopupKioskPage> createState() => _TopupKioskPageState();
}

// Ops hub page: consolidate operator/admin tools under one icon
class OpsPage extends StatelessWidget {
  final String baseUrl;
  const OpsPage(this.baseUrl, {super.key});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget btn(IconData icon, String label, VoidCallback onTap) {
      return SizedBox(
        width: 240,
        child: PayActionButton(icon: icon, label: label, onTap: onTap),
      );
    }

    final nativeTiles = <Widget>[
      btn(Icons.support_agent, 'Taxi Admin', () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TaxiOperatorPage(baseUrl)));
      }),
      btn(Icons.percent, 'Taxi Settings', () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TaxiSettingsPage(baseUrl)));
      }),
      btn(Icons.directions_bus_filled_outlined, 'Bus Operator', () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => BusOperatorPage(baseUrl)));
      }),
	      btn(Icons.business, 'Hotel Operator', () {
	        Navigator.push(
	          context,
	          MaterialPageRoute(builder: (_) => PmsGlassPage(baseUrl)),
	        );
	      }),
      btn(Icons.construction_outlined, 'Building Materials Operator', () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => BuildingMaterialsOperatorPage(baseUrl)));
      }),
      btn(Icons.directions_car_filled_outlined, 'Carmarket Operator', () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => CarmarketPage(baseUrl)));
      }),
      btn(Icons.car_rental, 'Carrental Operator', () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => CarrentalModernPage(baseUrl)));
      }),
      btn(Icons.engineering, 'Equipment Ops', () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => EquipmentOpsDashboardPage(baseUrl: baseUrl)));
      }),
      btn(Icons.point_of_sale, 'Merchant POS', () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => PosGlassPage(baseUrl)));
      }),
      btn(Icons.local_printshop_outlined, 'Topup Kiosk', () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => TopupKioskPage(baseUrl)));
      }),
      btn(Icons.health_and_safety_outlined, l.opsSystemStatus, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => SystemStatusPage(baseUrl)));
      }),
    ];
    final webTiles = <Widget>[
      btn(Icons.shield_moon_outlined, 'Risk Admin', () {
        launchWithSession(Uri.parse('$baseUrl/admin/risk'));
      }),
      btn(Icons.file_download_outlined, 'Admin Exports', () {
        launchWithSession(Uri.parse('$baseUrl/admin/exports'));
      }),
      btn(Icons.manage_accounts_outlined, 'Topup Sellers', () {
        launchWithSession(Uri.parse('$baseUrl/admin/topup-sellers'));
      }),
    ];
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.opsTitle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: nativeTiles,
        ),
        const SizedBox(height: 16),
        const Text('Web Admin (opens browser)',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: webTiles,
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.opsTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: content,
        ),
      ),
    );
  }
}

class OperatorDashboardPage extends StatefulWidget {
  final String baseUrl;
  final List<String>? operatorDomains;
  const OperatorDashboardPage(this.baseUrl, {super.key, this.operatorDomains});
  @override
  State<OperatorDashboardPage> createState() => _OperatorDashboardPageState();
}

class _OperatorDashboardPageState extends State<OperatorDashboardPage> {
  List<String> _domains = const [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // If domains are provided (e.g. from login), use them; otherwise load from /me/home_snapshot.
    final provided = widget.operatorDomains;
    if (provided != null) {
      setState(() {
        _domains = List<String>.from(provided);
        _loading = false;
      });
      return;
    }
    try {
      final uri = Uri.parse('${widget.baseUrl}/me/home_snapshot');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final opDomains = (body['operator_domains'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];
        setState(() {
          _domains = opDomains;
          _loading = false;
        });
      } else if (r.statusCode == 404) {
        // Legacy BFF without snapshot endpoint: treat as "no operator domains"
        // but avoid showing a hard error screen.
        setState(() {
          _domains = const <String>[];
          _loading = false;
          _error = '';
        });
      } else {
        setState(() {
          _error = 'Failed to load operator profile (${r.statusCode}).';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading operator profile: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget btn(IconData icon, String label, VoidCallback onTap) {
      return SizedBox(
        width: 240,
        child: PayActionButton(icon: icon, label: label, onTap: onTap),
      );
    }

    final tiles = <Widget>[];
    if (_domains.contains('taxi')) {
      tiles.add(btn(Icons.support_agent, l.homeTaxiOperator, () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => TaxiOperatorPage(widget.baseUrl)));
      }));
    }
    if (_domains.contains('bus')) {
      tiles.add(btn(Icons.directions_bus_filled_outlined,
          l.isArabic ? 'مشغل الباص' : 'Bus Operator', () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => BusOperatorPage(widget.baseUrl)));
      }));
    }
    if (_domains.contains('stays')) {
      tiles.add(btn(
        Icons.business,
        l.isArabic ? 'مشغل الفنادق والإقامات' : 'Stays Operator',
        () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PmsGlassPage(widget.baseUrl)));
        },
      ));
    }
    if (_domains.contains('commerce')) {
      tiles.add(btn(
        Icons.construction_outlined,
        l.isArabic
            ? 'مشغل مواد البناء / التجارة'
            : 'Building Materials Operator',
        () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      BuildingMaterialsOperatorPage(widget.baseUrl)));
        },
      ));
    }
    // Doctors admin
    tiles.add(btn(Icons.medical_services_outlined,
        l.isArabic ? 'مشغل الأطباء' : 'Doctors Admin', () {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => DoctorsAdminPage(baseUrl: widget.baseUrl)));
    }));
    if (_domains.contains('realestate')) {
      tiles.add(btn(
        Icons.apartment_outlined,
        l.isArabic ? 'مشغل العقارات' : 'Realestate Operator',
        () {
          Navigator.push(
              context,
	              MaterialPageRoute(
	                  builder: (_) => RealEstateEnduser(baseUrl: widget.baseUrl)));
        },
      ));
    }
    if (_domains.contains('food')) {
      tiles.add(btn(
        Icons.restaurant,
        l.isArabic ? 'مشغل الطعام' : 'Food Operator',
        () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FoodOrdersPage(widget.baseUrl)));
        },
      ));
    }
    if (_domains.contains('freight')) {
      tiles.add(btn(
        Icons.local_shipping_outlined,
        l.isArabic ? 'مشغل الشحن' : 'Freight Operator',
        () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => FreightPage(widget.baseUrl)));
        },
      ));
    }
    if (_domains.contains('agriculture')) {
      tiles.add(btn(
        Icons.eco_outlined,
        l.isArabic ? 'مشغل الزراعة' : 'Agriculture Operator',
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ModuleHealthPage(
                  widget.baseUrl, 'Agriculture', '/agriculture/health'),
            ),
          );
        },
      ));
    }
    if (_domains.contains('livestock')) {
      tiles.add(btn(
        Icons.pets_outlined,
        l.isArabic ? 'مشغل الثروة الحيوانية' : 'Livestock Operator',
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ModuleHealthPage(
                  widget.baseUrl, 'Livestock', '/livestock/health'),
            ),
          );
        },
      ));
    }
    if (_domains.contains('carrental')) {
      tiles.add(btn(
        Icons.directions_car,
        l.isArabic ? 'مشغل تأجير السيارات' : 'Carrental Operator',
        () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => CarrentalModernPage(widget.baseUrl)));
        },
      ));
    }

    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: StatusBanner.error(_error, dense: false),
      );
    } else if (tiles.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: StatusBanner.error(
          l.isArabic
              ? 'لا توجد صلاحيات مشغل مرتبطة بهذا الرقم. يرجى التواصل مع المشرف.'
              : 'No operator domains assigned to this phone. Please contact an admin.',
          dense: false,
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.operatorDashboardTitle),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: tiles,
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.operatorDashboardTitle)),
      body: SafeArea(child: body),
    );
  }
}

class AdminDashboardPage extends StatelessWidget {
  final String baseUrl;
  const AdminDashboardPage(this.baseUrl, {super.key});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget btn(IconData icon, String label, VoidCallback onTap) {
      return SizedBox(
        width: 240,
        child: PayActionButton(icon: icon, label: label, onTap: onTap),
      );
    }

    final coreTiles = <Widget>[
      btn(Icons.health_and_safety_outlined, l.opsSystemStatus, () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => SystemStatusPage(baseUrl)));
      }),
      btn(Icons.layers_outlined, l.opsTitle, () {
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => OpsPage(baseUrl)));
      }),
    ];
    final webTiles = <Widget>[
      btn(Icons.dashboard_outlined, 'Admin overview (web)', () {
        launchWithSession(Uri.parse('$baseUrl/admin/overview'));
      }),
      btn(Icons.file_download_outlined, 'Admin exports (web)', () {
        launchWithSession(Uri.parse('$baseUrl/admin/exports'));
      }),
      btn(Icons.manage_accounts_outlined, 'Topup sellers (web)', () {
        launchWithSession(Uri.parse('$baseUrl/admin/topup-sellers'));
      }),
    ];
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.adminDashboardTitle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: coreTiles,
        ),
        const SizedBox(height: 16),
        const Text('Admin web consoles',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: webTiles,
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.adminDashboardTitle)),
      body: SafeArea(child: content),
    );
  }
}

class SuperadminDashboardPage extends StatefulWidget {
  final String baseUrl;
  const SuperadminDashboardPage(this.baseUrl, {super.key});

  @override
  State<SuperadminDashboardPage> createState() =>
      _SuperadminDashboardPageState();
}

class _SuperadminDashboardPageState extends State<SuperadminDashboardPage> {
  String _financeRange = '24h'; // 24h, 7d, 30d

  String get baseUrl => widget.baseUrl;

  Future<Map<String, dynamic>> _fetchStats() async {
    try {
      final uri = Uri.parse('$baseUrl/admin/stats');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return j;
      }
    } catch (_) {}
    return const {};
  }

  Future<Map<String, dynamic>> _fetchFinanceStats() async {
    try {
      // Compute time range on client side.
      DateTime now = DateTime.now().toUtc();
      Duration d;
      switch (_financeRange) {
        case '7d':
          d = const Duration(days: 7);
          break;
        case '30d':
          d = const Duration(days: 30);
          break;
        case '24h':
        default:
          d = const Duration(days: 1);
      }
      final start = now.subtract(d);
      String iso(DateTime dt) =>
          dt.toIso8601String().replaceFirst(RegExp(r'\\+00:00\$'), 'Z');
      final params = {
        'from_iso': iso(start),
        'to_iso': iso(now),
      };
      final uri = Uri.parse('$baseUrl/admin/finance_stats')
          .replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        return j;
      }
    } catch (_) {}
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    Widget superTile(
        {required IconData icon,
        required String label,
        required Color tint,
        required VoidCallback onTap}) {
      return SizedBox(
        width: 240,
        child: PayActionButton(
          icon: icon,
          label: label,
          onTap: onTap,
          tint: tint,
        ),
      );
    }

    Widget btn(IconData icon, String label, VoidCallback onTap, {Color? tint}) {
      return SizedBox(
        width: 240,
        child:
            PayActionButton(icon: icon, label: label, onTap: onTap, tint: tint),
      );
    }

    final domainTiles = <Widget>[
      superTile(
        icon: Icons.account_balance_wallet_outlined,
        label: 'Payment',
        tint: Tokens.colorPayments,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PaymentsMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.local_taxi_outlined,
        label: 'Taxi',
        tint: Tokens.colorTaxi,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => TaxiMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.directions_bus_filled_outlined,
        label: 'Bus',
        tint: Tokens.colorBus,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BusMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.restaurant_outlined,
        label: 'Food',
        tint: Tokens.colorFood,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => FoodMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.hotel_outlined,
        label: 'Stays & Hotels',
        tint: Tokens.colorHotelsStays,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StaysMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.home_outlined,
        label: 'Realestate',
        tint: Tokens.colorHotelsStays,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => RealestateMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.construction_outlined,
        label: 'Building materials',
        tint: Tokens.colorBuildingMaterials,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      BuildingMaterialsMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.local_shipping_outlined,
        label: 'Courier',
        tint: Tokens.colorCourierTransport,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CourierMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.directions_car_filled_outlined,
        label: 'Carrental & Carmarket',
        tint: Tokens.colorCars,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      CarrentalCarmarketMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.store_mall_directory_outlined,
        label: 'Agri Marketplace',
        tint: Tokens.colorAgricultureLivestock,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      AgricultureLivestockMultiLevelPage(baseUrl: baseUrl)));
        },
      ),
      superTile(
        icon: Icons.pets_outlined,
        label: 'Livestock Marketplace',
        tint: Tokens.colorAgricultureLivestock,
        onTap: () {
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      LivestockMarketplacePage(baseUrl: baseUrl)));
        },
      ),
    ];

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l.superadminDashboardTitle),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: domainTiles,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            ChoiceChip(
              label: const Text('24h'),
              selected: _financeRange == '24h',
              onSelected: (_) {
                setState(() => _financeRange = '24h');
              },
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('7d'),
              selected: _financeRange == '7d',
              onSelected: (_) {
                setState(() => _financeRange = '7d');
              },
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('30d'),
              selected: _financeRange == '30d',
              onSelected: (_) {
                setState(() => _financeRange = '30d');
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>>(
          future: _fetchFinanceStats(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            final data = snap.data ?? const {};
            if (data.isEmpty) {
              return const SizedBox.shrink();
            }
            final totalTxns = data['total_txns'] ?? 0;
            final totalFeeCents = data['total_fee_cents'] ?? 0;
            final fromIso = (data['from_iso'] ?? '') as String;
            final toIso = (data['to_iso'] ?? '') as String;
            final feeStr = totalFeeCents is int
                ? '${(totalFeeCents / 100.0).toStringAsFixed(2)} SYP'
                : totalFeeCents.toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassPanel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Finance overview',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Txns: $totalTxns  ·  Fees: $feeStr',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (fromIso.isNotEmpty || toIso.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Range: ${fromIso.isNotEmpty ? fromIso : '?'} → ${toIso.isNotEmpty ? toIso : '?'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        FutureBuilder<Map<String, dynamic>>(
          future: _fetchStats(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            final data = snap.data ?? const {};
            final samples = (data['samples'] as Map?) ?? const {};
            final actions = (data['actions'] as Map?) ?? const {};
            final guardrails = (data['guardrails'] as Map?) ?? const {};
            final building = (data['building_orders'] as Map?) ?? const {};
            final totalEvents = data['total_events'] ?? 0;

            String lineFor(String metric, String label) {
              final m = samples[metric];
              if (m is Map) {
                final cnt = m['count'] ?? 0;
                final avg = m['avg_ms'] ?? 0.0;
                return '$label: avg ${avg.toStringAsFixed(0)} ms · count ${cnt.toString()}';
              }
              return '';
            }

            final lines = <String>[
              lineFor('pay_send_ms', 'Payments send'),
              lineFor('taxi_book_ms', 'Taxi booking'),
              lineFor('bus_book_ms', 'Bus booking'),
              lineFor('stays_book_ms', 'Stays booking'),
              lineFor('food_order_ms', 'Food order'),
            ].where((s) => s.isNotEmpty).toList();

            if (lines.isEmpty && (totalEvents == 0 || totalEvents == '0')) {
              return const SizedBox.shrink();
            }

            int _intFor(String key) {
              final v = actions[key];
              if (v is int) return v;
              if (v is num) return v.toInt();
              if (v is String) {
                return int.tryParse(v) ?? 0;
              }
              return 0;
            }

            Widget domainCard(
                IconData icon, String title, String line1, String? line2) {
              return Container(
                width: 160,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: .96),
                  borderRadius: Tokens.radiusMd,
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(line1, style: Theme.of(context).textTheme.bodySmall),
                    if (line2 != null && line2.isNotEmpty)
                      Text(line2, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              );
            }

            final payOk = _intFor('pay_send_ok');
            final payFail = _intFor('pay_send_fail');
            final taxiOk = _intFor('taxi_book_ok');
            final taxiFail = _intFor('taxi_book_fail');
            final busOk = _intFor('bus_book_ok');
            final busFail = _intFor('bus_book_fail');
            final staysOk = _intFor('stays_book_ok');
            final staysFail = _intFor('stays_book_fail');
            final foodOk = _intFor('food_order_ok');
            final foodFail = _intFor('food_order_fail');
            final buildingTotal = (building['total'] ?? 0) is int
                ? building['total'] as int
                : int.tryParse((building['total'] ?? '0').toString()) ?? 0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassPanel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System overview',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        domainCard(
                          Icons.account_balance_wallet_outlined,
                          'Payments',
                          'ok: $payOk · fail: $payFail',
                          'guardrails: ${(guardrails.keys.where((k) => k.toString().contains('pay') || k.toString().contains('wallet')).length)} keys',
                        ),
                        domainCard(
                          Icons.directions_bus_filled,
                          'Mobility',
                          'taxi ok/fail: $taxiOk/$taxiFail',
                          'bus ok/fail: $busOk/$busFail',
                        ),
                        domainCard(
                          Icons.hotel,
                          'Stays',
                          'ok/fail: $staysOk/$staysFail',
                          null,
                        ),
                        domainCard(
                          Icons.restaurant_outlined,
                          'Food',
                          'ok/fail: $foodOk/$foodFail',
                          null,
                        ),
                        domainCard(
                          Icons.storefront,
                          'Marketplace',
                          'building orders: $buildingTotal',
                          null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Key stats (last $totalEvents events)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    if (lines.isEmpty)
                      Text(
                        'No detailed latency metrics yet.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      ...lines.map((s) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(s,
                                style: Theme.of(context).textTheme.bodySmall),
                          )),
                    const SizedBox(height: 6),
                    if (actions.isNotEmpty) ...[
                      const Divider(height: 12),
                      Text(
                        'Recent actions (counts)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (_) {
                          String fmt(String key, String label) {
                            final v = actions[key];
                            if (v == null) return '';
                            return '$label: ${v.toString()}';
                          }

                          final actionLines = <String>[
                            fmt('pay_send_ok', 'Payments ok'),
                            fmt('pay_send_fail', 'Payments fail'),
                            fmt('taxi_book_ok', 'Taxi ok'),
                            fmt('taxi_book_fail', 'Taxi fail'),
                            fmt('bus_book_ok', 'Bus ok'),
                            fmt('bus_book_fail', 'Bus fail'),
                            fmt('stays_book_ok', 'Stays ok'),
                            fmt('stays_book_fail', 'Stays fail'),
                            fmt('food_order_ok', 'Food ok'),
                            fmt('food_order_fail', 'Food fail'),
                          ].where((s) => s.isNotEmpty).toList();
                          if (actionLines.isEmpty) {
                            return Text(
                              'No action counts yet.',
                              style: Theme.of(context).textTheme.bodySmall,
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: actionLines
                                .map((s) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 1),
                                      child: Text(s,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                    if (building.isNotEmpty) ...[
                      const Divider(height: 16),
                      Text(
                        'Building orders (audit, last window)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (_) {
                          final lines = building.entries
                              .map((e) => '${e.key}: ${e.value}')
                              .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: lines
                                .map((s) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 1),
                                      child: Text(s,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                    if (guardrails.isNotEmpty) ...[
                      const Divider(height: 16),
                      Builder(
                        builder: (_) {
                          int total = 0;
                          int risk = 0;
                          int payments = 0;
                          int mobility = 0;
                          guardrails.forEach((k, vRaw) {
                            final v = (vRaw as int? ?? 0);
                            total += v;
                            final key = k.toString();
                            if (key.contains('risk') || key.contains('deny')) {
                              risk += v;
                            }
                            if (key.contains('pay') ||
                                key.contains('wallet') ||
                                key.contains('alias')) {
                              payments += v;
                            }
                            if (key.contains('taxi') ||
                                key.contains('bus') ||
                                key.contains('freight') ||
                                key.contains('carrental')) {
                              mobility += v;
                            }
                          });
                          final txt = [
                            'Guardrail hits: $total',
                            if (risk > 0) 'risk/deny: $risk',
                            if (payments > 0) 'payments: $payments',
                            if (mobility > 0) 'mobility: $mobility',
                          ].join(' · ');
                          return StatusBanner.info(txt, dense: true);
                        },
                      ),
                    ],
                    if (guardrails.isNotEmpty) ...[
                      const Divider(height: 16),
                      Text(
                        'Guardrails (last ${guardrails.values.fold<int>(0, (p, v) => p + (v as int? ?? 0))} hits)',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Builder(
                        builder: (_) {
                          final lines = guardrails.entries
                              .map((e) => '${e.key}: ${e.value}')
                              .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: lines
                                .map((s) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 1),
                                      child: Text(s,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          l.isArabic ? 'إدارة الصلاحيات' : 'Role management',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        GlassPanel(
          padding: const EdgeInsets.all(12),
          child: Text(
            l.isArabic
                ? 'أدوار المشغلين (تاكسي، باص، الفنادق وغيرها) تُدار الآن داخل كل تطبيق نطاقي لتبقى لوحة Superadmin بسيطة ومركزة على الإحصاءات العامة.'
                : 'Operator roles for Taxi, Bus, Stays and other domains are now managed inside each domain dashboard so this Superadmin home stays focused on global stats.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: .80),
                ),
          ),
        ),
        const Text('Core dashboards',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            btn(Icons.health_and_safety_outlined, l.opsSystemStatus, () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => SystemStatusPage(baseUrl)));
            }, tint: Tokens.colorPayments),
            btn(Icons.dashboard_customize_outlined, l.operatorDashboardTitle,
                () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => OperatorDashboardPage(baseUrl)));
            }, tint: Tokens.colorBus),
            btn(Icons.admin_panel_settings_outlined, l.adminDashboardTitle, () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AdminDashboardPage(baseUrl)));
            }, tint: Tokens.colorHotelsStays),
            btn(Icons.layers_outlined, l.opsTitle, () {
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => OpsPage(baseUrl)));
            }, tint: Tokens.colorBuildingMaterials),
          ],
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.superadminDashboardTitle)),
      body: SafeArea(child: content),
    );
  }
}

class _TopupKioskPageState extends State<TopupKioskPage> {
  int _denom = 10000; // SYP major
  final _countCtrl = TextEditingController(text: '10');
  final _noteCtrl = TextEditingController();
  String out = '';
  String _batchId = '';
  List<dynamic> _items = [];
  List<dynamic> _batches = [];
  bool _mineOnly = true;

  Future<void> _createBatch() async {
    setState(() => out = '...');
    try {
      final count = int.tryParse(_countCtrl.text.trim()) ?? 0;
      if (count <= 0) {
        setState(() => out = 'Count must be > 0');
        return;
      }
      final uri = Uri.parse('${widget.baseUrl}/topup/batch_create');
      final r = await http.post(uri,
          headers: await _hdr(json: true),
          body: jsonEncode({
            'amount': _denom,
            'count': count,
            'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim()
          }));
      final j = jsonDecode(r.body);
      if (r.statusCode == 200) {
        _batchId = (j['batch_id'] ?? '').toString();
        _items = (j['items'] as List?) ?? [];
        setState(() => out = 'Created batch $_batchId');
      } else {
        setState(() => out = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }

  Future<void> _loadBatches() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/topup/batches?limit=50' +
          (_mineOnly ? '' : '&seller_id='));
      final r = await http.get(uri, headers: await _hdr());
      _batches = jsonDecode(r.body) as List? ?? [];
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _openBatch(String bid) async {
    setState(() => out = '...');
    try {
      final r = await http.get(
          Uri.parse(
              '${widget.baseUrl}/topup/batches/' + Uri.encodeComponent(bid)),
          headers: await _hdr());
      _batchId = bid;
      _items = jsonDecode(r.body) as List? ?? [];
      setState(() => out = 'Loaded $bid');
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  @override
  void dispose() {
    _countCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final chips = [5000, 10000, 20000, 50000];
    final grid = _items.isEmpty
        ? const SizedBox()
        : GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: .9,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8),
            itemCount: _items.length,
            itemBuilder: (_, i) {
              final v = _items[i] as Map;
              final payload = (v['payload'] ?? '').toString();
              final code = (v['code'] ?? '').toString();
              final amt = (v['amount_cents'] ?? 0) as int;
              final status = (v['status'] ?? '').toString();
              return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(children: [
                        Expanded(
                            child: Center(
                                child: Image.network(
                                    '${widget.baseUrl}/qr.png?data=' +
                                        Uri.encodeComponent(payload),
                                    width: 180,
                                    height: 180))),
                        const SizedBox(height: 6),
                        Text(code, style: const TextStyle(fontSize: 12)),
                        Text(
                            '$amt SYP · ${status.isEmpty ? 'reserved' : status}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 6),
                        if (status == 'reserved')
                          SizedBox(
                              width: double.infinity,
                              child: PayActionButton(
                                  icon: Icons.remove_circle_outline,
                                  label: 'Void',
                                  onTap: () => _voidVoucher(code)))
                      ])));
            },
          );
    final batchesList = _batches.isEmpty
        ? const SizedBox()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 16),
            const Text('Recent Batches'),
            const SizedBox(height: 8),
            ..._batches.map((b) {
              final bid = (b['batch_id'] ?? '').toString();
              final total = (b['total'] ?? 0) as int;
              final reserved = (b['reserved'] ?? 0) as int;
              final redeemed = (b['redeemed'] ?? 0) as int;
              return ListTile(
                  title: Text(bid, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                      'total $total  reserved $reserved  redeemed $redeemed'),
                  trailing: IconButton(
                      icon: const Icon(Icons.open_in_new),
                      onPressed: () => _openBatch(bid)));
            }).toList()
          ]);

    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      Text(l.isArabic ? 'كشك شحن' : 'Topup Kiosk'),
      const SizedBox(height: 8),
      Wrap(
          spacing: 8,
          children: chips.map((v) {
            final sel = _denom == v;
            return ChoiceChip(
                label: Text('$v'),
                selected: sel,
                onSelected: (_) {
                  setState(() => _denom = v);
                });
          }).toList()),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.isArabic ? 'دفعاتي فقط' : 'My batches only'),
                value: _mineOnly,
                onChanged: (v) {
                  setState(() => _mineOnly = v);
                  _loadBatches();
                })),
        const SizedBox(width: 8),
        Expanded(child: Container())
      ]),
      const SizedBox(height: 4),
      Row(children: [
        Expanded(
            child: TextField(
                controller: _countCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'عدد القسائم' : 'Count'),
                keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                    labelText:
                        l.isArabic ? 'ملاحظة (اختياري)' : 'Note (optional)'))),
      ]),
      const SizedBox(height: 12),
      PayActionButton(
          icon: Icons.grid_view,
          label: l.isArabic ? 'إنشاء دفعة' : 'Create Batch',
          onTap: _createBatch),
      if (_batchId.isNotEmpty)
        Row(children: [
          Expanded(
              child: PayActionButton(
                  icon: Icons.print_outlined,
                  label: l.isArabic ? 'طباعة الدفعة' : 'Print Batch',
                  onTap: () {
                    launchWithSession(Uri.parse(
                        '${widget.baseUrl}/topup/print/' +
                            Uri.encodeComponent(_batchId)));
                  })),
          const SizedBox(width: 8),
          Expanded(
              child: PayActionButton(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                  onTap: () {
                    launchWithSession(Uri.parse(
                        '${widget.baseUrl}/topup/print_pdf/' +
                            Uri.encodeComponent(_batchId)));
                  })),
        ]),
      if (_batchId.isNotEmpty) const SizedBox(height: 8),
      if (_batchId.isNotEmpty)
        PayActionButton(
            icon: Icons.refresh,
            label: l.isArabic ? 'إعادة تحميل الدفعة' : 'Reload Batch',
            onTap: () => _openBatch(_batchId)),
      const SizedBox(height: 8),
      grid,
      SelectableText(out),
      batchesList,
    ]);
    return Scaffold(
        appBar: AppBar(
            title: Text(l.isArabic ? 'كشك شحن' : 'Topup Kiosk'),
            backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          bg,
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }

  Future<void> _voidVoucher(String code) async {
    setState(() => out = '...');
    try {
      final r = await http.post(
          Uri.parse('${widget.baseUrl}/topup/vouchers/' +
              Uri.encodeComponent(code) +
              '/void'),
          headers: await _hdr());
      if (r.statusCode == 200) {
        setState(() => out = 'Voided $code');
        if (_batchId.isNotEmpty) await _openBatch(_batchId);
      } else {
        setState(() => out = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }
}

class SystemStatusPage extends StatefulWidget {
  final String baseUrl;
  const SystemStatusPage(this.baseUrl, {super.key});
  @override
  State<SystemStatusPage> createState() => _SystemStatusPageState();
}

class _SystemStatusPageState extends State<SystemStatusPage> {
  Map<String, dynamic>? _data;
  String _error = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _error = '';
    try {
      final uri = Uri.parse('${widget.baseUrl}/upstreams/health');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        Perf.action('system_status_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        setState(() => _data = j);
      } else {
        Perf.action('system_status_fail');
        setState(() => _error = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      Perf.action('system_status_error');
      setState(() => _error = 'error: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Color _statusColor(Map<String, dynamic> v) {
    final sc = v['status_code'];
    final err = v['error'];
    if (err != null) {
      return Colors.red;
    }
    if (sc is int) {
      if (sc >= 200 && sc < 300) return Colors.green;
      if (sc >= 500) return Colors.red;
      return Colors.orange;
    }
    return Colors.grey;
  }

  String _statusLabel(Map<String, dynamic> v) {
    final sc = v['status_code'];
    final err = v['error'];
    if (err != null) {
      return 'ERROR';
    }
    if (sc is int) {
      if (sc >= 200 && sc < 300) return 'OK';
      if (sc >= 500) return 'DOWN';
      return 'WARN';
    }
    return 'UNKNOWN';
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    final l = L10n.of(context);
    if (_loading && _data == null && _error.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error.isNotEmpty) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StatusBanner.error(_error),
        ],
      );
    } else {
      final entries = (_data ?? const {}).entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length + (_error.isNotEmpty ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0 && _error.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: StatusBanner.error(_error, dense: true),
              );
            }
            final adjIndex = _error.isNotEmpty ? index - 1 : index;
            final e = entries[adjIndex];
            final name = e.key;
            final v = (e.value as Map).cast<String, dynamic>();
            final col = _statusColor(v);
            final status = _statusLabel(v);
            final sc = v['status_code'];
            final err = v['error'];
            final detail = err is String
                ? err
                : (v['body'] is Map && (v['body'] as Map).containsKey('status')
                    ? (v['body']['status'] ?? '').toString()
                    : '');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  status == 'OK'
                      ? Icons.check_circle_outline
                      : status == 'DOWN'
                          ? Icons.error_outline
                          : Icons.warning_amber_outlined,
                  color: col,
                ),
                title: Text(name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.systemStatusStatusLabel}: $status'
                        '${sc != null ? ' · ${l.systemStatusHttpLabel} $sc' : ''}'),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.systemStatusTitle),
      ),
      body: body,
    );
  }
}

class StaysPage extends StatefulWidget {
  final String baseUrl;
  const StaysPage(this.baseUrl, {super.key});
  @override
  State<StaysPage> createState() => _StaysPageState();
}

class _StaysPageState extends State<StaysPage> {
  final qCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final listOut = ValueNotifier<String>('');
  final pageCtrl = TextEditingController(text: '0');
  final sizeCtrl = TextEditingController(text: '10');
  String _sortBy = 'created_at';
  String _order = 'desc';
  String _type = '';
  List<dynamic> _items = [];
  int _page = 0;
  int _size = 10;
  String _curSym = 'SYP';
  final lidCtrl = TextEditingController();
  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  final gnameCtrl = TextEditingController();
  final gphoneCtrl = TextEditingController();
  final gwalletCtrl = TextEditingController();
  String out = '';
  Map<String, dynamic>? _lastQuote;
  int? _lastQuoteLid;
  String _bannerMsg = '';
  StatusKind _bannerKind = StatusKind.info;

  Future<void> _load() async {
    try {
      _page = int.tryParse(pageCtrl.text.trim()) ?? 0;
      if (_page < 0) _page = 0;
      _size = int.tryParse(sizeCtrl.text.trim()) ?? 10;
      if (_size <= 0) _size = 10;
    } catch (_) {
      _page = 0;
      _size = 10;
    }
    final off = _page * _size;
    final u = Uri.parse(
        '${widget.baseUrl}/stays/listings/search?q=${Uri.encodeComponent(qCtrl.text)}&city=${Uri.encodeComponent(cityCtrl.text)}&type=${Uri.encodeComponent(_type)}&limit=$_size&offset=$off&sort_by=${Uri.encodeComponent(_sortBy)}&order=${Uri.encodeComponent(_order)}');
    final r = await http.get(u, headers: await _hdr());
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      _items = (j['items'] as List?) ?? [];
      final total = (j['total'] ?? 0) as int;
      final start = off + 1;
      final end = off + _items.length;
      listOut.value = '${r.statusCode}: $start-$end of $total';
    } catch (_) {
      _items = [];
      listOut.value = '${r.statusCode}: ${r.body}';
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadCurrency();
    _loadWallet();
  }

  Future<void> _loadCurrency() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final cs = sp.getString('currency_symbol');
      if (cs != null && cs.isNotEmpty) {
        _curSym = cs;
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty) {
        gwalletCtrl.text = w;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  void _next() {
    pageCtrl.text = '${_page + 1}';
    _load();
  }

  void _prev() {
    if (_page > 0) {
      pageCtrl.text = '${_page - 1}';
      _load();
    }
  }

  Future<void> _quote() async {
    setState(() => out = '...');
    _lastQuote = null;
    _lastQuoteLid = null;
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final r = await http.post(Uri.parse('${widget.baseUrl}/stays/quote'),
        headers: await _hdr(json: true),
        body: jsonEncode({
          'listing_id': int.tryParse(lidCtrl.text.trim()) ?? 0,
          'from_iso': fromCtrl.text.trim(),
          'to_iso': toCtrl.text.trim()
        }));
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      _lastQuote = j;
      _lastQuoteLid = int.tryParse(lidCtrl.text.trim());
      final nights = j['nights'];
      final amount = j['amount_cents'];
      final cur = (j['currency'] ?? '').toString();
      setState(() => out =
          '${r.statusCode}: ${nights} nights · ${(amount / 100).toString()} $cur');
      final dt = DateTime.now().millisecondsSinceEpoch - t0;
      Perf.action('stays_quote_ok');
      Perf.sample('stays_quote_ms', dt);
      setState(() {
        _bannerKind = StatusKind.info;
        _bannerMsg = 'Quote updated: $nights nights';
      });
    } catch (_) {
      setState(() => out = '${r.statusCode}: ${r.body}');
      Perf.action('stays_quote_fail');
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = 'Could not calculate quote';
      });
    }
  }

  Future<void> _book() async {
    setState(() => out = '...');
    final t0 = DateTime.now().millisecondsSinceEpoch;
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'stay-${DateTime.now().millisecondsSinceEpoch}';
    final r = await http.post(Uri.parse('${widget.baseUrl}/stays/book'),
        headers: h,
        body: jsonEncode({
          'listing_id': int.tryParse(lidCtrl.text.trim()) ?? 0,
          'from_iso': fromCtrl.text.trim(),
          'to_iso': toCtrl.text.trim(),
          'guest_name': gnameCtrl.text.trim(),
          'guest_phone':
              gphoneCtrl.text.trim().isEmpty ? null : gphoneCtrl.text.trim(),
          'guest_wallet_id':
              gwalletCtrl.text.trim().isEmpty ? null : gwalletCtrl.text.trim(),
          'confirm': true,
        }));
    try {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final id = (j['id'] ?? '').toString();
      final st = (j['status'] ?? '').toString();
      setState(() => out = '${r.statusCode}: Booking $id · $st');
      final dt = DateTime.now().millisecondsSinceEpoch - t0;
      Perf.action('stays_book_ok');
      Perf.sample('stays_book_ms', dt);
      setState(() {
        _bannerKind = StatusKind.success;
        _bannerMsg = 'Stay booked (ID: $id, status: $st)';
      });
    } catch (_) {
      setState(() => out = '${r.statusCode}: ${r.body}');
      Perf.action('stays_book_fail');
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = 'Could not book stay';
      });
    }
  }

  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: now,
        lastDate: now.add(const Duration(days: 365)));
    if (d != null) {
      fromCtrl.text =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  Future<void> _pickTo() async {
    final base = fromCtrl.text.trim().isNotEmpty
        ? DateTime.tryParse(fromCtrl.text.trim()) ?? DateTime.now()
        : DateTime.now();
    final d = await showDatePicker(
        context: context,
        initialDate: base.add(const Duration(days: 1)),
        firstDate: base.add(const Duration(days: 1)),
        lastDate: base.add(const Duration(days: 365)));
    if (d != null) {
      toCtrl.text =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      setState(() {});
    }
  }

  void _openBookingForListing(int listingId) {
    lidCtrl.text = listingId.toString();
    out = '';
    _lastQuote = null;
    _lastQuoteLid = null;
    fromCtrl.clear();
    toCtrl.clear();
    gnameCtrl.clear();
    gphoneCtrl.clear();
    // wallet field keeps last known wallet by default
    setState(() {});
    final l = L10n.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(
            color: Colors.black54,
            child: GestureDetector(
              onTap: () {},
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: .98),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 10,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            height: 4,
                            width: 44,
                            margin: const EdgeInsets.only(bottom: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Text(
                            l.isArabic ? 'حجز الإقامة' : 'Book stay',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            SizedBox(
                                width: 220,
                                child: TextField(
                                    controller: lidCtrl,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                        labelText: l.isArabic
                                            ? 'معرف العرض'
                                            : 'listing id'))),
                            SizedBox(
                                width: 220,
                                child: TextField(
                                    controller: fromCtrl,
                                    decoration: InputDecoration(
                                        labelText: l.isArabic
                                            ? 'من (YYYY-MM-DD)'
                                            : 'from (YYYY-MM-DD)'))),
                            SizedBox(
                                width: 220,
                                child: TextField(
                                    controller: toCtrl,
                                    decoration: InputDecoration(
                                        labelText: l.isArabic
                                            ? 'إلى (YYYY-MM-DD)'
                                            : 'to (YYYY-MM-DD)'))),
                          ]),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              PrimaryButton(
                                  label: l.isArabic ? 'اختر من' : 'Pick From',
                                  onPressed: _pickFrom),
                              PrimaryButton(
                                  label: l.isArabic ? 'اختر إلى' : 'Pick To',
                                  onPressed: _pickTo),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            SizedBox(
                                width: 220,
                                child: TextField(
                                    controller: gnameCtrl,
                                    decoration: InputDecoration(
                                        labelText: l.isArabic
                                            ? 'اسم الضيف'
                                            : 'guest name'))),
                            SizedBox(
                                width: 220,
                                child: TextField(
                                    controller: gphoneCtrl,
                                    decoration: InputDecoration(
                                        labelText: l.isArabic
                                            ? 'هاتف الضيف (اختياري)'
                                            : 'guest phone (opt)'))),
                            SizedBox(
                                width: 220,
                                child: TextField(
                                    controller: gwalletCtrl,
                                    decoration: InputDecoration(
                                        labelText: l.isArabic
                                            ? 'محفظة الضيف (اختياري)'
                                            : 'guest wallet (opt)'))),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              PrimaryButton(
                                  label: l.isArabic ? 'تسعير' : 'Quote',
                                  onPressed: _quote),
                              PrimaryButton(
                                  label:
                                      l.isArabic ? 'حجز و دفع' : 'Book & Pay',
                                  onPressed: _book),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (out.isNotEmpty) SelectableText(out),
                          const SizedBox(height: 8),
                          Builder(builder: (_) {
                            final lq = _lastQuote;
                            if (lq == null) return const SizedBox.shrink();
                            final days = (lq['days'] as List?) ?? [];
                            if (days.isEmpty) return const SizedBox.shrink();
                            return GlassPanel(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      l.isArabic
                                          ? 'تفصيل يومي'
                                          : 'Daily breakdown',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  ...days.map((d) {
                                    final ds = (d['date'] ?? '').toString();
                                    final pc = (d['price_cents'] ?? 0) as int;
                                    final closed =
                                        (d['closed'] ?? false) == true;
                                    final sold =
                                        (d['sold_out'] ?? false) == true;
                                    final st = closed
                                        ? (l.isArabic ? 'مغلق' : 'CLOSED')
                                        : (sold
                                            ? (l.isArabic
                                                ? 'مباع بالكامل'
                                                : 'SOLD OUT')
                                            : '${(pc / 100).toStringAsFixed(2)}');
                                    final col = Colors.white70;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(ds),
                                          Text(st, style: TextStyle(color: col))
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final types = const [
      'Hotels',
      'Apartments',
      'Resorts',
      'Villas',
      'Cabins',
      'Cottages',
      'Glamping Sites',
      'Serviced Apartments',
      'Vacation Homes',
      'Guest Houses',
      'Hostels',
      'Motels',
      'B&Bs',
      'Ryokans',
      'Riads',
      'Resort Villages',
      'Homestays',
      'Campgrounds',
      'Country Houses',
      'Farm Stays',
      'Boats',
      'Luxury Tents',
      'Self-Catering Accomodations',
      'Tiny Houses'
    ];

    final typeSection = FormSection(
      title: l.rsBrowseByPropertyType,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ChoiceChip(
              label: Text(l.rsAllTypes),
              selected: _type.isEmpty,
              onSelected: (_) {
                setState(() => _type = '');
                _load();
              },
            ),
            const SizedBox(width: 6),
            ...types.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: _type == t,
                    onSelected: (_) {
                      setState(() => _type = t);
                      _load();
                    },
                  ),
                )),
          ]),
        ),
      ],
    );

    final searchSection = FormSection(
      title: l.isArabic ? 'البحث عن إقامة' : 'Search stays',
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(
              width: 220,
              child: TextField(
                  controller: qCtrl,
                  decoration: InputDecoration(labelText: l.labelSearch))),
          SizedBox(
              width: 220,
              child: TextField(
                  controller: cityCtrl,
                  decoration: InputDecoration(labelText: l.labelCity))),
          SizedBox(
              width: 120,
              child: PrimaryButton(label: l.reSearch, onPressed: _load)),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                initialValue: _sortBy,
                items: const [
                  DropdownMenuItem(
                      value: 'created_at', child: Text('Sort: Created')),
                  DropdownMenuItem(value: 'price', child: Text('Sort: Price')),
                  DropdownMenuItem(value: 'title', child: Text('Sort: Title')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _sortBy = v);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                initialValue: _order,
                items: [
                  DropdownMenuItem(
                      value: 'desc',
                      child:
                          Text(l.isArabic ? 'الأحدث أولاً' : 'Newest first')),
                  DropdownMenuItem(
                      value: 'asc',
                      child:
                          Text(l.isArabic ? 'الأقدم أولاً' : 'Oldest first')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _order = v);
                    _load();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                initialValue: _type.isEmpty ? null : _type,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.rsPropertyType),
                items: [
                  DropdownMenuItem(value: '', child: Text(l.rsAllTypes)),
                  ...types
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                ],
                onChanged: (v) {
                  setState(() => _type = v ?? '');
                  _load();
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
                width: 90,
                child: TextField(
                    controller: pageCtrl,
                    decoration: InputDecoration(labelText: l.labelPage))),
            const SizedBox(width: 8),
            SizedBox(
                width: 90,
                child: TextField(
                    controller: sizeCtrl,
                    decoration: InputDecoration(labelText: l.labelSize))),
            const SizedBox(width: 8),
            IconButton(onPressed: _prev, icon: const Icon(Icons.chevron_left)),
            IconButton(onPressed: _next, icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder(
          valueListenable: listOut,
          builder: (_, v, __) => StatusBanner.info(v.toString(), dense: true),
        ),
      ],
    );

    final listingsSection = FormSection(
      title: l.isArabic ? 'العروض المتاحة' : 'Available listings',
      children: [
        if (_items.isEmpty)
          Text(l.isArabic
              ? 'لا توجد عروض بعد.'
              : 'No listings yet – search with filters above.'),
        if (_items.isNotEmpty)
          ..._items.map((x) {
            final id = x['id'] ?? '';
            final title = (x['title'] ?? '').toString();
            final city = (x['city'] ?? '').toString();
            final price = ((x['price_per_night_cents'] ?? 0) as int);
            final imgs = (x['image_urls'] as List?) ?? const [];
            final img = imgs.isNotEmpty ? imgs.first.toString() : '';
            final ttype = (x['property_type'] ?? '').toString();
            final selected = (_lastQuoteLid != null && _lastQuoteLid == id);
            String? avail;
            try {
              if (selected && _lastQuote != null) {
                final days = (_lastQuote!['days'] as List?) ?? [];
                final anyClosed =
                    days.any((e) => (e['closed'] ?? false) == true);
                final anySold =
                    days.any((e) => (e['sold_out'] ?? false) == true);
                avail =
                    (anyClosed || anySold) ? l.rsUnavailable : l.rsAvailable;
              }
            } catch (_) {}
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: GlassPanel(
                padding: EdgeInsets.zero,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (img.isNotEmpty)
                        ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(20)),
                            child: Image.network(img,
                                height: 140,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox())),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        child: Row(children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(title,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 2),
                                Text(
                                    '${(price / 100).toStringAsFixed(2)} $_curSym  ·  $city',
                                    style:
                                        const TextStyle(color: Colors.white70)),
                              ])),
                        ]),
                      ),
                      if (avail != null)
                        Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white24)),
                                child: Text(avail!,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white70)))),
                      if (ttype.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white24)),
                              child: Text(ttype,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white70)),
                            )),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.end,
                            children: [
                              SizedBox(
                                  width: 140,
                                  child: PrimaryButton(
                                      label: l.rsPrices,
                                      onPressed: () {
                                        lidCtrl.text = id.toString();
                                        _quote();
                                      })),
                              SizedBox(
                                  width: 140,
                                  child: PrimaryButton(
                                      label: l.isArabic
                                          ? 'حجز الإقامة'
                                          : 'Book stay',
                                      onPressed: () {
                                        _openBookingForListing(
                                            int.tryParse(id.toString()) ?? 0);
                                      })),
                            ],
                          ),
                        ),
                      ),
                    ]),
              ),
            );
          }),
      ],
    );

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_bannerMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusBanner(
                kind: _bannerKind, message: _bannerMsg, dense: true),
          ),
        typeSection,
        searchSection,
        listingsSection,
      ],
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.homeStays)),
      body: SafeArea(child: content),
    );
  }
}

class FreightPage extends StatefulWidget {
  final String baseUrl;
  const FreightPage(this.baseUrl, {super.key});
  @override
  State<FreightPage> createState() => _FreightPageState();
}

class FoodPage extends StatefulWidget {
  final String baseUrl;
  const FoodPage(this.baseUrl, {super.key});
  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  final addressCtrl = TextEditingController();
  final qCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  List<dynamic> _restaurants = const [];
  bool _restsLoading = false;
  String _restsOut = '';
  final ridCtrl = TextEditingController();
  final cnameCtrl = TextEditingController();
  final cphoneCtrl = TextEditingController();
  final wCtrl = TextEditingController();
  final oidCtrl = TextEditingController();
  String oOut = '';
  String sOut = '';
  String _bannerMsg = '';
  StatusKind _bannerKind = StatusKind.info;
  // Courier request (for Food operator)
  final courierPickupCtrl = TextEditingController();
  final courierDropCtrl = TextEditingController();
  final courierWeightCtrl = TextEditingController(text: '1.0');
  final courierIdCtrl = TextEditingController();
  double? _courierPickupLat;
  double? _courierPickupLon;
  double? _courierDropLat;
  double? _courierDropLon;
  String _courierOut = '';
  String _courierStatus = '';
  String _lastOrderId = '';
  String _lastOrderStatus = '';
  int _lastOrderTotalCents = 0;
  bool _lastOrderLoading = false;

  @override
  void initState() {
    super.initState();
    _loadWallet();
    Future.microtask(_loadLastOrderSummary);
  }

  void _applyAddressAndLoad() {
    final addr = addressCtrl.text.trim();
    if (addr.isEmpty) return;
    // Naive city extraction: last part after comma or full string.
    String city = addr;
    final parts = addr.split(',');
    if (parts.length > 1) {
      city = parts.last.trim();
    }
    cityCtrl.text = city;
    qCtrl.text = '';
    _loadRests();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty) {
        wCtrl.text = w;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _loadRests() async {
    setState(() {
      _restsLoading = true;
      _restsOut = '';
      _restaurants = const [];
    });
    final uri = Uri.parse(
      '${widget.baseUrl}/food/restaurants?q=${Uri.encodeComponent(qCtrl.text)}&city=${Uri.encodeComponent(cityCtrl.text)}',
    );
    try {
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        try {
          final body = jsonDecode(r.body);
          if (body is List) {
            _restaurants = body;
            _restsOut = '';
          } else {
            _restaurants = const [];
            _restsOut = 'Unexpected response: ${r.body}';
          }
        } catch (e) {
          _restaurants = const [];
          _restsOut = 'Error parsing restaurants: $e';
        }
      } else {
        _restaurants = const [];
        _restsOut = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _restaurants = const [];
      _restsOut = 'error: $e';
    } finally {
      if (mounted) {
        setState(() => _restsLoading = false);
      }
    }
  }

  Future<void> _loadLastOrderSummary() async {
    setState(() {
      _lastOrderLoading = true;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      final phone = sp.getString('last_login_phone') ?? '';
      if (phone.isEmpty) {
        return;
      }
      final uri = Uri.parse('${widget.baseUrl}/food/orders')
          .replace(queryParameters: {'phone': phone, 'limit': '1'});
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List && body.isNotEmpty && body.first is Map) {
          final o = body.first as Map;
          if (mounted) {
            setState(() {
              _lastOrderId = (o['id'] ?? '').toString();
              _lastOrderStatus = (o['status'] ?? '').toString();
              _lastOrderTotalCents = (o['total_cents'] ?? 0) as int;
            });
          }
        }
      }
    } catch (_) {
      // Best-effort only; ignore errors.
    } finally {
      if (mounted) {
        setState(() {
          _lastOrderLoading = false;
        });
      }
    }
  }

  void _openFoodOrders() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FoodOrdersPage(widget.baseUrl),
      ),
    );
  }

  Future<void> _scanDeliveryQr() async {
    try {
      final raw = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScanPage()),
      );
      if (!mounted) return;
      if (raw == null) return;
      final text = raw.toString();
      if (!text.startsWith('FOOD_ESCROW|')) {
        final l = L10n.of(context);
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = l.isArabic
              ? 'ليس رمز تسليم للطعام'
              : 'Not a food delivery QR';
        });
        return;
      }
      final Map<String, String> map = {};
      try {
        final parts = text.split('|');
        for (final p in parts.skip(1)) {
          final kv = p.split('=');
          if (kv.length != 2) continue;
          final key = kv[0].trim();
          final value = Uri.decodeComponent(kv[1].trim());
          if (key.isNotEmpty) {
            map[key] = value;
          }
        }
      } catch (_) {}
      final oid = (map['order_id'] ?? '').trim();
      final token = (map['token'] ?? '').trim();
      final l = L10n.of(context);
      if (oid.isEmpty || token.isEmpty) {
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = l.isArabic
              ? 'رمز تسليم غير مكتمل'
              : 'Incomplete delivery QR';
        });
        return;
      }
      final uri =
          Uri.parse('${widget.baseUrl}/food/orders/$oid/escrow_release');
      final r = await http.post(
        uri,
        headers: await _hdr(json: true),
        body: jsonEncode({'token': token}),
      );
      setState(() {
        _bannerKind =
            r.statusCode == 200 ? StatusKind.success : StatusKind.error;
        _bannerMsg = '${r.statusCode}: ${r.body}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = 'Scan error: $e';
      });
    }
  }

  Future<bool> _courierEnsureCoords() async {
    // Geocode pickup and dropoff addresses using /osm/geocode
    Future<bool> geocodeOnce(String text, bool pickup) async {
      final q = text.trim();
      if (q.isEmpty) return false;
      try {
        final uri = Uri.parse('${widget.baseUrl}/osm/geocode')
            .replace(queryParameters: {'q': q});
        final r = await http.get(uri);
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          if (data is List && data.isNotEmpty) {
            final first = data.first;
            final lat = double.tryParse((first['lat'] ?? '').toString());
            final lon = double.tryParse((first['lon'] ?? '').toString());
            if (lat != null && lon != null) {
              if (pickup) {
                _courierPickupLat = lat;
                _courierPickupLon = lon;
              } else {
                _courierDropLat = lat;
                _courierDropLon = lon;
              }
              return true;
            }
          }
        }
      } catch (_) {}
      return false;
    }

    bool ok = true;
    if (_courierPickupLat == null || _courierPickupLon == null) {
      ok = await geocodeOnce(courierPickupCtrl.text, true) && ok;
    }
    if (_courierDropLat == null || _courierDropLon == null) {
      ok = await geocodeOnce(courierDropCtrl.text, false) && ok;
    }
    if (!ok) {
      setState(() {
        _courierOut = 'Please check pickup/dropoff addresses for courier.';
      });
    }
    return ok;
  }

  Future<void> _courierQuote() async {
    setState(() => _courierOut = '...');
    if (!await _courierEnsureCoords()) {
      return;
    }
    final lat1 = _courierPickupLat!;
    final lon1 = _courierPickupLon!;
    final lat2 = _courierDropLat!;
    final lon2 = _courierDropLon!;
    final weight = double.tryParse(courierWeightCtrl.text.trim()) ?? 1.0;
    final body = jsonEncode({
      'title':
          'Food courier from restaurant ${ridCtrl.text.trim().isEmpty ? "-" : ridCtrl.text.trim()}',
      'from_lat': lat1,
      'from_lon': lon1,
      'to_lat': lat2,
      'to_lon': lon2,
      'weight_kg': weight <= 0 ? 1.0 : weight,
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/courier/quote');
      final r =
          await http.post(uri, headers: await _hdr(json: true), body: body);
      if (r.statusCode == 200) {
        try {
          final j = jsonDecode(r.body);
          final dist = (j['distance_km'] ?? 0) as num;
          final cents = (j['amount_cents'] ?? 0) as int;
          final cur = (j['currency'] ?? 'SYP').toString();
          setState(() {
            _courierOut =
                'Distance: ${dist.toStringAsFixed(2)} km · ${fmtCents(cents)} $cur';
          });
        } catch (e) {
          setState(() => _courierOut = 'Parse error: $e');
        }
      } else {
        setState(() => _courierOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => _courierOut = 'error: $e');
    }
  }

  Future<void> _courierBook() async {
    setState(() => _courierStatus = '...');
    if (!await _courierEnsureCoords()) {
      return;
    }
    final lat1 = _courierPickupLat!;
    final lon1 = _courierPickupLon!;
    final lat2 = _courierDropLat!;
    final lon2 = _courierDropLon!;
    final weight = double.tryParse(courierWeightCtrl.text.trim()) ?? 1.0;
    final payerWallet = wCtrl.text.trim();
    final body = jsonEncode({
      'title':
          'Food courier from restaurant ${ridCtrl.text.trim().isEmpty ? "-" : ridCtrl.text.trim()}',
      'from_lat': lat1,
      'from_lon': lon1,
      'to_lat': lat2,
      'to_lon': lon2,
      'weight_kg': weight <= 0 ? 1.0 : weight,
      'payer_wallet_id': payerWallet.isEmpty ? null : payerWallet,
      'confirm': true,
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/courier/book');
      final r =
          await http.post(uri, headers: await _hdr(json: true), body: body);
      String msg = '${r.statusCode}: ${r.body}';
      try {
        final j = jsonDecode(r.body);
        if (j is Map) {
          final sid = (j['id'] ?? '').toString();
          if (sid.isNotEmpty) {
            courierIdCtrl.text = sid;
            msg = 'Shipment $sid booked (${r.statusCode})';
          }
        }
      } catch (_) {}
      setState(() => _courierStatus = msg);
    } catch (e) {
      setState(() => _courierStatus = 'error: $e');
    }
  }

  Future<void> _courierStatusRefresh() async {
    final sid = courierIdCtrl.text.trim();
    if (sid.isEmpty) {
      setState(() => _courierStatus = 'Set shipment id first');
      return;
    }
    setState(() => _courierStatus = '...');
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/courier/shipments/' + Uri.encodeComponent(sid));
      final r = await http.get(uri, headers: await _hdr());
      setState(() => _courierStatus = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => _courierStatus = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final addressSection = FormSection(
      title:
          l.isArabic ? 'أين تريد أن نوصّل؟' : 'Where should we deliver?',
      children: [
        Text(
          l.isArabic
              ? 'أدخل عنوانك لنُظهر لك المطاعم، البقالة والمتاجر القريبة منك.'
              : 'Enter your address to see restaurants, groceries and convenience stores near you.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .75),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0.5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.dividerColor.withValues(alpha: .4),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Tokens.colorFood.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.location_on_outlined,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: addressCtrl,
                        decoration: InputDecoration(
                          labelText:
                              l.isArabic ? 'العنوان' : 'Delivery address',
                          helperText: l.isArabic
                              ? 'مثال: دمشق، ساروجة'
                              : 'Example: Damascus, Sarouja',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: 200,
                          child: PrimaryButton(
                            label: l.isArabic
                                ? 'اعرض المطاعم القريبة'
                                : 'Show options nearby',
                            onPressed: _applyAddressAndLoad,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.restaurant_outlined, size: 18),
              label: Text(
                l.isArabic ? 'مطاعم' : 'Restaurants',
              ),
            ),
            Chip(
              avatar:
                  const Icon(Icons.local_grocery_store_outlined, size: 18),
              label: Text(
                l.isArabic ? 'بقالة' : 'Groceries',
              ),
            ),
            Chip(
              avatar: const Icon(Icons.storefront_outlined, size: 18),
              label: Text(
                l.isArabic ? 'متاجر سريعة' : 'Convenience',
              ),
            ),
            Chip(
              avatar: const Icon(Icons.cake_outlined, size: 18),
              label: Text(
                l.isArabic ? 'حلويات' : 'Sweets',
              ),
            ),
          ],
        )
      ],
    );
    List<Map<String, dynamic>> restRestaurants = [];
    List<Map<String, dynamic>> restGroceries = [];
    List<Map<String, dynamic>> restConvenience = [];
    List<Map<String, dynamic>> restSweets = [];
    for (final r in _restaurants) {
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r as Map);
      final name = (m['name'] ?? '').toString().toLowerCase();
      if (name.contains('market') ||
          name.contains('grocery') ||
          name.contains('سوبر') ||
          name.contains('ماركت')) {
        restGroceries.add(m);
      } else if (name.contains('mini') ||
          name.contains('mart') ||
          name.contains('shop') ||
          name.contains('convenience')) {
        restConvenience.add(m);
      } else if (name.contains('sweet') ||
          name.contains('cake') ||
          name.contains('bakery') ||
          name.contains('حلويات')) {
        restSweets.add(m);
      } else {
        restRestaurants.add(m);
      }
    }

    Widget buildCategoryRow(
        String title, List<Map<String, dynamic>> items, IconData icon) {
      if (_restsLoading) {
        return const LinearProgressIndicator(minHeight: 2);
      }
      if (_restsOut.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: StatusBanner.info(_restsOut, dense: true),
        );
      }
      if (items.isEmpty) {
        return Text(
          l.isArabic ? 'لا شيء متاح حالياً.' : 'Nothing available yet.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .70),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              Text(
                l.isArabic
                    ? '${items.length} خيار'
                    : '${items.length} options',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: items.take(12).map((m) {
                final id = (m['id'] ?? '').toString();
                final name = (m['name'] ?? '').toString();
                final city = (m['city'] ?? '').toString();
                // Placeholder meta for now – backend has no ratings/ETA yet.
                const rating = '4.7';
                const reviews = '–';
                const eta = '10–15 min';
                const freeFrom = 'Free delivery from 100000 SYP';
                return Container(
                  width: 260,
                  margin: const EdgeInsets.only(right: 12),
                    child: Card(
                    elevation: 0.5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color:
                            theme.dividerColor.withValues(alpha: .35),
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        final rid = int.tryParse(id) ?? 0;
                        if (rid <= 0) return;
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => FoodCheckoutPage(
                                  baseUrl: widget.baseUrl,
                                  restaurantId: rid,
                                  restaurantName:
                                      name.isEmpty ? 'Restaurant #$id' : name,
                                  restaurantCity: city,
                                )));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(icon,
                                    color: Tokens.colorFood, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    name.isEmpty ? 'Restaurant #$id' : name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              city.isEmpty ? 'ID $id' : city,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .80),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '★ $rating ($reviews) · $eta',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .85),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              freeFrom,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: .75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      );
    }

    final courierSection = FormSection(
      title: l.isArabic ? 'طلب مندوب توصيل' : 'Request courier',
      children: [
        Text(
          l.isArabic
              ? 'يمكن لمشغل Food طلب مندوب لتوصيل الطلب من المطعم إلى الزبون.'
              : 'As a Food operator, you can request a courier to deliver the order from the restaurant to the customer.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: courierPickupCtrl,
          decoration: InputDecoration(
            labelText: l.isArabic
                ? 'عنوان الاستلام (المطعم)'
                : 'Pickup address (restaurant)',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: courierDropCtrl,
          decoration: InputDecoration(
            labelText: l.isArabic
                ? 'عنوان التسليم (الزبون)'
                : 'Dropoff address (customer)',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: courierWeightCtrl,
          decoration: InputDecoration(
            labelText:
                l.isArabic ? 'الوزن (كغ، اختياري)' : 'Weight (kg, optional)',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: courierIdCtrl,
          decoration: InputDecoration(
            labelText: l.isArabic
                ? 'معرّف الشحنة (اختياري)'
                : 'Shipment id (optional)',
            helperText: l.isArabic
                ? 'يتم تعبئة هذا الحقل تلقائياً عند حجز مندوب. يمكنك لصقه هنا لمتابعة حالة الشحنة.'
                : 'This is filled automatically when booking a courier. You can paste an id here to track status.',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: l.isArabic ? 'تسعير المندوب' : 'Quote courier',
                onPressed: _courierQuote,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PrimaryButton(
                label: l.isArabic ? 'حجز و دفع المندوب' : 'Book courier',
                onPressed: _courierBook,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _courierStatusRefresh,
            icon: const Icon(Icons.local_shipping_outlined),
            label: Text(
                l.isArabic ? 'تحديث حالة الشحنة' : 'Refresh shipment status'),
          ),
        ),
        if (_courierOut.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: StatusBanner.info(_courierOut, dense: true),
          ),
        if (_courierStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: StatusBanner.info(_courierStatus, dense: true),
          ),
      ],
    );
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_bannerMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusBanner(
                kind: _bannerKind, message: _bannerMsg, dense: true),
          ),
        addressSection,
        const SizedBox(height: 16),
        FormSection(
          title: l.isArabic ? 'طلباتي' : 'My orders',
          children: [
            if (_lastOrderLoading)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_lastOrderId.isNotEmpty)
              Card(
                elevation: 0.5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: theme.dividerColor.withValues(alpha: .35),
                  ),
                ),
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                    l.isArabic
                        ? 'آخر طلب #$_lastOrderId'
                        : 'Last order #$_lastOrderId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _lastOrderTotalCents > 0
                        ? '${fmtCents(_lastOrderTotalCents)} SYP · ${_lastOrderStatus}'
                        : _lastOrderStatus,
                  ),
                  trailing: TextButton(
                    onPressed: _openFoodOrders,
                    child: Text(
                      l.isArabic ? 'تتبع' : 'Track',
                    ),
                  ),
                  onTap: _openFoodOrders,
                ),
              )
            else
              Text(
                l.isArabic
                    ? 'لا توجد طلبات بعد. اطلب أول وجبة لك الآن.'
                    : 'No orders yet. Discover restaurants and place your first order.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: .70),
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _openFoodOrders,
                icon: const Icon(Icons.list_alt_outlined),
                label: Text(
                  l.isArabic ? 'عرض جميع الطلبات' : 'View all orders',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FormSection(
          title: l.isArabic ? 'المطاعم' : 'Restaurants',
          children: [buildCategoryRow(l.isArabic ? 'المطاعم' : 'Restaurants', restRestaurants, Icons.restaurant_outlined)],
        ),
        const SizedBox(height: 12),
        FormSection(
          title: l.isArabic ? 'البقالة' : 'Groceries',
          children: [buildCategoryRow(l.isArabic ? 'البقالة' : 'Groceries', restGroceries, Icons.local_grocery_store_outlined)],
        ),
        const SizedBox(height: 12),
        FormSection(
          title: l.isArabic ? 'المتاجر السريعة' : 'Convenience',
          children: [buildCategoryRow(l.isArabic ? 'المتاجر السريعة' : 'Convenience', restConvenience, Icons.storefront_outlined)],
        ),
        const SizedBox(height: 12),
        FormSection(
          title: l.isArabic ? 'الحلويات' : 'Sweets',
          children: [buildCategoryRow(l.isArabic ? 'الحلويات' : 'Sweets', restSweets, Icons.cake_outlined)],
        ),
        const SizedBox(height: 16),
        courierSection,
        const SizedBox(height: 16),
        FormSection(
          title: l.isArabic ? 'استلام الطلب' : 'Order delivery',
          children: [
            Text(
              l.isArabic
                  ? 'بعد استلام الطلب من المندوب، امسح رمز QR الخاص بالتسليم لإطلاق الدفعة من محفظتك إلى المطعم.'
                  : 'After the courier hands over your order, scan their delivery QR code to release the escrow payment from your wallet to the restaurant.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 220,
              child: PrimaryButton(
                label:
                    l.isArabic ? 'مسح رمز التسليم' : 'Scan delivery QR',
                onPressed: _scanDeliveryQr,
              ),
            ),
          ],
        ),
      ],
    );
    return Scaffold(
        appBar: AppBar(
            title: Text(l.homeFood), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          bg,
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }
}

class FoodCheckoutPage extends StatefulWidget {
  final String baseUrl;
  final int restaurantId;
  final String restaurantName;
  final String restaurantCity;
  const FoodCheckoutPage({
    super.key,
    required this.baseUrl,
    required this.restaurantId,
    required this.restaurantName,
    required this.restaurantCity,
  });

  @override
  State<FoodCheckoutPage> createState() => _FoodCheckoutPageState();
}

class _FoodCheckoutPageState extends State<FoodCheckoutPage> {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final walletCtrl = TextEditingController();
  final orderIdCtrl = TextEditingController();

  List<dynamic> _menu = const [];
  bool _loadingMenu = false;
  bool _submitting = false;
  String _out = '';
  final Map<int, int> _qtyById = <int, int>{};

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _loadMenu();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty && mounted) {
        setState(() {
          walletCtrl.text = w;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadMenu() async {
    setState(() {
      _loadingMenu = true;
      _menu = const [];
      _out = '';
    });
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/food/restaurants/${widget.restaurantId}/menu');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() {
            _menu = body;
          });
        } else {
          setState(() {
            _out = '${r.statusCode}: ${r.body}';
          });
        }
      } else {
        setState(() {
          _out = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _out = 'error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingMenu = false);
      }
    }
  }

  int _qtyFor(int id) => _qtyById[id] ?? 0;

  void _changeQty(int id, int delta) {
    setState(() {
      final cur = _qtyById[id] ?? 0;
      final next = cur + delta;
      if (next <= 0) {
        _qtyById.remove(id);
      } else {
        _qtyById[id] = next;
      }
    });
  }

  Future<void> _placeOrder() async {
    if (_menu.isEmpty) {
      setState(() => _out = 'load menu first');
      return;
    }
    final wallet = walletCtrl.text.trim();
    if (wallet.isEmpty) {
      setState(() => _out = 'set wallet id for payment');
      return;
    }
    final items = <Map<String, dynamic>>[];
    for (final m in _menu) {
      if (m is! Map) continue;
      final id = (m['id'] ?? 0) as int;
      final q = _qtyFor(id);
      if (q > 0) {
        items.add({'menu_item_id': id, 'qty': q});
      }
    }
    if (items.isEmpty) {
      setState(() => _out = 'select at least one item');
      return;
    }
    setState(() {
      _submitting = true;
      _out = '';
    });
    final uri = Uri.parse('${widget.baseUrl}/food/orders');
    final payload = {
      'restaurant_id': widget.restaurantId,
      'customer_name':
          nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      'customer_phone':
          phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      'customer_wallet_id': wallet,
      'items': items,
      'confirm': true,
    };
    try {
      final headers = await _hdr(json: true);
      headers['Idempotency-Key'] =
          'food-${DateTime.now().millisecondsSinceEpoch}';
      final r = await http.post(uri,
          headers: headers, body: jsonEncode(payload));
      setState(() => _out = '${r.statusCode}: ${r.body}');
      try {
        final j = jsonDecode(r.body);
        final id = (j['id'] ?? '').toString();
        if (id.isNotEmpty) {
          orderIdCtrl.text = id;
        }
      } catch (_) {}
    } catch (e) {
      setState(() => _out = 'error: $e');
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    const bg = AppBG();
    final theme = Theme.of(context);
    int totalCents = 0;
    for (final m in _menu) {
      if (m is! Map) continue;
      final id = (m['id'] ?? 0) as int;
      final q = _qtyFor(id);
      if (q <= 0) continue;
      final cents = (m['price_cents'] ?? 0) as int;
      totalCents += cents * q;
    }
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          widget.restaurantName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        if (widget.restaurantCity.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text(
              widget.restaurantCity,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
          ),
        if (_out.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusBanner.info(_out, dense: true),
          ),
        const SizedBox(height: 8),
        Text(
          l.isArabic ? 'القائمة' : 'Menu',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (_loadingMenu)
          const LinearProgressIndicator(minHeight: 2)
        else if (_menu.isEmpty)
          Text(
            l.isArabic
                ? 'لا توجد عناصر متاحة حالياً.'
                : 'No items available yet.',
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: .70),
            ),
          )
        else
          ..._menu.map((m) {
            if (m is! Map) return const SizedBox.shrink();
            final id = (m['id'] ?? 0) as int;
            final name = (m['name'] ?? '').toString();
            final cents = (m['price_cents'] ?? 0) as int;
            final cur = (m['currency'] ?? 'SYP').toString();
            final qty = _qtyFor(id);
            final price = cents > 0
                ? '${fmtCents(cents)} ${cur.isNotEmpty ? cur : 'SYP'}'
                : '';
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? 'Item #$id' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          if (price.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 2.0),
                              child: Text(
                                price,
                                style:
                                    theme.textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _changeQty(id, -1),
                        ),
                        Text(
                          qty.toString(),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _changeQty(id, 1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        const SizedBox(height: 16),
        Text(
          l.isArabic ? 'بيانات الدفع' : 'Payment details',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: l.isArabic ? 'اسم الزبون' : 'Customer name',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: phoneCtrl,
          decoration: InputDecoration(
            labelText:
                l.isArabic ? 'الهاتف (اختياري)' : 'Phone (optional)',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: walletCtrl,
          decoration: InputDecoration(
            labelText: l.isArabic ? 'محفظة الدفع' : 'Wallet for payment',
          ),
        ),
        const SizedBox(height: 12),
        if (totalCents > 0)
          Text(
            l.isArabic
                ? 'الإجمالي: ${fmtCents(totalCents)} SYP'
                : 'Total: ${fmtCents(totalCents)} SYP',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16),
          ),
        const SizedBox(height: 12),
        PrimaryButton(
          label: _submitting
              ? (l.isArabic ? 'جاري المعالجة…' : 'Processing…')
              : (l.isArabic ? 'طلب و دفع' : 'Order & pay'),
          onPressed: _submitting ? null : _placeOrder,
          expanded: true,
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'طلب طعام' : 'Food checkout'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          bg,
          Positioned.fill(
            child: SafeArea(
              child: GlassPanel(
                padding: const EdgeInsets.all(16),
                child: content,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CarmarketPage extends StatefulWidget {
  final String baseUrl;
  const CarmarketPage(this.baseUrl, {super.key});
  @override
  State<CarmarketPage> createState() => _CarmarketPageState();
}

class _CarmarketPageState extends State<CarmarketPage> {
  final qCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  String list = '';
  List<dynamic> _items = const [];
  String _listOut = '';
  bool _listLoading = false;
  final titleCtrl = TextEditingController();
  final priceCtrl = TextEditingController(text: '100000');
  final makeCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  final yearCtrl = TextEditingController();
  final ownerCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final selCtrl = TextEditingController();
  final inameCtrl = TextEditingController();
  final iphoneCtrl = TextEditingController();
  final imsgCtrl = TextEditingController();
  String out = '';
  String iout = '';
  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty) {
        ownerCtrl.text = w;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _listLoading = true;
      _listOut = '';
    });
    try {
      final u = Uri.parse(
          '${widget.baseUrl}/carmarket/listings?q=${Uri.encodeComponent(qCtrl.text)}&city=${Uri.encodeComponent(cityCtrl.text)}');
      final r = await http.get(u, headers: await _hdr());
      if (!mounted) return;
      list = '${r.statusCode}: ${r.body}';
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() {
            _items = body;
            _listOut = '';
          });
        } else {
          setState(() {
            _items = const [];
            _listOut = '${r.statusCode}: ${r.body}';
          });
        }
      } else {
        setState(() {
          _items = const [];
          _listOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _listOut = 'error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _listLoading = false);
      }
    }
  }

  Future<void> _deleteListing(int id) async {
    try {
      final r = await http.delete(
          Uri.parse('${widget.baseUrl}/carmarket/listings/$id'),
          headers: await _hdr());
      if (mounted) {
        setState(() => _listOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _listOut = 'error: $e');
      }
    }
    await _load();
  }

  Future<void> _create() async {
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'car-${DateTime.now().millisecondsSinceEpoch}';
    final r = await http.post(Uri.parse('${widget.baseUrl}/carmarket/listings'),
        headers: h,
        body: jsonEncode({
          'title': titleCtrl.text.trim(),
          'price_cents': int.tryParse(priceCtrl.text.trim()) ?? 0,
          'make': makeCtrl.text.trim().isEmpty ? null : makeCtrl.text.trim(),
          'model': modelCtrl.text.trim().isEmpty ? null : modelCtrl.text.trim(),
          'year': int.tryParse(yearCtrl.text.trim()),
          'city': cityCtrl.text.trim().isEmpty ? null : cityCtrl.text.trim(),
          'description':
              descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
          'owner_wallet_id':
              ownerCtrl.text.trim().isEmpty ? null : ownerCtrl.text.trim()
        }));
    setState(() => out = '${r.statusCode}: ${r.body}');
    _load();
  }

  Future<void> _inquiry() async {
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'ci-${DateTime.now().millisecondsSinceEpoch}';
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/carmarket/inquiries'),
        headers: h,
        body: jsonEncode({
          'listing_id': int.tryParse(selCtrl.text.trim()) ?? 0,
          'name': inameCtrl.text.trim(),
          'phone':
              iphoneCtrl.text.trim().isEmpty ? null : iphoneCtrl.text.trim(),
          'message': imsgCtrl.text.trim().isEmpty ? null : imsgCtrl.text.trim()
        }));
    setState(() => iout = '${r.statusCode}: ${r.body}');
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: qCtrl,
                decoration: InputDecoration(labelText: l.labelSearch))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: cityCtrl,
                decoration: InputDecoration(labelText: l.labelCity))),
        SizedBox(
            width: 140, child: WaterButton(label: l.reSearch, onTap: _load)),
      ]),
      const SizedBox(height: 8),
      if (_listLoading)
        const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      if (_listOut.isNotEmpty) StatusBanner.info(_listOut, dense: true),
      const SizedBox(height: 8),
      if (_items.isNotEmpty) ...[
        Builder(builder: (ctx) {
          int totalPrice = 0;
          for (final x in _items) {
            try {
              final p = x['price_cents'];
              if (p is int) {
                totalPrice += p;
              }
            } catch (_) {}
          }
          final count = _items.length;
          final avg = count > 0 ? (totalPrice ~/ count) : 0;
          final txt = l.isArabic
              ? 'العروض: $count · القيمة الإجمالية: ${totalPrice} ل.س · متوسط السعر: ${avg} ل.س'
              : 'Listings: $count · Total value: ${totalPrice} SYP · Avg price: ${avg} SYP';
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: StatusBanner.info(txt, dense: true),
          );
        }),
        const SizedBox(height: 4),
      ],
      ..._items.map((x) {
        final id = (x['id'] ?? '').toString();
        final title = (x['title'] ?? '').toString();
        final city = (x['city'] ?? '').toString();
        final make = (x['make'] ?? '').toString();
        final model = (x['model'] ?? '').toString();
        final year = (x['year'] ?? '').toString();
        final price = x['price_cents'];
        final priceStr = price == null ? '' : '${price} SYP';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassPanel(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Listing $id · $title',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$city  ·  $make $model $year'),
                if (priceStr.isNotEmpty)
                  Text(priceStr, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    SizedBox(
                      height: 32,
                      child: ElevatedButton(
                        onPressed: () {
                          selCtrl.text = id;
                        },
                        child: Text(l.isArabic ? 'اختيار' : 'Select'),
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: OutlinedButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text(
                                  l.isArabic ? 'حذف العرض' : 'Delete listing'),
                              content: Text(l.isArabic
                                  ? 'هل تريد حذف هذا العرض؟'
                                  : 'Delete this listing?'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child:
                                        Text(l.isArabic ? 'إلغاء' : 'Cancel')),
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: Text(l.isArabic ? 'حذف' : 'Delete')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await _deleteListing(int.tryParse(id) ?? 0);
                          }
                        },
                        child: Text(l.isArabic ? 'حذف' : 'Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
      const Divider(height: 24),
      TextField(
          controller: titleCtrl,
          decoration:
              InputDecoration(labelText: l.isArabic ? 'العنوان' : 'title')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: priceCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'السعر (ليرة)' : 'price (SYP)'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: ownerCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'محفظة المالك' : 'owner wallet'))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: makeCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'الشركة المصنعة' : 'make'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: modelCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'الطراز' : 'model'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: yearCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'سنة الصنع' : 'year'))),
      ]),
      const SizedBox(height: 8),
      TextField(
          controller: descCtrl,
          decoration:
              InputDecoration(labelText: l.isArabic ? 'الوصف' : 'description')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'إنشاء' : 'Create', onTap: _create))
      ]),
      const Divider(height: 24),
      TextField(
          controller: selCtrl,
          decoration: InputDecoration(
              labelText: l.isArabic ? 'معرّف العرض' : 'listing id')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 180,
            child: WaterButton(label: l.reSendInquiry, onTap: _inquiry))
      ]),
      const SizedBox(height: 8),
      if (out.isNotEmpty) StatusBanner.info(out, dense: true),
      const SizedBox(height: 8),
      if (iout.isNotEmpty) StatusBanner.info(iout, dense: true),
    ]);
    return Scaffold(
      appBar: AppBar(
          title: Text(l.carmarketTitle), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        Positioned.fill(
            child: SafeArea(
                child: GlassPanel(
                    padding: const EdgeInsets.all(16), child: content))),
      ]),
    );
  }
}

class CarrentalPage extends StatefulWidget {
  final String baseUrl;
  const CarrentalPage(this.baseUrl, {super.key});
  @override
  State<CarrentalPage> createState() => _CarrentalPageState();
}

class _CarrentalPageState extends State<CarrentalPage> {
  final qCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final carIdCtrl = TextEditingController();
  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final rwCtrl = TextEditingController();
  final bidCtrl = TextEditingController();
  String qOut = '', bOut = '', bsOut = '';
  List<dynamic> _cars = const [];
  String _carsOut = '';
  bool confirm = true;
  // Operator view: aggregated bookings
  String _bookingStatusFilter = '';
  bool _bookingsLoading = false;
  String _bookingsOut = '';
  List<dynamic> _bookings = const [];
  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty) {
        rwCtrl.text = w;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _loadCars() async {
    final u = Uri.parse(
        '${widget.baseUrl}/carrental/cars?q=${Uri.encodeComponent(qCtrl.text)}&city=${Uri.encodeComponent(cityCtrl.text)}');
    final r = await http.get(u, headers: await _hdr());
    if (!mounted) return;
    try {
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() {
            _cars = body;
            _carsOut = '';
          });
        } else {
          setState(() {
            _cars = const [];
            _carsOut = '${r.statusCode}: ${r.body}';
          });
        }
      } else {
        setState(() {
          _cars = const [];
          _carsOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      setState(() {
        _cars = const [];
        _carsOut = 'error: $e';
      });
    }
  }

  Future<void> _quote() async {
    final r = await http.post(Uri.parse('${widget.baseUrl}/carrental/quote'),
        headers: await _hdr(json: true),
        body: jsonEncode({
          'car_id': int.tryParse(carIdCtrl.text.trim()) ?? 0,
          'from_iso': fromCtrl.text.trim(),
          'to_iso': toCtrl.text.trim()
        }));
    setState(() => qOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _book() async {
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'crb-${DateTime.now().millisecondsSinceEpoch}';
    final r = await http.post(Uri.parse('${widget.baseUrl}/carrental/book'),
        headers: h,
        body: jsonEncode({
          'car_id': int.tryParse(carIdCtrl.text.trim()) ?? 0,
          'renter_name': nameCtrl.text.trim(),
          'renter_phone':
              phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
          'renter_wallet_id':
              rwCtrl.text.trim().isEmpty ? null : rwCtrl.text.trim(),
          'from_iso': fromCtrl.text.trim(),
          'to_iso': toCtrl.text.trim(),
          'confirm': confirm
        }));
    setState(() => bOut = '${r.statusCode}: ${r.body}');
    try {
      final j = jsonDecode(r.body);
      bidCtrl.text = (j['id'] ?? '').toString();
    } catch (_) {}
  }

  Future<void> _status() async {
    final id = bidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http.get(
        Uri.parse('${widget.baseUrl}/carrental/bookings/$id'),
        headers: await _hdr());
    setState(() => bsOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _cancel() async {
    final id = bidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http
        .post(Uri.parse('${widget.baseUrl}/carrental/bookings/$id/cancel'));
    setState(() => bsOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _confirm() async {
    final id = bidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/carrental/bookings/$id/confirm'),
        headers: await _hdr(json: true),
        body: jsonEncode({'confirm': true}));
    setState(() => bsOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _loadBookings() async {
    setState(() {
      _bookingsLoading = true;
      _bookingsOut = '';
    });
    try {
      final params = <String, String>{'limit': '100'};
      if (_bookingStatusFilter.isNotEmpty) {
        params['status'] = _bookingStatusFilter;
      }
      final uri = Uri.parse('${widget.baseUrl}/carrental/bookings')
          .replace(queryParameters: params);
      final r = await http.get(uri, headers: await _hdr());
      if (!mounted) return;
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is List) {
          setState(() {
            _bookings = body;
            _bookingsOut = '';
          });
        } else {
          setState(() {
            _bookings = const [];
            _bookingsOut = '${r.statusCode}: ${r.body}';
          });
        }
      } else {
        setState(() {
          _bookings = const [];
          _bookingsOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bookings = const [];
        _bookingsOut = 'error: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _bookingsLoading = false);
      }
    }
  }

  Future<void> _opConfirm(String id) async {
    try {
      final r = await http.post(
        Uri.parse('${widget.baseUrl}/carrental/bookings/$id/confirm'),
        headers: await _hdr(json: true),
        body: jsonEncode({'confirm': true}),
      );
      if (mounted) {
        setState(() => _bookingsOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _bookingsOut = 'error: $e');
      }
    }
    await _loadBookings();
  }

  Future<void> _opCancel(String id) async {
    try {
      final r = await http
          .post(Uri.parse('${widget.baseUrl}/carrental/bookings/$id/cancel'));
      if (mounted) {
        setState(() => _bookingsOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _bookingsOut = 'error: $e');
      }
    }
    await _loadBookings();
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: qCtrl,
                decoration: InputDecoration(labelText: l.labelSearch))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: cityCtrl,
                decoration: InputDecoration(labelText: l.labelCity))),
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'تحميل السيارات' : 'Load cars',
                onTap: _loadCars)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: carIdCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'معرّف السيارة' : 'car id'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: fromCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'من (ISO)' : 'from ISO'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: toCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'إلى (ISO)' : 'to ISO'))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'تسعير' : 'Quote', onTap: _quote)),
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'حجز و دفع' : 'Book & Pay', onTap: _book)),
      ]),
      const SizedBox(height: 8),
      if (qOut.isNotEmpty) StatusBanner.info(qOut, dense: true),
      if (_carsOut.isNotEmpty) StatusBanner.info(_carsOut, dense: true),
      if (_cars.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(l.isArabic ? 'السيارات المتاحة' : 'Available cars',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ..._cars.take(10).map((c) {
          final id = c['id'] ?? c['car_id'] ?? '';
          final title = (c['title'] ??
                  c['name'] ??
                  '${c['make'] ?? ''} ${c['model'] ?? ''}')
              .toString()
              .trim();
          final city = (c['city'] ?? '').toString();
          final price = (c['price_per_day_cents'] ??
                  c['price_cents'] ??
                  c['daily_price_cents'] ??
                  0) as num;
          final priceText =
              price > 0 ? '${(price / 100).toStringAsFixed(2)} SYP/day' : '';
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .35))),
            child: ListTile(
              leading: const Icon(Icons.directions_car_filled_outlined),
              title: Text(title.isEmpty ? 'Car' : title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [if (city.isNotEmpty) city, if (priceText.isNotEmpty) priceText]
                    .where((e) => e.isNotEmpty)
                    .join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(id.toString()),
              onTap: () {
                carIdCtrl.text = id.toString();
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l.isArabic ? 'تم اختيار السيارة' : 'Car selected')));
              },
            ),
          );
        }),
      ],
      const Divider(height: 24),
      TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
              labelText: l.isArabic ? 'اسم المستأجر' : 'renter name')),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: phoneCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic
                        ? 'هاتف المستأجر (اختياري)'
                        : 'renter phone (opt)'))),
        SizedBox(
            width: 220,
            child: TextField(
                controller: rwCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic
                        ? 'محفظة المستأجر (اختياري)'
                        : 'renter wallet (opt)'))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 220,
            child: TextField(
                controller: bidCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'معرّف الحجز' : 'booking id'))),
        SizedBox(
            width: 140,
            child: WaterButton(
                label: l.isArabic ? 'الحالة' : 'Status', onTap: _status)),
        SizedBox(
            width: 140,
            child: WaterButton(
                label: l.isArabic ? 'إلغاء' : 'Cancel', onTap: _cancel)),
        SizedBox(
            width: 140,
            child: WaterButton(
                label: l.isArabic ? 'تأكيد' : 'Confirm', onTap: _confirm)),
      ]),
      const SizedBox(height: 8),
      SelectableText(bOut),
      const SizedBox(height: 8),
      if (bsOut.isNotEmpty) StatusBanner.info(bsOut, dense: true),
      const Divider(height: 32),
      Text(l.isArabic ? 'حجوزات (عرض المشغل)' : 'Bookings (operator view)',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (_bookings.isNotEmpty) ...[
        Builder(builder: (ctx) {
          final total = _bookings.length;
          int requested = 0, confirmed = 0, canceled = 0, completed = 0;
          int totalAmount = 0;
          for (final b in _bookings) {
            try {
              final st = (b['status'] ?? '').toString();
              switch (st) {
                case 'requested':
                  requested++;
                  break;
                case 'confirmed':
                  confirmed++;
                  break;
                case 'canceled':
                  canceled++;
                  break;
                case 'completed':
                  completed++;
                  break;
              }
              final amt = b['amount_cents'];
              if (amt is int) {
                totalAmount += amt;
              }
            } catch (_) {}
          }
          final cancelRate = total > 0 ? (canceled / total) : 0.0;
          final highRisk = total >= 10 && cancelRate >= 0.5;
          final baseTxtEn =
              'Bookings: $total · requested: $requested · confirmed: $confirmed · canceled: $canceled · completed: $completed · total amount: ${totalAmount} SYP';
          final baseTxtAr =
              'إجمالي الحجوزات: $total · قيد الطلب: $requested · مؤكدة: $confirmed · ملغاة: $canceled · مكتملة: $completed · إجمالي المبلغ: ${totalAmount} ل.س';
          final alertEn = ' · Anti‑fraud: HIGH cancellation rate';
          final alertAr = ' · مكافحة الاحتيال: معدل إلغاء مرتفع';
          final txt = l.isArabic
              ? (baseTxtAr + (highRisk ? alertAr : ''))
              : (baseTxtEn + (highRisk ? alertEn : ''));
          final banner = highRisk
              ? StatusBanner.error(txt, dense: true)
              : StatusBanner.info(txt, dense: true);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: banner,
          );
        }),
        const SizedBox(height: 8),
      ],
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String>(
            decoration:
                InputDecoration(labelText: l.isArabic ? 'الحالة' : 'status'),
            initialValue: _bookingStatusFilter.isEmpty ? null : _bookingStatusFilter,
            items: const [
              DropdownMenuItem(value: '', child: Text('All')),
              DropdownMenuItem(value: 'requested', child: Text('requested')),
              DropdownMenuItem(value: 'confirmed', child: Text('confirmed')),
              DropdownMenuItem(value: 'canceled', child: Text('canceled')),
              DropdownMenuItem(value: 'completed', child: Text('completed')),
            ],
            onChanged: (v) {
              setState(() => _bookingStatusFilter = v ?? '');
            },
          ),
        ),
        SizedBox(
            width: 160,
            child: WaterButton(
                label: l.isArabic ? 'تحديث الحجوزات' : 'Reload bookings',
                onTap: _loadBookings)),
        SizedBox(
          width: 200,
          child: WaterButton(
            label: l.isArabic ? 'تصدير CSV' : 'Export CSV',
            onTap: () {
              final params = _bookingStatusFilter.isNotEmpty
                  ? '?status=${Uri.encodeComponent(_bookingStatusFilter)}'
                  : '';
              launchWithSession(Uri.parse(
                  '${widget.baseUrl}/carrental/admin/bookings/export$params'));
            },
          ),
        ),
        if (_bookingsLoading)
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ]),
      const SizedBox(height: 8),
      if (_bookingsOut.isNotEmpty) StatusBanner.info(_bookingsOut, dense: true),
      const SizedBox(height: 8),
      ..._bookings.map((b) {
        final id = (b['id'] ?? '').toString();
        final carId = (b['car_id'] ?? '').toString();
        final renter = (b['renter_name'] ?? '').toString();
        final phone = (b['renter_phone'] ?? '').toString();
        final fromIso = (b['from_iso'] ?? '').toString();
        final toIso = (b['to_iso'] ?? '').toString();
        final status = (b['status'] ?? '').toString();
        final amount = b['amount_cents'];
        final amtStr = amount == null ? '' : '${amount} SYP';
        final canConfirm = status == 'requested';
        final canCancel = status == 'requested' || status == 'confirmed';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: GlassPanel(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Booking $id · car $carId · $status',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('$fromIso → $toIso'),
                if (renter.isNotEmpty || phone.isNotEmpty)
                  Text('$renter · $phone',
                      style: Theme.of(context).textTheme.bodySmall),
                if (amtStr.isNotEmpty)
                  Text(amtStr, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    if (canConfirm)
                      SizedBox(
                        height: 32,
                        child: ElevatedButton(
                          onPressed: () => _opConfirm(id),
                          child: Text(l.isArabic ? 'تأكيد' : 'Confirm'),
                        ),
                      ),
                    if (canCancel)
                      SizedBox(
                        height: 32,
                        child: OutlinedButton(
                          onPressed: () => _opCancel(id),
                          child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ]);
    return Scaffold(
        appBar: AppBar(
            title: Text(l.carrentalTitle), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          bg,
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }
}

class _FreightPageState extends State<FreightPage> {
  final titleCtrl = TextEditingController();
  final fromLatCtrl = TextEditingController();
  final fromLonCtrl = TextEditingController();
  final toLatCtrl = TextEditingController();
  final toLonCtrl = TextEditingController();
  final kgCtrl = TextEditingController(text: '5');
  final payerCtrl = TextEditingController();
  final carrierCtrl = TextEditingController();
  final sidCtrl = TextEditingController();
  String qOut = '', bOut = '', sOut = '';
  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final w = sp.getString('wallet_id') ?? '';
      if (w.isNotEmpty) {
        payerCtrl.text = w;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Map<String, dynamic> _req() {
    return {
      'title': titleCtrl.text.trim(),
      'from_lat': double.tryParse(fromLatCtrl.text.trim()) ?? 0.0,
      'from_lon': double.tryParse(fromLonCtrl.text.trim()) ?? 0.0,
      'to_lat': double.tryParse(toLatCtrl.text.trim()) ?? 0.0,
      'to_lon': double.tryParse(toLonCtrl.text.trim()) ?? 0.0,
      'weight_kg': double.tryParse(kgCtrl.text.trim()) ?? 0.0,
    };
  }

  Future<void> _quote() async {
    final r = await http.post(
      Uri.parse('${widget.baseUrl}/courier/quote'),
      headers: await _hdr(json: true),
      body: jsonEncode(_req()),
    );
    setState(() => qOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _book() async {
    final body = {
      ..._req(),
      'payer_wallet_id':
          payerCtrl.text.trim().isEmpty ? null : payerCtrl.text.trim(),
      'carrier_wallet_id':
          carrierCtrl.text.trim().isEmpty ? null : carrierCtrl.text.trim(),
      'confirm': true,
    };
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'frb-${DateTime.now().millisecondsSinceEpoch}';
    try {
      final r = await http.post(
        Uri.parse('${widget.baseUrl}/courier/book'),
        headers: h,
        body: jsonEncode(body),
      );
      if (r.statusCode >= 200 && r.statusCode < 300) {
        setState(() => bOut = '${r.statusCode}: ${r.body}');
        try {
          final j = jsonDecode(r.body);
          sidCtrl.text = (j['id'] ?? '').toString();
        } catch (_) {}
      } else {
        String msg;
        try {
          final ct = r.headers['content-type'] ?? '';
          if (ct.startsWith('application/json')) {
            final j = jsonDecode(r.body);
            final detail = j is Map<String, dynamic> ? j['detail'] : null;
            final detailStr = detail == null ? '' : detail.toString();
            final l = L10n.of(context);
            if (detailStr.contains('freight amount exceeds guardrail')) {
              msg = l.freightGuardrailAmount;
            } else if (detailStr
                .contains('freight distance exceeds guardrail')) {
              msg = l.freightGuardrailDistance;
            } else if (detailStr.contains('freight weight exceeds guardrail')) {
              msg = l.freightGuardrailWeight;
            } else if (detailStr
                .contains('freight velocity guardrail (payer)')) {
              msg = l.freightGuardrailVelocityPayer;
            } else if (detailStr
                .contains('freight velocity guardrail (device)')) {
              msg = l.freightGuardrailVelocityDevice;
            } else {
              msg =
                  '${r.statusCode}: ${detailStr.isNotEmpty ? detailStr : r.body}';
            }
          } else {
            msg = '${r.statusCode}: ${r.body}';
          }
        } catch (_) {
          msg = '${r.statusCode}: ${r.body}';
        }
        setState(() => bOut = msg);
      }
    } catch (e) {
      setState(() => bOut = 'error: $e');
    }
  }

  Future<void> _status() async {
    final id = sidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http.get(
        Uri.parse('${widget.baseUrl}/courier/shipments/$id'),
        headers: await _hdr());
    setState(() => sOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _set() async {
    final id = sidCtrl.text.trim();
    if (id.isEmpty) return;
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/courier/shipments/$id/status'),
        headers: await _hdr(json: true),
        body: jsonEncode({'status': 'in_transit'}));
    setState(() => sOut = '${r.statusCode}: ${r.body}');
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        FormSection(
          title: l.isArabic ? 'تفاصيل الشحنة' : 'Shipment details',
          children: [
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                  labelText: l.isArabic ? 'عنوان الشحنة' : 'Title'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: fromLatCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic ? 'خط العرض من' : 'From lat'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: fromLonCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic ? 'خط الطول من' : 'From lon'))),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: toLatCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic ? 'خط العرض إلى' : 'To lat'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: toLonCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic ? 'خط الطول إلى' : 'To lon'))),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: kgCtrl,
              decoration: InputDecoration(
                  labelText: l.isArabic ? 'الوزن (كغ)' : 'Weight (kg)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: PrimaryButton(
                      label: l.freightQuoteLabel, onPressed: _quote)),
              const SizedBox(width: 8),
              Expanded(
                  child: PrimaryButton(
                      label: l.freightBookPayLabel, onPressed: _book)),
            ]),
            const SizedBox(height: 8),
            if (qOut.isNotEmpty) StatusBanner.info(qOut, dense: true),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'المحفظة والدفع' : 'Wallet & payment',
          children: [
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: payerCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'محفظة الدافع (اختياري)'
                              : 'Payer wallet (opt)'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: carrierCtrl,
                      decoration: InputDecoration(
                          labelText: l.isArabic
                              ? 'محفظة الناقل (اختياري)'
                              : 'Carrier wallet (opt)'))),
            ]),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'تتبع الشحنة' : 'Track shipment',
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 220,
                  child: TextField(
                      controller: sidCtrl,
                      decoration: InputDecoration(
                          labelText:
                              l.isArabic ? 'معرّف الشحنة' : 'Shipment id')),
                ),
                PrimaryButton(
                    label: l.isArabic ? 'الحالة' : 'Status',
                    onPressed: _status),
                PrimaryButton(
                    label: l.isArabic ? 'تعيين in_transit' : 'Set in_transit',
                    onPressed: _set),
              ],
            ),
            const SizedBox(height: 8),
            if (sOut.isNotEmpty) StatusBanner.info(sOut, dense: true),
          ],
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.freightTitle),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        Positioned.fill(
          child: SafeArea(
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
        ),
      ]),
    );
  }
}

// Building Materials: simple storefront on top of Commerce products
class BuildingMaterialsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  const BuildingMaterialsPage(this.baseUrl, {super.key, this.walletId = ''});
  @override
  State<BuildingMaterialsPage> createState() => _BuildingMaterialsPageState();
}

class _BuildingMaterialsPageState extends State<BuildingMaterialsPage> {
  final qCtrl = TextEditingController();
  String _out = '';
  List<dynamic> _items = [];
  bool _loading = false;
  bool _placing = false;
  bool _ordersLoading = false;
  List<dynamic> _orders = [];

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final qs = <String, String>{'limit': '50'};
      if (qCtrl.text.trim().isNotEmpty) {
        qs['q'] = qCtrl.text.trim();
      }
      final uri = Uri.parse('${widget.baseUrl}/building/materials')
          .replace(queryParameters: qs);
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        try {
          _items = (jsonDecode(r.body) as List).cast<dynamic>();
          _out = '';
        } catch (e) {
          _items = [];
          _out = 'Error: $e';
        }
      } else {
        _items = [];
        _out = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _items = [];
      _out = 'Error: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadOrders();
  }

  Future<void> _placeOrder(Map<String, dynamic> product, int qty) async {
    if (widget.walletId.isEmpty) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'يرجى تعيين المحفظة أولاً من الشاشة الرئيسية.'
                : 'Please set your wallet first from the home screen.',
          ),
        ),
      );
      return;
    }
    final l = L10n.of(context);
    setState(() {
      _placing = true;
      _out = '';
    });
    try {
      final pid = product['id'];
      final uri = Uri.parse('${widget.baseUrl}/building/orders');
      final body = jsonEncode({
        'product_id': pid,
        'quantity': qty,
        'buyer_wallet_id': widget.walletId,
      });
      final r =
          await http.post(uri, headers: await _hdr(json: true), body: body);
      if (r.statusCode == 200) {
        setState(() {
          _out = l.isArabic
              ? 'تم إنشاء الطلب وحجز المبلغ في محفظة الضمان.'
              : 'Order created and amount held in escrow.';
        });
        await _loadOrders();
      } else {
        setState(() {
          _out = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      setState(() {
        _out = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _placing = false;
        });
      }
    }
  }

  Future<void> _loadOrders() async {
    if (widget.walletId.isEmpty) {
      return;
    }
    setState(() {
      _ordersLoading = true;
    });
    try {
      final qs = <String, String>{
        'limit': '50',
        'buyer_wallet_id': widget.walletId,
      };
      final uri = Uri.parse('${widget.baseUrl}/building/orders')
          .replace(queryParameters: qs);
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        try {
          _orders = (jsonDecode(r.body) as List).cast<dynamic>();
        } catch (_) {
          _orders = [];
        }
      } else {
        _orders = [];
      }
    } catch (_) {
      _orders = [];
    }
    if (mounted) {
      setState(() {
        _ordersLoading = false;
      });
    }
  }

  Future<void> _confirmDelivered(int orderId) async {
    final l = L10n.of(context);
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/building/orders/$orderId/status');
      final r = await http.post(
        uri,
        headers: await _hdr(json: true),
        body: jsonEncode({"status": "delivered"}),
      );
      if (r.statusCode == 200) {
        setState(() {
          _out = l.isArabic ? 'تم تأكيد الاستلام.' : 'Delivery confirmed.';
        });
        await _loadOrders();
      } else {
        setState(() {
          _out = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      setState(() {
        _out = 'Error: $e';
      });
    }
  }

  Future<void> _openOrderDialog(Map<String, dynamic> product) async {
    final l = L10n.of(context);
    final name = (product['name'] ?? '').toString();
    final cents = product['price_cents'] ?? 0;
    final cur = (product['currency'] ?? 'SYP').toString();
    final unitPrice = cents is int
        ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
        : cents.toString();
    final qtyCtrl = TextEditingController(text: '1');
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            l.isArabic ? 'طلب مادة البناء' : 'Order building material',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(unitPrice),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l.isArabic ? 'الكمية' : 'Quantity',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final q = int.tryParse(qtyCtrl.text.trim()) ?? 0;
                if (q <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        l.isArabic
                            ? 'الكمية يجب أن تكون أكبر من 0.'
                            : 'Quantity must be greater than 0.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, q);
              },
              child: Text(l.isArabic ? 'تأكيد الطلب' : 'Place order'),
            ),
          ],
        );
      },
    );
    if (res != null && res > 0) {
      await _placeOrder(product, res);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final searchSection = FormSection(
      title: l.homeBuildingMaterials,
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: qCtrl,
              decoration: InputDecoration(labelText: l.labelSearch),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: PrimaryButton(
              label: l.reSearch,
              onPressed: _load,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_out.isNotEmpty) StatusBanner.info(_out, dense: true),
      ],
    );

    final listSection = FormSection(
      title: l.isArabic ? 'المنتجات' : 'Products',
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (_placing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (!_loading && _items.isEmpty && _out.isEmpty)
          Text(
            l.isArabic
                ? 'لا توجد مواد بناء بعد.'
                : 'No building materials yet.',
            style: theme.textTheme.bodySmall,
          ),
        if (!_loading && _items.isNotEmpty)
          ..._items.map<Widget>((it) {
            try {
              final m = (it as Map).cast<String, dynamic>();
              final name = (m['name'] ?? '').toString();
              final cents = m['price_cents'] ?? 0;
              final cur = (m['currency'] ?? 'SYP').toString();
              final wallet = (m['merchant_wallet_id'] ?? '').toString();
              final price = cents is int
                  ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
                  : cents.toString();
              return StandardListTile(
                leading: const Icon(Icons.construction_outlined),
                title: Text(name),
                subtitle: Text(wallet.isNotEmpty ? wallet : ''),
                trailing: Text(price,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: widget.walletId.isNotEmpty && !_placing
                    ? () => _openOrderDialog(m)
                    : null,
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          }),
      ],
    );

    final ordersSection = widget.walletId.isEmpty
        ? const SizedBox.shrink()
        : FormSection(
            title: l.isArabic ? 'طلباتي' : 'My building orders',
            children: [
              if (_ordersLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              if (!_ordersLoading && _orders.isEmpty)
                Text(
                  l.isArabic ? 'لا توجد طلبات بعد.' : 'No orders yet.',
                  style: theme.textTheme.bodySmall,
                ),
              if (!_ordersLoading && _orders.isNotEmpty)
                ..._orders.map<Widget>((it) {
                  try {
                    final m = (it as Map).cast<String, dynamic>();
                    final rawId = m['id'];
                    final id = rawId is int
                        ? rawId
                        : int.tryParse(rawId?.toString() ?? '') ?? 0;
                    final pid = m['product_id']?.toString() ?? '';
                    final qty = m['quantity'] ?? 0;
                    final status = (m['status'] ?? '').toString();
                    final statusLower = status.toLowerCase();
                    final cents = m['amount_cents'] ?? 0;
                    final cur = (m['currency'] ?? 'SYP').toString();
                    final price = cents is int
                        ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
                        : cents.toString();
                    final title = l.isArabic
                        ? 'طلب #${m['id'] ?? ''} · $status'
                        : 'Order #${m['id'] ?? ''} · $status';
                    final subtitle = l.isArabic
                        ? 'منتج $pid · كمية $qty'
                        : 'Product $pid · Qty $qty';
                    final canConfirm = id != 0 &&
                        (statusLower == 'paid_escrow' ||
                            statusLower == 'shipped');
                    return StandardListTile(
                      leading: const Icon(Icons.assignment_outlined),
                      title: Text(title),
                      subtitle: Text(subtitle),
                      trailing: Text(
                        price,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: canConfirm ? () => _confirmDelivered(id) : null,
                    );
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                }),
            ],
          );

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        searchSection,
        listSection,
        ordersSection,
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.homeBuildingMaterials),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        Positioned.fill(
          child: SafeArea(
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
        ),
      ]),
    );
  }
}

class BuildingMaterialsOperatorPage extends StatefulWidget {
  final String baseUrl;
  const BuildingMaterialsOperatorPage(this.baseUrl, {super.key});
  @override
  State<BuildingMaterialsOperatorPage> createState() =>
      _BuildingMaterialsOperatorPageState();
}

class _BuildingMaterialsOperatorPageState
    extends State<BuildingMaterialsOperatorPage> {
  final nameCtrl = TextEditingController();
  final priceCtrl = TextEditingController(text: '100000');
  final skuCtrl = TextEditingController();
  final walletCtrl = TextEditingController();
  final qCtrl = TextEditingController();
  String _out = '';
  List<dynamic> _items = [];
  bool _loading = false;
  bool _ordersLoading = false;
  List<dynamic> _orders = [];

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final qs = <String, String>{'limit': '50'};
      if (qCtrl.text.trim().isNotEmpty) {
        qs['q'] = qCtrl.text.trim();
      }
      final uri = Uri.parse('${widget.baseUrl}/building/materials')
          .replace(queryParameters: qs);
      final r = await http.get(uri);
      if (r.statusCode == 200) {
        try {
          _items = (jsonDecode(r.body) as List).cast<dynamic>();
          _out = '';
        } catch (e) {
          _items = [];
          _out = 'Error: $e';
        }
      } else {
        _items = [];
        _out = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _items = [];
      _out = 'Error: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadOrders() async {
    setState(() {
      _ordersLoading = true;
    });
    try {
      final qs = <String, String>{'limit': '50'};
      final seller = walletCtrl.text.trim();
      if (seller.isNotEmpty) {
        qs['seller_wallet_id'] = seller;
      }
      final uri = Uri.parse('${widget.baseUrl}/building/orders')
          .replace(queryParameters: qs);
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        try {
          _orders = (jsonDecode(r.body) as List).cast<dynamic>();
        } catch (_) {
          _orders = [];
        }
      } else {
        _orders = [];
      }
    } catch (_) {
      _orders = [];
    }
    if (mounted) {
      setState(() {
        _ordersLoading = false;
      });
    }
  }

  Future<void> _create() async {
    setState(() => _out = '...');
    try {
      final uri = Uri.parse('${widget.baseUrl}/commerce/products');
      final body = {
        'name': nameCtrl.text.trim(),
        'price_cents': int.tryParse(priceCtrl.text.trim()) ?? 0,
        'sku': skuCtrl.text.trim().isEmpty ? null : skuCtrl.text.trim(),
        'merchant_wallet_id':
            walletCtrl.text.trim().isEmpty ? null : walletCtrl.text.trim(),
      };
      final r = await http.post(uri,
          headers: await _hdr(json: true), body: jsonEncode(body));
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _out = 'Created: ${r.body}';
        await _load();
      } else {
        _out = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      _out = 'Error: $e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final formSection = FormSection(
      title: l.homeBuildingMaterials,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'اسم المادة' : 'Material name'),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: priceCtrl,
                decoration: InputDecoration(labelText: l.labelAmount),
                keyboardType: TextInputType.number,
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: skuCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic ? 'SKU (اختياري)' : 'SKU (optional)'),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: walletCtrl,
                decoration: InputDecoration(
                    labelText: l.isArabic
                        ? 'محفظة التاجر (اختياري)'
                        : 'Merchant wallet (optional)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PrimaryButton(
          label: l.isArabic ? 'إضافة مادة' : 'Add material',
          onPressed: _create,
        ),
        const SizedBox(height: 8),
        if (_out.isNotEmpty) StatusBanner.info(_out, dense: true),
      ],
    );

    final listSection = FormSection(
      title: l.isArabic ? 'المنتجات' : 'Products',
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: qCtrl,
              decoration: InputDecoration(labelText: l.labelSearch),
              onSubmitted: (_) => _load(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: PrimaryButton(
              label: l.reSearch,
              onPressed: _load,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_loading) const SkeletonListTile(),
        if (!_loading && _items.isEmpty && _out.isEmpty)
          Text(
            l.isArabic
                ? 'لا توجد مواد بناء بعد.'
                : 'No building materials yet.',
            style: theme.textTheme.bodySmall,
          ),
        if (!_loading && _items.isNotEmpty)
          ..._items.map<Widget>((it) {
            try {
              final m = (it as Map).cast<String, dynamic>();
              final name = (m['name'] ?? '').toString();
              final cents = m['price_cents'] ?? 0;
              final cur = (m['currency'] ?? 'SYP').toString();
              final wallet = (m['merchant_wallet_id'] ?? '').toString();
              final price = cents is int
                  ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
                  : cents.toString();
              return StandardListTile(
                leading: const Icon(Icons.construction_outlined),
                title: Text(name),
                subtitle: Text(wallet.isNotEmpty ? wallet : ''),
                trailing: Text(price,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          }),
      ],
    );

    final ordersSection = FormSection(
      title: l.isArabic ? 'طلبات العملاء' : 'Customer orders',
      children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: walletCtrl,
              decoration: InputDecoration(
                labelText: l.isArabic
                    ? 'محفظة التاجر (لتصفية الطلبات)'
                    : 'Merchant wallet (filter orders)',
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: PrimaryButton(
              label: l.reSearch,
              onPressed: _loadOrders,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_ordersLoading) const SkeletonListTile(),
        if (!_ordersLoading && _orders.isEmpty)
          Text(
            l.isArabic ? 'لا توجد طلبات بعد.' : 'No orders yet.',
            style: theme.textTheme.bodySmall,
          ),
        if (!_ordersLoading && _orders.isNotEmpty)
          ..._orders.map<Widget>((it) {
            try {
              final m = (it as Map).cast<String, dynamic>();
              final status = (m['status'] ?? '').toString();
              final buyer = (m['buyer_wallet_id'] ?? '').toString();
              final cents = m['amount_cents'] ?? 0;
              final cur = (m['currency'] ?? 'SYP').toString();
              final price = cents is int
                  ? '${(cents / 100.0).toStringAsFixed(2)} $cur'
                  : cents.toString();
              final title = l.isArabic
                  ? 'طلب #${m['id'] ?? ''} · $status'
                  : 'Order #${m['id'] ?? ''} · $status';
              final subtitle = buyer.isNotEmpty
                  ? (l.isArabic
                      ? 'محفظة المشتري: $buyer'
                      : 'Buyer wallet: $buyer')
                  : '';
              return StandardListTile(
                leading: const Icon(Icons.assignment_turned_in_outlined),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: Text(
                  price,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              );
            } catch (_) {
              return const SizedBox.shrink();
            }
          }),
      ],
    );

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        formSection,
        listSection,
        ordersSection,
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
            l.isArabic ? 'مشغل مواد البناء' : 'Building Materials Operator'),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        Positioned.fill(
          child: SafeArea(
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              child: content,
            ),
          ),
        ),
      ]),
    );
  }
}

class GlassCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const GlassCard(
      {super.key,
      required this.icon,
      required this.title,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withValues(alpha: .08),
            border: Border.all(color: Colors.white.withValues(alpha: .2)),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 42, color: Colors.white.withValues(alpha: .95)),
                    const SizedBox(height: 8),
                    Text(title,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .98),
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// Unified homescreen-like background for all pages
class AppBG extends StatelessWidget {
  final Widget? child;

  const AppBG({super.key, this.child});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Ultra realistic liquid-glass background:
    // deep navy base, vibrant blue gradients and soft refraction highlights.
    final base = const Color(0xFF050B1F); // slightly lighter navy base
    final blue = const Color(0xFF1D4ED8); // vivid blue
    final cyan = const Color(0xFF22D3EE); // cyan accent
    final purple = const Color(0xFF6366F1); // indigo/purple glow
    final paper = Colors.white.withValues(alpha: isDark ? 0.035 : 0.10);

    return SizedBox.expand(
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(base, blue, 0.22)!,
                  Color.lerp(base, purple, 0.38)!,
                  Color.lerp(base, cyan, 0.42)!,
                  Color.lerp(base, Colors.black, isDark ? 0.16 : 0.08)!,
                ],
              ),
            ),
          ),
          // Global blur + subtle paper tint for depth-of-field.
          Positioned.fill(
            child: IgnorePointer(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  color: paper,
                ),
              ),
            ),
          ),
          // Soft radial highlights to simulate light refraction spots.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _GlassHighlightPainter(isDark: isDark),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.03 : 0.05),
                      Colors.transparent,
                      Colors.white.withValues(alpha: isDark ? 0.018 : 0.028),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),
          if (child != null)
            SafeArea(
              child: child!,
            ),
        ],
      ),
    );
  }
}

/// Painter for subtle radial highlights behind the glass layers.
class _GlassHighlightPainter extends CustomPainter {
  final bool isDark;
  _GlassHighlightPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final centerTop = Offset(size.width * 0.25, size.height * 0.18);
    final centerBottom = Offset(size.width * 0.8, size.height * 0.82);

    final paintTop = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: isDark ? 0.18 : 0.26),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: centerTop, radius: size.width * 0.55));

    final paintBottom = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: isDark ? 0.26 : 0.32),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: centerBottom, radius: size.width * 0.65));

    canvas.drawCircle(centerTop, size.width * 0.55, paintTop);
    canvas.drawCircle(centerBottom, size.width * 0.65, paintBottom);
  }

  @override
  bool shouldRepaint(covariant _GlassHighlightPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}

class WaterButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? tint;
  const WaterButton(
      {super.key,
      this.icon,
      required this.label,
      required this.onTap,
      this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      this.radius = 12,
      this.tint});
  @override
  Widget build(BuildContext context) {
    // Use modern 3D/liquid tile style globally (same as Payments)
    return PayActionButton(
        icon: icon,
        label: label,
        onTap: onTap,
        padding: padding,
        radius: radius,
        tint: tint ?? Tokens.primary);
  }
}

class SettingsPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  const SettingsPage(
      {super.key, required this.baseUrl, required this.walletId});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController baseUrlCtrl;
  late final TextEditingController walletCtrl;
  String _uiRouteSel = 'A';
  bool _debugSkeletonLong = false;
  bool _skipLogin = false;
  bool _metricsRemote = false;

  @override
  void initState() {
    super.initState();
    baseUrlCtrl = TextEditingController(text: widget.baseUrl);
    walletCtrl = TextEditingController(text: widget.walletId);
    // Removed manual Google Maps API key and currency selection (SYP default)
    _loadUiRoute();
    _loadDebug();
    _loadSkip();
    _loadMetrics();
  }

  Future<void> _loadUiRoute() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _uiRouteSel = sp.getString('ui_route') ??
          const String.fromEnvironment('UI_ROUTE', defaultValue: 'A');
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadDebug() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _debugSkeletonLong = sp.getBool('debug_skeleton_long') ?? false;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadSkip() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _skipLogin = sp.getBool('skip_login') ?? false;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadMetrics() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _metricsRemote = sp.getBool('metrics_remote') ?? false;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final panel = GlassPanel(
      padding: const EdgeInsets.all(16),
      child: ListView(padding: const EdgeInsets.all(0), children: [
        TextField(
            controller: baseUrlCtrl,
            decoration: InputDecoration(labelText: l.settingsBaseUrl)),
        const SizedBox(height: 8),
        TextField(
            controller: walletCtrl,
            decoration: InputDecoration(labelText: l.settingsMyWallet)),
        const SizedBox(height: 8),
        // Removed manual Google Maps API key and currency fields (SYP is default)
        Row(children: [
          Text(l.settingsUiRoute),
          const SizedBox(width: 12),
          DropdownButton<String>(
            value: _uiRouteSel,
            items: [
              DropdownMenuItem(value: 'A', child: Text(l.settingsUiRouteA)),
              DropdownMenuItem(value: 'B', child: Text(l.settingsUiRouteB)),
              DropdownMenuItem(value: 'C', child: Text(l.settingsUiRouteC)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _uiRouteSel = v);
            },
          ),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
            value: _debugSkeletonLong,
            onChanged: (v) {
              setState(() => _debugSkeletonLong = v);
            },
            title: Text(l.settingsDebugSkeleton)),
        const SizedBox(height: 8),
        SwitchListTile(
            value: _skipLogin,
            onChanged: (v) {
              setState(() => _skipLogin = v);
            },
            title: Text(l.settingsSkipLogin)),
        const SizedBox(height: 8),
        SwitchListTile(
            value: _metricsRemote,
            onChanged: (v) {
              setState(() => _metricsRemote = v);
            },
            title: Text(l.settingsSendMetrics)),
        const SizedBox(height: 16),
        WaterButton(label: l.settingsSave, onTap: _save),
      ]),
    );
    return Scaffold(
      appBar: AppBar(
          title: Text(l.settingsTitle), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: panel)))),
      ]),
    );
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base_url', baseUrlCtrl.text.trim());
    await sp.setString('wallet_id', walletCtrl.text.trim());
    await sp.setString('ui_route', _uiRouteSel);
    await sp.setBool('debug_skeleton_long', _debugSkeletonLong);
    await sp.setBool('skip_login', _skipLogin);
    await sp.setBool('metrics_remote', _metricsRemote);
    if (!mounted) return;
    Navigator.pop(context);
  }
}

// (Legacy inline Taxi pages removed; use core/taxi/*.dart)

// Shared helper: parse taxi fare options from various API shapes
List<Map<String, dynamic>> parseTaxiFareOptions(dynamic j) {
  final opts = <Map<String, dynamic>>[];
  try {
    if (j is Map && j['options'] is List) {
      for (final o in (j['options'] as List)) {
        if (o is Map) {
          final name = (o['type'] ?? o['kind'] ?? '').toString();
          final cents = (o['price_cents'] ?? o['fare_cents'] ?? 0) as int;
          if (name.isNotEmpty && cents > 0)
            opts.add({'name': name.toUpperCase(), 'cents': cents});
        }
      }
    }
    if (opts.isEmpty && j is Map && j.containsKey('price_cents')) {
      opts.add({'name': 'STANDARD', 'cents': (j['price_cents'] ?? 0) as int});
    }
    if (opts.isEmpty && j is Map) {
      final vip = j['vip_price_cents'];
      final van = j['van_price_cents'];
      if (vip is int && vip > 0) opts.add({'name': 'VIP', 'cents': vip});
      if (van is int && van > 0) opts.add({'name': 'VAN', 'cents': van});
    }
  } catch (_) {}
  return opts;
}

class SonicPayPage extends StatefulWidget {
  final String baseUrl;
  const SonicPayPage(this.baseUrl, {super.key});
  @override
  State<SonicPayPage> createState() => _SonicPayPageState();
}

class _SonicPayPageState extends State<SonicPayPage> {
  final fromCtrl = TextEditingController();
  final toCtrl = TextEditingController();
  final amtCtrl = TextEditingController(text: '1000');
  String payload = '';
  String out = '';
  Future<void> _issue() async {
    setState(() => out = '...');
    try {
      final r =
          await http.post(Uri.parse('${widget.baseUrl}/payments/sonic/issue'),
              headers: await _hdr(json: true),
              body: jsonEncode({
                'from_wallet_id': fromCtrl.text.trim(),
                'amount_cents': int.tryParse(amtCtrl.text.trim()) ?? 0,
              }));
      out = '${r.statusCode}: ${r.body}';
      try {
        final j = jsonDecode(r.body);
        final tok = j['token'] ?? '';
        payload = tok is String && tok.startsWith('SONIC|')
            ? tok
            : 'SONIC|token=' + tok.toString();
      } catch (_) {}
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _redeem() async {
    setState(() => out = '...');
    try {
      // payload format: SONIC|token=... or any text, server expects token
      final map = <String, String>{};
      try {
        for (final p in payload.split('|').skip(1)) {
          final kv = p.split('=');
          if (kv.length == 2) map[kv[0]] = kv[1];
        }
      } catch (_) {}
      final token = map['token'] ?? payload;
      final r =
          await http.post(Uri.parse('${widget.baseUrl}/payments/sonic/redeem'),
              headers: await _hdr(json: true),
              body: jsonEncode({
                'token': token,
                'to_wallet_id':
                    toCtrl.text.trim().isEmpty ? null : toCtrl.text.trim(),
              }));
      out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.sonicTitle)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
            controller: fromCtrl,
            decoration: InputDecoration(labelText: l.sonicFromWallet)),
        const SizedBox(height: 8),
        TextField(
            controller: toCtrl,
            decoration: InputDecoration(labelText: l.sonicToWalletOpt)),
        const SizedBox(height: 8),
        TextField(
            controller: amtCtrl,
            decoration: InputDecoration(labelText: l.labelAmount),
            keyboardType: TextInputType.number),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: WaterButton(label: l.sonicIssueToken, onTap: _issue)),
          const SizedBox(width: 8),
          Expanded(child: WaterButton(label: l.sonicRedeem, onTap: _redeem))
        ]),
        const SizedBox(height: 12),
        if (payload.isNotEmpty)
          Center(
              child: Column(children: [
            Text(payload),
            const SizedBox(height: 8),
            QrImageView(data: payload, size: 220)
          ])),
        const SizedBox(height: 12),
        SelectableText(out),
      ]),
    );
  }
}

class CashMandatePage extends StatefulWidget {
  final String baseUrl;
  const CashMandatePage(this.baseUrl, {super.key});
  @override
  State<CashMandatePage> createState() => _CashMandatePageState();
}

class _CashMandatePageState extends State<CashMandatePage> {
  final amtCtrl = TextEditingController(text: '1000');
  final phraseCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String out = '';
  String payload = '';
  Future<void> _create() async {
    setState(() => out = '...');
    final uri = Uri.parse('${widget.baseUrl}/payments/cash/create');
    String? myWallet;
    try {
      final sp = await SharedPreferences.getInstance();
      myWallet = sp.getString('wallet_id');
    } catch (_) {}
    final body = jsonEncode({
      'from_wallet_id': myWallet,
      'amount_cents': int.tryParse(amtCtrl.text.trim()) ?? 0,
      'phrase': phraseCtrl.text.trim().isEmpty ? null : phraseCtrl.text.trim(),
    });
    try {
      final headers = await _hdr(json: true);
      final r = await http.post(uri, headers: headers, body: body);
      out = '${r.statusCode}: ${r.body}';
      if (r.statusCode >= 500) {
        await OfflineQueue.enqueue(OfflineTask(
            id: 'cash-${DateTime.now().millisecondsSinceEpoch}',
            method: 'POST',
            url: uri.toString(),
            headers: headers,
            body: body,
            tag: 'payments_cash',
            createdAt: DateTime.now().millisecondsSinceEpoch));
      }
      try {
        final j = jsonDecode(r.body);
        final code = j['code'] ?? '';
        codeCtrl.text = code.toString();
        payload = 'CASH|code=' + codeCtrl.text;
      } catch (_) {}
    } catch (e) {
      final headers = await _hdr(json: true);
      await OfflineQueue.enqueue(OfflineTask(
          id: 'cash-${DateTime.now().millisecondsSinceEpoch}',
          method: 'POST',
          url: uri.toString(),
          headers: headers,
          body: body,
          tag: 'payments_cash',
          createdAt: DateTime.now().millisecondsSinceEpoch));
      out = 'Queued (offline)';
    }
    if (mounted) setState(() {});
  }

  Future<void> _status() async {
    setState(() => out = '...');
    try {
      final r = await http.get(Uri.parse(
          '${widget.baseUrl}/payments/cash/status/' +
              Uri.encodeComponent(codeCtrl.text.trim())));
      out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _cancel() async {
    setState(() => out = '...');
    try {
      final r = await http.post(
          Uri.parse('${widget.baseUrl}/payments/cash/cancel'),
          headers: await _hdr(json: true),
          body: jsonEncode({'code': codeCtrl.text.trim()}));
      out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _redeem() async {
    setState(() => out = '...');
    try {
      String? myWallet;
      try {
        final sp = await SharedPreferences.getInstance();
        myWallet = sp.getString('wallet_id');
      } catch (_) {}
      final r =
          await http.post(Uri.parse('${widget.baseUrl}/payments/cash/redeem'),
              headers: await _hdr(json: true),
              body: jsonEncode({
                'code': codeCtrl.text.trim(),
                'phrase': phraseCtrl.text.trim().isEmpty
                    ? null
                    : phraseCtrl.text.trim(),
                'to_wallet_id': myWallet,
              }));
      out = '${r.statusCode}: ${r.body}';
    } catch (e) {
      out = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
          controller: amtCtrl,
          decoration: InputDecoration(labelText: l.labelAmount),
          keyboardType: TextInputType.number),
      const SizedBox(height: 8),
      TextField(
          controller: phraseCtrl,
          decoration: InputDecoration(labelText: l.cashSecretPhraseOpt)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: WaterButton(label: l.cashCreate, onTap: _create)),
        const SizedBox(width: 8),
        Expanded(child: WaterButton(label: l.cashStatus, onTap: _status)),
        const SizedBox(width: 8),
        Expanded(child: WaterButton(label: l.cashCancel, onTap: _cancel))
      ]),
      const SizedBox(height: 12),
      TextField(
          controller: codeCtrl,
          decoration: InputDecoration(labelText: l.labelCode)),
      const SizedBox(height: 8),
      WaterButton(label: l.cashRedeem, onTap: _redeem),
      const SizedBox(height: 12),
      if (payload.isNotEmpty)
        Center(
            child: Column(children: [
          Text(payload),
          const SizedBox(height: 8),
          QrImageView(data: payload, size: 220)
        ])),
      const SizedBox(height: 12),
      SelectableText(out),
    ]);
    return Scaffold(
        appBar: AppBar(
            title: Text(l.vouchersTitleText),
            backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          bg,
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }
}

// Generic health stub page for operator modules
// TaxiOperatorPage moved to core/taxi/taxi_operator.dart

class ModuleHealthPage extends StatefulWidget {
  final String baseUrl;
  final String title;
  final String path;
  const ModuleHealthPage(this.baseUrl, this.title, this.path, {super.key});
  @override
  State<ModuleHealthPage> createState() => _ModuleHealthPageState();
}

class _ModuleHealthPageState extends State<ModuleHealthPage> {
  String out = '';
  Future<void> _health() async {
    setState(() => out = '...');
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}${widget.path}'),
          headers: await _hdr());
      setState(() => out = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      WaterButton(label: 'Check Health', onTap: _health),
      const SizedBox(height: 12),
      SelectableText(out)
    ]);
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.title), backgroundColor: Colors.transparent),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          bg,
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
                      padding: const EdgeInsets.all(16), child: content)))
        ]));
  }
}

// Bus page: use upstreams health and show bus status
class BusPage extends StatefulWidget {
  final String baseUrl;
  const BusPage(this.baseUrl, {super.key});
  @override
  State<BusPage> createState() => _BusPageState();
}

class _BusPageState extends State<BusPage> {
  String out = '';
  Future<void> _health() async {
    setState(() => out = '...');
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/upstreams/health'),
          headers: await _hdr());
      setState(() => out = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    const bg = AppBG();
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            WaterButton(
              label: l.isArabic ? 'فتح صفحة الحجز' : 'Open Booking',
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => BusBookPage(widget.baseUrl)));
              },
            ),
            WaterButton(
              label: l.isArabic ? 'وحدة تشغيل الحافلات' : 'Operator Console',
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => BusOperatorPage(widget.baseUrl)));
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        WaterButton(
          label: l.isArabic ? 'فحص التوافر' : 'Check health',
          onTap: _health,
        ),
        if (out.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(out),
          ),
        const SizedBox(height: 8),
        Text(
          l.isArabic
              ? 'الواجهة الإدارية (ويب): /bus/admin (يتطلب تسجيل الدخول)'
              : 'Admin (web): /bus/admin (requires login)',
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
          title: Text(l.isArabic ? 'الحافلات' : 'Bus'),
          backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        Positioned.fill(
            child: SafeArea(
                child: GlassPanel(
                    padding: const EdgeInsets.all(16), child: content)))
      ]),
    );
  }
}

// Bus Control: simple overview for you (admin)
class BusControlPage extends StatefulWidget {
  final String baseUrl;
  const BusControlPage(this.baseUrl, {super.key});
  @override
  State<BusControlPage> createState() => _BusControlPageState();
}

class _BusControlPageState extends State<BusControlPage> {
  String _healthOut = '';
  String _summaryOut = '';
  bool _loadingHealth = false;
  bool _loadingSummary = false;
  bool _loadingOps = false;
  List<Map<String, dynamic>> _operators = [];
  String _opsError = '';

  Future<void> _checkHealth() async {
    setState(() => _loadingHealth = true);
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/bus/health'),
          headers: await _hdr());
      _healthOut = '${r.statusCode}: ${r.body}';
    } catch (e) {
      _healthOut = 'error: $e';
    }
    if (mounted) setState(() => _loadingHealth = false);
  }

  Future<void> _loadSummary() async {
    setState(() => _loadingSummary = true);
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/bus/admin/summary'),
          headers: await _hdr());
      if (r.statusCode != 200) {
        _summaryOut = '${r.statusCode}: ${r.body}';
      } else {
        final j = jsonDecode(r.body);
        final ops = j['operators'] ?? 0;
        final routes = j['routes'] ?? 0;
        final tripsToday = j['trips_today'] ?? 0;
        final bookingsToday = j['bookings_today'] ?? 0;
        final revenueCents = j['revenue_cents_today'] ?? 0;
        final revInt = revenueCents is int
            ? revenueCents
            : int.tryParse(revenueCents.toString()) ?? 0;
        final rev = revInt / 100.0;
        _summaryOut = 'Operators: $ops  •  Routes: $routes\n'
            'Today: $tripsToday trips · $bookingsToday bookings · ${rev.toStringAsFixed(2)} SYP revenue';
      }
    } catch (e) {
      _summaryOut = 'error: $e';
    }
    if (mounted) setState(() => _loadingSummary = false);
  }

  Future<void> _loadOperators() async {
    setState(() => _loadingOps = true);
    try {
      final r = await http.get(Uri.parse('${widget.baseUrl}/bus/operators'),
          headers: await _hdr());
      if (r.statusCode != 200) {
        _opsError = '${r.statusCode}: ${r.body}';
        _operators = [];
      } else {
        final j = jsonDecode(r.body);
        if (j is List) {
          _operators = j.whereType<Map<String, dynamic>>().toList();
          _opsError = '';
        } else {
          _opsError = 'Unexpected response';
          _operators = [];
        }
      }
    } catch (e) {
      _opsError = 'error: $e';
      _operators = [];
    }
    if (mounted) setState(() => _loadingOps = false);
  }

  Future<void> _setOperatorStatus(String id, bool online) async {
    setState(() => _loadingOps = true);
    try {
      final path =
          online ? '/bus/operators/$id/online' : '/bus/operators/$id/offline';
      final r = await http.post(Uri.parse('${widget.baseUrl}$path'),
          headers: await _hdr());
      _opsError = r.statusCode == 200 ? '' : '${r.statusCode}: ${r.body}';
    } catch (e) {
      _opsError = 'error: $e';
    }
    await _loadOperators();
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Bus Control',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        const SizedBox(height: 8),
        Text(
            'Monitor the bus service: health, operators, routes, trips and revenue for today.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        WaterButton(
          label: _loadingHealth ? 'Checking…' : 'Check /bus/health',
          onTap: () {
            if (_loadingHealth) return;
            _checkHealth();
          },
        ),
        const SizedBox(height: 8),
        if (_healthOut.isNotEmpty) SelectableText(_healthOut),
        const SizedBox(height: 16),
        WaterButton(
          label: _loadingSummary ? 'Loading…' : 'Load summary (today)',
          onTap: () {
            if (_loadingSummary) return;
            _loadSummary();
          },
        ),
        const SizedBox(height: 8),
        if (_summaryOut.isNotEmpty) SelectableText(_summaryOut),
        const SizedBox(height: 16),
        const Text('Web Admin', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        WaterButton(
            label: 'Open /bus/admin in browser',
            onTap: () {
              launchWithSession(Uri.parse('${widget.baseUrl}/bus/admin'));
            }),
        const SizedBox(height: 16),
        const Text('Operators', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        WaterButton(
            label: _loadingOps ? 'Loading…' : 'List operators',
            onTap: () {
              if (_loadingOps) return;
              _loadOperators();
            }),
        const SizedBox(height: 8),
        if (_opsError.isNotEmpty)
          SelectableText(_opsError, style: const TextStyle(color: Colors.red)),
        ..._operators.map((op) {
          final id = op['id']?.toString() ?? '';
          final name = op['name']?.toString() ?? '';
          final online = (op['is_online'] == true) ||
              (op['is_online'] is num && op['is_online'] != 0);
          return Card(
            child: ListTile(
              title: Text(name.isEmpty ? id : '$name · $id'),
              subtitle: Text(online ? 'Online' : 'Offline'),
              trailing: Wrap(
                spacing: 8,
                children: [
                  TextButton(
                      onPressed: () {
                        _setOperatorStatus(id, true);
                      },
                      child: const Text('Online')),
                  TextButton(
                      onPressed: () {
                        _setOperatorStatus(id, false);
                      },
                      child: const Text('Offline')),
                ],
              ),
            ),
          );
        }),
      ],
    );
    return Scaffold(
      appBar: AppBar(
          title: const Text('Bus Control'),
          backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        Positioned.fill(
            child: SafeArea(
                child: GlassPanel(
                    padding: const EdgeInsets.all(16), child: content)))
      ]),
    );
  }
}

class BusBookPage extends StatefulWidget {
  final String baseUrl;
  const BusBookPage(this.baseUrl, {super.key});
  @override
  State<BusBookPage> createState() => _BusBookPageState();
}

class BusBookingDetailPage extends StatefulWidget {
  final String baseUrl;
  final Map<String, dynamic> booking;
  const BusBookingDetailPage(
      {super.key, required this.baseUrl, required this.booking});
  @override
  State<BusBookingDetailPage> createState() => _BusBookingDetailPageState();
}

class _BusBookingDetailPageState extends State<BusBookingDetailPage> {
  List<dynamic> _tickets = [];
  String _ticketsOut = '';
  bool _loadingTickets = false;

  @override
  void initState() {
    super.initState();
    _loadTickets();
  }

  Future<void> _loadTickets() async {
    final id = (widget.booking['id'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() => _loadingTickets = true);
    try {
      final uri = Uri.parse('${widget.baseUrl}/bus/bookings/' +
          Uri.encodeComponent(id) +
          '/tickets');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode != 200) {
        _ticketsOut = '${r.statusCode}: ${r.body}';
        _tickets = [];
      } else {
        final arr = jsonDecode(r.body) as List<dynamic>;
        _tickets = arr;
        _ticketsOut = 'Tickets: ${arr.length}';
      }
    } catch (e) {
      _ticketsOut = 'error: $e';
      _tickets = [];
    }
    if (mounted) setState(() => _loadingTickets = false);
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final b = widget.booking;
    final trip = b['trip'];
    final origin = b['origin'];
    final dest = b['dest'];
    final op = b['operator'];
    final id = (b['id'] ?? '').toString();
    final seats = b['seats'] ?? 0;
    final status = (b['status'] ?? '').toString();
    final created = b['created_at']?.toString() ?? '';
    final dep = DateTime.tryParse(trip['depart_at'].toString())?.toLocal();
    final arr = DateTime.tryParse(trip['arrive_at'].toString())?.toLocal();
    final depStr = dep != null
        ? '${dep.year}-${dep.month}-${dep.day} ${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}'
        : '';
    final arrStr = arr != null
        ? '${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}'
        : '';
    final whenLine = depStr.isNotEmpty ? '$depStr → $arrStr' : created;
    final originName = (origin?['name'] ?? '').toString();
    final destName = (dest?['name'] ?? '').toString();
    final routeLine = (originName.isNotEmpty || destName.isNotEmpty)
        ? '${originName.isNotEmpty ? originName : '?'} → ${destName.isNotEmpty ? destName : '?'}'
        : '';
    final opName = (op?['name'] ?? '').toString();
    final price = trip['price_cents'];
    final cur = (trip['currency'] ?? '').toString();
    final pricePerSeat =
        price is int ? price : int.tryParse(price.toString()) ?? 0;
    final totalCents = pricePerSeat *
        (seats is int ? seats : int.tryParse(seats.toString()) ?? 1);
    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${L10n.of(context).busBookingTitle} $id',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 8),
        if (routeLine.isNotEmpty)
          Text(routeLine, style: theme.textTheme.titleMedium),
        if (opName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(opName, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 4),
        if (whenLine.isNotEmpty)
          Text(whenLine, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Text(
          '${L10n.of(context).busSeatsLabel}: $seats · ${L10n.of(context).busStatusPrefix}$status',
          style: theme.textTheme.bodyMedium,
        ),
        if (created.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${L10n.of(context).busCreatedAtLabel}$created',
              style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Text(
          L10n.of(context).busFareSummary(
            (pricePerSeat / 100).toStringAsFixed(2),
            cur,
            (totalCents / 100).toStringAsFixed(2),
          ),
          style: theme.textTheme.bodySmall,
        ),
        const Divider(height: 24),
        Text(L10n.of(context).busTicketsTitle,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: WaterButton(
              label: _loadingTickets
                  ? L10n.of(context).busTicketsLoadingLabel
                  : L10n.of(context).busTicketsReloadLabel,
              onTap: () {
                if (_loadingTickets) return;
                _loadTickets();
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        if (_ticketsOut.isNotEmpty)
          Text(_ticketsOut, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        if (_tickets.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final tk in _tickets)
                SizedBox(
                  width: 160,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Image.network(
                            Uri.parse('${widget.baseUrl}/qr.png').replace(
                                queryParameters: {
                                  'data': (tk['payload'] ?? '').toString()
                                }).toString(),
                            height: 140,
                            width: 140,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                            '${l.busSeatPrefix}${(tk['seat_no'] ?? '').toString()}',
                            style: const TextStyle(fontSize: 12)),
                        Text((tk['id'] ?? '').toString(),
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(
                            '${l.busStatusPrefix}${(tk['status'] ?? '').toString()}',
                            style: const TextStyle(fontSize: 11)),
                      ]),
                ),
            ],
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
          title: Text(l.busBookingTitle), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        bg,
        Positioned.fill(
            child: SafeArea(
                child: GlassPanel(
                    padding: const EdgeInsets.all(16), child: content))),
      ]),
    );
  }
}

// Stays Operator (Hotels) page: create operator, manage listings, view bookings
class StaysOperatorPage extends StatefulWidget {
  final String baseUrl;
  const StaysOperatorPage(this.baseUrl, {super.key});
  @override
  State<StaysOperatorPage> createState() => _StaysOperatorPageState();
}

class _StaysOperatorPageState extends State<StaysOperatorPage> {
  final opIdCtrl = TextEditingController();
  final opNameCtrl = TextEditingController();
  final opUserCtrl = TextEditingController();
  final opPhoneCtrl = TextEditingController();
  final opCityCtrl = TextEditingController();
  final opCodeCtrl = TextEditingController();
  final ltitleCtrl = TextEditingController();
  final lcityCtrl = TextEditingController();
  final laddrCtrl = TextEditingController();
  final lpriceCtrl = TextEditingController(text: '250000');
  int? _lRoomTypeSel;
  // Multi-property
  List<dynamic> _propList = [];
  int? _propSel;
  final propNameCtrl = TextEditingController();
  final propCityCtrl = TextEditingController();
  String _opRole = 'owner';
  // Per-form property selectors
  int? _propSelListing;
  int? _propSelRT;
  int? _propSelRoom;
  // Staff management
  final staffUserCtrl = TextEditingController();
  final staffPhoneCtrl = TextEditingController();
  String _staffRoleSel = 'frontdesk';
  int? _staffPropSel;
  String staffOut = '';
  List<dynamic> _staffList = [];
  final Map<int, String> _staffRoleEdit = {};
  final Map<int, int?> _staffPropEdit = {};
  final Set<int> _staffSel = <int>{};
  final staffSearchCtrl = TextEditingController();
  bool _staffOnlyActive = true; // default: show only active
  String _staffRoleFilter = '';
  bool _showOpControls = false;
  // Property types
  final List<String> _propTypes = const [
    'Hotels',
    'Apartments',
    'Resorts',
    'Villas',
    'Cabins',
    'Cottages',
    'Glamping Sites',
    'Serviced Apartments',
    'Vacation Homes',
    'Guest Houses',
    'Hostels',
    'Motels',
    'B&Bs',
    'Ryokans',
    'Riads',
    'Resort Villages',
    'Homestays',
    'Campgrounds',
    'Country Houses',
    'Farm Stays',
    'Boats',
    'Luxury Tents',
    'Self-Catering Accomodations',
    'Tiny Houses'
  ];
  String _lTypeSel = '';
  final _lImgCtrl = TextEditingController();
  final _lDescCtrl = TextEditingController();
  String oput = '';
  String lout = '';
  String bout = '';
  String? _token;
  // Listings filter/pagination
  final lqCtrl = TextEditingController();
  final lcityFilterCtrl = TextEditingController();
  String _lTypeFilterSel = '';
  final ltypeFilterCtrl = TextEditingController();
  final lpageCtrl = TextEditingController(text: '0');
  final lsizeCtrl = TextEditingController(text: '10');
  String _lSortBy = 'created_at';
  String _lOrder = 'desc';
  List<dynamic> _olist = [];
  int _ototal = 0;
  // Bookings pagination
  final bpageCtrl = TextEditingController(text: '0');
  final bsizeCtrl = TextEditingController(text: '10');
  List<dynamic> _obooks = [];
  int _btotal = 0;
  int _bRequested = 0, _bConfirmed = 0, _bCanceled = 0, _bCompleted = 0;
  int _bAmountCents = 0;
  String _curSym = 'SYP';
  String _bSortBy = 'created_at';
  String _bOrder = 'desc';
  String _bStatus = '';
  final bFromCtrl = TextEditingController();
  final bToCtrl = TextEditingController();
  // Room types
  final rtTitleCtrl = TextEditingController();
  final rtDescCtrl = TextEditingController();
  final rtPriceCtrl = TextEditingController(text: '200000');
  final rtGuestsCtrl = TextEditingController(text: '2');
  String rtOut = '';
  List<dynamic> _rtList = [];
  // Rooms
  final rmCodeCtrl = TextEditingController();
  final rmFloorCtrl = TextEditingController();
  String rmStatusSel = 'clean';
  int? rmTypeSel;
  String rmOut = '';
  List<dynamic> _roomList = [];
  // Housekeeping filters and selection
  String _roomFilterSel = '';
  Set<int> _roomSel = <int>{};
  String _roomBulkStatusSel = 'clean';
  // Rates
  DateTime rateFrom = DateTime.now();
  int rateDays = 30;
  int? rateRtSel;
  String rateOut = '';
  Map<String, Map<String, dynamic>> _rateMap = {};
  final rateFillAllotCtrl = TextEditingController(text: '5');
  // Rates · Bulk tools
  final bulkPriceCtrl = TextEditingController();
  final bulkAllotCtrl = TextEditingController();
  final bulkMinLosCtrl = TextEditingController();
  final bulkMaxLosCtrl = TextEditingController();
  final promoPercentCtrl = TextEditingController(text: '10');
  String _bulkClosedSel = '';
  String _bulkCtaSel = '';
  String _bulkCtdSel = '';
  bool _bulkOnlyMissing = true;
  // Paint/scroll state and sticky header helpers
  bool _paintMode = false;
  String _paintField = 'closed';
  bool _paintValue = true;
  Set<String> _paintSel = <String>{};
  String? _cursorDate;
  bool _isPainting = false;
  final FocusNode _ratesFocus = FocusNode();
  bool _appendBusy = false;
  int _appendChunk = 30;
  final jumpCtrl = TextEditingController();

  bool _onlyMissingPrice = true;
  bool _onlyMissingAllot = true;
  bool _onlyMissingMinLos = true;
  bool _onlyMissingMaxLos = true;
  // Copy range → target start
  final copyFromCtrl = TextEditingController();
  final copyDaysCtrl = TextEditingController(text: '7');
  final copyTargetCtrl = TextEditingController();
  bool _copyPrice = true,
      _copyAllot = true,
      _copyMinLos = true,
      _copyMaxLos = true,
      _copyClosed = true,
      _copyCta = true,
      _copyCtd = true;
  String _copyPattern = 'all';
  final copyEveryNCtrl = TextEditingController(text: '2');
  // Undo last bulk payload snapshot
  List<Map<String, dynamic>>? _undoDays;
  int? _undoRt;
  String? _undoOpId;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    try {
      final sp = await SharedPreferences.getInstance();
      opIdCtrl.text = sp.getString('stays_op_id') ?? '';
      final t = sp.getString('stays_op_token');
      if (t != null && t.isNotEmpty) {
        _token = t;
      }
      final rs = sp.getString('stays_op_role');
      if (rs != null && rs.isNotEmpty) _opRole = rs;
      final pid = sp.getInt('stays_prop_id');
      if (pid != null && pid > 0) _propSel = pid;
      final cs = sp.getString('currency_symbol');
      if (cs != null && cs.isNotEmpty) {
        _curSym = cs;
      }
      // Rates prefs
      final pf = sp.getString('rates_paint_field');
      if (pf != null && pf.isNotEmpty) _paintField = pf;
      final pv = sp.getBool('rates_paint_value');
      if (pv != null) _paintValue = pv;
      final pm = sp.getBool('rates_paint_mode');
      if (pm != null) _paintMode = pm;
      final cp = sp.getString('rates_copy_pattern');
      if (cp != null && cp.isNotEmpty) _copyPattern = cp;
      final cn = sp.getString('rates_copy_every_n');
      if (cn != null && cn.isNotEmpty) copyEveryNCtrl.text = cn;
      final rid = sp.getInt('rates_room_type_id');
      if (rid != null && rid > 0) rateRtSel = rid;
      final fr = sp.getString('rates_from_iso');
      if (fr != null && fr.contains('-')) {
        try {
          final d = DateTime.parse(fr);
          rateFrom = d;
        } catch (_) {}
      }
      final rds = sp.getInt('rates_days');
      if (rds != null && rds > 0) rateDays = rds;
      final ac = sp.getInt('rates_append_chunk');
      if (ac != null && ac > 0) _appendChunk = ac;
      if (mounted) setState(() {});
      try {
        if (opIdCtrl.text.trim().isNotEmpty &&
            _token != null &&
            _token!.isNotEmpty) {
          await _listRoomTypes();
          await _listProps();
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _saveRatesPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('rates_paint_field', _paintField);
      await sp.setBool('rates_paint_value', _paintValue);
      await sp.setString('rates_copy_pattern', _copyPattern);
      await sp.setString('rates_copy_every_n', copyEveryNCtrl.text.trim());
      await sp.setInt('rates_room_type_id', rateRtSel ?? 0);
      final ds =
          '${rateFrom.year.toString().padLeft(4, '0')}-${rateFrom.month.toString().padLeft(2, '0')}-${rateFrom.day.toString().padLeft(2, '0')}';
      await sp.setString('rates_from_iso', ds);
      await sp.setInt('rates_days', rateDays);
      await sp.setInt('rates_append_chunk', _appendChunk);
      await sp.setBool('rates_paint_mode', _paintMode);
    } catch (_) {}
  }

  Future<void> _saveOpId(String id) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('stays_op_id', id);
    } catch (_) {}
  }

  Future<void> _saveToken(String? t) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (t == null || t.isEmpty) {
        await sp.remove('stays_op_token');
      } else {
        await sp.setString('stays_op_token', t);
      }
    } catch (_) {}
  }

  Future<void> _saveRole(String r) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('stays_op_role', r);
    } catch (_) {}
  }

  Future<void> _savePropId(int? id) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (id == null || id <= 0) {
        await sp.remove('stays_prop_id');
      } else {
        await sp.setInt('stays_prop_id', id);
      }
    } catch (_) {}
  }

  Future<void> _logout() async {
    setState(() => oput = 'logged out');
    _token = null;
    await _saveToken(null);
    if (mounted) setState(() {});
  }

  Future<void> _createOperator() async {
    setState(() => oput = '...');
    final h = await _hdr(json: true);
    h['Idempotency-Key'] = 'op-${DateTime.now().millisecondsSinceEpoch}';
    final body = {
      'name': opNameCtrl.text.trim(),
      'username':
          opUserCtrl.text.trim().isEmpty ? null : opUserCtrl.text.trim(),
      'phone': opPhoneCtrl.text.trim().isEmpty ? null : opPhoneCtrl.text.trim(),
      'city': opCityCtrl.text.trim().isEmpty ? null : opCityCtrl.text.trim()
    };
    final r = await http.post(Uri.parse('${widget.baseUrl}/stays/operators'),
        headers: h, body: jsonEncode(body));
    setState(() => oput = '${r.statusCode}: ${r.body}');
    try {
      final j = jsonDecode(r.body);
      final id = (j['id'] ?? '').toString();
      if (id.isNotEmpty) {
        opIdCtrl.text = id;
        _saveOpId(id);
      }
    } catch (_) {}
  }

  Future<void> _reqOtp() async {
    setState(() => oput = '...');
    final user = opUserCtrl.text.trim();
    final phone = opPhoneCtrl.text.trim();
    final payload = user.isNotEmpty ? {'username': user} : {'phone': phone};
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/stays/operators/request_code'),
        headers: await _hdr(json: true),
        body: jsonEncode(payload));
    setState(() => oput = '${r.statusCode}: ${r.body}');
    try {
      final j = jsonDecode(r.body);
      final code = (j['code'] ?? '').toString();
      if (code.isNotEmpty) {
        opCodeCtrl.text = code;
      }
    } catch (_) {}
  }

  Future<void> _verifyOtp() async {
    setState(() => oput = '...');
    final payload = {
      'username':
          opUserCtrl.text.trim().isEmpty ? null : opUserCtrl.text.trim(),
      'phone': opPhoneCtrl.text.trim().isEmpty ? null : opPhoneCtrl.text.trim(),
      'code': opCodeCtrl.text.trim(),
      'name': opNameCtrl.text.trim().isEmpty ? null : opNameCtrl.text.trim(),
      'city': opCityCtrl.text.trim().isEmpty ? null : opCityCtrl.text.trim()
    };
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/stays/operators/verify'),
        headers: await _hdr(json: true),
        body: jsonEncode(payload));
    setState(() => oput = '${r.statusCode}: ${r.body}');
    try {
      final j = jsonDecode(r.body);
      final id = (j['operator_id'] ?? '').toString();
      final t = (j['token'] ?? '').toString();
      final role = (j['role'] ?? '').toString();
      final pid = (j['property_id'] ?? 0);
      if (id.isNotEmpty) {
        opIdCtrl.text = id;
        _saveOpId(id);
      }
      if (t.isNotEmpty) {
        _token = t;
        await _saveToken(t);
        if (mounted) setState(() {});
        try {
          await _listRoomTypes();
          await _listProps();
        } catch (_) {}
      }
      if (role.isNotEmpty) {
        setState(() => _opRole = role);
        await _saveRole(role);
      }
      if (pid is int && pid > 0) {
        setState(() => _propSel = pid);
        await _savePropId(pid);
      }
    } catch (_) {}
  }

  Future<void> _getOperator() async {
    setState(() => oput = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => oput = 'set operator id');
      return;
    }
    final r = await http.get(Uri.parse('${widget.baseUrl}/stays/operators/$id'),
        headers: await _hdr());
    setState(() => oput = '${r.statusCode}: ${r.body}');
  }

  Future<void> _createListing() async {
    setState(() => lout = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => lout = 'set operator id');
      return;
    }
    final title = ltitleCtrl.text.trim();
    final price = int.tryParse(lpriceCtrl.text.trim()) ?? 0;
    if (title.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Title required')));
      setState(() => lout = 'validation: title');
      return;
    }
    if (price <= 0) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Price must be > 0')));
      setState(() => lout = 'validation: price');
      return;
    }
    final imgs = _lImgCtrl.text.trim().isEmpty
        ? <String>[]
        : _lImgCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    final body = {
      'title': title,
      'city': lcityCtrl.text.trim().isEmpty ? null : lcityCtrl.text.trim(),
      'address': laddrCtrl.text.trim().isEmpty ? null : laddrCtrl.text.trim(),
      'description':
          _lDescCtrl.text.trim().isEmpty ? null : _lDescCtrl.text.trim(),
      'image_urls': imgs.isEmpty ? null : imgs,
      'property_type': _lTypeSel.isEmpty ? null : _lTypeSel,
      'room_type_id': _lRoomTypeSel,
      'property_id': (_propSelListing ?? _propSel),
      'price_per_night_cents': price
    };
    final h = await _hdr(json: true);
    if (_token != null && _token!.isNotEmpty)
      h['Authorization'] = 'Bearer ' + _token!;
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/stays/operators/$id/listings'),
        headers: h,
        body: jsonEncode(body));
    setState(() => lout = '${r.statusCode}: ${r.body}');
  }

  Future<Map<String, String>> _authHdr({bool json = false}) async {
    final h = await _hdr(json: json);
    if (_token != null && _token!.isNotEmpty)
      h['Authorization'] = 'Bearer ' + _token!;
    return h;
  }

  // Room types
  Future<void> _createRoomType() async {
    setState(() => rtOut = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rtOut = 'set operator id');
      return;
    }
    final body = {
      'title': rtTitleCtrl.text.trim(),
      'description':
          rtDescCtrl.text.trim().isEmpty ? null : rtDescCtrl.text.trim(),
      'base_price_cents': int.tryParse(rtPriceCtrl.text.trim()) ?? 0,
      'max_guests': int.tryParse(rtGuestsCtrl.text.trim()) ?? 2,
      'property_id': (_propSelRT ?? _propSel)
    };
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types'),
        headers: await _authHdr(json: true),
        body: jsonEncode(body));
    setState(() => rtOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _listRoomTypes() async {
    setState(() => rtOut = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rtOut = 'set operator id');
      return;
    }
    final params = <String, String>{
      if (_propSel != null && _propSel! > 0) 'property_id': _propSel.toString()
    };
    final r = await http.get(
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types')
            .replace(queryParameters: params),
        headers: await _authHdr());
    if (r.statusCode == 200) {
      try {
        _rtList = jsonDecode(r.body) as List;
        // Auto-select first room type in relevant dropdowns if empty
        if (_rtList.isNotEmpty) {
          final firstId = (_rtList.first['id'] ?? 0) as int;
          _lRoomTypeSel ??= firstId;
          rmTypeSel ??= firstId;
          rateRtSel ??= firstId;
        }
        rtOut = '${r.statusCode}: ${_rtList.length}';
      } catch (_) {
        rtOut = '${r.statusCode}: ${r.body}';
      }
    } else {
      rtOut = '${r.statusCode}: ${r.body}';
    }
    if (mounted) setState(() {});
  }

  // Rooms
  Future<void> _createRoom() async {
    setState(() => rmOut = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rmOut = 'set operator id');
      return;
    }
    if (rmTypeSel == null) {
      setState(() => rmOut = 'select room type');
      return;
    }
    final body = {
      'room_type_id': rmTypeSel,
      'code': rmCodeCtrl.text.trim(),
      'floor': rmFloorCtrl.text.trim().isEmpty ? null : rmFloorCtrl.text.trim(),
      'status': rmStatusSel,
      'property_id': (_propSelRoom ?? _propSel)
    };
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/stays/operators/$id/rooms'),
        headers: await _authHdr(json: true),
        body: jsonEncode(body));
    setState(() => rmOut = '${r.statusCode}: ${r.body}');
  }

  Future<void> _listProps() async {
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) return;
    try {
      final r = await http.get(
          Uri.parse('${widget.baseUrl}/stays/operators/$id/properties'),
          headers: await _authHdr());
      if (r.statusCode == 200) {
        _propList = jsonDecode(r.body) as List;
        if (_propSel == null && _propList.isNotEmpty) {
          _propSel = (_propList.first['id'] ?? 0) as int;
          await _savePropId(_propSel);
        }
        _propSelListing ??= _propSel;
        _propSelRT ??= _propSel;
        _propSelRoom ??= _propSel;
        _staffPropSel ??= _propSel;
        setState(() {});
      }
    } catch (_) {}
  }

  // NOTE: keep a single implementation with filters; removed duplicate without filters
  Future<void> _listStaff() async {
    setState(() => staffOut = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => staffOut = 'set operator id');
      return;
    }
    try {
      final params = <String, String>{};
      if (_staffOnlyActive) params['active'] = '1';
      if (staffSearchCtrl.text.trim().isNotEmpty)
        params['q'] = staffSearchCtrl.text.trim();
      if (_staffRoleFilter.isNotEmpty) params['role'] = _staffRoleFilter;
      final r = await http.get(
          Uri.parse('${widget.baseUrl}/stays/operators/$id/staff')
              .replace(queryParameters: params),
          headers: await _authHdr());
      if (r.statusCode == 200) {
        _staffList = jsonDecode(r.body) as List;
        staffOut = '${r.statusCode}: ${_staffList.length}';
      } else {
        staffOut = '${r.statusCode}: ${r.body}';
      }
    } catch (e) {
      staffOut = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _bulkDeactivateStaff() async {
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) return;
    final sel = [..._staffSel];
    if (sel.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select staff first')));
      return;
    }
    int ok = 0;
    for (final sid in sel) {
      try {
        final r = await http.delete(
            Uri.parse('${widget.baseUrl}/stays/operators/$id/staff/$sid'),
            headers: await _authHdr());
        if (r.statusCode == 200) ok++;
      } catch (_) {}
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deactivated $ok/${sel.length} staff')));
    await _listStaff();
    setState(() => _staffSel.clear());
  }

  Future<void> _createStaff() async {
    setState(() => staffOut = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => staffOut = 'set operator id');
      return;
    }
    final body = {
      'username': staffUserCtrl.text.trim(),
      'role': _staffRoleSel,
      'property_id': _staffPropSel,
      'phone':
          staffPhoneCtrl.text.trim().isEmpty ? null : staffPhoneCtrl.text.trim()
    };
    try {
      final r = await http.post(
          Uri.parse('${widget.baseUrl}/stays/operators/$id/staff'),
          headers: await _authHdr(json: true),
          body: jsonEncode(body));
      staffOut = '${r.statusCode}: ${r.body}';
      await _listStaff();
    } catch (e) {
      staffOut = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _saveStaff(Map s) async {
    setState(() => staffOut = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => staffOut = 'set operator id');
      return;
    }
    final sid = (s['id'] ?? 0) as int;
    if (sid <= 0) {
      setState(() => staffOut = 'invalid staff');
      return;
    }
    final role = _staffRoleEdit[sid] ?? (s['role'] ?? '').toString();
    final pid = _staffPropEdit[sid] ?? (s['property_id'] as int?);
    final body = {'role': role, 'property_id': pid};
    try {
      final r = await http.patch(
          Uri.parse('${widget.baseUrl}/stays/operators/$id/staff/$sid'),
          headers: await _authHdr(json: true),
          body: jsonEncode(body));
      staffOut = '${r.statusCode}: ${r.body}';
      await _listStaff();
    } catch (e) {
      staffOut = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleStaffActive(Map s) async {
    setState(() => staffOut = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => staffOut = 'set operator id');
      return;
    }
    final sid = (s['id'] ?? 0) as int;
    if (sid <= 0) {
      setState(() => staffOut = 'invalid staff');
      return;
    }
    final active = (s['active'] ?? true) == true;
    try {
      if (active) {
        final r = await http.delete(
            Uri.parse('${widget.baseUrl}/stays/operators/$id/staff/$sid'),
            headers: await _authHdr());
        staffOut = '${r.statusCode}: ${r.body}';
      } else {
        final r = await http.patch(
            Uri.parse('${widget.baseUrl}/stays/operators/$id/staff/$sid'),
            headers: await _authHdr(json: true),
            body: jsonEncode({'active': true}));
        staffOut = '${r.statusCode}: ${r.body}';
      }
      await _listStaff();
    } catch (e) {
      staffOut = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _createProp() async {
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) return;
    try {
      final body = {
        'name': propNameCtrl.text.trim(),
        'city':
            propCityCtrl.text.trim().isEmpty ? null : propCityCtrl.text.trim()
      };
      final r = await http.post(
          Uri.parse('${widget.baseUrl}/stays/operators/$id/properties'),
          headers: await _authHdr(json: true),
          body: jsonEncode(body));
      lout = '${r.statusCode}: ${r.body}';
      await _listProps();
    } catch (e) {
      lout = 'error: $e';
      setState(() {});
    }
  }

  Future<void> _listRooms() async {
    setState(() => rmOut = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rmOut = 'set operator id');
      return;
    }
    final params = <String, String>{
      if (_propSel != null && _propSel! > 0) 'property_id': _propSel.toString()
    };
    final r = await http.get(
        Uri.parse('${widget.baseUrl}/stays/operators/$id/rooms')
            .replace(queryParameters: params),
        headers: await _authHdr());
    if (r.statusCode == 200) {
      try {
        _roomList = jsonDecode(r.body) as List;
        rmOut = '${r.statusCode}: ${_roomList.length}';
      } catch (_) {
        rmOut = '${r.statusCode}: ${r.body}';
      }
    } else {
      rmOut = '${r.statusCode}: ${r.body}';
    }
    if (mounted) setState(() {});
  }

  // Rates
  Future<void> _loadRates() async {
    setState(() => rateOut = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rateOut = 'set operator id');
      return;
    }
    final rt = rateRtSel ??
        (_rtList.isNotEmpty ? (_rtList.first['id'] as int?) : null);
    if (rt == null) {
      setState(() => rateOut = 'select room type');
      return;
    }
    final f =
        '${rateFrom.year.toString().padLeft(4, '0')}-${rateFrom.month.toString().padLeft(2, '0')}-${rateFrom.day.toString().padLeft(2, '0')}';
    final t = rateFrom.add(Duration(days: rateDays - 1));
    final to =
        '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    final u =
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types/$rt/rates')
            .replace(queryParameters: {'frm': f, 'to': to});
    final r = await http.get(u, headers: await _authHdr());
    if (r.statusCode == 200) {
      try {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final items = (j['items'] as List?) ?? [];
        _rateMap.clear();
        for (final it in items) {
          final d = (it['date'] ?? '').toString();
          _rateMap[d] = Map<String, dynamic>.from(it);
        }
        rateOut = '${r.statusCode}: ${items.length} days';
      } catch (_) {
        rateOut = '${r.statusCode}: ${r.body}';
      }
    } else {
      rateOut = '${r.statusCode}: ${r.body}';
    }
    if (mounted) setState(() {});
  }

  // Use _appendChunk for keyboard and dynamic append size
  Future<void> _appendNext() async {
    await _appendRange(forward: true, days: _appendChunk);
  }

  Future<void> _appendPrev() async {
    await _appendRange(forward: false, days: _appendChunk);
  }

  Future<void> _appendRange({required bool forward, required int days}) async {
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rateOut = 'set operator id');
      return;
    }
    final rt = rateRtSel ??
        (_rtList.isNotEmpty ? (_rtList.first['id'] as int?) : null);
    if (rt == null) {
      setState(() => rateOut = 'select room type');
      return;
    }
    DateTime frm, to;
    if (forward) {
      frm = rateFrom.add(Duration(days: rateDays));
      to = frm.add(Duration(days: days - 1));
    } else {
      to = rateFrom.subtract(const Duration(days: 1));
      frm = rateFrom.subtract(Duration(days: days));
    }
    final f =
        '${frm.year.toString().padLeft(4, '0')}-${frm.month.toString().padLeft(2, '0')}-${frm.day.toString().padLeft(2, '0')}';
    final t =
        '${to.year.toString().padLeft(4, '0')}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
    final u =
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types/$rt/rates')
            .replace(queryParameters: {'frm': f, 'to': t});
    final r = await http.get(u, headers: await _authHdr());
    if (r.statusCode == 200) {
      try {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final items = (j['items'] as List?) ?? [];
        for (final it in items) {
          final d = (it['date'] ?? '').toString();
          _rateMap[d] = Map<String, dynamic>.from(it);
        }
        if (forward) {
          rateDays += days;
        } else {
          rateFrom = frm;
          rateDays += days;
        }
        rateOut = 'append ok: ${items.length} days';
      } catch (_) {
        rateOut = '${r.statusCode}: ${r.body}';
      }
    } else {
      rateOut = '${r.statusCode}: ${r.body}';
    }
    if (mounted) setState(() {});
    try {
      await _saveRatesPrefs();
    } catch (_) {}
  }

  Future<void> _applyBulkRange() async {
    setState(() => rateOut = 'applying...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rateOut = 'set operator id');
      return;
    }
    final rt = rateRtSel ??
        (_rtList.isNotEmpty ? (_rtList.first['id'] as int?) : null);
    if (rt == null) {
      setState(() => rateOut = 'select room type');
      return;
    }
    final price = int.tryParse(bulkPriceCtrl.text.trim());
    final allot = int.tryParse(bulkAllotCtrl.text.trim());
    final minLos = int.tryParse(bulkMinLosCtrl.text.trim());
    final maxLos = int.tryParse(bulkMaxLosCtrl.text.trim());
    bool? closedSel =
        _bulkClosedSel.isEmpty ? null : (_bulkClosedSel == 'true');
    bool? ctaSel = _bulkCtaSel.isEmpty ? null : (_bulkCtaSel == 'true');
    bool? ctdSel = _bulkCtdSel.isEmpty ? null : (_bulkCtdSel == 'true');
    final days = <Map<String, dynamic>>[];
    final undo = <Map<String, dynamic>>[];
    for (int i = 0; i < rateDays; i++) {
      final d = rateFrom.add(Duration(days: i));
      final ds =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final cur = _rateMap[ds];
      final item = <String, dynamic>{'date': ds};
      // Numeric fields: include if provided; if onlyMissing enabled, apply per-property setting
      if (price != null) {
        final miss = _bulkOnlyMissing && _onlyMissingPrice;
        if (!miss || cur == null || (cur['price_cents'] == null)) {
          item['price_cents'] = price;
          if (cur != null && cur['price_cents'] != null)
            undo.add({'date': ds, 'price_cents': cur['price_cents']});
          else
            undo.add({'date': ds, 'clear_price': true});
        }
      }
      if (allot != null) {
        final miss = _bulkOnlyMissing && _onlyMissingAllot;
        if (!miss || cur == null || (cur['allotment'] == null)) {
          item['allotment'] = allot;
          if (cur != null && cur['allotment'] != null)
            undo.add({'date': ds, 'allotment': cur['allotment']});
          else
            undo.add({'date': ds, 'clear_allotment': true});
        }
      }
      if (minLos != null) {
        final miss = _bulkOnlyMissing && _onlyMissingMinLos;
        if (!miss || cur == null || (cur['min_los'] == null)) {
          item['min_los'] = minLos;
          if (cur != null && cur['min_los'] != null)
            undo.add({'date': ds, 'min_los': cur['min_los']});
          else
            undo.add({'date': ds, 'clear_min_los': true});
        }
      }
      if (maxLos != null) {
        final miss = _bulkOnlyMissing && _onlyMissingMaxLos;
        if (!miss || cur == null || (cur['max_los'] == null)) {
          item['max_los'] = maxLos;
          if (cur != null && cur['max_los'] != null)
            undo.add({'date': ds, 'max_los': cur['max_los']});
          else
            undo.add({'date': ds, 'clear_max_los': true});
        }
      }
      // Boolean fields: include if selected (keep/true/false); do not apply 'onlyMissing'
      if (closedSel != null) {
        item['closed'] = closedSel;
        if (cur != null && cur.containsKey('closed'))
          undo.add({'date': ds, 'closed': cur['closed'] == true});
      }
      if (ctaSel != null) {
        item['cta'] = ctaSel;
        if (cur != null && cur.containsKey('cta'))
          undo.add({'date': ds, 'cta': cur['cta'] == true});
      }
      if (ctdSel != null) {
        item['ctd'] = ctdSel;
        if (cur != null && cur.containsKey('ctd'))
          undo.add({'date': ds, 'ctd': cur['ctd'] == true});
      }
      if (item.length > 1) {
        days.add(item);
      }
    }
    if (days.isEmpty) {
      setState(() => rateOut = 'nothing to apply');
      return;
    }
    // save undo snapshot
    _undoDays = undo;
    _undoRt = rt;
    _undoOpId = id;
    final uri =
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types/$rt/rates');
    final r = await http.post(uri,
        headers: await _authHdr(json: true), body: jsonEncode({'days': days}));
    setState(() => rateOut = '${r.statusCode}: ${r.body}');
    await _loadRates();
  }

  Future<void> _applyPromotion() async {
    if (!(_opRole == 'owner' || _opRole == 'revenue')) {
      setState(() => rateOut = 'no access');
      return;
    }
    setState(() => rateOut = 'applying promotion...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rateOut = 'set operator id');
      return;
    }
    final rt = rateRtSel ??
        (_rtList.isNotEmpty ? (_rtList.first['id'] as int?) : null);
    if (rt == null) {
      setState(() => rateOut = 'select room type');
      return;
    }
    if (_rateMap.isEmpty) {
      setState(() => rateOut = 'load rates first');
      return;
    }
    final pct = int.tryParse(promoPercentCtrl.text.trim());
    if (pct == null || pct <= 0 || pct >= 100) {
      setState(() => rateOut = 'set discount % between 1 and 99');
      return;
    }
    final days = <Map<String, dynamic>>[];
    final undo = <Map<String, dynamic>>[];
    for (int i = 0; i < rateDays; i++) {
      final d = rateFrom.add(Duration(days: i));
      final ds =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final cur = _rateMap[ds];
      if (cur == null) continue;
      final oldPrice = cur['price_cents'];
      if (oldPrice is! int || oldPrice <= 0) continue;
      final newPrice = (oldPrice * (100 - pct) / 100).round();
      days.add({'date': ds, 'price_cents': newPrice});
      undo.add({'date': ds, 'price_cents': oldPrice});
    }
    if (days.isEmpty) {
      setState(() => rateOut = 'nothing to apply');
      return;
    }
    _undoDays = undo;
    _undoRt = rt;
    _undoOpId = id;
    final uri =
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types/$rt/rates');
    final r = await http.post(uri,
        headers: await _authHdr(json: true), body: jsonEncode({'days': days}));
    setState(() => rateOut = 'promo: ${r.statusCode}');
    await _loadRates();
  }

  Future<void> _undoLastBulk() async {
    if (!(_opRole == 'owner' || _opRole == 'revenue')) {
      setState(() => rateOut = 'no access');
      return;
    }
    if (_undoDays == null ||
        _undoDays!.isEmpty ||
        _undoRt == null ||
        (_undoOpId == null || _undoOpId!.isEmpty)) {
      setState(() => rateOut = 'nothing to undo');
      return;
    }
    final uri = Uri.parse(
        '${widget.baseUrl}/stays/operators/${_undoOpId}/room_types/${_undoRt}/rates');
    final r = await http.post(uri,
        headers: await _authHdr(json: true),
        body: jsonEncode({'days': _undoDays}));
    setState(() => rateOut = 'undo: ${r.statusCode}');
    _undoDays = null;
    _undoRt = null;
    _undoOpId = null;
    await _loadRates();
  }

  DateTime? _parseYmd(String s) {
    try {
      final p = s.trim().split('-');
      if (p.length != 3) return null;
      return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {
      return null;
    }
  }

  Future<void> _copyRangeApply() async {
    if (!(_opRole == 'owner' || _opRole == 'revenue')) {
      setState(() => rateOut = 'no access');
      return;
    }
    setState(() => rateOut = 'copying...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rateOut = 'set operator id');
      return;
    }
    final rt = rateRtSel ??
        (_rtList.isNotEmpty ? (_rtList.first['id'] as int?) : null);
    if (rt == null) {
      setState(() => rateOut = 'select room type');
      return;
    }
    final src0 = _parseYmd(copyFromCtrl.text.trim());
    final tgt0 = _parseYmd(copyTargetCtrl.text.trim());
    final n = int.tryParse(copyDaysCtrl.text.trim()) ?? 0;
    if (src0 == null || tgt0 == null || n <= 0) {
      setState(() => rateOut = 'invalid copy inputs');
      return;
    }
    final days = <Map<String, dynamic>>[];
    final undo = <Map<String, dynamic>>[];
    for (int i = 0; i < n; i++) {
      final src =
          DateTime(src0.year, src0.month, src0.day).add(Duration(days: i));
      final tgt =
          DateTime(tgt0.year, tgt0.month, tgt0.day).add(Duration(days: i));
      if (_copyPattern == 'weekends') {
        final wd = src.weekday;
        if (!(wd == DateTime.saturday || wd == DateTime.sunday)) continue;
      } else if (_copyPattern == 'weekdays') {
        final wd = src.weekday;
        if (wd == DateTime.saturday || wd == DateTime.sunday) continue;
      } else if (_copyPattern == 'every_n') {
        final nstep = int.tryParse(copyEveryNCtrl.text.trim()) ?? 0;
        if (nstep > 1 && (i % nstep) != 0) continue;
      }
      final ss =
          '${src.year.toString().padLeft(4, '0')}-${src.month.toString().padLeft(2, '0')}-${src.day.toString().padLeft(2, '0')}';
      final ts =
          '${tgt.year.toString().padLeft(4, '0')}-${tgt.month.toString().padLeft(2, '0')}-${tgt.day.toString().padLeft(2, '0')}';
      final curSrc = _rateMap[ss];
      final curTgt = _rateMap[ts];
      if (curSrc == null) continue;
      final item = <String, dynamic>{'date': ts};
      if (_copyPrice && curSrc['price_cents'] != null) {
        item['price_cents'] = curSrc['price_cents'];
        if (curTgt != null && curTgt['price_cents'] != null)
          undo.add({'date': ts, 'price_cents': curTgt['price_cents']});
        else
          undo.add({'date': ts, 'clear_price': true});
      }
      if (_copyAllot && curSrc['allotment'] != null) {
        item['allotment'] = curSrc['allotment'];
        if (curTgt != null && curTgt['allotment'] != null)
          undo.add({'date': ts, 'allotment': curTgt['allotment']});
        else
          undo.add({'date': ts, 'clear_allotment': true});
      }
      if (_copyMinLos && curSrc['min_los'] != null) {
        item['min_los'] = curSrc['min_los'];
        if (curTgt != null && curTgt['min_los'] != null)
          undo.add({'date': ts, 'min_los': curTgt['min_los']});
        else
          undo.add({'date': ts, 'clear_min_los': true});
      }
      if (_copyMaxLos && curSrc['max_los'] != null) {
        item['max_los'] = curSrc['max_los'];
        if (curTgt != null && curTgt['max_los'] != null)
          undo.add({'date': ts, 'max_los': curTgt['max_los']});
        else
          undo.add({'date': ts, 'clear_max_los': true});
      }
      if (_copyClosed && curSrc.containsKey('closed')) {
        item['closed'] = curSrc['closed'] == true;
        if (curTgt != null && curTgt.containsKey('closed'))
          undo.add({'date': ts, 'closed': curTgt['closed'] == true});
      }
      if (_copyCta && curSrc.containsKey('cta')) {
        item['cta'] = curSrc['cta'] == true;
        if (curTgt != null && curTgt.containsKey('cta'))
          undo.add({'date': ts, 'cta': curTgt['cta'] == true});
      }
      if (_copyCtd && curSrc.containsKey('ctd')) {
        item['ctd'] = curSrc['ctd'] == true;
        if (curTgt != null && curTgt.containsKey('ctd'))
          undo.add({'date': ts, 'ctd': curTgt['ctd'] == true});
      }
      if (item.length > 1) {
        days.add(item);
      }
    }
    if (days.isEmpty) {
      setState(() => rateOut = 'nothing to copy');
      return;
    }
    _undoDays = undo;
    _undoRt = rt;
    _undoOpId = id;
    final uri =
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types/$rt/rates');
    final r = await http.post(uri,
        headers: await _authHdr(json: true), body: jsonEncode({'days': days}));
    setState(() => rateOut = 'copy: ${r.statusCode}');
    await _loadRates();
  }

  Widget _rateBadge(String label, Color color) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: .35))),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: .95),
                fontWeight: FontWeight.w600)));
  }

  Future<void> _applyPaint() async {
    if (!(_opRole == 'owner' || _opRole == 'revenue')) {
      setState(() => rateOut = 'no access');
      return;
    }
    if (_paintSel.isEmpty) {
      setState(() => rateOut = 'no days selected');
      return;
    }
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rateOut = 'set operator id');
      return;
    }
    final rt = rateRtSel ??
        (_rtList.isNotEmpty ? (_rtList.first['id'] as int?) : null);
    if (rt == null) {
      setState(() => rateOut = 'select room type');
      return;
    }
    final days = _paintSel.map((ds) {
      final m = <String, dynamic>{'date': ds};
      if (_paintField == 'closed')
        m['closed'] = _paintValue;
      else if (_paintField == 'cta')
        m['cta'] = _paintValue;
      else if (_paintField == 'ctd') m['ctd'] = _paintValue;
      return m;
    }).toList();
    final uri =
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types/$rt/rates');
    final r = await http.post(uri,
        headers: await _authHdr(json: true), body: jsonEncode({'days': days}));
    setState(() => rateOut = 'paint: ${r.statusCode}');
    await _loadRates();
  }

  void _onRatesKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final total = rateDays;
    int idxFromStart(String ds) {
      try {
        final y = int.parse(ds.substring(0, 4));
        final m = int.parse(ds.substring(5, 7));
        final d = int.parse(ds.substring(8, 10));
        final base = DateTime(rateFrom.year, rateFrom.month, rateFrom.day);
        final cur = DateTime(y, m, d);
        return cur.difference(base).inDays;
      } catch (_) {
        return 0;
      }
    }

    String dsAt(int idx) {
      final dt = rateFrom.add(Duration(days: idx));
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    }

    if (_cursorDate == null) _cursorDate = dsAt(0);
    var idx = idxFromStart(_cursorDate!);
    final key = e.logicalKey.keyLabel.toLowerCase();
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final ctrl = pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight) ||
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    if (ctrl && e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _appendNext();
      return;
    }
    if (ctrl && e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _appendPrev();
      return;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      idx = (idx + 1).clamp(0, total - 1);
      setState(() => _cursorDate = dsAt(idx));
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      idx = (idx - 1).clamp(0, total - 1);
      setState(() => _cursorDate = dsAt(idx));
    } else if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      idx = (idx + 7).clamp(0, total - 1);
      setState(() => _cursorDate = dsAt(idx));
    } else if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      idx = (idx - 7).clamp(0, total - 1);
      setState(() => _cursorDate = dsAt(idx));
    } else if (e.logicalKey == LogicalKeyboardKey.space) {
      if (_cursorDate != null) {
        setState(() => _paintSel.contains(_cursorDate!)
            ? _paintSel.remove(_cursorDate!)
            : _paintSel.add(_cursorDate!));
      }
    } else if (key == '1') {
      setState(() => _paintField = 'closed');
    } else if (key == '2') {
      setState(() => _paintField = 'cta');
    } else if (key == '3') {
      setState(() => _paintField = 'ctd');
    } else if (key == 't') {
      setState(() => _paintValue = !_paintValue);
    } else if (e.logicalKey == LogicalKeyboardKey.enter) {
      _applyPaint();
    }
  }

  Future<void> _editRate() async {
    if (!(_opRole == 'owner' || _opRole == 'revenue')) {
      setState(() => rateOut = 'no access');
      return;
    }
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) return;
    final rt = rateRtSel ??
        (_rtList.isNotEmpty ? (_rtList.first['id'] as int?) : null);
    if (rt == null) return;
    final day = await showDatePicker(
        context: context,
        initialDate: rateFrom,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (day == null) return;
    final dateStr =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final pCtrl = TextEditingController(
        text: (_rateMap[dateStr]?['price_cents'] ?? '').toString());
    final aCtrl = TextEditingController(
        text: (_rateMap[dateStr]?['allotment'] ?? '').toString());
    bool closed = (_rateMap[dateStr]?['closed'] ?? false) == true;
    final res = await showDialog<bool>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text('Rate $dateStr'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: pCtrl,
                  decoration: const InputDecoration(labelText: 'Price (SYP)'),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(
                  controller: aCtrl,
                  decoration: const InputDecoration(labelText: 'Allotment'),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              StatefulBuilder(builder: (ctx, setS) {
                return CheckboxListTile(
                    value: closed,
                    onChanged: (v) {
                      setS(() => closed = v ?? false);
                    },
                    title: const Text('Closed'));
              }),
            ]),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save')),
            ],
          );
        });
    if (res != true) return;
    final body = {
      'days': [
        {
          'date': dateStr,
          'price_cents': int.tryParse(pCtrl.text.trim()),
          'allotment': int.tryParse(aCtrl.text.trim()),
          'closed': closed
        }
      ]
    };
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types/$rt/rates'),
        headers: await _authHdr(json: true),
        body: jsonEncode(body));
    rateOut = '${r.statusCode}: ${r.body}';
    await _loadRates();
  }

  Future<void> _editRateOn(String dateStr) async {
    if (!(_opRole == 'owner' || _opRole == 'revenue')) {
      setState(() => rateOut = 'no access');
      return;
    }
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) return;
    final rt = rateRtSel ??
        (_rtList.isNotEmpty ? (_rtList.first['id'] as int?) : null);
    if (rt == null) return;
    final pCtrl = TextEditingController(
        text: (_rateMap[dateStr]?['price_cents'] ?? '').toString());
    final aCtrl = TextEditingController(
        text: (_rateMap[dateStr]?['allotment'] ?? '').toString());
    bool closed = (_rateMap[dateStr]?['closed'] ?? false) == true;
    bool cta = (_rateMap[dateStr]?['cta'] ?? false) == true;
    bool ctd = (_rateMap[dateStr]?['ctd'] ?? false) == true;
    final minLosCtrl = TextEditingController(
        text: (_rateMap[dateStr]?['min_los'] ?? '').toString());
    final maxLosCtrl = TextEditingController(
        text: (_rateMap[dateStr]?['max_los'] ?? '').toString());
    bool clrP = false, clrA = false, clrMin = false, clrMax = false;
    final res = await showDialog<bool>(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text('Rate $dateStr'),
            content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: pCtrl,
                  decoration: const InputDecoration(labelText: 'Price (SYP)'),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextField(
                  controller: aCtrl,
                  decoration: const InputDecoration(labelText: 'Allotment'),
                  keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: minLosCtrl,
                        decoration: const InputDecoration(labelText: 'Min LOS'),
                        keyboardType: TextInputType.number)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: maxLosCtrl,
                        decoration: const InputDecoration(labelText: 'Max LOS'),
                        keyboardType: TextInputType.number)),
              ]),
              const SizedBox(height: 8),
              StatefulBuilder(builder: (ctx, setS) {
                return Column(children: [
                  CheckboxListTile(
                      value: closed,
                      onChanged: (v) {
                        setS(() => closed = v ?? false);
                      },
                      title: const Text('Closed')),
                  CheckboxListTile(
                      value: cta,
                      onChanged: (v) {
                        setS(() => cta = v ?? false);
                      },
                      title: const Text('Closed to Arrival (CTA)')),
                  CheckboxListTile(
                      value: ctd,
                      onChanged: (v) {
                        setS(() => ctd = v ?? false);
                      },
                      title: const Text('Closed to Departure (CTD)')),
                  const Divider(height: 16),
                  const Text('Clear fields'),
                  CheckboxListTile(
                      value: clrP,
                      onChanged: (v) {
                        setS(() => clrP = v ?? false);
                      },
                      title: const Text('Clear price')),
                  CheckboxListTile(
                      value: clrA,
                      onChanged: (v) {
                        setS(() => clrA = v ?? false);
                      },
                      title: const Text('Clear allotment')),
                  CheckboxListTile(
                      value: clrMin,
                      onChanged: (v) {
                        setS(() => clrMin = v ?? false);
                      },
                      title: const Text('Clear min LOS')),
                  CheckboxListTile(
                      value: clrMax,
                      onChanged: (v) {
                        setS(() => clrMax = v ?? false);
                      },
                      title: const Text('Clear max LOS')),
                ]);
              }),
            ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Save')),
            ],
          );
        });
    if (res != true) return;
    final body = {
      'days': [
        {
          'date': dateStr,
          'price_cents': int.tryParse(pCtrl.text.trim()),
          'allotment': int.tryParse(aCtrl.text.trim()),
          'closed': closed,
          'min_los': int.tryParse(minLosCtrl.text.trim()),
          'max_los': int.tryParse(maxLosCtrl.text.trim()),
          'cta': cta,
          'ctd': ctd,
          if (clrP) 'clear_price': true,
          if (clrA) 'clear_allotment': true,
          if (clrMin) 'clear_min_los': true,
          if (clrMax) 'clear_max_los': true,
        }
      ]
    };
    final r = await http.post(
        Uri.parse('${widget.baseUrl}/stays/operators/$id/room_types/$rt/rates'),
        headers: await _authHdr(json: true),
        body: jsonEncode(body));
    rateOut = '${r.statusCode}: ${r.body}';
    await _loadRates();
  }

  Future<void> _fillDefaults() async {
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => rateOut = 'set operator id');
      return;
    }
    final rtId = rateRtSel ??
        (_rtList.isNotEmpty ? (_rtList.first['id'] as int?) : null);
    if (rtId == null) {
      setState(() => rateOut = 'select room type');
      return;
    }
    final rt =
        _rtList.firstWhere((e) => (e['id'] ?? 0) == rtId, orElse: () => {});
    final base = (rt is Map && rt.containsKey('base_price_cents'))
        ? (rt['base_price_cents'] ?? 0) as int
        : 0;
    final allot = int.tryParse(rateFillAllotCtrl.text.trim()) ?? 0;
    final days = List.generate(rateDays, (i) {
      final d = rateFrom.add(Duration(days: i));
      final ds =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return {'date': ds, 'price_cents': base, 'allotment': allot};
    });
    final body = {'days': days};
    final r = await http.post(
        Uri.parse(
            '${widget.baseUrl}/stays/operators/$id/room_types/$rtId/rates'),
        headers: await _authHdr(json: true),
        body: jsonEncode(body));
    setState(() => rateOut = '${r.statusCode}: ${r.body}');
    await _loadRates();
  }

  Future<void> _myListings() async {
    setState(() => lout = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => lout = 'set operator id');
      return;
    }
    int page = int.tryParse(lpageCtrl.text.trim()) ?? 0;
    if (page < 0) page = 0;
    int size = int.tryParse(lsizeCtrl.text.trim()) ?? 10;
    if (size <= 0) size = 10;
    final off = page * size;
    final params = {
      'limit': '$size',
      'offset': '$off',
      if (lqCtrl.text.trim().isNotEmpty) 'q': lqCtrl.text.trim(),
      if (lcityFilterCtrl.text.trim().isNotEmpty)
        'city': lcityFilterCtrl.text.trim(),
      if (_lTypeFilterSel.isNotEmpty) 'type': _lTypeFilterSel,
      if (_propSel != null && _propSel! > 0) 'property_id': _propSel.toString(),
      'sort_by': _lSortBy,
      'order': _lOrder,
    };
    final h = await _hdr();
    if (_token != null && _token!.isNotEmpty)
      h['Authorization'] = 'Bearer ' + _token!;
    final u = Uri.parse('${widget.baseUrl}/stays/operators/$id/listings/search')
        .replace(queryParameters: params);
    final r = await http.get(u, headers: h);
    if (r.statusCode == 200) {
      try {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        _olist = (j['items'] as List?) ?? [];
        _ototal = (j['total'] ?? 0) as int;
        final start = _ototal == 0 ? 0 : off + 1;
        final end = off + _olist.length;
        setState(() => lout = '${r.statusCode}: $start-$end of $_ototal');
      } catch (_) {
        setState(() => lout = '${r.statusCode}: ${r.body}');
      }
    } else {
      setState(() => lout = '${r.statusCode}: ${r.body}');
    }
  }

  Future<void> _myBookings() async {
    setState(() => bout = '...');
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => bout = 'set operator id');
      return;
    }
    int page = int.tryParse(bpageCtrl.text.trim()) ?? 0;
    if (page < 0) page = 0;
    int size = int.tryParse(bsizeCtrl.text.trim()) ?? 10;
    if (size <= 0) size = 10;
    final off = page * size;
    final params = {
      'limit': '$size',
      'offset': '$off',
      'sort_by': _bSortBy,
      'order': _bOrder,
      if (_bStatus.isNotEmpty) 'status': _bStatus,
      if (bFromCtrl.text.trim().isNotEmpty) 'from_iso': bFromCtrl.text.trim(),
      if (bToCtrl.text.trim().isNotEmpty) 'to_iso': bToCtrl.text.trim(),
      if (_propSel != null && _propSel! > 0) 'property_id': _propSel.toString(),
    };
    final h = await _hdr();
    if (_token != null && _token!.isNotEmpty)
      h['Authorization'] = 'Bearer ' + _token!;
    final u = Uri.parse('${widget.baseUrl}/stays/operators/$id/bookings/search')
        .replace(queryParameters: params);
    final r = await http.get(u, headers: h);
    if (r.statusCode == 200) {
      try {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        _obooks = (j['items'] as List?) ?? [];
        _btotal = (j['total'] ?? 0) as int;
        // aggregate per-status counts and total amount (Booking.com-style dashboard feel)
        int rq = 0, cf = 0, cc = 0, cp = 0, amount = 0;
        for (final it in _obooks) {
          try {
            final st = (it['status'] ?? '').toString();
            switch (st) {
              case 'requested':
                rq++;
                break;
              case 'confirmed':
                cf++;
                break;
              case 'canceled':
                cc++;
                break;
              case 'completed':
                cp++;
                break;
            }
            final a = it['amount_cents'];
            if (a is int) amount += a;
          } catch (_) {}
        }
        final start = _btotal == 0 ? 0 : off + 1;
        final end = off + _obooks.length;
        setState(() {
          _bRequested = rq;
          _bConfirmed = cf;
          _bCanceled = cc;
          _bCompleted = cp;
          _bAmountCents = amount;
          bout = '${r.statusCode}: $start-$end of $_btotal';
        });
      } catch (_) {
        setState(() => bout = '${r.statusCode}: ${r.body}');
      }
    } else {
      setState(() => bout = '${r.statusCode}: ${r.body}');
    }
  }

  Widget _buildOperatorIntro(BuildContext context) {
    final l = L10n.of(context);
    final color =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: .70);
    final text = l.isArabic
        ? '١) أدخل أو أنشئ معرف المشغل (Operator ID) ثم سجّل الدخول عبر OTP.\n'
            '٢) أضف العقارات (الفنادق / المباني) في قسم Properties.\n'
            '٣) أنشئ أنواع الغرف (Room types) والغرف (Rooms) واربطها بكل عقار.\n'
            '٤) استخدم تقويم الأسعار (Rates calendar) لتحديد الأسعار والتوافر.\n'
            '٥) أضف طاقم العمل (Staff) وحدد أدوارهم مثل frontdesk وhousekeeping وrevenue.\n'
            '٦) راقب الحجوزات والمدفوعات في قسم Bookings.'
        : '1) Enter or create the operator ID, then log in via OTP.\n'
            '2) Add properties (hotels / buildings) in the Properties section.\n'
            '3) Define room types and rooms and attach them to each property.\n'
            '4) Use the Rates calendar to control prices and availability.\n'
            '5) Add staff members and assign roles like frontdesk, housekeeping, revenue.\n'
            '6) Manage incoming bookings and statuses in the Bookings section.';
    return FormSection(
      title: l.isArabic
          ? 'دليل سريع لمشغل الفنادق'
          : 'Quick guide – Hotels & Stays operator',
      children: [
        Text(
          text,
          style: TextStyle(color: color),
        ),
      ],
    );
  }

  Future<void> _editListing(Map x) async {
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) {
      return;
    }
    final lid = (x['id'] ?? '').toString();
    if (lid.isEmpty) return;
    final titleC = TextEditingController(text: (x['title'] ?? '').toString());
    final cityC = TextEditingController(text: (x['city'] ?? '').toString());
    final priceC = TextEditingController(
        text: ((x['price_per_night_cents'] ?? 0) as int).toString());
    final addrC = TextEditingController(text: (x['address'] ?? '').toString());
    final imgs = (x['image_urls'] as List?) ?? const [];
    final imgC = TextEditingController(text: imgs.join(', '));
    final descC =
        TextEditingController(text: (x['description'] ?? '').toString());
    String typeSel = (x['property_type'] ?? '').toString();
    await showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text('Edit Listing'),
            content: SizedBox(
                width: 420,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                      controller: titleC,
                      decoration: const InputDecoration(labelText: 'Title')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: cityC,
                      decoration: const InputDecoration(labelText: 'City')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: priceC,
                      decoration:
                          const InputDecoration(labelText: 'Price (SYP)'),
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 8),
                  TextField(
                      controller: addrC,
                      decoration: const InputDecoration(
                          labelText: 'Address (optional)')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: typeSel.isEmpty ? null : typeSel,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Property type (optional)'),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('— none —')),
                      ..._propTypes
                          .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList()
                    ],
                    onChanged: (v) {
                      typeSel = v ?? '';
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: imgC,
                      decoration: const InputDecoration(
                          labelText:
                              'Image URL(s), comma-separated (optional)')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: descC,
                      decoration: const InputDecoration(
                          labelText: 'Description (optional)')),
                ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () async {
                    final title = titleC.text.trim();
                    final price = int.tryParse(priceC.text.trim()) ?? 0;
                    if (title.isEmpty || price <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Title and positive price required')));
                      return;
                    }
                    final imgs = imgC.text.trim().isEmpty
                        ? <String>[]
                        : imgC.text
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                    final body = {
                      'title': title,
                      'city':
                          cityC.text.trim().isEmpty ? null : cityC.text.trim(),
                      'price_per_night_cents': price,
                      'address':
                          addrC.text.trim().isEmpty ? null : addrC.text.trim(),
                      'property_type': typeSel.isEmpty ? null : typeSel,
                      'image_urls': imgs.isEmpty ? null : imgs,
                      'description':
                          descC.text.trim().isEmpty ? null : descC.text.trim(),
                    };
                    final h = await _hdr(json: true);
                    if (_token != null && _token!.isNotEmpty)
                      h['Authorization'] = 'Bearer ' + _token!;
                    final uri = Uri.parse(
                        '${widget.baseUrl}/stays/operators/$id/listings/$lid');
                    try {
                      final r = await http.patch(uri,
                          headers: h, body: jsonEncode(body));
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Update: ${r.statusCode}')));
                      if (r.statusCode == 200) {
                        Navigator.pop(context);
                        await _myListings();
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text('Save')),
            ],
          );
        });
  }

  Future<void> _deleteListing(Map x) async {
    final id = opIdCtrl.text.trim();
    if (id.isEmpty) return;
    final lid = (x['id'] ?? '').toString();
    if (lid.isEmpty) return;
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) {
          return AlertDialog(
              title: const Text('Delete Listing?'),
              content: Text('Delete listing #$lid? This cannot be undone.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete')),
              ]);
        });
    if (ok != true) return;
    final h = await _hdr();
    if (_token != null && _token!.isNotEmpty)
      h['Authorization'] = 'Bearer ' + _token!;
    final uri =
        Uri.parse('${widget.baseUrl}/stays/operators/$id/listings/$lid');
    final r = await http.delete(uri, headers: h);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Delete: ${r.statusCode}')));
    if (r.statusCode == 200) {
      await _myListings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Operator (Hotel)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 4),
      Text(
        '1. Create operator & log in\n'
        '2. Add properties (hotels / stays)\n'
        '3. Create listings and room types\n'
        '4. Add rooms and manage housekeeping\n'
        '5. Maintain rates & availability\n'
        '6. Manage staff and view bookings',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: .72),
        ),
      ),
      const SizedBox(height: 12),
      if (_token == null || _token!.isEmpty || _showOpControls) ...[
        Row(children: [
          Expanded(
              child: TextField(
                  controller: opNameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: opUserCtrl,
                  decoration: const InputDecoration(labelText: 'Username'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: opPhoneCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Phone (optional)'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: opCityCtrl,
                  decoration:
                      const InputDecoration(labelText: 'City (optional)'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: opIdCtrl,
                  decoration: const InputDecoration(labelText: 'Operator ID'))),
          const SizedBox(width: 8),
          Expanded(
              child: WaterButton(
                  label: 'Create / Ensure Operator', onTap: _createOperator))
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: WaterButton(label: 'Get Operator', onTap: _getOperator)),
          const SizedBox(width: 8),
          Expanded(child: WaterButton(label: 'Request OTP', onTap: _reqOtp))
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: opCodeCtrl,
                  decoration: const InputDecoration(labelText: 'OTP Code'))),
          const SizedBox(width: 8),
          Expanded(child: WaterButton(label: 'Verify', onTap: _verifyOtp)),
          const SizedBox(width: 8),
          Expanded(
              child: WaterButton(
            label: _token == null || _token!.isEmpty
                ? 'Logout (disabled)'
                : 'Logout',
            onTap: _logout,
          )),
        ]),
      ] else ...[
        Row(children: [
          Expanded(child: Text('Logged in')),
          const SizedBox(width: 8),
          SizedBox(
              width: 180,
              child: WaterButton(
                  label: _showOpControls
                      ? 'Hide operator controls'
                      : 'Show operator controls',
                  onTap: () {
                    setState(() => _showOpControls = !_showOpControls);
                  })),
        ]),
      ],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: Text(_token == null || _token!.isEmpty
                ? 'Not logged in'
                : 'Logged in')),
      ]),
      const SizedBox(height: 8),
      SelectableText(oput),
      const SizedBox(height: 8),
      Text('Role: ' +
          _opRole +
          (_propSel == null ? '' : '  ·  Property: P#' + _propSel.toString())),
      const Divider(height: 24),
      if (_opRole == 'owner' || _opRole == 'revenue') ...[
        const Text('Listings'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: ltitleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: lcityCtrl,
                  decoration: const InputDecoration(labelText: 'City'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: laddrCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Address (optional)'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: DropdownButtonFormField<int>(
                  initialValue: _lRoomTypeSel,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Room Type (optional)'),
                  items: _rtList.map((x) {
                    final id = (x['id'] ?? 0) as int;
                    final t = (x['title'] ?? '').toString();
                    return DropdownMenuItem(
                        value: id, child: Text('$t (RT#$id)'));
                  }).toList(),
                  onChanged: (v) {
                    setState(() => _lRoomTypeSel = v);
                  })),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: DropdownButtonFormField<int>(
                  initialValue: _propSelListing,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Property'),
                  items: _propList.map((p) {
                    final id = (p['id'] ?? 0) as int;
                    final n = (p['name'] ?? '').toString();
                    return DropdownMenuItem(
                        value: id, child: Text('$n (P#$id)'));
                  }).toList(),
                  onChanged: (v) {
                    setState(() => _propSelListing = v);
                  })),
        ]),
        const SizedBox(height: 8),
        SizedBox(
            width: 360,
            child: DropdownButtonFormField<String>(
              initialValue: _lTypeSel.isEmpty ? null : _lTypeSel,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Property type'),
              items: [
                const DropdownMenuItem(value: '', child: Text('— none —')),
                ..._propTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList()
              ],
              onChanged: (v) {
                setState(() => _lTypeSel = v ?? '');
              },
            )),
        const SizedBox(height: 8),
        TextField(
            controller: lpriceCtrl,
            decoration: const InputDecoration(labelText: 'Price (SYP)'),
            keyboardType: TextInputType.number),
        const SizedBox(height: 8),
        TextField(
            controller: _lImgCtrl,
            decoration: const InputDecoration(
                labelText: 'Image URL(s), comma-separated (optional)')),
        const SizedBox(height: 8),
        TextField(
            controller: _lDescCtrl,
            decoration:
                const InputDecoration(labelText: 'Description (optional)')),
        const SizedBox(height: 8),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              SizedBox(
                  width: 220,
                  child: TextField(
                      controller: lqCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Filter title'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 200,
                  child: TextField(
                      controller: lcityFilterCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Filter city'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _lTypeFilterSel.isEmpty ? null : _lTypeFilterSel,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Filter type'),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('All types')),
                      ..._propTypes
                          .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList()
                    ],
                    onChanged: (v) {
                      setState(() => _lTypeFilterSel = v ?? '');
                    },
                  )),
              const SizedBox(width: 8),
              SizedBox(
                  width: 90,
                  child: TextField(
                      controller: lpageCtrl,
                      decoration: const InputDecoration(labelText: 'page'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 90,
                  child: TextField(
                      controller: lsizeCtrl,
                      decoration: const InputDecoration(labelText: 'size'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                      initialValue: _lSortBy,
                      items: const [
                        DropdownMenuItem(
                            value: 'created_at', child: Text('Sort: Created')),
                        DropdownMenuItem(
                            value: 'price', child: Text('Sort: Price')),
                        DropdownMenuItem(
                            value: 'title', child: Text('Sort: Title')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _lSortBy = v);
                        }
                      })),
              const SizedBox(width: 8),
              SizedBox(
                  width: 130,
                  child: DropdownButtonFormField<String>(
                      initialValue: _lOrder,
                      items: const [
                        DropdownMenuItem(value: 'desc', child: Text('Desc')),
                        DropdownMenuItem(value: 'asc', child: Text('Asc')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _lOrder = v);
                        }
                      })),
            ])),
        const SizedBox(height: 8),
        Row(children: [
          if (_opRole == 'owner' || _opRole == 'revenue')
            Expanded(
                child: WaterButton(
                    label: 'Create Listing', onTap: _createListing)),
          if (_opRole == 'owner' || _opRole == 'revenue')
            const SizedBox(width: 8),
          Expanded(child: WaterButton(label: 'My Listings', onTap: _myListings))
        ]),
        const SizedBox(height: 8),
        SelectableText(lout),
        const SizedBox(height: 8),
        ..._olist.map((x) {
          final id = (x['id'] ?? '').toString();
          final t = (x['title'] ?? '').toString();
          final c = (x['city'] ?? '').toString();
          final p = ((x['price_per_night_cents'] ?? 0) as int);
          final imgs = (x['image_urls'] as List?) ?? const [];
          final img = imgs.isNotEmpty ? imgs.first.toString() : '';
          final ttype = (x['property_type'] ?? '').toString();
          return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (img.isNotEmpty)
                      ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(18)),
                          child: Image.network(img,
                              height: 120,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const SizedBox())),
                    ListTile(
                        title: Text(t),
                        subtitle: Text(
                            '${(p / 100).toStringAsFixed(2)} $_curSym  ·  $c'),
                        trailing: id.isNotEmpty ? Text('#$id') : null),
                    if (ttype.isNotEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .08),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: Colors.white24)),
                              child: Text(ttype,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white70)))),
                    if (_opRole == 'owner' || _opRole == 'revenue')
                      Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(spacing: 8, children: [
                                SizedBox(
                                    width: 100,
                                    child: WaterButton(
                                        label: 'Edit',
                                        onTap: () {
                                          _editListing(x);
                                        })),
                                SizedBox(
                                    width: 100,
                                    child: WaterButton(
                                        label: 'Delete',
                                        onTap: () {
                                          _deleteListing(x);
                                        })),
                              ]))),
                  ]));
        }).toList(),
        const Divider(height: 24),
      ],
      const Text('Properties'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: DropdownButtonFormField<int>(
                initialValue: _propSel,
                decoration: const InputDecoration(labelText: 'Select property'),
                items: _propList.map((p) {
                  final id = (p['id'] ?? 0) as int;
                  final n = (p['name'] ?? '').toString();
                  return DropdownMenuItem(value: id, child: Text('$n (P#$id)'));
                }).toList(),
                onChanged: (v) async {
                  setState(() => _propSel = v);
                  await _savePropId(v);
                })),
        const SizedBox(width: 8),
        SizedBox(
            width: 150,
            child: WaterButton(label: 'Refresh', onTap: _listProps)),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: TextField(
                controller: propNameCtrl,
                decoration:
                    const InputDecoration(labelText: 'New property name'))),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: propCityCtrl,
                decoration: const InputDecoration(labelText: 'City (opt)'))),
        const SizedBox(width: 8),
        if (_opRole == 'owner')
          SizedBox(
              width: 160,
              child: WaterButton(label: 'Create Property', onTap: _createProp))
      ]),
      const Divider(height: 24),
      if (_opRole == 'owner') ...[
        const Text('Staff'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: staffUserCtrl,
                  decoration: const InputDecoration(labelText: 'Username'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: staffPhoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone (opt)'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: DropdownButtonFormField<String>(
                  initialValue: _staffRoleSel,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'owner', child: Text('owner')),
                    DropdownMenuItem(
                        value: 'frontdesk', child: Text('frontdesk')),
                    DropdownMenuItem(
                        value: 'housekeeping', child: Text('housekeeping')),
                    DropdownMenuItem(value: 'revenue', child: Text('revenue')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _staffRoleSel = v);
                  })),
          const SizedBox(width: 8),
          Expanded(
              child: DropdownButtonFormField<int>(
                  initialValue: _staffPropSel,
                  decoration:
                      const InputDecoration(labelText: 'Property (opt)'),
                  items: _propList.map((p) {
                    final id = (p['id'] ?? 0) as int;
                    final n = (p['name'] ?? '').toString();
                    return DropdownMenuItem(
                        value: id, child: Text('$n (P#$id)'));
                  }).toList(),
                  onChanged: (v) {
                    setState(() => _staffPropSel = v);
                  })),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: WaterButton(label: 'Create Staff', onTap: _createStaff)),
          const SizedBox(width: 8),
          Expanded(child: WaterButton(label: 'List Staff', onTap: _listStaff))
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: staffSearchCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Search username'))),
          const SizedBox(width: 8),
          SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                  initialValue: _staffRoleFilter.isEmpty ? null : _staffRoleFilter,
                  decoration: const InputDecoration(labelText: 'Role filter'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All')),
                    DropdownMenuItem(value: 'owner', child: Text('owner')),
                    DropdownMenuItem(
                        value: 'frontdesk', child: Text('frontdesk')),
                    DropdownMenuItem(
                        value: 'housekeeping', child: Text('housekeeping')),
                    DropdownMenuItem(value: 'revenue', child: Text('revenue')),
                  ],
                  onChanged: (v) {
                    setState(() => _staffRoleFilter = v ?? '');
                  })),
          const SizedBox(width: 8),
          SizedBox(
              width: 180,
              child: SwitchListTile(
                  value: _staffOnlyActive,
                  onChanged: (v) {
                    setState(() => _staffOnlyActive = v);
                  },
                  title: const Text('Only active'))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: WaterButton(label: 'Apply Filters', onTap: _listStaff)),
          const SizedBox(width: 8),
          Expanded(
              child: WaterButton(
                  label: 'Bulk Deactivate (selected)',
                  onTap: _bulkDeactivateStaff))
        ]),
        const SizedBox(height: 8),
        SelectableText(staffOut),
        const SizedBox(height: 8),
        ..._staffList.map((s) {
          final sid = (s['id'] ?? 0) as int;
          final u = (s['username'] ?? '').toString();
          final r = (s['role'] ?? '').toString();
          final pid = s['property_id'] as int?;
          final act = (s['active'] ?? true) == true;
          final curRole = _staffRoleEdit[sid] ?? r;
          final curPid = _staffPropEdit[sid] ?? pid;
          final selected = _staffSel.contains(sid);
          return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(u,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600))),
                          const SizedBox(width: 8),
                          Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .06),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white24)),
                              child: Text(act ? 'active' : 'inactive'))
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          SizedBox(
                              width: 40,
                              child: Checkbox(
                                  value: selected,
                                  onChanged: (v) {
                                    setState(() => v == true
                                        ? _staffSel.add(sid)
                                        : _staffSel.remove(sid));
                                  })),
                          const SizedBox(width: 8),
                          Expanded(
                              child: DropdownButtonFormField<String>(
                                  initialValue: curRole,
                                  decoration:
                                      const InputDecoration(labelText: 'Role'),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'owner', child: Text('owner')),
                                    DropdownMenuItem(
                                        value: 'frontdesk',
                                        child: Text('frontdesk')),
                                    DropdownMenuItem(
                                        value: 'housekeeping',
                                        child: Text('housekeeping')),
                                    DropdownMenuItem(
                                        value: 'revenue',
                                        child: Text('revenue')),
                                  ],
                                  onChanged: (v) {
                                    if (v != null)
                                      setState(() => _staffRoleEdit[sid] = v);
                                  })),
                          const SizedBox(width: 8),
                          Expanded(
                              child: DropdownButtonFormField<int>(
                                  initialValue: curPid,
                                  decoration: const InputDecoration(
                                      labelText: 'Property (opt)'),
                                  items: [
                                    const DropdownMenuItem(
                                        value: null, child: Text('— none —')),
                                    ..._propList.map((p) {
                                      final id = (p['id'] ?? 0) as int;
                                      final n = (p['name'] ?? '').toString();
                                      return DropdownMenuItem(
                                          value: id, child: Text('$n (P#$id)'));
                                    }).toList()
                                  ],
                                  onChanged: (v) {
                                    setState(() => _staffPropEdit[sid] = v);
                                  })),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: WaterButton(
                                  label: 'Save',
                                  onTap: () {
                                    _saveStaff(s);
                                  })),
                          const SizedBox(width: 8),
                          Expanded(
                              child: WaterButton(
                                  label: act ? 'Deactivate' : 'Activate',
                                  onTap: () {
                                    _toggleStaffActive(s);
                                  }))
                        ]),
                      ])));
        }).toList(),
        const Divider(height: 24),
      ],
      const Text('Room Types'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: TextField(
                controller: rtTitleCtrl,
                decoration: const InputDecoration(labelText: 'Title'))),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: rtDescCtrl,
                decoration:
                    const InputDecoration(labelText: 'Description (opt)'))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: TextField(
                controller: rtPriceCtrl,
                decoration:
                    const InputDecoration(labelText: 'Base price (SYP)'),
                keyboardType: TextInputType.number)),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: rtGuestsCtrl,
                decoration: const InputDecoration(labelText: 'Max guests'),
                keyboardType: TextInputType.number))
      ]),
      const SizedBox(height: 8),
      Row(children: [
        if (_opRole == 'owner' || _opRole == 'revenue')
          Expanded(
              child: WaterButton(
                  label: 'Create Room Type', onTap: _createRoomType)),
        if (_opRole == 'owner' || _opRole == 'revenue')
          const SizedBox(width: 8),
        Expanded(
            child: WaterButton(label: 'List Room Types', onTap: _listRoomTypes))
      ]),
      const SizedBox(height: 8),
      SelectableText(rtOut),
      const SizedBox(height: 8),
      ..._rtList.map((x) {
        final id = (x['id'] ?? '').toString();
        final t = (x['title'] ?? '').toString();
        final p = (x['base_price_cents'] ?? 0) as int;
        final g = (x['max_guests'] ?? 0) as int;
        return Card(
            child: ListTile(
                title: Text(t),
                subtitle: Text(
                    '${(p / 100).toStringAsFixed(2)} $_curSym · max $g pax · RT#$id')));
      }).toList(),
      const Divider(height: 24),
      const Text('Rooms'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: TextField(
                controller: rmCodeCtrl,
                decoration: const InputDecoration(labelText: 'Room code'))),
        const SizedBox(width: 8),
        Expanded(
            child: TextField(
                controller: rmFloorCtrl,
                decoration: const InputDecoration(labelText: 'Floor (opt)'))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: DropdownButtonFormField<int>(
                initialValue: rmTypeSel,
                decoration: const InputDecoration(labelText: 'Room type'),
                items: _rtList.map((x) {
                  final id = (x['id'] ?? 0) as int;
                  final t = (x['title'] ?? '').toString();
                  return DropdownMenuItem(
                      value: id, child: Text('$t (RT#$id)'));
                }).toList(),
                onChanged: (v) {
                  setState(() => rmTypeSel = v);
                })),
        const SizedBox(width: 8),
        Expanded(
            child: DropdownButtonFormField<String>(
                initialValue: rmStatusSel,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'clean', child: Text('clean')),
                  DropdownMenuItem(value: 'dirty', child: Text('dirty')),
                  DropdownMenuItem(value: 'oos', child: Text('out of service'))
                ],
                onChanged: (v) {
                  if (v != null) setState(() => rmStatusSel = v);
                })),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        if (_opRole == 'owner' || _opRole == 'revenue')
          Expanded(
              child: WaterButton(label: 'Create Room', onTap: _createRoom)),
        if (_opRole == 'owner' || _opRole == 'revenue')
          const SizedBox(width: 8),
        Expanded(child: WaterButton(label: 'List Rooms', onTap: _listRooms))
      ]),
      const SizedBox(height: 8),
      SelectableText(rmOut),
      const SizedBox(height: 8),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: DropdownButtonFormField<String>(
                initialValue: _roomFilterSel.isEmpty ? '' : _roomFilterSel,
                decoration: const InputDecoration(labelText: 'Filter status'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All')),
                  DropdownMenuItem(value: 'clean', child: Text('clean')),
                  DropdownMenuItem(value: 'dirty', child: Text('dirty')),
                  DropdownMenuItem(value: 'oos', child: Text('out of service')),
                ],
                onChanged: (v) {
                  setState(() => _roomFilterSel = v ?? '');
                })),
        const SizedBox(width: 8),
        Expanded(
            child: WaterButton(
                label: 'Select all (filter)',
                onTap: () {
                  setState(() {
                    _roomSel.clear();
                    for (final r in _roomList) {
                      final st = (r['status'] ?? '').toString();
                      if (_roomFilterSel.isEmpty || st == _roomFilterSel) {
                        final id = (r['id'] ?? 0) as int;
                        _roomSel.add(id);
                      }
                    }
                  });
                })),
        const SizedBox(width: 8),
        Expanded(
            child: WaterButton(
                label: 'Clear selection',
                onTap: () {
                  setState(() => _roomSel.clear());
                })),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: DropdownButtonFormField<String>(
                initialValue: _roomBulkStatusSel,
                decoration:
                    const InputDecoration(labelText: 'Set selected status'),
                items: const [
                  DropdownMenuItem(value: 'clean', child: Text('clean')),
                  DropdownMenuItem(value: 'dirty', child: Text('dirty')),
                  DropdownMenuItem(value: 'oos', child: Text('out of service')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _roomBulkStatusSel = v);
                })),
        const SizedBox(width: 8),
        Expanded(
            child: WaterButton(
                label: 'Apply',
                onTap: () async {
                  if (!(_opRole == 'owner' || _opRole == 'housekeeping')) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No access')));
                    return;
                  }
                  final id = opIdCtrl.text.trim();
                  if (id.isEmpty) return;
                  final sel = [..._roomSel];
                  int ok = 0;
                  for (final rid in sel) {
                    final r = await http.patch(
                        Uri.parse(
                            '${widget.baseUrl}/stays/operators/$id/rooms/$rid'),
                        headers: await _authHdr(json: true),
                        body: jsonEncode({'status': _roomBulkStatusSel}));
                    if (r.statusCode == 200) ok++;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Updated $ok/${sel.length} rooms')));
                  await _listRooms();
                }))
      ]),
      const SizedBox(height: 8),
      ..._roomList.where((r) {
        final st = (r['status'] ?? '').toString();
        return _roomFilterSel.isEmpty || st == _roomFilterSel;
      }).map((x) {
        final id = (x['id'] ?? 0) as int;
        final code = (x['code'] ?? '').toString();
        final floor = (x['floor'] ?? '').toString();
        final st = (x['status'] ?? '').toString();
        final rt = (x['room_type_id'] ?? '').toString();
        final sel = _roomSel.contains(id);
        return Card(
            child: CheckboxListTile(
                value: sel,
                onChanged: (v) {
                  setState(
                      () => v == true ? _roomSel.add(id) : _roomSel.remove(id));
                },
                title: Text('Room $code (ID $id)'),
                subtitle: Text(
                    'Type $rt · Floor: ${floor.isEmpty ? '—' : floor} · $st')));
      }).toList(),
      const SizedBox(height: 12),
      if (_roomList.isNotEmpty)
        Builder(builder: (ctx) {
          final l = L10n.of(ctx);
          final Map<String, Map<String, List<Map<String, dynamic>>>> byFloor =
              {};
          for (final r in _roomList) {
            if (r is! Map) continue;
            final m = Map<String, dynamic>.from(r as Map);
            final floor = (m['floor'] ?? '').toString().trim();
            final fKey = floor.isEmpty ? '—' : floor;
            final status = (m['status'] ?? '').toString();
            final bucket =
                (status == 'clean' || status == 'dirty' || status == 'oos')
                    ? status
                    : 'other';
            final fm = byFloor.putIfAbsent(fKey, () {
              return {
                'clean': <Map<String, dynamic>>[],
                'dirty': <Map<String, dynamic>>[],
                'oos': <Map<String, dynamic>>[],
                'other': <Map<String, dynamic>>[],
              };
            });
            (fm[bucket] as List<Map<String, dynamic>>).add(m);
          }
          if (byFloor.isEmpty) return const SizedBox.shrink();
          final floors = byFloor.keys.toList()
            ..sort((a, b) {
              if (a == '—') return 1;
              if (b == '—') return -1;
              return a.compareTo(b);
            });
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  l.isArabic
                      ? 'لوحة التدبير الفندقي حسب الطابق'
                      : 'Housekeeping board by floor',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: floors.map((fKey) {
                    final data = byFloor[fKey]!;
                    final clean = data['clean']!.length;
                    final dirty = data['dirty']!.length;
                    final oos = data['oos']!.length;
                    final other = data['other']!.length;
                    final summary =
                        'Clean $clean · Dirty $dirty · OOS $oos · Other $other';
                    final title = fKey == '—'
                        ? (l.isArabic ? 'بدون طابق' : 'No floor')
                        : (l.isArabic ? 'الطابق $fKey' : 'Floor $fKey');
                    Widget _buildRow(String label, List<Map<String, dynamic>> xs,
                        Color color) {
                      if (xs.isEmpty) {
                        return Text('$label: 0',
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: .65)));
                      }
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$label: ${xs.length}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: color.withValues(alpha: .9))),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: xs.map((m) {
                                final code =
                                    (m['code'] ?? '').toString().trim();
                                final id = (m['id'] ?? 0).toString();
                                final label = code.isEmpty ? 'R$id' : code;
                                return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: .12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(label,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: color.withValues(
                                                alpha: .95))));
                              }).toList(),
                            )
                          ]);
                    }

                    return SizedBox(
                        width: 260,
                        child: Card(
                            elevation: 0.5,
                            child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(title,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(summary,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                      const SizedBox(height: 4),
                                      _buildRow(
                                          l.isArabic ? 'نظيف' : 'Clean',
                                          data['clean']!,
                                          Colors.green),
                                      const SizedBox(height: 4),
                                      _buildRow(
                                          l.isArabic ? 'متسخ' : 'Dirty',
                                          data['dirty']!,
                                          Colors.orange),
                                      const SizedBox(height: 4),
                                      _buildRow(
                                          l.isArabic
                                              ? 'خارج الخدمة'
                                              : 'Out of service',
                                          data['oos']!,
                                          Colors.red),
                                      if (other > 0) ...[
                                        const SizedBox(height: 4),
                                        _buildRow(
                                            l.isArabic ? 'أخرى' : 'Other',
                                            data['other']!,
                                            Colors.grey),
                                      ]
                                    ]))));
                  }).toList())
            ],
          );
        }),
      const Divider(height: 24),
      if (_opRole == 'owner' || _opRole == 'revenue') ...[
        const Text('Rates Calendar'), const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: DropdownButtonFormField<int>(
                  initialValue: rateRtSel,
                  decoration: const InputDecoration(labelText: 'Room type'),
                  items: _rtList.map((x) {
                    final id = (x['id'] ?? 0) as int;
                    final t = (x['title'] ?? '').toString();
                    return DropdownMenuItem(
                        value: id, child: Text('$t (RT#$id)'));
                  }).toList(),
                  onChanged: (v) {
                    setState(() => rateRtSel = v);
                    _saveRatesPrefs();
                  })),
        const SizedBox(width: 8),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WaterButton(
                label:
                    'From: ${'${rateFrom.year}-${rateFrom.month}-${rateFrom.day}'}',
                onTap: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: rateFrom,
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 1)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)));
                  if (d != null) {
                    setState(() => rateFrom = d);
                  }
                }),
            const SizedBox(height: 4),
            Row(children: [
              SizedBox(
                  width: 120,
                  child: WaterButton(
                      label: 'Today',
                      onTap: () {
                        final today = DateTime.now();
                        setState(() {
                          rateFrom = DateTime(
                              today.year, today.month, today.day);
                          rateDays = 30;
                        });
                        _saveRatesPrefs();
                        _loadRates();
                      })),
              const SizedBox(width: 8),
              SizedBox(
                  width: 150,
                  child: WaterButton(
                      label: 'Next 7 days',
                      onTap: () {
                        final today = DateTime.now();
                        setState(() {
                          rateFrom = DateTime(
                              today.year, today.month, today.day);
                          rateDays = 7;
                        });
                        _saveRatesPrefs();
                        _loadRates();
                      })),
            ])
          ],
        )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: WaterButton(label: 'Load Rates', onTap: _loadRates)),
          const SizedBox(width: 8),
          Expanded(child: WaterButton(label: 'Edit Day', onTap: _editRate))
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: rateFillAllotCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Default allotment'),
                  keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(
              child: WaterButton(label: 'Fill defaults', onTap: _fillDefaults))
        ]),
        const SizedBox(height: 8),
        // Bulk tools
        Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bulk apply (loaded range)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: bulkPriceCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Price (cents, optional)'),
                                keyboardType: TextInputType.number)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: bulkAllotCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Allotment (optional)'),
                                keyboardType: TextInputType.number)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: bulkMinLosCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Min LOS (optional)'),
                                keyboardType: TextInputType.number)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: bulkMaxLosCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Max LOS (optional)'),
                                keyboardType: TextInputType.number)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: DropdownButtonFormField<String>(
                                initialValue: _bulkClosedSel,
                                decoration:
                                    const InputDecoration(labelText: 'Closed'),
                                items: const [
                                  DropdownMenuItem(
                                      value: '', child: Text('keep')),
                                  DropdownMenuItem(
                                      value: 'true', child: Text('true')),
                                  DropdownMenuItem(
                                      value: 'false', child: Text('false'))
                                ],
                                onChanged: (v) {
                                  setState(() => _bulkClosedSel = v ?? '');
                                })),
                        const SizedBox(width: 8),
                        Expanded(
                            child: DropdownButtonFormField<String>(
                                initialValue: _bulkCtaSel,
                                decoration:
                                    const InputDecoration(labelText: 'CTA'),
                                items: const [
                                  DropdownMenuItem(
                                      value: '', child: Text('keep')),
                                  DropdownMenuItem(
                                      value: 'true', child: Text('true')),
                                  DropdownMenuItem(
                                      value: 'false', child: Text('false'))
                                ],
                                onChanged: (v) {
                                  setState(() => _bulkCtaSel = v ?? '');
                                })),
                        const SizedBox(width: 8),
                        Expanded(
                            child: DropdownButtonFormField<String>(
                                initialValue: _bulkCtdSel,
                                decoration:
                                    const InputDecoration(labelText: 'CTD'),
                                items: const [
                                  DropdownMenuItem(
                                      value: '', child: Text('keep')),
                                  DropdownMenuItem(
                                      value: 'true', child: Text('true')),
                                  DropdownMenuItem(
                                      value: 'false', child: Text('false'))
                                ],
                                onChanged: (v) {
                                  setState(() => _bulkCtdSel = v ?? '');
                                })),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: CheckboxListTile(
                                value: _bulkOnlyMissing,
                                onChanged: (v) {
                                  setState(() => _bulkOnlyMissing = v ?? true);
                                },
                                title: const Text(
                                    'Only fill missing (global toggle)'))),
                      ]),
                      Row(children: [
                        Expanded(
                            child: CheckboxListTile(
                                value: _onlyMissingPrice,
                                onChanged: (v) {
                                  setState(() => _onlyMissingPrice = v ?? true);
                                },
                                title: const Text('Missing only: Price'))),
                        Expanded(
                            child: CheckboxListTile(
                                value: _onlyMissingAllot,
                                onChanged: (v) {
                                  setState(() => _onlyMissingAllot = v ?? true);
                                },
                                title: const Text('Missing only: Allot'))),
                      ]),
                      Row(children: [
                        Expanded(
                            child: CheckboxListTile(
                                value: _onlyMissingMinLos,
                                onChanged: (v) {
                                  setState(
                                      () => _onlyMissingMinLos = v ?? true);
                                },
                                title: const Text('Missing only: Min LOS'))),
                        Expanded(
                            child: CheckboxListTile(
                                value: _onlyMissingMaxLos,
                                onChanged: (v) {
                                  setState(
                                      () => _onlyMissingMaxLos = v ?? true);
                                },
                                title: const Text('Missing only: Max LOS'))),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: WaterButton(
                                label: 'Apply to current range',
                                onTap: _applyBulkRange)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: WaterButton(
                                label: 'Undo last bulk', onTap: _undoLastBulk)),
                      ]),
                    ]))),
        // Promotions (simple percentage discount on loaded range)
        Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Promotions (discount)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: promoPercentCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Discount % (e.g. 10)'),
                                keyboardType: TextInputType.number)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: WaterButton(
                                label: 'Apply promotion',
                                onTap: _applyPromotion)),
                      ]),
                      const SizedBox(height: 4),
                      const Text(
                          'Uses current loaded range and room type; only days with an existing price are discounted.'),
                    ]))),
        // Copy range → target start
        Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Copy range → target start',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: copyFromCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Source start (YYYY-MM-DD)'))),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 120,
                            child: TextField(
                                controller: copyDaysCtrl,
                                decoration:
                                    const InputDecoration(labelText: 'Days'),
                                keyboardType: TextInputType.number)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                                controller: copyTargetCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Target start (YYYY-MM-DD)'))),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: DropdownButtonFormField<String>(
                                initialValue: _copyPattern,
                                decoration:
                                    const InputDecoration(labelText: 'Pattern'),
                                items: const [
                                  DropdownMenuItem(
                                      value: 'all', child: Text('All days')),
                                  DropdownMenuItem(
                                      value: 'weekends',
                                      child: Text('Weekends only')),
                                  DropdownMenuItem(
                                      value: 'weekdays',
                                      child: Text('Weekdays only')),
                                  DropdownMenuItem(
                                      value: 'every_n',
                                      child: Text('Every Nth day')),
                                ],
                                onChanged: (v) {
                                  if (v != null)
                                    setState(() => _copyPattern = v);
                                })),
                        const SizedBox(width: 8),
                        if (_copyPattern == 'every_n')
                          SizedBox(
                              width: 140,
                              child: TextField(
                                  controller: copyEveryNCtrl,
                                  decoration:
                                      const InputDecoration(labelText: 'N'),
                                  keyboardType: TextInputType.number)),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 12, children: [
                        FilterChip(
                            label: const Text('Price'),
                            selected: _copyPrice,
                            onSelected: (v) {
                              setState(() => _copyPrice = v);
                            }),
                        FilterChip(
                            label: const Text('Allot'),
                            selected: _copyAllot,
                            onSelected: (v) {
                              setState(() => _copyAllot = v);
                            }),
                        FilterChip(
                            label: const Text('Min LOS'),
                            selected: _copyMinLos,
                            onSelected: (v) {
                              setState(() => _copyMinLos = v);
                            }),
                        FilterChip(
                            label: const Text('Max LOS'),
                            selected: _copyMaxLos,
                            onSelected: (v) {
                              setState(() => _copyMaxLos = v);
                            }),
                        FilterChip(
                            label: const Text('Closed'),
                            selected: _copyClosed,
                            onSelected: (v) {
                              setState(() => _copyClosed = v);
                            }),
                        FilterChip(
                            label: const Text('CTA'),
                            selected: _copyCta,
                            onSelected: (v) {
                              setState(() => _copyCta = v);
                            }),
                        FilterChip(
                            label: const Text('CTD'),
                            selected: _copyCtd,
                            onSelected: (v) {
                              setState(() => _copyCtd = v);
                            }),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: WaterButton(
                                label: 'Copy & apply', onTap: _copyRangeApply)),
                      ]),
                    ]))),
        const SizedBox(height: 8), SelectableText(rateOut),
        const SizedBox(height: 8),
        // Sticky header + internal scrollable grid
        SizedBox(
          height: 480,
          child: Column(children: [
            // Sticky header row inside this panel
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                SwitchListTile(
                    value: _paintMode,
                    onChanged: (v) {
                      setState(() => _paintMode = v);
                      _saveRatesPrefs();
                      if (v) _ratesFocus.requestFocus();
                    },
                    title: const Text('Paint')),
                const SizedBox(width: 8),
                SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String>(
                        initialValue: _paintField,
                        items: const [
                          DropdownMenuItem(
                              value: 'closed', child: Text('Closed')),
                          DropdownMenuItem(value: 'cta', child: Text('CTA')),
                          DropdownMenuItem(value: 'ctd', child: Text('CTD')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _paintField = v);
                        })),
                const SizedBox(width: 8),
                SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<bool>(
                        initialValue: _paintValue,
                        items: const [
                          DropdownMenuItem(
                              value: true, child: Text('Value: true')),
                          DropdownMenuItem(
                              value: false, child: Text('Value: false'))
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _paintValue = v);
                        })),
                const SizedBox(width: 8),
                SizedBox(
                    width: 170,
                    child: WaterButton(
                        label: 'Apply (${_paintSel.length})',
                        onTap: _applyPaint)),
                const SizedBox(width: 8),
                SizedBox(
                    width: 90,
                    child: WaterButton(
                        label: 'Focus',
                        onTap: () {
                          _ratesFocus.requestFocus();
                        })),
                const SizedBox(width: 12),
                SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<int>(
                        initialValue: rateDays,
                        decoration: const InputDecoration(labelText: 'Range'),
                        items: const [
                          DropdownMenuItem(value: 7, child: Text('7 days')),
                          DropdownMenuItem(value: 14, child: Text('14 days')),
                          DropdownMenuItem(value: 30, child: Text('30 days')),
                          DropdownMenuItem(value: 60, child: Text('60 days')),
                          DropdownMenuItem(value: 90, child: Text('90 days')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => rateDays = v);
                            _saveRatesPrefs();
                            _loadRates();
                          }
                        })),
                const SizedBox(width: 8),
                SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<int>(
                        initialValue: _appendChunk,
                        decoration:
                            const InputDecoration(labelText: 'Append size'),
                        items: const [
                          DropdownMenuItem(value: 7, child: Text('7')),
                          DropdownMenuItem(value: 14, child: Text('14')),
                          DropdownMenuItem(value: 30, child: Text('30')),
                          DropdownMenuItem(value: 60, child: Text('60')),
                          DropdownMenuItem(value: 90, child: Text('90')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _appendChunk = v);
                            _saveRatesPrefs();
                          }
                        })),
                const SizedBox(width: 8),
                SizedBox(
                    width: 190,
                    child: TextField(
                        controller: jumpCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Jump (YYYY-MM-DD)'))),
                const SizedBox(width: 8),
                SizedBox(
                    width: 120,
                    child: WaterButton(
                        label: 'Jump',
                        onTap: () {
                          final s = jumpCtrl.text.trim();
                          try {
                            final d = DateTime.parse(s);
                            setState(() => rateFrom = d);
                            _saveRatesPrefs();
                            _loadRates();
                          } catch (_) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invalid date')));
                          }
                        })),
                const SizedBox(width: 8),
                SizedBox(
                    width: 150,
                    child: WaterButton(
                        label: 'Prev 7d',
                        onTap: () {
                          setState(() => rateFrom =
                              rateFrom.subtract(const Duration(days: 7)));
                          _saveRatesPrefs();
                          _loadRates();
                        })),
                const SizedBox(width: 8),
                SizedBox(
                    width: 150,
                    child: WaterButton(
                        label: 'Next 7d',
                        onTap: () {
                          setState(() =>
                              rateFrom = rateFrom.add(const Duration(days: 7)));
                          _saveRatesPrefs();
                          _loadRates();
                        })),
                const SizedBox(width: 8),
                SizedBox(
                    width: 170,
                    child: WaterButton(
                        label: 'Append prev ${_appendChunk}d',
                        onTap: _appendPrev)),
                const SizedBox(width: 8),
                SizedBox(
                    width: 170,
                    child: WaterButton(
                        label: 'Append next ${_appendChunk}d',
                        onTap: _appendNext)),
              ]),
            ),
            const SizedBox(height: 8),
            // Internal scrollable grid with virtualization
            Expanded(
              child: LayoutBuilder(builder: (ctx, cons) {
                final tileW = 160.0; // target tile width
                int cols = (cons.maxWidth / tileW).floor();
                if (cols < 1) cols = 1;
                if (cols > 12) cols = 12;
                return NotificationListener<ScrollNotification>(
                  onNotification: (sn) {
                    try {
                      if (sn.metrics.pixels >
                              sn.metrics.maxScrollExtent - 200 &&
                          !_appendBusy) {
                        _appendNext();
                      }
                    } catch (_) {}
                    return false;
                  },
                  child: KeyboardListener(
                    focusNode: _ratesFocus,
                    onKeyEvent: _onRatesKey,
                    child: Listener(
                      onPointerDown: (_) {
                        _isPainting = true;
                      },
                      onPointerUp: (_) {
                        _isPainting = false;
                      },
                      child: GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            mainAxisExtent: 150),
                        itemCount: rateDays,
                        itemBuilder: (ctx, i) {
                          final d = rateFrom.add(Duration(days: i));
                          final key =
                              '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                          final r = _rateMap[key];
                          final pc = r == null ? null : r['price_cents'];
                          final al = r == null ? null : r['allotment'];
                          final cl = r == null ? false : (r['closed'] == true);
                          final minL =
                              r == null ? null : (r['min_los'] as int?);
                          final maxL =
                              r == null ? null : (r['max_los'] as int?);
                          final cta = r == null ? null : (r['cta'] == true);
                          final ctd = r == null ? null : (r['ctd'] == true);
                          final hasBadges = (cl == true) ||
                              (cta == true) ||
                              (ctd == true) ||
                              (minL != null) ||
                              (maxL != null);
                          final isSel = _paintSel.contains(key);
                          final isCur = _cursorDate == key;
                          Color? bg;
                          if (cl == true) {
                            bg = Colors.white.withValues(alpha: .06);
                          } else if (cta == true || ctd == true) {
                            bg = Colors.white.withValues(alpha: .06);
                          } else if (minL != null || maxL != null) {
                            bg = Colors.white.withValues(alpha: .06);
                          }
                          final tip = 'Date: ' +
                              key +
                              '\nPrice: ' +
                              ((pc == null)
                                  ? '—'
                                  : '${((pc as int) / 100).toStringAsFixed(2)} $_curSym') +
                              '\nAllot: ' +
                              ((al == null) ? '—' : (al).toString()) +
                              '\nClosed: ' +
                              ((cl == true) ? 'yes' : 'no') +
                              '\nCTA: ' +
                              ((cta == true) ? 'yes' : 'no') +
                              '\nCTD: ' +
                              ((ctd == true) ? 'yes' : 'no') +
                              '\nMin LOS: ' +
                              ((minL == null) ? '—' : (minL).toString()) +
                              '\nMax LOS: ' +
                              ((maxL == null) ? '—' : (maxL).toString());
                          return MouseRegion(
                            onEnter: (_) {
                              if (_paintMode && _isPainting) {
                                setState(() => _paintSel.add(key));
                              }
                            },
                            child: GestureDetector(
                              onTap: () {
                                if (_paintMode) {
                                  setState(() => _paintSel.contains(key)
                                      ? _paintSel.remove(key)
                                      : _paintSel.add(key));
                                } else {
                                  _editRateOn(key);
                                }
                                setState(() => _cursorDate = key);
                              },
                              onLongPress: () {
                                showDialog(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                            title: const Text('Day details'),
                                            content: Text(
                                                tip.replaceAll('\\n', '\n')),
                                            actions: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(context),
                                                  child: const Text('Close'))
                                            ]));
                              },
                              child: Tooltip(
                                message: tip,
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: isCur
                                              ? Tokens.focus
                                              : (isSel
                                                  ? Tokens.focus
                                                  : Colors.white24))),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(key,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 4),
                                        Text('Price: ' +
                                            ((pc == null)
                                                ? '—'
                                                : '${((pc as int) / 100).toStringAsFixed(2)} $_curSym')),
                                        const SizedBox(height: 2),
                                        Text('Allot: ' +
                                            ((al == null)
                                                ? '—'
                                                : (al).toString())),
                                        const SizedBox(height: 4),
                                        if (hasBadges)
                                          Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                if (cl == true)
                                                  _rateBadge(
                                                      'CLOSED', Tokens.focus),
                                                if (cta == true)
                                                  _rateBadge(
                                                      'CTA', Tokens.focus),
                                                if (ctd == true)
                                                  _rateBadge(
                                                      'CTD', Tokens.focus),
                                                if (minL != null)
                                                  _rateBadge('LOS≥$minL',
                                                      Tokens.focus),
                                                if (maxL != null)
                                                  _rateBadge('LOS≤$maxL',
                                                      Tokens.focus),
                                              ]),
                                      ]),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              }),
            ),
          ]),
        ),
      ],
      if (_opRole == 'owner' || _opRole == 'frontdesk') ...[
        const Text('Bookings'),
        const SizedBox(height: 8),
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<String>(
                      initialValue: _bSortBy,
                      items: const [
                        DropdownMenuItem(
                            value: 'created_at', child: Text('Sort: Created')),
                        DropdownMenuItem(
                            value: 'from', child: Text('Sort: From')),
                        DropdownMenuItem(value: 'to', child: Text('Sort: To')),
                        DropdownMenuItem(
                            value: 'amount', child: Text('Sort: Amount')),
                        DropdownMenuItem(
                            value: 'status', child: Text('Sort: Status')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _bSortBy = v);
                        }
                      })),
              const SizedBox(width: 8),
              SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String>(
                      initialValue: _bOrder,
                      items: const [
                        DropdownMenuItem(value: 'desc', child: Text('Desc')),
                        DropdownMenuItem(value: 'asc', child: Text('Asc')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _bOrder = v);
                        }
                      })),
              const SizedBox(width: 8),
              SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                      initialValue: _bStatus.isEmpty ? '' : _bStatus,
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Status: any')),
                        DropdownMenuItem(
                            value: 'requested', child: Text('requested')),
                        DropdownMenuItem(
                            value: 'confirmed', child: Text('confirmed')),
                        DropdownMenuItem(
                            value: 'canceled', child: Text('canceled')),
                        DropdownMenuItem(
                            value: 'completed', child: Text('completed')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _bStatus = v);
                        }
                      })),
              const SizedBox(width: 8),
              SizedBox(
                  width: 200,
                  child: TextField(
                      controller: bFromCtrl,
                      decoration: const InputDecoration(
                          labelText: 'from (YYYY-MM-DD)'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 200,
                  child: TextField(
                      controller: bToCtrl,
                      decoration:
                          const InputDecoration(labelText: 'to (YYYY-MM-DD)'))),
            ])),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SizedBox(
            width: 80,
            child: TextField(
                controller: bpageCtrl,
                decoration: const InputDecoration(labelText: 'page'))),
        SizedBox(
            width: 80,
            child: TextField(
                controller: bsizeCtrl,
                decoration: const InputDecoration(labelText: 'size'))),
        SizedBox(
            width: 130,
            child: WaterButton(label: 'My Bookings', onTap: _myBookings)),
        SizedBox(
            width: 140,
            child: WaterButton(
                label: 'Today arrivals',
                onTap: () {
                  final today = DateTime.now();
                  final ds =
                      '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
                  setState(() {
                    bFromCtrl.text = ds;
                    bToCtrl.text = ds;
                    _bStatus = 'confirmed';
                    bpageCtrl.text = '0';
                  });
                  _myBookings();
                })),
        SizedBox(
            width: 170,
            child: WaterButton(
                label: 'Next 7 days',
                onTap: () {
                  final today = DateTime.now();
                  final from =
                      '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
                  final after = today.add(const Duration(days: 7));
                  final to =
                      '${after.year.toString().padLeft(4, '0')}-${after.month.toString().padLeft(2, '0')}-${after.day.toString().padLeft(2, '0')}';
                  setState(() {
                    bFromCtrl.text = from;
                    bToCtrl.text = to;
                    _bStatus = '';
                    bpageCtrl.text = '0';
                  });
                  _myBookings();
                })),
      ]),
      const SizedBox(height: 8),
      if (_btotal > 0)
        Builder(builder: (ctx) {
          final l = L10n.of(ctx);
          final total = _btotal;
          final baseEn =
              'Bookings: $total · requested: $_bRequested · confirmed: $_bConfirmed · canceled: $_bCanceled · completed: $_bCompleted · total: ${(_bAmountCents / 100).toStringAsFixed(2)} $_curSym';
          final baseAr =
              'الحجوزات: $total · قيد الطلب: $_bRequested · مؤكدة: $_bConfirmed · ملغاة: $_bCanceled · مكتملة: $_bCompleted · المجموع: ${(_bAmountCents / 100).toStringAsFixed(2)} $_curSym';
          final txt = l.isArabic ? baseAr : baseEn;
          final today = DateTime.now();
          final ds =
              '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
          final arrivals = _obooks.where((x) {
            final f = (x['from_iso'] ?? '').toString();
            return f.startsWith(ds);
          }).toList();
          final deps = _obooks.where((x) {
            final t = (x['to_iso'] ?? '').toString();
            return t.startsWith(ds);
          }).toList();
          final banner = Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: StatusBanner.info(txt, dense: true),
          );
          if (arrivals.isEmpty && deps.isEmpty) {
            return banner;
          }
          Widget buildList(String title, List<dynamic> src) {
            return Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('$title (${src.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ...src.take(6).map((b) {
                    final id = (b['id'] ?? '').toString();
                    final name = (b['guest_name'] ?? '').toString();
                    final phone = (b['guest_phone'] ?? '').toString();
                    final fromIso = (b['from_iso'] ?? '').toString();
                    final toIso = (b['to_iso'] ?? '').toString();
                    return Text(
                        '#$id · ${name.isEmpty ? '—' : name} · ${phone.isEmpty ? '' : phone} · $fromIso → $toIso',
                        style: Theme.of(ctx)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: Theme.of(ctx)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: .75)));
                  })
                ]));
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              banner,
              Row(
                children: [
                  if (arrivals.isNotEmpty)
                    buildList(
                        l.isArabic ? 'الوصول اليوم' : 'Arrivals today',
                        arrivals),
                  if (deps.isNotEmpty) const SizedBox(width: 12),
                  if (deps.isNotEmpty)
                    buildList(
                        l.isArabic ? 'المغادرة اليوم' : 'Departures today',
                        deps),
                ],
              )
            ],
          );
        }),
      SelectableText(bout),
      const SizedBox(height: 8),
      ..._obooks.map((x) {
          final id = (x['id'] ?? '').toString();
          final st = (x['status'] ?? '').toString();
          final a = ((x['amount_cents'] ?? 0) as int);
          return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                title: Text('Booking $id'),
                subtitle:
                    Text('${(a / 100).toStringAsFixed(2)} $_curSym  ·  $st'),
                trailing: SizedBox(
                    width: 260,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                              width: 80,
                              child: WaterButton(
                                  label: 'Confirm',
                                  onTap: () async {
                                    final idop = opIdCtrl.text.trim();
                                    if (idop.isEmpty) return;
                                    final r = await http.post(
                                        Uri.parse(
                                            '${widget.baseUrl}/stays/operators/$idop/bookings/$id/status'),
                                        headers: await _authHdr(json: true),
                                        body: jsonEncode(
                                            {'status': 'confirmed'}));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content:
                                                Text('Set: ${r.statusCode}')));
                                    await _myBookings();
                                  })),
                          const SizedBox(width: 6),
                          SizedBox(
                              width: 80,
                              child: WaterButton(
                                  label: 'Cancel',
                                  onTap: () async {
                                    final idop = opIdCtrl.text.trim();
                                    if (idop.isEmpty) return;
                                    final r = await http.post(
                                        Uri.parse(
                                            '${widget.baseUrl}/stays/operators/$idop/bookings/$id/status'),
                                        headers: await _authHdr(json: true),
                                        body:
                                            jsonEncode({'status': 'canceled'}));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content:
                                                Text('Set: ${r.statusCode}')));
                                    await _myBookings();
                                  })),
                          const SizedBox(width: 6),
                          SizedBox(
                              width: 80,
                              child: WaterButton(
                                  label: 'Complete',
                                  onTap: () async {
                                    final idop = opIdCtrl.text.trim();
                                    if (idop.isEmpty) return;
                                    final r = await http.post(
                                        Uri.parse(
                                            '${widget.baseUrl}/stays/operators/$idop/bookings/$id/status'),
                                        headers: await _authHdr(json: true),
                                        body: jsonEncode(
                                            {'status': 'completed'}));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content:
                                                Text('Set: ${r.statusCode}')));
                                    await _myBookings();
                                  }))
                        ])),
              ));
        }).toList(),
      ],
    ]);
    const bg = AppBG();
    final l = L10n.of(context);
    final dashboard = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildOperatorIntro(context),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Card(
                      elevation: 0.5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isArabic
                                  ? 'نظرة عامة على المنشأة'
                                  : 'Property overview',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              (_token == null || _token!.isEmpty)
                                  ? (l.isArabic
                                      ? 'لم يتم تسجيل الدخول كمشغل.'
                                      : 'Not logged in as operator.')
                                  : (l.isArabic
                                      ? 'مسجل الدخول كمشغل.'
                                      : 'Logged in as operator.'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: .75)),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                SizedBox(
                                  width: 180,
                                  child: WaterButton(
                                      label: l.isArabic
                                          ? 'إدارة الغرف والأسعار'
                                          : 'Manage rooms & rates',
                                      onTap: () {
                                        final ctrl =
                                            DefaultTabController.of(context);
                                        ctrl?.animateTo(1);
                                      }),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: WaterButton(
                                      label: l.isArabic
                                          ? 'عرض الحجوزات'
                                          : 'View bookings',
                                      onTap: () {
                                        final ctrl =
                                            DefaultTabController.of(context);
                                        ctrl?.animateTo(1);
                                      }),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      elevation: 0.5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.isArabic
                                  ? 'الحجوزات (الفترة الحالية)'
                                  : 'Bookings (current filter)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _btotal <= 0
                                  ? (l.isArabic
                                      ? 'لا توجد حجوزات محملة بعد — استخدم تبويب الأدوات لتحديث الحجوزات.'
                                      : 'No bookings loaded yet – use the tools tab to load bookings.')
                                  : (l.isArabic
                                      ? 'الحجوزات: $_btotal · قيد الطلب: $_bRequested · مؤكدة: $_bConfirmed · ملغاة: $_bCanceled · مكتملة: $_bCompleted · المجموع: ${(_bAmountCents / 100).toStringAsFixed(2)} $_curSym'
                                      : 'Bookings: $_btotal · requested: $_bRequested · confirmed: $_bConfirmed · canceled: $_bCanceled · completed: $_bCompleted · total: ${(_bAmountCents / 100).toStringAsFixed(2)} $_curSym'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: .75)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  elevation: 0.5,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.isArabic
                              ? 'فريق التشغيل والضيافة'
                              : 'Operations & housekeeping',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.isArabic
                              ? 'استخدم تبويب الأدوات لإدارة الغرف، الأسعار، الطاقم والحجوزات بتفاصيل كاملة.'
                              : 'Use the tools tab to manage rooms, rates, staff and bookings in detail.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: .75)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            l.isArabic ? 'لوحة الفنادق والإقامات' : 'Stays · Operator',
          ),
          bottom: TabBar(tabs: [
            Tab(text: l.isArabic ? 'الأدوات' : 'Tools'),
            Tab(text: l.isArabic ? 'لوحة المعلومات' : 'Dashboard'),
          ]),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            bg,
            Positioned.fill(
              child: SafeArea(
                child: GlassPanel(
                  padding: const EdgeInsets.all(16),
                  child: TabBarView(
                    children: [
                      content,
                      dashboard,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusBookPageState extends State<BusBookPage> {
  final originCtrl = TextEditingController();
  final destCtrl = TextEditingController();
  DateTime date = DateTime.now();
  String? originId;
  String? destId;
  List<dynamic> trips = [];
  String out = '';
  final seatsCtrl = TextEditingController(text: '1');
  final walletCtrl = TextEditingController();
  String booking = '';
  String? lastBookingId;
  List<dynamic> myBookings = [];
  String myBookingsOut = '';
  String _bannerMsg = '';
  StatusKind _bannerKind = StatusKind.info;
  // Optional seat selection per trip (seat numbers), used when booking.
  final Map<String, Set<int>> _selectedSeatsByTrip = <String, Set<int>>{};
  // Optional exchange context: when set, the next booking will first cancel
  // the original booking (according to refund policy) and then create a new
  // booking for the selected trip.
  String? _exchangeFromBookingId;
  // Static metadata for city labels (used to provide Arabic/English names
  // where we know them). IDs here should match the bus service city IDs.
  static const List<Map<String, String>> _cityMeta = [
    {'id': '021', 'en': 'Aleppo', 'ar': 'حلب'},
    {'id': '011', 'en': 'Damascus', 'ar': 'دمشق'},
    {'id': 'HOMS', 'en': 'Homs', 'ar': 'حمص'},
    {'id': 'HAMA', 'en': 'Hama', 'ar': 'حماة'},
    {'id': 'LATAKIA', 'en': 'Latakia', 'ar': 'اللاذقية'},
    {'id': 'TARTUS', 'en': 'Tartus', 'ar': 'طرطوس'},
    {'id': 'RAQQA', 'en': 'Raqqa', 'ar': 'الرقة'},
    {'id': 'DEIR_EZ_ZOR', 'en': 'Deir ez-Zor', 'ar': 'دير الزور'},
    {'id': 'IDLIB', 'en': 'Idlib', 'ar': 'إدلب'},
    {'id': 'SWEIDA', 'en': 'As-Suwayda', 'ar': 'السويداء'},
    {'id': 'DARA', 'en': 'Daraa', 'ar': 'درعا'},
    {'id': 'HASAKAH', 'en': 'Al-Hasakah', 'ar': 'الحسكة'},
  ];
  // Resolved choices from backend (/bus/cities_cached), enriched with labels
  // from _cityMeta where available. This keeps the IDs exactly identical to
  // those used by the Bus Operator console and backend routes/trips.
  List<Map<String, String>> _cityChoices = const [];

  @override
  void initState() {
    super.initState();
    walletCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    seatsCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _loadWallet();
    _loadLastBooking();
    _loadCities();
  }

  Future<void> _loadWallet() async {
    try {
      final sp = await SharedPreferences.getInstance();
      walletCtrl.text = sp.getString('wallet_id') ?? '';
    } catch (_) {}
  }

  Future<void> _loadLastBooking() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final id = sp.getString('bus_last_booking_id');
      if (id != null && id.isNotEmpty && mounted) {
        setState(() => lastBookingId = id);
      }
    } catch (_) {}
  }

  Future<void> _loadCities() async {
    try {
      final uri = Uri.parse('${widget.baseUrl}/bus/cities_cached');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode != 200) {
        return;
      }
      final data = jsonDecode(r.body);
      if (data is! List) {
        return;
      }
      final Map<String, Map<String, String>> bestByName = {};
      bool isDial(String v) {
        if (v.length < 3 || !v.startsWith('0')) return false;
        return int.tryParse(v.substring(1)) != null;
      }

      for (final c in data) {
        if (c is! Map) continue;
        final id = (c['id'] ?? '').toString();
        final name = (c['name'] ?? '').toString();
        if (id.isEmpty || name.isEmpty) continue;
        final key = name.trim().toLowerCase();
        final existing = bestByName[key];
        if (existing == null) {
          final meta = _cityMeta.firstWhere(
            (m) => m['id'] == id,
            orElse: () => const {},
          );
          final en = (meta['en'] ?? name).toString();
          final ar = (meta['ar'] ?? name).toString();
          bestByName[key] = {'id': id, 'en': en, 'ar': ar};
        } else {
          final oldId = existing['id'] ?? '';
          if (isDial(id) && !isDial(oldId)) {
            final meta = _cityMeta.firstWhere(
              (m) => m['id'] == id,
              orElse: () => const {},
            );
            final en = (meta['en'] ?? name).toString();
            final ar = (meta['ar'] ?? name).toString();
            bestByName[key] = {'id': id, 'en': en, 'ar': ar};
          }
        }
      }
      final List<Map<String, String>> choices = bestByName.values.toList()
        ..sort((a, b) => (a['en'] ?? '').compareTo(b['en'] ?? ''));
      if (choices.isNotEmpty && mounted) {
        setState(() => _cityChoices = choices);
      }
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 1));
    final last = first.add(const Duration(days: 365));
    final initial =
        date.isBefore(first) ? first : (date.isAfter(last) ? last : date);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (d != null) {
      setState(() => date = d);
    }
  }

  void _changeSeats(int delta) {
    int current = int.tryParse(seatsCtrl.text.trim()) ?? 1;
    current += delta;
    if (current < 1) current = 1;
    if (current > 10) current = 10;
    seatsCtrl.text = current.toString();
    // Changing passenger count resets any explicit seat selection.
    _selectedSeatsByTrip.clear();
    setState(() {});
  }

  bool get _canSearch {
    final seats = int.tryParse(seatsCtrl.text.trim()) ?? 0;
    return originId != null && destId != null && seats > 0;
  }

  void _openSeatPickerForTrip(Map<String, dynamic> trip) {
    final l = L10n.of(context);
    final tripId = (trip['id'] ?? '').toString();
    if (tripId.isEmpty) return;
    final seatsTotal = (trip['seats_total'] ?? 40) is int
        ? trip['seats_total'] as int
        : int.tryParse(trip['seats_total'].toString()) ?? 40;
    final seatsAvailable = (trip['seats_available'] ?? seatsTotal) is int
        ? trip['seats_available'] as int
        : int.tryParse(trip['seats_available'].toString()) ?? seatsTotal;
    final maxSelectable = seatsAvailable.clamp(1, 10);
    final currentSelected = _selectedSeatsByTrip[tripId] ?? <int>{};
    if (currentSelected.isEmpty) {
      // Default selection: first N seats according to passenger count
      final count = int.tryParse(seatsCtrl.text.trim()) ?? 1;
      final target = count.clamp(1, maxSelectable);
      _selectedSeatsByTrip[tripId] = {for (var i = 1; i <= target; i++) i};
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(
            color: Colors.black54,
            child: GestureDetector(
              onTap: () {},
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: .98),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 10,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: SafeArea(
                    top: false,
                    child: StatefulBuilder(
                      builder: (ctx2, setLocal) {
                        final selected =
                            _selectedSeatsByTrip[tripId] ?? <int>{};
                        void toggle(int seatNo) {
                          setState(() {
                            final s = _selectedSeatsByTrip[tripId] ?? <int>{};
                            if (s.contains(seatNo)) {
                              s.remove(seatNo);
                            } else {
                              if (s.length >= maxSelectable) {
                                return;
                              }
                              s.add(seatNo);
                            }
                            _selectedSeatsByTrip[tripId] = s;
                            seatsCtrl.text =
                                s.isEmpty ? '1' : s.length.toString();
                          });
                          setLocal(() {});
                        }

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              height: 4,
                              width: 44,
                              margin: const EdgeInsets.only(bottom: 8),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Text(
                              l.isArabic ? 'اختيار المقاعد' : 'Select seats',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l.isArabic
                                  ? 'اختر حتى $maxSelectable مقعداً متاحاً.'
                                  : 'Select up to $maxSelectable available seats.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (int sn = 1; sn <= seatsTotal; sn++)
                                  GestureDetector(
                                    onTap: () => toggle(sn),
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: selected.contains(sn)
                                            ? Tokens.colorBus
                                                .withValues(alpha: .9)
                                            : Colors.white
                                                .withValues(alpha: .06),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: selected.contains(sn)
                                              ? Tokens.colorBus
                                              : Colors.white24,
                                        ),
                                      ),
                                      child: Text(
                                        sn.toString(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: selected.contains(sn)
                                              ? Colors.black
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l.isArabic
                                      ? 'الركاب: ${selected.isNotEmpty ? selected.length : 1}'
                                      : 'Passengers: ${selected.isNotEmpty ? selected.length : 1}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                SizedBox(
                                  width: 160,
                                  child: WaterButton(
                                    label: 'Book & Pay',
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _book(tripId);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _searchTrips() async {
    if (!_canSearch) {
      setState(() {
        final l = L10n.of(context);
        out = l.busSelectOriginDestError;
        _bannerKind = StatusKind.error;
        _bannerMsg = l.busSelectOriginDestError;
      });
      return;
    }
    final ds =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    setState(() => out = '...');
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      final u = Uri.parse(
          '${widget.baseUrl}/bus/trips/search?origin_city_id=$originId&dest_city_id=$destId&date=$ds');
      final r = await http.get(u, headers: await _hdr());
      trips = jsonDecode(r.body) as List<dynamic>;
      out = '${r.statusCode}: ${trips.length} trips';
      final dt = DateTime.now().millisecondsSinceEpoch - t0;
      Perf.action('bus_search_ok');
      Perf.sample('bus_search_ms', dt);
      setState(() {
        final l = L10n.of(context);
        _bannerKind = StatusKind.info;
        _bannerMsg = l.busFoundTripsBanner(trips.length, ds);
      });
    } catch (e) {
      out = 'error: $e';
      trips = [];
      Perf.action('bus_search_error');
      setState(() {
        final l = L10n.of(context);
        _bannerKind = StatusKind.error;
        _bannerMsg = l.busSearchErrorBanner;
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _book(String tripId) async {
    final l = L10n.of(context);
    setState(() => booking = '...');
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      // If the user started an exchange, cancel the original booking first
      // according to the refund policy, then proceed with the new booking.
      final exchangeId = _exchangeFromBookingId;
      _exchangeFromBookingId = null;
      if (exchangeId != null) {
        try {
          final uriCancel = Uri.parse(
              '${widget.baseUrl}/bus/bookings/${Uri.encodeComponent(exchangeId)}/cancel');
          final rc = await http.post(uriCancel, headers: await _hdr(json: true));
          if (rc.statusCode != 200) {
            // If cancellation fails, abort the exchange before creating
            // a new booking.
            setState(() {
              booking = '${rc.statusCode}: ${rc.body}';
              _bannerKind = StatusKind.error;
              _bannerMsg = l.isArabic
                  ? 'تعذر تغيير الرحلة (فشل إلغاء الحجز الحالي).'
                  : 'Could not change trip (cancellation failed).';
            });
            return;
          }
        } catch (e) {
          setState(() {
            booking = 'cancel error: $e';
            _bannerKind = StatusKind.error;
            _bannerMsg = l.isArabic
                ? 'تعذر تغيير الرحلة (خطأ أثناء إلغاء الحجز).'
                : 'Could not change trip (error while cancelling).';
          });
          return;
        }
      }
      final seats = int.tryParse(seatsCtrl.text.trim()) ?? 1;
      final uri = Uri.parse('${widget.baseUrl}/bus/trips/' + tripId + '/book');
      final headers = await _hdr(json: true);
      headers['Idempotency-Key'] =
          'bus-${DateTime.now().millisecondsSinceEpoch}';
      final selected = _selectedSeatsByTrip[tripId];
      final body = <String, dynamic>{
        'seats': selected == null || selected.isEmpty ? seats : selected.length,
        'wallet_id':
            walletCtrl.text.trim().isEmpty ? null : walletCtrl.text.trim(),
        if (selected != null && selected.isNotEmpty)
          'seat_numbers': selected.toList(),
      };
      final r = await http.post(uri, headers: headers, body: jsonEncode(body));
      booking = '${r.statusCode}: ${r.body}';
      try {
        final j = jsonDecode(r.body);
        final id = (j['id'] ?? '').toString();
        if (id.isNotEmpty) {
          lastBookingId = id;
          try {
            final sp = await SharedPreferences.getInstance();
            await sp.setString('bus_last_booking_id', id);
          } catch (_) {}
        }
        final tix = (j['tickets'] as List?) ?? [];
        if (tix.isNotEmpty) {
          showDialog(
              context: context,
              builder: (_) {
                return Dialog(
                    child: Container(
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              const Text('Tickets',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              ...tix.map((t) {
                                final p = (t['payload'] ?? '').toString();
                                final id = (t['id'] ?? '').toString();
                                return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(id,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 6),
                                      QrImageView(data: p, size: 220),
                                      const SizedBox(height: 8),
                                      Row(children: [
                                        Expanded(
                                            child:
                                                SelectableText(p, maxLines: 2)),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                            width: 120,
                                            child: WaterButton(
                                                label: 'Copy',
                                                onTap: () {
                                                  Clipboard.setData(
                                                      ClipboardData(text: p));
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(const SnackBar(
                                                          content: Text(
                                                              'Payload copied')));
                                                }))
                                      ]),
                                      const Divider(height: 24),
                                    ]);
                              }).toList(),
                              WaterButton(
                                  label: 'Close',
                                  onTap: () => Navigator.pop(context))
                            ]))));
              });
        }
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.action('bus_book_ok');
        Perf.sample('bus_book_ms', dt);
        setState(() {
          _bannerKind = StatusKind.success;
          _bannerMsg = 'Bus booking created (ID: $id)';
        });
      } catch (_) {
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.action('bus_book_fail');
        Perf.sample('bus_book_ms', dt);
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = l.isArabic
              ? 'تعذر إنشاء الحجز.'
              : 'Could not create booking';
        });
      }
    } catch (e) {
      booking = 'error: $e';
      Perf.action('bus_book_error');
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = l.isArabic
            ? 'خطأ أثناء إنشاء الحجز.'
            : 'Error while creating booking';
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _openLastTickets() async {
    final id = (lastBookingId ?? '').trim();
    if (id.isEmpty) return;
    setState(() => booking = 'Loading tickets for booking $id ...');
    try {
      final uri = Uri.parse('${widget.baseUrl}/bus/bookings/' +
          Uri.encodeComponent(id) +
          '/tickets');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode != 200) {
        booking = '${r.statusCode}: ${r.body}';
      } else {
        final tix = (jsonDecode(r.body) as List?) ?? [];
        if (tix.isEmpty) {
          booking = 'No tickets found for booking $id';
        } else {
          booking = 'tickets: ${tix.length}';
          showDialog(
              context: context,
              builder: (_) {
                return Dialog(
                    child: Container(
                        padding: const EdgeInsets.all(16),
                        child: SingleChildScrollView(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              const Text('Tickets',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              ...tix.map((t) {
                                final p = (t['payload'] ?? '').toString();
                                final tid = (t['id'] ?? '').toString();
                                return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(tid,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 6),
                                      QrImageView(data: p, size: 220),
                                      const SizedBox(height: 8),
                                      Row(children: [
                                        Expanded(
                                            child:
                                                SelectableText(p, maxLines: 2)),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                            width: 120,
                                            child: WaterButton(
                                                label: 'Copy',
                                                onTap: () {
                                                  Clipboard.setData(
                                                      ClipboardData(text: p));
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(const SnackBar(
                                                          content: Text(
                                                              'Payload copied')));
                                                }))
                                      ]),
                                      const Divider(height: 24),
                                    ]);
                              }).toList(),
                              WaterButton(
                                  label: 'Close',
                                  onTap: () => Navigator.pop(context))
                            ]))));
              });
        }
      }
    } catch (e) {
      booking = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadMyBookings() async {
    final wid = walletCtrl.text.trim();
    if (wid.isEmpty) {
      setState(
          () => myBookingsOut = 'Add your wallet first to see your bookings.');
      return;
    }
    setState(() {
      myBookingsOut = 'Loading bookings...';
      myBookings = [];
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/bus/bookings/search?wallet_id=' +
          Uri.encodeComponent(wid) +
          '&limit=20');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode != 200) {
        myBookingsOut = '${r.statusCode}: ${r.body}';
      } else {
        final arr = jsonDecode(r.body) as List<dynamic>;
        myBookings = arr;
        myBookingsOut = arr.isEmpty
            ? 'No bookings for this wallet yet.'
            : 'Showing latest ${arr.length} bookings for this wallet.';
      }
    } catch (e) {
      myBookingsOut = 'error: $e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _cancelBooking(String bookingId) async {
    final l = L10n.of(context);
    setState(() {
      booking = 'Cancelling booking $bookingId ...';
      _bannerKind = StatusKind.info;
      _bannerMsg = l.isArabic
          ? 'جارٍ إلغاء الحجز وفقاً لسياسة الاسترداد.'
          : 'Cancelling booking according to refund policy.';
    });
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/bus/bookings/${Uri.encodeComponent(bookingId)}/cancel');
      final r = await http.post(uri, headers: await _hdr(json: true));
      if (r.statusCode != 200) {
        setState(() {
          booking = '${r.statusCode}: ${r.body}';
          _bannerKind = StatusKind.error;
          _bannerMsg = l.isArabic
              ? 'تعذر إلغاء الحجز.'
              : 'Could not cancel booking.';
        });
        return;
      }
      final j = jsonDecode(r.body);
      final refund = (j['refund_cents'] ?? 0) as num;
      final cur = (j['refund_currency'] ?? 'SYP').toString();
      final pct = (j['refund_pct'] ?? 0).toString();
      final amt = (refund / 100.0).toStringAsFixed(2);
      setState(() {
        booking =
            'Canceled booking $bookingId, refund: $amt $cur ($pct%)';
        _bannerKind = StatusKind.success;
        _bannerMsg = l.isArabic
            ? 'تم إلغاء الحجز. سيتم إرسال رصيد الاسترداد إلى محفظتك.'
            : 'Booking canceled. Refund will be added to your wallet.';
      });
      // Refresh bookings list so status updates.
      await _loadMyBookings();
    } catch (e) {
      setState(() {
        booking = 'error: $e';
        _bannerKind = StatusKind.error;
        _bannerMsg =
            l.isArabic ? 'خطأ أثناء إلغاء الحجز.' : 'Error while cancelling.';
      });
    }
  }

  void _startExchange(Map<String, dynamic> booking) {
    final l = L10n.of(context);
    try {
      final trip = booking['trip'] as Map<String, dynamic>?;
      final origin = booking['origin'] as Map<String, dynamic>?;
      final dest = booking['dest'] as Map<String, dynamic>?;
      final seatsVal = booking['seats'];
      final seatsNum =
          seatsVal is int ? seatsVal : int.tryParse(seatsVal.toString()) ?? 1;
      final originIdVal = (origin?['id'] ?? '').toString();
      final destIdVal = (dest?['id'] ?? '').toString();
      DateTime? dep;
      try {
        dep = DateTime.parse((trip?['depart_at'] ?? '').toString()).toLocal();
      } catch (_) {}
      setState(() {
        _exchangeFromBookingId = (booking['id'] ?? '').toString();
        if (originIdVal.isNotEmpty) {
          originId = originIdVal;
          originCtrl.text = (origin?['name'] ?? '').toString();
        }
        if (destIdVal.isNotEmpty) {
          destId = destIdVal;
          destCtrl.text = (dest?['name'] ?? '').toString();
        }
        if (dep != null) {
          date = DateTime(dep.year, dep.month, dep.day);
        }
        seatsCtrl.text = seatsNum.toString();
        _selectedSeatsByTrip.clear();
        _bannerKind = StatusKind.info;
        _bannerMsg = l.isArabic
            ? 'اختر رحلة جديدة واضغط على "Book & Pay" لتغيير الحجز. سيتم تطبيق سياسة الاسترداد.'
            : 'Select a new trip and tap "Book & Pay" to change your booking. Refund policy will apply.';
      });
      final controller = DefaultTabController.of(context);
      controller?.animateTo(0);
    } catch (_) {
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = l.isArabic
            ? 'تعذر بدء تغيير الحجز.'
            : 'Could not start booking change.';
      });
    }
  }

  Widget _bookingTile(dynamic b) {
    try {
      final id = (b['id'] ?? '').toString();
      final trip = b['trip'];
      final origin = b['origin'];
      final dest = b['dest'];
      final op = b['operator'];
      final seats = b['seats'] ?? 0;
      final status = (b['status'] ?? '').toString();
      final created = b['created_at']?.toString() ?? '';
      final dep = DateTime.tryParse(trip['depart_at'].toString())?.toLocal();
      final arr = DateTime.tryParse(trip['arrive_at'].toString())?.toLocal();
      final depStr = dep != null
          ? '${dep.year}-${dep.month}-${dep.day} ${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}'
          : '';
      final arrStr = arr != null
          ? '${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}'
          : '';
      final whenLine = depStr.isNotEmpty ? '$depStr → $arrStr' : created;
      final originName = (origin?['name'] ?? '').toString();
      final destName = (dest?['name'] ?? '').toString();
      final routeLine = (originName.isNotEmpty || destName.isNotEmpty)
          ? '${originName.isNotEmpty ? originName : '?'} → ${destName.isNotEmpty ? destName : '?'}'
          : '';
      final opName = (op?['name'] ?? '').toString();
      final depIsFuture = (() {
        try {
          if (dep == null) return false;
          return dep.isAfter(DateTime.now().subtract(const Duration(hours: 1)));
        } catch (_) {
          return false;
        }
      })();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          radius: 16,
          child: Row(
            children: [
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Booking $id',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  if (routeLine.isNotEmpty)
                    Text(routeLine, style: const TextStyle(fontSize: 11)),
                  if (opName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(opName,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                  ],
                  const SizedBox(height: 2),
                  if (whenLine.isNotEmpty)
                    Text(whenLine,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                  const SizedBox(height: 2),
                  Text('Seats: $seats · Status: $status',
                      style: const TextStyle(fontSize: 11)),
                ],
              )),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    WaterButton(
                        label: 'Details',
                        onTap: () {
                          lastBookingId = id;
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => BusBookingDetailPage(
                                      baseUrl: widget.baseUrl,
                                      booking: Map<String, dynamic>.from(
                                          b as Map))));
                        }),
                    const SizedBox(height: 4),
                    if (status != 'canceled') ...[
                      TextButton(
                          onPressed: () => _cancelBooking(id),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 11),
                          )),
                      if (depIsFuture)
                        TextButton(
                            onPressed: () {
                              _startExchange(Map<String, dynamic>.from(b as Map));
                            },
                            child: const Text(
                              'Change',
                              style: TextStyle(fontSize: 11),
                            )),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _tripTile(dynamic t) {
    try {
      final trip = t['trip'];
      final op = t['operator'];
      final origin = t['origin'];
      final dest = t['dest'];
      final features = (t['features'] ?? '').toString().trim();
      final depUtc = DateTime.parse(trip['depart_at'].toString());
      final arrUtc = DateTime.parse(trip['arrive_at'].toString());
      final dep = depUtc.toLocal();
      final arr = arrUtc.toLocal();
      final price = trip['price_cents'];
      final cur = (trip['currency'] ?? '').toString();
      final avail = trip['seats_available'];
      final seats = int.tryParse(seatsCtrl.text.trim()) ?? 1;
      final totalCents =
          (price is int ? price : int.tryParse(price.toString()) ?? 0) *
              (seats <= 0 ? 1 : seats);
      final opName = (op['name'] ?? 'Operator').toString();
      final originName = (origin?['name'] ?? '').toString();
      final destName = (dest?['name'] ?? '').toString();
      final dur = arr.difference(dep);
      final dh = dur.inMinutes ~/ 60;
      final dm = dur.inMinutes % 60;
      final depTime =
          '${dep.hour.toString().padLeft(2, '0')}:${dep.minute.toString().padLeft(2, '0')}';
      final arrTime =
          '${arr.hour.toString().padLeft(2, '0')}:${arr.minute.toString().padLeft(2, '0')}';
      final durStr = dh > 0 ? '${dh}h${dm > 0 ? ' ${dm}m' : ''}' : '${dm}m';
      final availLine = '$avail seats left';
      final tripId = (trip['id'] ?? '').toString();
      final selectedSeats = _selectedSeatsByTrip[tripId] ?? const <int>{};
      final cs = Theme.of(context).colorScheme;
      final primary = cs.onSurface;
      final secondary = cs.onSurface.withValues(alpha: .70);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          radius: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              depTime,
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: primary),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                originName.isNotEmpty ? originName : '?',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: primary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              arrTime,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: primary),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                destName.isNotEmpty ? destName : '?',
                                style: TextStyle(
                                    fontSize: 13, color: secondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$durStr • $availLine',
                          style:
                              TextStyle(fontSize: 11, color: secondary),
                        ),
                        if (opName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            opName,
                            style: TextStyle(
                                fontSize: 11, color: secondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${(totalCents / 100).toStringAsFixed(2)} $cur',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: primary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'for $seats seat${seats == 1 ? '' : 's'}',
                        style:
                            TextStyle(fontSize: 11, color: secondary),
                      ),
                    ],
                  ),
                ],
              ),
              if (features.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  features,
                  style:
                      TextStyle(fontSize: 11, color: secondary),
                ),
              ],
              if (selectedSeats.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Seats: ${selectedSeats.toList()..sort()}',
                  style:
                      TextStyle(fontSize: 11, color: secondary),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 160,
                  child: WaterButton(
                    label: 'Book & Pay',
                    onTap: () {
                      _openSeatPickerForTrip(trip);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _searchTab(BuildContext context) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    final searchSection = FormSection(
      title: l.busSearchSectionTitle,
      subtitle: l.isArabic
          ? 'اختر المسار والتاريخ وعدد المقاعد، ثم ادفع من محفظتك لتحصل على رموز QR للتذاكر.'
          : 'Choose your route, date and seats, then pay from your wallet and get QR tickets.',
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: originId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.isArabic ? 'من' : 'From',
                ),
                items: (_cityChoices.isNotEmpty ? _cityChoices : _cityMeta)
                    .map((c) => DropdownMenuItem<String>(
                          value: c['id'],
                          child: Text(
                              l.isArabic ? (c['ar'] ?? c['en']!) : c['en']!),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    originId = v;
                    final list =
                        _cityChoices.isNotEmpty ? _cityChoices : _cityMeta;
                    final city = list.firstWhere((c) => c['id'] == v);
                    originCtrl.text =
                        l.isArabic ? (city['ar'] ?? city['en']!) : city['en']!;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: .60),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: destId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l.isArabic ? 'إلى' : 'To',
                ),
                items: (_cityChoices.isNotEmpty ? _cityChoices : _cityMeta)
                    .map((c) => DropdownMenuItem<String>(
                          value: c['id'],
                          child: Text(
                              l.isArabic ? (c['ar'] ?? c['en']!) : c['en']!),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    destId = v;
                    final list =
                        _cityChoices.isNotEmpty ? _cityChoices : _cityMeta;
                    final city = list.firstWhere((c) => c['id'] == v);
                    destCtrl.text =
                        l.isArabic ? (city['ar'] ?? city['en']!) : city['en']!;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            flex: 2,
            child: WaterButton(
              label:
                  '${l.busDatePrefix}: ${date.year}-${date.month}-${date.day}',
              onTap: _pickDate,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.busSeatsLabel,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white24),
                    color: Colors.white.withValues(alpha: .04),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 24, minHeight: 24),
                        icon: const Icon(Icons.remove),
                        onPressed: () => _changeSeats(-1),
                      ),
                      Text(
                        seatsCtrl.text.trim().isEmpty
                            ? '1'
                            : seatsCtrl.text.trim(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 24, minHeight: 24),
                        icon: const Icon(Icons.add),
                        onPressed: () => _changeSeats(1),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Opacity(
          opacity: _canSearch ? 1.0 : 0.4,
          child: IgnorePointer(
            ignoring: !_canSearch,
            child: WaterButton(
              label: l.busSearchButton,
              onTap: _searchTrips,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (out.isNotEmpty) SelectableText(out),
      ],
    );

    final tripsSection = FormSection(
      title: l.busAvailableTripsTitle,
      children: [
        if (trips.isEmpty)
          Text(l.busNoTripsHint, style: theme.textTheme.bodySmall),
        if (trips.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...trips.map(_tripTile),
        ],
        const SizedBox(height: 12),
        if (booking.isNotEmpty) SelectableText(booking),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_bannerMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusBanner(
                kind: _bannerKind, message: _bannerMsg, dense: true),
          ),
        searchSection,
        tripsSection,
      ],
    );
  }

  Widget _myTripsTab(BuildContext context) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    // Filter upcoming based on depart_at
    final now = DateTime.now();
    final upcoming = myBookings.where((b) {
      try {
        final trip = b['trip'];
        final dep = DateTime.parse(trip['depart_at'].toString()).toLocal();
        return dep.isAfter(now.subtract(const Duration(hours: 1)));
      } catch (_) {
        return false;
      }
    }).toList();
    final past = myBookings.where((b) => !upcoming.contains(b)).toList();
    final overviewSection = FormSection(
      title: l.busMyTripsTitle,
      subtitle: l.busMyTripsSubtitle,
      children: [
        Row(children: [
          Expanded(
              child: WaterButton(
                  label: l.busLoadBookingsLabel, onTap: _loadMyBookings)),
        ]),
        const SizedBox(height: 4),
        if (myBookingsOut.isNotEmpty)
          Text(myBookingsOut, style: theme.textTheme.bodySmall),
      ],
    );

    final upcomingSection = FormSection(
      title: l.busUpcomingTitle,
      children: [
        if (upcoming.isEmpty)
          Text(l.busNoUpcomingTrips, style: theme.textTheme.bodySmall),
        if (upcoming.isNotEmpty) ...upcoming.map(_bookingTile),
      ],
    );

    final pastSection = FormSection(
      title: l.busPastTitle,
      children: [
        if (past.isEmpty)
          Text(l.busNoPastTrips, style: theme.textTheme.bodySmall),
        if (past.isNotEmpty) ...past.map(_bookingTile),
      ],
    );

    final ticketsSection = FormSection(
      title: l.busMyTicketsSectionTitle,
      children: [
        if (lastBookingId != null && (lastBookingId ?? '').isNotEmpty)
          Row(children: [
            Expanded(
              child: Text(
                '${l.busLastBookingPrefix}${lastBookingId!}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
                width: 150,
                child: WaterButton(
                    label: l.busOpenTicketsLabel, onTap: _openLastTickets)),
          ])
        else
          Text(
            l.busMyTicketsHint,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        overviewSection,
        upcomingSection,
        pastSection,
        const SizedBox(height: 24),
        ticketsSection,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final l = L10n.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.busBookingTitle),
          backgroundColor: Colors.transparent,
          bottom: TabBar(tabs: [
            Tab(text: l.busBookingTabSearch),
            Tab(text: l.busBookingTabMyTrips),
          ]),
        ),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          bg,
          Positioned.fill(
              child: SafeArea(
                  child: GlassPanel(
            padding: const EdgeInsets.all(16),
            child: TabBarView(children: [
              _searchTab(context),
              _myTripsTab(context),
            ]),
          ))),
        ]),
      ),
    );
  }
}

// Bus Operator console: manage cities, operators, routes, trips, and boarding
class BusOperatorPage extends StatefulWidget {
  final String baseUrl;
  const BusOperatorPage(this.baseUrl, {super.key});
  @override
  State<BusOperatorPage> createState() => _BusOperatorPageState();
}

class _BusOperatorPageState extends State<BusOperatorPage> {
  @override
  void initState() {
    super.initState();
    // Load cities and operator id once when the page opens so that
    // the From/To dropdowns and stats are immediately usable.
    _loadCities();
    _loadBusOperatorId();
  }

  // Cities
  final cityNameCtrl = TextEditingController();
  final countryCtrl = TextEditingController();
  String cityOut = '';
  List<dynamic> _cities = const [];
  String? _routeOriginId;
  String? _routeDestId;
  bool _isAdminOrSuper = false;
  // Route
  final originIdCtrl = TextEditingController();
  final destIdCtrl = TextEditingController();
  final routeOpCtrl = TextEditingController();
  final routeBusModelCtrl = TextEditingController();
  final routeFeaturesCtrl = TextEditingController();
  String routeOut = '';
  // Trip
  final routeIdCtrl = TextEditingController();
  DateTime dep = DateTime.now().add(const Duration(days: 1));
  DateTime arr = DateTime.now().add(const Duration(days: 1, hours: 2));
  final priceCtrl = TextEditingController(text: '100000');
  final seatsTotalCtrl = TextEditingController(text: '40');
  String tripOut = '';
  // Boarding
  final payloadCtrl = TextEditingController();
  String boardOut = '';
  // Tickets list/grid
  final bookingCtrl = TextEditingController();
  List<Map<String, dynamic>> _tickets = [];
  // Reservations
  final reserveTripCtrl = TextEditingController();
  final reserveSeatsCtrl = TextEditingController(text: '1');
  String reserveOut = '';
  // Stats
  final statsOpIdCtrl = TextEditingController();
  String statsOut = '';
  String statsPeriod = 'today';
  // Operators (admin view)
  List<Map<String, dynamic>> _operators = [];
  String operatorsOut = '';
  bool _operatorsLoading = false;
  // Bus amenities (clickable presets)
  final List<String> _amenityPresets = const [
    '🌐 Wi‑Fi',
    '❄️ A/C',
    '🔌 Power',
    '🛏 Reclining seats',
    '🚻 Toilet',
    '🍽 Food',
    '🥤 Drinks',
  ];
  final Set<String> _selectedAmenities = <String>{};
  // Last created trip (for quick publish/modify actions)
  Map<String, dynamic>? _lastTrip;
  bool _lastTripPublished = false;
  Future<void> _scanTicket() async {
    try {
      final res = await Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ScanPage()));
      if (res != null && res is String && res.isNotEmpty) {
        payloadCtrl.text = res;
        setState(() {});
        // Auto-board immediately after scanning the ticket QR
        await _board();
      }
    } catch (_) {}
  }

  Future<void> _loadCities() async {
    setState(() => cityOut = '');
    try {
      final uri = Uri.parse('${widget.baseUrl}/bus/cities_cached');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        try {
          final data = jsonDecode(r.body);
          if (data is List) {
            // Deduplicate by city name and prefer phone-style IDs (e.g. 021, 011)
            final Map<String, Map<String, dynamic>> bestByName = {};
            bool isDial(String v) {
              if (v.length < 3 || !v.startsWith('0')) return false;
              return int.tryParse(v.substring(1)) != null;
            }

            for (final raw in data) {
              if (raw is! Map) continue;
              final id = (raw['id'] ?? '').toString();
              final name = (raw['name'] ?? '').toString();
              final country = (raw['country'] ?? '').toString();
              if (id.isEmpty || name.isEmpty) continue;
              final key = name.trim().toLowerCase();
              final existing = bestByName[key];
              if (existing == null) {
                bestByName[key] = {
                  'id': id,
                  'name': name,
                  'country': country.isEmpty ? null : country,
                };
              } else {
                final oldId = (existing['id'] ?? '').toString();
                if (isDial(id) && !isDial(oldId)) {
                  bestByName[key] = {
                    'id': id,
                    'name': name,
                    'country': country.isEmpty ? null : country,
                  };
                }
              }
            }
            final list = bestByName.values.toList()
              ..sort((a, b) => ((a['name'] ?? '') as String)
                  .compareTo((b['name'] ?? '') as String));
            setState(() => _cities = list);
          } else {
            setState(
                () => cityOut = 'unexpected cities payload (${r.statusCode})');
          }
        } catch (e) {
          setState(() => cityOut = 'error parsing cities: $e');
        }
      } else {
        setState(() => cityOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => cityOut = 'error loading cities: $e');
    }
  }

  Future<void> _loadBusOperatorId() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final stored = sp.getString('bus_operator_id');
      if (stored != null && stored.isNotEmpty) {
        setState(() {
          routeOpCtrl.text = stored;
          statsOpIdCtrl.text = stored;
        });
      }
    } catch (_) {}
    // Always try to auto-link the operator id based on the current wallet.
    // Admin/Superadmin should create the operator; this lookup only resolves it.
    await _ensureBusOperatorForWallet();
  }

  Future<void> _saveBusOperatorId(String id) async {
    if (id.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('bus_operator_id', id);
    } catch (_) {}
    if (mounted) {
      setState(() {
        routeOpCtrl.text = id;
        statsOpIdCtrl.text = id;
      });
    } else {
      routeOpCtrl.text = id;
      statsOpIdCtrl.text = id;
    }
  }

  Future<void> _ensureBusOperatorForWallet() async {
    try {
      // 1) Get current wallet_id of this logged-in phone.
      final overviewUri = Uri.parse('${widget.baseUrl}/me/overview');
      final overviewResp = await http.get(overviewUri, headers: await _hdr());
      if (overviewResp.statusCode != 200) {
        return;
      }
      final ov = jsonDecode(overviewResp.body);
      if (ov is! Map<String, dynamic>) {
        return;
      }
      final roles =
          (ov['roles'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
      final isAdminOrSuper = _hasAdminRole(roles) || _hasSuperadminRole(roles);
      if (mounted) {
        setState(() {
          _isAdminOrSuper = isAdminOrSuper;
        });
      } else {
        _isAdminOrSuper = isAdminOrSuper;
      }
      final walletId = (ov['wallet_id'] ?? '').toString().trim();
      if (walletId.isEmpty) {
        return;
      }
      // 2) Try to find existing bus operator with this wallet_id.
      String? opId;
      try {
        final opsUri = Uri.parse('${widget.baseUrl}/bus/operators');
        final opsResp = await http.get(opsUri, headers: await _hdr());
        if (opsResp.statusCode == 200) {
          final arr = jsonDecode(opsResp.body);
          if (arr is List) {
            for (final o in arr) {
              if (o is! Map) continue;
              final wid = (o['wallet_id'] ?? '').toString().trim();
              if (wid != walletId) continue;
              final id = (o['id'] ?? '').toString().trim();
              if (id.isNotEmpty) {
                opId = id;
                break;
              }
            }
          }
        }
      } catch (_) {}
      if (opId != null && opId.isNotEmpty) {
        await _saveBusOperatorId(opId);
      } else {
        // No operator configured for this wallet yet; keep the fields empty.
        // Admin/Superadmin must create a bus operator for this phone.
      }
    } catch (_) {}
  }

  String _buildFeatures() {
    final chips = _selectedAmenities.toList();
    final parts = <String>[];
    if (chips.isNotEmpty) parts.addAll(chips);
    return parts.join(' · ');
  }

  List<DropdownMenuItem<String>> _buildCityItems() {
    final items = <DropdownMenuItem<String>>[];
    for (final c in _cities) {
      try {
        if (c is! Map) continue;
        final id = (c['id'] ?? '').toString();
        final name = (c['name'] ?? '').toString();
        if (id.isEmpty || name.isEmpty) continue;
        final label = name;
        items.add(DropdownMenuItem<String>(
          value: id,
          child: Text(label),
        ));
      } catch (_) {}
    }
    return items;
  }

  Future<void> _createCity() async {
    final name = cityNameCtrl.text.trim();
    final country = countryCtrl.text.trim();
    // Simple client-side duplicate check to give a friendly message
    // before hitting the backend.
    for (final c in _cities) {
      try {
        if (c is! Map) continue;
        final existingName = (c['name'] ?? '').toString().trim();
        final existingCountry = (c['country'] ?? '').toString().trim();
        if (existingName.isEmpty) continue;
        final sameName = existingName.toLowerCase() == name.toLowerCase();
        final sameCountry =
            existingCountry.toLowerCase() == country.toLowerCase();
        if (sameName && (country.isEmpty || sameCountry)) {
          setState(() {
            cityOut = L10n.of(context).isArabic
                ? 'المدينة موجودة مسبقاً'
                : 'City already exists';
          });
          return;
        }
      } catch (_) {}
    }
    setState(() => cityOut = '...');
    try {
      final r = await http.post(
        Uri.parse('${widget.baseUrl}/bus/cities'),
        headers: await _hdr(json: true),
        body: jsonEncode({
          'name': name,
          'country': country.isNotEmpty ? country : null,
        }),
      );
      setState(() => cityOut = '${r.statusCode}: ${r.body}');
      await _loadCities();
    } catch (e) {
      setState(() => cityOut = 'error: $e');
    }
  }

  Future<void> _pickDep() async {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final last = first.add(const Duration(days: 365));
    final initial =
        dep.isBefore(first) ? first : (dep.isAfter(last) ? last : dep);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (d != null) {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(dep),
      );
      final dt = DateTime(
        d.year,
        d.month,
        d.day,
        t?.hour ?? dep.hour,
        t?.minute ?? dep.minute,
      );
      setState(() {
        dep = dt;
        // Ensure arrival is not before departure; default to +2h if needed.
        if (!arr.isAfter(dep)) {
          arr = dep.add(const Duration(hours: 2));
        }
      });
    }
  }

  Future<void> _pickArr() async {
    final now = DateTime.now();
    final minDep = dep;
    final first = DateTime(minDep.year, minDep.month, minDep.day);
    final last =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 365));
    final currentArr =
        arr.isBefore(minDep) ? minDep.add(const Duration(hours: 2)) : arr;
    final initial = currentArr.isBefore(first)
        ? first
        : (currentArr.isAfter(last) ? last : currentArr);
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
    );
    if (d != null) {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(currentArr),
      );
      var dt = DateTime(
        d.year,
        d.month,
        d.day,
        t?.hour ?? currentArr.hour,
        t?.minute ?? currentArr.minute,
      );
      if (!dt.isAfter(dep)) {
        dt = dep.add(const Duration(hours: 1));
      }
      setState(() => arr = dt);
    }
  }

  Future<void> _createTrip() async {
    setState(() => tripOut = '...');
    try {
      final opId = routeOpCtrl.text.trim();
      final orig = originIdCtrl.text.trim();
      final dest = destIdCtrl.text.trim();
      if (orig.isEmpty || dest.isEmpty) {
        setState(() => tripOut = 'set origin/dest first');
        return;
      }
      final features = _buildFeatures();
      final routeBody = {
        'origin_city_id': orig,
        'dest_city_id': dest,
        'operator_id': opId,
        if (routeBusModelCtrl.text.trim().isNotEmpty)
          'bus_model': routeBusModelCtrl.text.trim(),
        if (features.isNotEmpty) 'features': features,
      };
      final routeUri = Uri.parse('${widget.baseUrl}/bus/routes');
      final routeResp = await http.post(routeUri,
          headers: await _hdr(json: true), body: jsonEncode(routeBody));
      if (routeResp.statusCode < 200 || routeResp.statusCode >= 300) {
        setState(
            () => tripOut = 'route ${routeResp.statusCode}: ${routeResp.body}');
        return;
      }
      String routeDbId = '';
      try {
        final rj = jsonDecode(routeResp.body);
        if (rj is Map) {
          if (rj['id'] != null) {
            routeDbId = rj['id'].toString();
          }
          final opIdFromResp = (rj['operator_id'] ?? '').toString();
          if (opIdFromResp.isNotEmpty) {
            await _saveBusOperatorId(opIdFromResp);
          }
        }
      } catch (_) {}
      if (routeDbId.isEmpty) {
        setState(() => tripOut = 'route created, but id missing');
        return;
      }
      final suggestedId = _computedRouteDisplayId();
      if (suggestedId.isNotEmpty) {
        routeIdCtrl.text = suggestedId;
      }
      final tripBody = {
        'route_id': routeDbId,
        'depart_at_iso': dep.toUtc().toIso8601String(),
        'arrive_at_iso': arr.toUtc().toIso8601String(),
        'price_cents': int.tryParse(priceCtrl.text.trim()) ?? 0,
        'currency': 'SYP',
        'seats_total': int.tryParse(seatsTotalCtrl.text.trim()) ?? 40,
      };
      final tripUri = Uri.parse('${widget.baseUrl}/bus/trips');
      final tripResp = await http.post(tripUri,
          headers: await _hdr(json: true), body: jsonEncode(tripBody));
      Map<String, dynamic>? trip;
      try {
        final body = jsonDecode(tripResp.body);
        if (body is Map<String, dynamic>) {
          trip = body;
        }
      } catch (_) {}
      if (tripResp.statusCode >= 200 &&
          tripResp.statusCode < 300 &&
          trip != null) {
        final id = (trip['id'] ?? '').toString();
        final l = L10n.of(context);
        setState(() {
          _lastTrip = trip;
          _lastTripPublished = false;
          tripOut = l.isArabic ? 'تم إنشاء الرحلة: $id' : 'Trip created: $id';
        });
      } else {
        setState(() {
          _lastTrip = null;
          _lastTripPublished = false;
          tripOut = '${tripResp.statusCode}: ${tripResp.body}';
        });
      }
    } catch (e) {
      setState(() => tripOut = 'error: $e');
    }
  }

  String _tripSummaryText(Map<String, dynamic> trip, L10n l) {
    final id = (trip['id'] ?? '').toString();
    final depart =
        (trip['depart_at'] ?? trip['depart_at_iso'] ?? '').toString();
    final arrive =
        (trip['arrive_at'] ?? trip['arrive_at_iso'] ?? '').toString();
    final price = (trip['price_cents'] ?? '').toString();
    final seats = (trip['seats_total'] ?? '').toString();
    if (l.isArabic) {
      return 'الرحلة #$id · مغادرة: $depart · وصول: $arrive · السعر: $price · المقاعد: $seats';
    } else {
      return 'Trip #$id · Depart: $depart · Arrive: $arrive · Price: $price · Seats: $seats';
    }
  }

  Future<void> _onPublishLastTrip() async {
    final trip = _lastTrip;
    if (trip == null) return;
    final id = (trip['id'] ?? '').toString();
    if (id.isEmpty) return;
    if (!mounted) return;
    final l = L10n.of(context);
    setState(() => _lastTripPublished = true);
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/bus/trips/${Uri.encodeComponent(id)}/publish');
      final r = await http.post(uri, headers: await _hdr());
      if (r.statusCode < 200 || r.statusCode >= 300) {
        setState(() => _lastTripPublished = false);
        String extra = '';
        try {
          if (r.body.isNotEmpty) {
            extra = ' · ${r.body}';
          }
        } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${l.isArabic ? 'فشل نشر الرحلة' : 'Failed to publish trip'} (${r.statusCode})$extra'),
        ));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic ? 'تم نشر الرحلة' : 'Trip published'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastTripPublished = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.isArabic
            ? 'خطأ أثناء نشر الرحلة'
            : 'Error while publishing trip'),
      ));
    }
  }

  void _onModifyLastTrip() {
    final trip = _lastTrip;
    if (trip == null) return;
    try {
      final depIso =
          (trip['depart_at'] ?? trip['depart_at_iso'] ?? '').toString();
      final arrIso =
          (trip['arrive_at'] ?? trip['arrive_at_iso'] ?? '').toString();
      DateTime? depParsed;
      DateTime? arrParsed;
      if (depIso.isNotEmpty) {
        depParsed = DateTime.tryParse(depIso);
      }
      if (arrIso.isNotEmpty) {
        arrParsed = DateTime.tryParse(arrIso);
      }
      final price = trip['price_cents'];
      final seats = trip['seats_total'];
      setState(() {
        if (depParsed != null) dep = depParsed.toLocal();
        if (arrParsed != null) arr = arrParsed.toLocal();
        if (price != null) priceCtrl.text = price.toString();
        if (seats != null) seatsTotalCtrl.text = seats.toString();
      });
    } catch (_) {}
  }

  Future<void> _board() async {
    setState(() => boardOut = '...');
    try {
      final r = await http.post(
          Uri.parse('${widget.baseUrl}/bus/tickets/board'),
          headers: await _hdr(json: true),
          body: jsonEncode({'payload': payloadCtrl.text.trim()}));
      if (r.statusCode == 200) {
        try {
          final j = jsonDecode(r.body);
          if (j is Map<String, dynamic>) {
            final ok = j['ok'] == true;
            final booking = j['booking'];
            final ticket = j['ticket'];
            final trip = j['trip'];
            String seat = '';
            String status = '';
            String boardedAt = '';
            String phone = '';
            String tripId = '';
            if (ticket is Map) {
              seat = (ticket['seat_no'] ?? '').toString();
              status = (ticket['status'] ?? '').toString();
            }
            if (j['status'] != null && status.isEmpty) {
              status = j['status'].toString();
            }
            boardedAt = (j['boarded_at'] ?? '').toString();
            if (booking is Map) {
              phone = (booking['customer_phone'] ?? '').toString();
              tripId = (booking['trip_id'] ?? '').toString();
            }
            if (trip is Map && tripId.isEmpty) {
              tripId = (trip['id'] ?? '').toString();
            }
            final buf = StringBuffer();
            buf.writeln('ok: $ok');
            if (tripId.isNotEmpty) {
              buf.writeln('Trip: $tripId');
            }
            if (seat.isNotEmpty) {
              buf.writeln('Seat: $seat');
            }
            if (phone.isNotEmpty) {
              buf.writeln('Passenger: $phone');
            }
            if (status.isNotEmpty) {
              buf.writeln('Status: $status');
            }
            if (boardedAt.isNotEmpty) {
              buf.writeln('Boarded at: $boardedAt');
            }
            setState(() => boardOut = buf.toString().trim());
            return;
          }
        } catch (_) {
          // fall through to raw output
        }
      }
      setState(() => boardOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => boardOut = 'error: $e');
    }
  }

  Future<void> _loadTickets() async {
    setState(() => boardOut = '...');
    try {
      final id = bookingCtrl.text.trim();
      if (id.isEmpty) {
        setState(() => boardOut = 'enter booking id');
        return;
      }
      final r = await http.get(
          Uri.parse('${widget.baseUrl}/bus/bookings/' +
              Uri.encodeComponent(id) +
              '/tickets'),
          headers: await _hdr());
      if (r.statusCode == 200) {
        final arr = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
        setState(() {
          _tickets = arr;
          boardOut = 'tickets: ' + arr.length.toString();
        });
      } else {
        setState(() => boardOut = '${r.statusCode}: ${r.body}');
      }
    } catch (e) {
      setState(() => boardOut = 'error: $e');
    }
  }

  Future<void> _loadOperators() async {
    setState(() {
      _operatorsLoading = true;
      operatorsOut = '';
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/bus/operators');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode == 200) {
        try {
          final body = jsonDecode(r.body);
          final List<Map<String, dynamic>> list = [];
          if (body is List) {
            for (final it in body) {
              if (it is Map<String, dynamic>) {
                list.add(it);
              }
            }
          }
          setState(() {
            _operators = list;
            operatorsOut =
                list.isEmpty ? 'No operators yet.' : 'Operators: ${list.length}';
          });
        } catch (e) {
          setState(() {
            _operators = [];
            operatorsOut = 'error parsing operators: $e';
          });
        }
      } else {
        setState(() {
          _operators = [];
          operatorsOut = '${r.statusCode}: ${r.body}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _operators = [];
        operatorsOut = 'error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _operatorsLoading = false;
        });
      }
    }
  }

  Future<void> _setOperatorOnline(String opId, bool online) async {
    if (opId.isEmpty) return;
    setState(() {
      operatorsOut =
          online ? 'Setting operator online…' : 'Setting operator offline…';
    });
    try {
      final suffix = online ? 'online' : 'offline';
      final uri = Uri.parse(
        '${widget.baseUrl}/bus/operators/${Uri.encodeComponent(opId)}/$suffix',
      );
      final r = await http.post(uri, headers: await _hdr());
      setState(() {
        operatorsOut = '${r.statusCode}: ${r.body}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        operatorsOut = 'error: $e';
      });
    }
    if (mounted) {
      await _loadOperators();
    }
  }

  Future<void> _reserveSeats() async {
    final tripId = reserveTripCtrl.text.trim();
    if (tripId.isEmpty) {
      setState(() => reserveOut = 'enter trip id');
      return;
    }
    final seats = int.tryParse(reserveSeatsCtrl.text.trim()) ?? 0;
    if (seats <= 0) {
      setState(() => reserveOut = 'enter seats > 0');
      return;
    }
    setState(() => reserveOut = '...');
    try {
      final uri = Uri.parse('${widget.baseUrl}/bus/trips/' +
          Uri.encodeComponent(tripId) +
          '/book');
      final headers = await _hdr(json: true);
      headers['Idempotency-Key'] =
          'bus-reserve-${DateTime.now().millisecondsSinceEpoch}';
      final body = jsonEncode({
        'seats': seats,
        // wallet_id intentionally omitted for operator reservation
      });
      final r = await http.post(uri, headers: headers, body: body);
      setState(() => reserveOut = '${r.statusCode}: ${r.body}');
    } catch (e) {
      setState(() => reserveOut = 'error: $e');
    }
  }

  Future<void> _loadStats() async {
    final id = statsOpIdCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => statsOut = 'enter operator id');
      return;
    }
    setState(() => statsOut = '...');
    try {
      final uri = Uri.parse('${widget.baseUrl}/bus/operators/' +
          Uri.encodeComponent(id) +
          '/stats?period=$statsPeriod');
      final r = await http.get(uri, headers: await _hdr());
      if (r.statusCode != 200) {
        setState(() => statsOut = '${r.statusCode}: ${r.body}');
        return;
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final trips = j['trips'] ?? 0;
      final bookings = j['bookings'] ?? 0;
      final confirmed = j['confirmed_bookings'] ?? 0;
      final seatsSold = j['seats_sold'] ?? 0;
      final seatsTotal = j['seats_total'] ?? 0;
      final seatsBoarded = j['seats_boarded'] ?? 0;
      final revenueCents = j['revenue_cents'] ?? 0;
      final revInt = revenueCents is int
          ? revenueCents
          : int.tryParse(revenueCents.toString()) ?? 0;
      final revenue = revInt / 100.0;
      double? occ;
      int soldInt = seatsSold is int
          ? seatsSold
          : int.tryParse(seatsSold.toString()) ?? 0;
      final int totalInt = seatsTotal is int
          ? seatsTotal
          : int.tryParse(seatsTotal.toString()) ?? 0;
      if (totalInt > 0 && soldInt > 0) {
        occ = soldInt * 100.0 / totalInt;
      }
      final buf = StringBuffer();
      buf.write(
          'Trips: $trips · Bookings: $bookings (confirmed: $confirmed)\n');
      buf.write('Seats booked (app): $soldInt');
      if (totalInt > 0 && occ != null) {
        buf.write(' of $totalInt (${occ.toStringAsFixed(1)}% load)');
      }
      final boardedInt = seatsBoarded is int
          ? seatsBoarded
          : int.tryParse(seatsBoarded.toString()) ?? 0;
      buf.write('\nBoarded (via QR): $boardedInt of $soldInt');
      buf.write('\nRevenue: ${revenue.toStringAsFixed(2)} SYP');
      setState(() => statsOut = buf.toString());
    } catch (e) {
      setState(() => statsOut = 'error: $e');
    }
  }

  String _computedRouteDisplayId() {
    final op = routeOpCtrl.text.trim();
    final orig = originIdCtrl.text.trim();
    final dest = destIdCtrl.text.trim();
    if (op.isEmpty || orig.isEmpty || dest.isEmpty) {
      return '';
    }
    final d = dep;
    final y = d.year.toString().padLeft(4, '0').substring(2); // yy
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$op-$orig-$dest-$y$m$day-$hh$mm';
  }

  @override
  Widget build(BuildContext context) {
    const bg = AppBG();
    final theme = Theme.of(context);

    final l = L10n.of(context);
    final createTripBody = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l.isArabic ? 'إنشاء رحلة حافلة' : 'Create bus trip',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          l.isArabic
              ? 'اختَر المدن، المشغل والمسار، ثم أنشئ الرحلة بمواعيد وأسعار وعدد المقاعد.'
              : 'Select cities, operator and route, then create the trip with times, price and seats.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _routeOriginId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.isArabic ? 'من' : 'From',
                helperText: _cities.isEmpty
                    ? (l.isArabic
                        ? 'أنشئ مدينة أولاً في القسم أدناه'
                        : 'Create a city first below')
                    : null,
              ),
              items: _cities.isEmpty
                  ? const <DropdownMenuItem<String>>[]
                  : _buildCityItems(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _routeOriginId = v;
                  originIdCtrl.text = v;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_right_alt, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _routeDestId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l.isArabic ? 'إلى' : 'To',
                helperText: _cities.isEmpty
                    ? (l.isArabic
                        ? 'أنشئ مدينة أولاً في القسم أدناه'
                        : 'Create a city first below')
                    : null,
              ),
              items: _cities.isEmpty
                  ? const <DropdownMenuItem<String>>[]
                  : _buildCityItems(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _routeDestId = v;
                  destIdCtrl.text = v;
                });
              },
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          l.isArabic ? 'ميزات الحافلة' : 'Bus amenities',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final label in _amenityPresets)
              FilterChip(
                label: Text(label),
                selected: _selectedAmenities.contains(label),
                onSelected: (sel) {
                  setState(() {
                    if (sel) {
                      _selectedAmenities.add(label);
                    } else {
                      _selectedAmenities.remove(label);
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Builder(builder: (ctx) {
          final rid = _computedRouteDisplayId();
          if (rid.isEmpty) return const SizedBox.shrink();
          return Text(
            '${l.isArabic ? 'معرّف المسار المقترح' : 'Suggested route id'}: $rid',
            style: theme.textTheme.bodySmall,
          );
        }),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(labelText: 'Price (SYP)'),
                  keyboardType: TextInputType.number)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: WaterButton(
            label:
                'Depart: ${"${dep.year}-${dep.month}-${dep.day} ${dep.hour}:${dep.minute.toString().padLeft(2, '0')}"}',
            onTap: _pickDep,
            tint: Tokens.colorBus,
          )),
          const SizedBox(width: 8),
          Expanded(
              child: WaterButton(
            label:
                'Arrive: ${"${arr.year}-${arr.month}-${arr.day} ${arr.hour}:${arr.minute.toString().padLeft(2, '0')}"}',
            onTap: _pickArr,
            tint: Tokens.colorBus,
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: seatsTotalCtrl,
                  decoration: const InputDecoration(labelText: 'Seats total'),
                  keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(
              child: WaterButton(
            label: 'Create Trip',
            onTap: _createTrip,
            tint: Tokens.colorBus,
          )),
        ]),
        const SizedBox(height: 4),
        if (tripOut.isNotEmpty) SelectableText(tripOut),
        const SizedBox(height: 12),
        const Divider(height: 24),
        const SizedBox(height: 16),
        Text(l.isArabic ? 'المدن' : 'Cities',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: cityNameCtrl,
                  decoration: const InputDecoration(labelText: 'City name'))),
          const SizedBox(width: 8),
          Expanded(
              child: TextField(
                  controller: countryCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Country (opt)'))),
        ]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: WaterButton(
            label: l.isArabic ? 'إنشاء مدينة' : 'Create City',
            onTap: _createCity,
            tint: Tokens.colorBus,
          ),
        ),
        const SizedBox(height: 4),
        if (cityOut.isNotEmpty) SelectableText(cityOut),
        if (_lastTrip != null) ...[
          const SizedBox(height: 12),
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.isArabic ? 'آخر رحلة تم إنشاؤها' : 'Last created trip',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(_tripSummaryText(_lastTrip!, l)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: WaterButton(
                        label: _lastTripPublished
                            ? (l.isArabic ? 'تم النشر' : 'Trip published')
                            : (l.isArabic ? 'نشر الرحلة' : 'Publish trip'),
                        onTap: _onPublishLastTrip,
                        tint: Tokens.colorBus,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _onModifyLastTrip,
                        child:
                            Text(l.isArabic ? 'تعديل الرحلة' : 'Modify trip'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ],
    );

    final boardingBody = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Boarding (check-in)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Scan passenger QR tickets at the station to board them.',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: WaterButton(
                label: l.isArabic ? 'مسح رمز QR للتسجيل' : 'Scan QR to board',
                onTap: _scanTicket,
                tint: Tokens.colorBus,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (boardOut.isNotEmpty) SelectableText(boardOut),
      ],
    );

    final ticketsBody = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Tickets & stats',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
            'Lookup tickets for a booking and see basic operator stats (today).',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        if (_isAdminOrSuper) ...[
          const Text('Operators',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'View all bus operators and toggle their online status.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: WaterButton(
              label:
                  _operatorsLoading ? 'Loading operators…' : 'List operators',
              onTap: () {
                if (_operatorsLoading) return;
                _loadOperators();
              },
              tint: Tokens.colorBus,
            ),
          ),
          const SizedBox(height: 4),
          if (operatorsOut.isNotEmpty) SelectableText(operatorsOut),
          const SizedBox(height: 8),
          if (_operators.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _operators.map((op) {
                final id = (op['id'] ?? '').toString();
                final name = (op['name'] ?? '').toString();
                final isOnlineRaw = op['is_online'];
                final isOnline = isOnlineRaw is bool
                    ? isOnlineRaw
                    : (isOnlineRaw is num ? isOnlineRaw != 0 : false);
                final statusText = isOnline ? 'Online' : 'Offline';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '$id  ·  ${name.isEmpty ? "(no name)" : name}  ·  $statusText',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => _setOperatorOnline(id, true),
                        child: const Text('Online'),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => _setOperatorOnline(id, false),
                        child: const Text('Offline'),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 16),
        ],
        const Text('Tickets (QR)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: bookingCtrl,
                  decoration: const InputDecoration(labelText: 'Booking ID'))),
          const SizedBox(width: 8),
          Expanded(
              child: WaterButton(
                  label: 'Load Tickets',
                  onTap: _loadTickets,
                  tint: Tokens.colorBus)),
        ]),
        const SizedBox(height: 8),
        if (boardOut.isNotEmpty) SelectableText(boardOut),
        const SizedBox(height: 8),
        if (_tickets.isNotEmpty)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final tk in _tickets)
                SizedBox(
                  width: 160,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.white24),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.white,
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Image.network(
                            Uri.parse('${widget.baseUrl}/qr.png').replace(
                                queryParameters: {
                                  'data': (tk['payload'] ?? '').toString()
                                }).toString(),
                            height: 140,
                            width: 140,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Seat: ' + ((tk['seat_no'] ?? '').toString()),
                            style: const TextStyle(fontSize: 12)),
                        Text((tk['id'] ?? '').toString(),
                            style: const TextStyle(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ]),
                ),
            ],
          ),
        const SizedBox(height: 24),
        const Text('Reservations (operator)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Reserve seats for a specific trip (offline bookings).',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: reserveTripCtrl,
                  decoration: const InputDecoration(labelText: 'Trip ID'))),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: TextField(
              controller: reserveSeatsCtrl,
              decoration: const InputDecoration(labelText: 'Seats'),
              keyboardType: TextInputType.number,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: WaterButton(
                  label: 'Reserve seats',
                  onTap: _reserveSeats,
                  tint: Tokens.colorBus)),
        ]),
        const SizedBox(height: 4),
        if (reserveOut.isNotEmpty) SelectableText(reserveOut),
        const SizedBox(height: 24),
        const Text('Operator stats (today)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Operator ID',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                    color: Colors.white.withValues(alpha: .04),
                  ),
                  child: Text(
                    statsOpIdCtrl.text.trim().isEmpty
                        ? '(not set)'
                        : statsOpIdCtrl.text.trim(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: WaterButton(
                  label: 'Load stats',
                  onTap: _loadStats,
                  tint: Tokens.colorBus)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(
              label: const Text('Today'),
              selected: statsPeriod == 'today',
              onSelected: (_) {
                setState(() => statsPeriod = 'today');
                if (statsOpIdCtrl.text.trim().isNotEmpty) _loadStats();
              }),
          const SizedBox(width: 6),
          ChoiceChip(
              label: const Text('7 days'),
              selected: statsPeriod == '7d',
              onSelected: (_) {
                setState(() => statsPeriod = '7d');
                if (statsOpIdCtrl.text.trim().isNotEmpty) _loadStats();
              }),
          const SizedBox(width: 6),
          ChoiceChip(
              label: const Text('30 days'),
              selected: statsPeriod == '30d',
              onSelected: (_) {
                setState(() => statsPeriod = '30d');
                if (statsOpIdCtrl.text.trim().isNotEmpty) _loadStats();
              }),
        ]),
        const SizedBox(height: 8),
        if (statsOut.isNotEmpty) SelectableText(statsOut),
      ],
    );

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bus · Operator'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Create Trip'),
            Tab(text: 'Boarding'),
            Tab(text: 'Tickets & Stats'),
          ]),
          backgroundColor: Colors.transparent,
        ),
        extendBodyBehindAppBar: true,
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            bg,
            Positioned.fill(
              child: SafeArea(
                child: GlassPanel(
                  padding: const EdgeInsets.all(16),
                  child: TabBarView(children: [
                    createTripBody,
                    boardingBody,
                    ticketsBody,
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
