part of '../main.dart';

class SuperApp extends StatelessWidget {
  const SuperApp({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // Debug log to verify HomePage from this repo is running on device.
    debugPrint('HOME_PAGE_BUILD: Shamell');
    // Shamell-like light theme: flat surfaces + Shamell green accent.
    const shamellGreen = ShamellPalette.green;
    final baseBtnShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: shamellGreen,
        secondary: shamellGreen,
        surface: Colors.white,
        onSurface: Color(0xFF111111),
      ),
      scaffoldBackgroundColor: ShamellPalette.background,
      dividerColor: ShamellPalette.divider,
      dividerTheme: const DividerThemeData(
        color: ShamellPalette.divider,
        thickness: 0.5,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: shamellGreen,
        unselectedItemColor: Color(0xFF8A8A8A),
        elevation: 0.5,
      ),
      textTheme: GoogleFonts.interTextTheme().apply(
          bodyColor: const Color(0xFF111111),
          displayColor: const Color(0xFF111111)),
      iconTheme: const IconThemeData(color: Color(0xFF111111)),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: shamellGreen,
        foregroundColor: Colors.white,
        shape: baseBtnShape,
        minimumSize: const Size.fromHeight(48),
      )),
      filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(shamellGreen),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        shape: WidgetStatePropertyAll(baseBtnShape),
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
        side:
            const WidgetStatePropertyAll(BorderSide(color: Color(0xFFDDDDDD))),
        foregroundColor: const WidgetStatePropertyAll(Color(0xFF111111)),
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        shape: WidgetStatePropertyAll(baseBtnShape),
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1.0)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1.0)),
        focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide(color: shamellGreen, width: 2.0)),
        labelStyle: const TextStyle(color: Color(0xFF555555)),
        hintStyle: const TextStyle(color: Color(0xFF999999)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: ShamellPalette.divider)),
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: .05),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.white,
        titleTextStyle: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF111111)),
        foregroundColor: Color(0xFF111111),
        iconTheme: IconThemeData(color: Color(0xFF111111)),
        systemOverlayStyle: SystemUiOverlayStyle(
            statusBarBrightness: Brightness.light,
            statusBarIconBrightness: Brightness.dark,
            statusBarColor: Colors.transparent),
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: shamellGreen,
        secondary: shamellGreen,
        surface: Color(0xFF1C1C1E),
        onSurface: Color(0xFFEDEDED),
      ),
      scaffoldBackgroundColor: const Color(0xFF0F0F10),
      dividerColor: const Color(0xFF2C2C2E),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF2C2C2E),
        thickness: 0.5,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1C1C1E),
        selectedItemColor: shamellGreen,
        unselectedItemColor: Color(0xFF9A9A9A),
        elevation: 0.5,
      ),
      textTheme: GoogleFonts.interTextTheme(
        ThemeData(brightness: Brightness.dark).textTheme,
      ).apply(
          bodyColor: const Color(0xFFEDEDED),
          displayColor: const Color(0xFFEDEDED)),
      iconTheme: const IconThemeData(color: Color(0xFFEDEDED)),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: shamellGreen,
          foregroundColor: Colors.white,
          shape: baseBtnShape,
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: const WidgetStatePropertyAll(shamellGreen),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(baseBtnShape),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(
            BorderSide(color: Color(0xFF3A3A3C)),
          ),
          foregroundColor: const WidgetStatePropertyAll(Color(0xFFEDEDED)),
          backgroundColor: const WidgetStatePropertyAll(Color(0xFF1C1C1E)),
          shape: WidgetStatePropertyAll(baseBtnShape),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF3A3A3C), width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF3A3A3C), width: 1.0),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: shamellGreen, width: 2.0),
        ),
        labelStyle: const TextStyle(color: Color(0xFFB0B0B0)),
        hintStyle: const TextStyle(color: Color(0xFF8A8A8A)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF2C2C2E)),
        ),
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: .35),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1C1C1E),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Color(0xFF1C1C1E),
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: Color(0xFFEDEDED),
        ),
        foregroundColor: Color(0xFFEDEDED),
        iconTheme: IconThemeData(color: Color(0xFFEDEDED)),
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
            final effectiveScale =
                (mq.textScaler.scale(1.0) * uiTextScale.value)
                    .clamp(0.85, 1.45)
                    .toDouble();
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(effectiveScale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          title: l.appTitle,
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
          home: const LoginGate(),
        );
      },
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
  try {
    final sp = await SharedPreferences.getInstance();
    final base = (sp.getString('base_url') ?? '').trim();
    if (base.isNotEmpty) {
      return await getSessionCookieHeader(base);
    }
  } catch (_) {}
  final fallbackBase = const String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
  return await getSessionCookieHeader(fallbackBase);
}

Future<void> _clearCookie() async {
  await clearSessionCookie();
}

Future<Map<String, String>> _hdr({bool json = false, String? baseUrl}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final host = Uri.tryParse((baseUrl ?? '').trim())?.host.toLowerCase();
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
    // Local dev shortcut: edge-attested client IP is normally injected by
    // reverse proxy; direct localhost calls provide an explicit loopback IP.
    h['x-shamell-client-ip'] = '127.0.0.1';
  }
  final b = (baseUrl ?? '').trim();
  if (b.isNotEmpty) {
    final c = await getSessionCookieHeader(b);
    if (c != null && c.isNotEmpty) {
      // Best practice: use real Cookie header so prod/staging can disable
      // header-based session auth without breaking native clients.
      h['cookie'] = c;
    }
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
  bool _checking = true;
  bool _unlocked = false;
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cookie = await _getCookie();
    final hasSession = cookie != null && cookie.isNotEmpty;
    bool unlocked = false;
    if (hasSession) {
      unlocked = await _authenticateWithBiometrics();
      if (unlocked) {
        // Best-effort: provision biometric re-login for future logins.
        try {
          final sp = await SharedPreferences.getInstance();
          var base = (sp.getString('base_url') ?? '').trim();
          if (base.isEmpty) {
            base = const String.fromEnvironment(
              'BASE_URL',
              defaultValue: 'http://localhost:8080',
            );
          }
          unawaited(ensureBiometricLoginEnrolled(base));
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _c = cookie;
      _unlocked = unlocked;
      _checking = false;
    });
  }

  Future<bool> _authenticateWithBiometrics() async {
    if (kIsWeb) return false;
    try {
      final auth = LocalAuthentication();
      final canCheck =
          await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!canCheck) return false;
      const reason = 'Authenticate to unlock Shamell';
      final didAuth = await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
        ),
      );
      return didAuth;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final hasSession = _c != null && _c!.isNotEmpty;
    if (hasSession && _unlocked && currentAppMode != AppMode.auto) {
      return const HomePage();
    }
    return LoginPage(hasSession: hasSession);
  }
}

class LoginPage extends StatefulWidget {
  final bool hasSession;
  const LoginPage({super.key, this.hasSession = false});
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
  late final TextEditingController _deviceLabelCtrl;
  String out = '';
  AppMode _loginMode = AppMode.user;
  bool _driverLogin = false;
  bool _showAdvanced = false;
  bool _busy = false;
  bool _hasSessionCookie = false;
  bool _biometricsAvailable = false;
  bool _hasBiometricEnrollment = false;

  // Linking additional devices: strictly via Device-Login QR (no OTP fallback).
  String? _deviceLoginToken;
  String _deviceLoginLabel = '';
  DateTime? _deviceLoginStartedAt;
  bool _deviceLoginStarting = false;
  bool _deviceLoginRedeeming = false;
  Timer? _deviceLoginPollTimer;
  int _deviceLoginPollAttempts = 0;
  @override
  void initState() {
    super.initState();
    _deviceLabelCtrl = TextEditingController(text: _defaultDeviceLabel());
    _loadBase();
  }

  @override
  void dispose() {
    _deviceLoginPollTimer?.cancel();
    baseCtrl.dispose();
    _deviceLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final b = sp.getString('base_url');
      if (b != null && b.isNotEmpty) {
        final v = b.trim();
        // Ignore legacy dev defaults so the new
        // default BFF port (8080) is used automatically.
        if (!(v.contains('localhost:5003') || v.contains('127.0.0.1:5003'))) {
          baseCtrl.text = v;
        }
      }
    } catch (_) {}
    await _refreshBiometricState();
  }

  Future<void> _refreshBiometricState() async {
    bool bioAvailable = false;
    if (!kIsWeb) {
      try {
        final auth = LocalAuthentication();
        bioAvailable =
            await auth.canCheckBiometrics || await auth.isDeviceSupported();
      } catch (_) {
        bioAvailable = false;
      }
    }
    final tok = await getBiometricLoginTokenForBaseUrl(baseCtrl.text.trim());
    final enrolled = tok != null && tok.isNotEmpty;
    if (!mounted) return;
    setState(() {
      _biometricsAvailable = bioAvailable;
      _hasBiometricEnrollment = enrolled;
    });
  }

  String _defaultDeviceLabel() {
    if (kIsWeb) return 'Web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      case TargetPlatform.fuchsia:
        return 'Device';
    }
  }

  String? _deviceLoginQrPayload() {
    final token = (_deviceLoginToken ?? '').trim();
    if (token.isEmpty) return null;
    final qp = <String, String>{'token': token};
    final label = _deviceLoginLabel.trim();
    if (label.isNotEmpty) qp['label'] = label;
    return Uri(scheme: 'shamell', host: 'device_login', queryParameters: qp)
        .toString();
  }

  void _stopDeviceLoginRedeemPoll() {
    _deviceLoginPollTimer?.cancel();
    _deviceLoginPollTimer = null;
    _deviceLoginPollAttempts = 0;
  }

  void _startDeviceLoginRedeemPoll() {
    _stopDeviceLoginRedeemPoll();
    // Respect server-side rate limits:
    // - default redeem max per token is 30/300s -> keep well below.
    const interval = Duration(seconds: 15);
    const maxAttempts = 20; // 20 * 15s = 300s (matches default TTL)
    _deviceLoginPollTimer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      _deviceLoginPollAttempts++;
      if (_deviceLoginPollAttempts > maxAttempts) {
        _stopDeviceLoginRedeemPoll();
        setState(() {
          out = L10n.of(context).isArabic
              ? 'انتهت مهلة تسجيل الدخول. ابدأ رمز QR جديد.'
              : 'Device login timed out. Start a new QR.';
        });
        return;
      }
      unawaited(_tryRedeemDeviceLogin(fromPoll: true));
    });
  }

  String _extractApiDetail(String rawBody) {
    final text = rawBody.trim();
    if (text.isEmpty) return '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is String) return detail.trim();
      }
    } catch (_) {}
    return text;
  }

  Future<void> _startDeviceLoginQr() async {
    void setOutSafe(String message) {
      if (!mounted) return;
      setState(() => out = message);
    }

    final l = L10n.of(context);
    if (_deviceLoginStarting || _deviceLoginRedeeming) return;
    final base = baseCtrl.text.trim();
    if (base.isEmpty) {
      setOutSafe(l.isArabic ? 'عنوان الخادم مطلوب.' : 'Server URL is required.');
      return;
    }
    if (!isSecureApiBaseUrl(base)) {
      setOutSafe(l.isArabic
          ? 'يجب استخدام HTTPS (باستثناء localhost).'
          : 'HTTPS is required (except localhost).');
      return;
    }
    setState(() {
      _deviceLoginStarting = true;
      out = '';
    });

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('base_url', base);
    } catch (_) {}

    final labelIn = _deviceLabelCtrl.text.trim();
    final deviceId = await getOrCreateStableDeviceId();
    final uri = Uri.parse('${base.trim()}/auth/device_login/start');
    try {
      final resp = await http.post(
        uri,
        headers: await _hdr(json: true, baseUrl: base),
        body: jsonEncode(<String, Object?>{
          'label': labelIn.isEmpty ? null : labelIn,
          'device_id': deviceId.trim().isEmpty ? null : deviceId.trim(),
        }),
      );
      if (resp.statusCode != 200) {
        setOutSafe(sanitizeHttpError(
          statusCode: resp.statusCode,
          rawBody: resp.body,
          isArabic: l.isArabic,
        ));
        if (mounted) setState(() => _deviceLoginStarting = false);
        return;
      }
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) {
        setOutSafe(l.isArabic
            ? 'استجابة غير صالحة من الخادم.'
            : 'Invalid server response.');
        if (mounted) setState(() => _deviceLoginStarting = false);
        return;
      }
      final token = (decoded['token'] ?? '').toString().trim().toLowerCase();
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
        setOutSafe(l.isArabic
            ? 'رمز تسجيل الدخول غير صالح.'
            : 'Invalid device-login token.');
        if (mounted) setState(() => _deviceLoginStarting = false);
        return;
      }
      final labelOut = (decoded['label'] ?? labelIn).toString().trim();
      _stopDeviceLoginRedeemPoll();
      if (!mounted) return;
      setState(() {
        _deviceLoginToken = token;
        _deviceLoginLabel = labelOut;
        _deviceLoginStartedAt = DateTime.now();
        _deviceLoginStarting = false;
      });
      _startDeviceLoginRedeemPoll();
    } catch (e) {
      setOutSafe(sanitizeExceptionForUi(error: e, isArabic: l.isArabic));
      if (mounted) setState(() => _deviceLoginStarting = false);
    }
  }

  Future<void> _tryRedeemDeviceLogin({bool fromPoll = false}) async {
    void setOutSafe(String message) {
      if (!mounted) return;
      setState(() => out = message);
    }

    final l = L10n.of(context);
    if (_deviceLoginRedeeming) return;
    final base = baseCtrl.text.trim();
    final token = (_deviceLoginToken ?? '').trim().toLowerCase();
    if (base.isEmpty || token.isEmpty) return;
    if (!isSecureApiBaseUrl(base)) {
      if (!fromPoll) {
        setOutSafe(l.isArabic
            ? 'يجب استخدام HTTPS (باستثناء localhost).'
            : 'HTTPS is required (except localhost).');
      }
      return;
    }
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(token)) {
      if (!fromPoll) {
        setOutSafe(l.isArabic
            ? 'رمز تسجيل الدخول غير صالح.'
            : 'Invalid device-login token.');
      }
      return;
    }

    setState(() {
      _deviceLoginRedeeming = true;
      if (!fromPoll) {
        out = l.isArabic ? 'جارٍ التحقق…' : 'Checking…';
      }
    });

    final deviceId = await getOrCreateStableDeviceId();
    final uri = Uri.parse('${base.trim()}/auth/device_login/redeem');
    try {
      final resp = await http.post(
        uri,
        headers: await _hdr(json: true, baseUrl: base),
        body: jsonEncode(<String, Object?>{
          'token': token,
          'device_id': deviceId.trim().isEmpty ? null : deviceId.trim(),
        }),
      );

      if (resp.statusCode == 200) {
        final sess = extractSessionTokenFromSetCookieHeader(
          resp.headers['set-cookie'],
        );
        if (sess == null || sess.isEmpty) {
          setOutSafe(l.isArabic
              ? 'تعذّر استلام جلسة من الخادم.'
              : 'Could not obtain a server session.');
          if (mounted) setState(() => _deviceLoginRedeeming = false);
          return;
        }
        await setSessionTokenForBaseUrl(base, sess);
        _stopDeviceLoginRedeemPoll();

        // Best-effort: enroll biometric re-login now that we have a session.
        await ensureBiometricLoginEnrolled(base);
        await _refreshBiometricState();

        if (!mounted) return;
        setState(() {
          _hasSessionCookie = true;
          _deviceLoginToken = null;
          _deviceLoginLabel = '';
          _deviceLoginStartedAt = null;
          _deviceLoginRedeeming = false;
          out = l.isArabic
              ? 'تم ربط الجهاز. أكمل تسجيل الدخول بالبصمة.'
              : 'Device linked. Continue with biometrics.';
        });
        return;
      }

      final detail = _extractApiDetail(resp.body).toLowerCase();
      if (resp.statusCode == 400 && detail.contains('not approved')) {
        // Expected while waiting for scan/approval. Keep polling quietly.
        if (!fromPoll) {
          setOutSafe(l.isArabic
              ? 'بانتظار المسح والموافقة على جهاز آخر…'
              : 'Waiting for scan and approval on another device…');
        }
        if (mounted) setState(() => _deviceLoginRedeeming = false);
        return;
      }
      if (resp.statusCode == 400 && detail.contains('expired')) {
        _stopDeviceLoginRedeemPoll();
        if (!fromPoll) {
          setOutSafe(l.isArabic
              ? 'انتهت صلاحية رمز QR. ابدأ رمزاً جديداً.'
              : 'QR expired. Start a new one.');
        }
        if (mounted) {
          setState(() {
            _deviceLoginToken = null;
            _deviceLoginLabel = '';
            _deviceLoginStartedAt = null;
            _deviceLoginRedeeming = false;
          });
        }
        return;
      }
      if (resp.statusCode == 404 && detail.contains('not found')) {
        _stopDeviceLoginRedeemPoll();
        if (!fromPoll) {
          setOutSafe(l.isArabic
              ? 'رمز تسجيل الدخول غير موجود. ابدأ رمزاً جديداً.'
              : 'Device-login challenge not found. Start a new one.');
        }
        if (mounted) {
          setState(() {
            _deviceLoginToken = null;
            _deviceLoginLabel = '';
            _deviceLoginStartedAt = null;
            _deviceLoginRedeeming = false;
          });
        }
        return;
      }

      if (!fromPoll) {
        setOutSafe(sanitizeHttpError(
          statusCode: resp.statusCode,
          rawBody: resp.body,
          isArabic: l.isArabic,
        ));
      }
      if (mounted) setState(() => _deviceLoginRedeeming = false);
    } catch (e) {
      if (!fromPoll) {
        setOutSafe(sanitizeExceptionForUi(error: e, isArabic: l.isArabic));
      }
      if (mounted) setState(() => _deviceLoginRedeeming = false);
    }
  }

  Future<void> _createNewAccount() async {
    void setOutSafe(String message) {
      if (!mounted) return;
      setState(() => out = message);
    }

    final l = L10n.of(context);
    if (_busy) return;
    final base = baseCtrl.text.trim();
    if (base.isEmpty) {
      setOutSafe(l.isArabic ? 'عنوان الخادم مطلوب.' : 'Server URL is required.');
      return;
    }
    if (!isSecureApiBaseUrl(base)) {
      setOutSafe(l.isArabic
          ? 'يجب استخدام HTTPS (باستثناء localhost).'
          : 'HTTPS is required (except localhost).');
      return;
    }
    if (kIsWeb) {
      setOutSafe(l.isArabic
          ? 'إنشاء حساب جديد غير متاح على الويب.'
          : 'Creating a new account is not available on web.');
      return;
    }
    final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!isMobilePlatform) {
      setOutSafe(l.isArabic
          ? 'إنشاء معرّف جديد متاح فقط على iOS/Android. اربط هذا الجهاز عبر رمز QR.'
          : 'Creating a new ID is only supported on iOS/Android. Link this device via a Device‑Login QR.');
      return;
    }
    if (!_biometricsAvailable) {
      setOutSafe(l.loginBiometricRequired);
      return;
    }

    setState(() {
      _busy = true;
      out = l.isArabic ? 'جارٍ إنشاء معرّف جديد…' : 'Creating a new Shamell ID…';
    });

    try {
      final auth = LocalAuthentication();
      const reason = 'Authenticate to create your Shamell ID';
      final didAuth = await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
        ),
      );
      if (!didAuth) {
        setOutSafe(l.loginAuthCancelled);
        if (mounted) setState(() => _busy = false);
        return;
      }
    } catch (_) {
      setOutSafe(l.loginBiometricFailed);
      if (mounted) setState(() => _busy = false);
      return;
    }

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('base_url', base);
    } catch (_) {}

    final deviceId = await getOrCreateStableDeviceId();
    final didTrim = deviceId.trim();
    String? powSolution;
    String? challengeToken;
    String? iosDeviceCheckTokenB64;
    String? androidPlayIntegrityToken;

    // Best practice: for public account creation, require an attestation layer.
    // Server policy may enforce:
    // - PoW (cheap, anti-abuse)
    // - hardware attestation (stronger anti-fraud / anti-bot)
    final challengeUri = Uri.parse('${base.trim()}/auth/account/create/challenge');
    try {
      Future<bool> prepareAttestation() async {
        powSolution = null;
        challengeToken = null;
        iosDeviceCheckTokenB64 = null;
        androidPlayIntegrityToken = null;

        final chResp = await http.post(
          challengeUri,
          headers: await _hdr(json: true, baseUrl: base),
          body: jsonEncode(<String, Object?>{
            'device_id': didTrim.isEmpty ? null : didTrim,
          }),
        );
        if (chResp.statusCode == 404) {
          // Legacy dev servers may not have attestation endpoints.
          return true;
        }
        if (chResp.statusCode != 200) {
          setOutSafe(sanitizeHttpError(
            statusCode: chResp.statusCode,
            rawBody: chResp.body,
            isArabic: l.isArabic,
          ));
          return false;
        }

        final decoded = jsonDecode(chResp.body);
        if (decoded is! Map) {
          setOutSafe(l.isArabic
              ? 'استجابة غير صالحة من الخادم.'
              : 'Invalid server response.');
          return false;
        }

        final tok = (decoded['challenge_token'] ?? decoded['token'] ?? '')
            .toString()
            .trim();
        if (tok.isNotEmpty) {
          challengeToken = tok;
        }

        final hwEnabled = decoded['hw_attestation_enabled'] == true;
        final hwRequired = decoded['hw_attestation_required'] == true;
        final hwNonceB64 =
            (decoded['hw_attestation_nonce_b64'] ?? '').toString().trim();

        if (hwEnabled) {
          if (!mounted) return false;
          setState(() {
            out = l.isArabic ? 'جارٍ التحقق من الجهاز…' : 'Attesting device…';
          });

          // Each platform returns its own token; others return null.
          iosDeviceCheckTokenB64 =
              await HardwareAttestation.tryGetAppleDeviceCheckTokenB64();
          androidPlayIntegrityToken =
              await HardwareAttestation.tryGetPlayIntegrityToken(
            nonceB64: hwNonceB64,
          );

          final ok = (iosDeviceCheckTokenB64 != null &&
                  iosDeviceCheckTokenB64!.trim().isNotEmpty) ||
              (androidPlayIntegrityToken != null &&
                  androidPlayIntegrityToken!.trim().isNotEmpty);
          if (!ok && hwRequired) {
            setOutSafe(l.isArabic
                ? 'تعذّر إجراء التحقق من الجهاز.'
                : 'Device attestation failed.');
            return false;
          }
        }

        final powEnabled = decoded['enabled'] == true;
        if (powEnabled) {
          final token = (decoded['token'] ?? '').toString().trim();
          final nonce = (decoded['nonce'] ?? '').toString().trim();
          final diffRaw = decoded['difficulty_bits'];
          final diffBits = diffRaw is num
              ? diffRaw.toInt()
              : int.tryParse((diffRaw ?? '').toString()) ?? -1;
          if (token.isEmpty || nonce.isEmpty || diffBits < 0) {
            setOutSafe(l.isArabic
                ? 'فشل إنشاء التحقق. حاول مرة أخرى.'
                : 'Failed to start attestation. Try again.');
            return false;
          }
          // Keep compatibility: if server only returns `token` when PoW is enabled,
          // treat it as the challenge token.
          if (challengeToken == null || challengeToken!.trim().isEmpty) {
            challengeToken = token;
          }

          if (!mounted) return false;
          setState(() {
            out = l.isArabic ? 'جارٍ التحقق من الجهاز…' : 'Solving attestation…';
          });

          final sol = await compute(
            shamellSolveAccountCreatePow,
            <String, Object?>{
              'nonce': nonce,
              'device_id': didTrim,
              'difficulty_bits': diffBits,
              'max_millis': 15000,
              'max_iters': 50000000,
            },
          );
          if (sol == null || sol.trim().isEmpty) {
            setOutSafe(l.isArabic
                ? 'تعذّر حل التحقق. حاول مرة أخرى.'
                : 'Could not solve attestation. Try again.');
            return false;
          }
          powSolution = sol.trim();
        }

        return true;
      }

      final ok = await prepareAttestation();
      if (!ok) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      Future<http.Response> doCreate() async {
        final uri = Uri.parse('${base.trim()}/auth/account/create');
        return http.post(
          uri,
          headers: await _hdr(json: true, baseUrl: base),
          body: jsonEncode(<String, Object?>{
            'device_id': didTrim.isEmpty ? null : didTrim,
            if (challengeToken != null) 'challenge_token': challengeToken,
            if (challengeToken != null) 'pow_token': challengeToken,
            if (powSolution != null) 'pow_solution': powSolution,
            if (iosDeviceCheckTokenB64 != null)
              'ios_devicecheck_token_b64': iosDeviceCheckTokenB64,
            if (androidPlayIntegrityToken != null)
              'android_play_integrity_token': androidPlayIntegrityToken,
          }),
        );
      }

      var resp = await doCreate();
      if (resp.statusCode == 401) {
        final detail = _extractApiDetail(resp.body).toLowerCase();
        if (detail.contains('attestation required')) {
          // One retry: refresh challenge in case it expired or was invalidated.
          final ok2 = await prepareAttestation();
          if (ok2) {
            resp = await doCreate();
          }
        }
      }

      if (resp.statusCode != 200) {
        setOutSafe(sanitizeHttpError(
          statusCode: resp.statusCode,
          rawBody: resp.body,
          isArabic: l.isArabic,
        ));
        if (mounted) setState(() => _busy = false);
        return;
      }

      final sess = extractSessionTokenFromSetCookieHeader(resp.headers['set-cookie']);
      if (sess == null || sess.isEmpty) {
        setOutSafe(l.isArabic
            ? 'تعذّر استلام جلسة من الخادم.'
            : 'Could not obtain a server session.');
        if (mounted) setState(() => _busy = false);
        return;
      }
      await setSessionTokenForBaseUrl(base, sess);

      // Stop any pending device-login polling; this device is now provisioned.
      _stopDeviceLoginRedeemPoll();
      _deviceLoginToken = null;
      _deviceLoginLabel = '';
      _deviceLoginStartedAt = null;

      // Best-effort: enroll biometric re-login now that we have a session.
      await ensureBiometricLoginEnrolled(base);
      await _refreshBiometricState();

      String shamellId = '';
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map) {
          shamellId = (decoded['shamell_id'] ?? '').toString().trim();
        }
      } catch (_) {}

      if (shamellId.isNotEmpty) {
        setOutSafe(l.isArabic
            ? 'تم إنشاء معرّف Shamell: $shamellId'
            : 'Created Shamell ID: $shamellId');
      }

      await _handlePostLoginNavigation();
      if (!mounted) return;
      setState(() {
        _hasSessionCookie = true;
        _busy = false;
      });
    } catch (e) {
      setOutSafe(sanitizeExceptionForUi(error: e, isArabic: l.isArabic));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithBiometrics() async {
    void setOutSafe(String message) {
      if (!mounted) return;
      setState(() => out = message);
    }

    final l = L10n.of(context);
    if (_busy) return;
    setState(() {
      _busy = true;
      out = l.loginAuthenticating;
    });

    final base = baseCtrl.text.trim();
    if (!isSecureApiBaseUrl(base)) {
      setOutSafe(l.isArabic
          ? 'يجب استخدام HTTPS (باستثناء localhost).'
          : 'HTTPS is required (except localhost).');
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (kIsWeb) {
      setOutSafe(l.loginBiometricWebUnavailable);
      if (mounted) setState(() => _busy = false);
      return;
    }

    if (!_biometricsAvailable) {
      setOutSafe(l.loginBiometricRequired);
      if (mounted) setState(() => _busy = false);
      return;
    }

    try {
      final auth = LocalAuthentication();
      const reason = 'Authenticate to unlock Shamell';
      final didAuth = await auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
        ),
      );
      if (!didAuth) {
        setOutSafe(l.loginAuthCancelled);
        if (mounted) setState(() => _busy = false);
        return;
      }
    } catch (_) {
      setOutSafe(l.loginBiometricFailed);
      if (mounted) setState(() => _busy = false);
      return;
    }

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('base_url', base);
    } catch (_) {}

    // Ensure a server session exists. If this device has no active session
    // cookie, fall back to biometric token sign-in.
    final existingCookie = await getSessionCookieHeader(base);
    final hasSession = existingCookie != null && existingCookie.isNotEmpty;
    if (!hasSession) {
      final ok = await biometricSignIn(base);
      if (!ok) {
        setOutSafe(l.loginDeviceNotEnrolled);
        await _refreshBiometricState();
        if (mounted) setState(() => _busy = false);
        return;
      }
    }

    // Best-effort: keep an enrollment token for future sign-ins.
    await ensureBiometricLoginEnrolled(base);
    await _refreshBiometricState();

    await _handlePostLoginNavigation();
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _handlePostLoginNavigation() async {
    final l = L10n.of(context);
    final base = baseCtrl.text.trim();
    Map<String, dynamic>? snapshot;
    List<String> roles = const <String>[];
    List<String> opDomains = const <String>[];
    bool isSuper = false;
    bool isAdmin = false;

    Future<bool> _loadSnapshot() async {
      if (snapshot != null) return true;
      try {
        final uri = Uri.parse('$base/me/home_snapshot');
        final r = await http.get(
          uri,
          headers: await _hdr(baseUrl: baseCtrl.text.trim()),
        );
        if (r.statusCode == 404) {
          // Legacy BFF without /me/home_snapshot.
          return false;
        }
        if (r.statusCode != 200) {
          setState(() => out = sanitizeHttpError(
                statusCode: r.statusCode,
                rawBody: r.body,
                isArabic: l.isArabic,
              ));
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
        isSuper = (body['is_superadmin'] ?? false) == true;
        isAdmin = (body['is_admin'] ?? false) == true ||
            isSuper ||
            roles.contains('admin');
        return true;
      } catch (e) {
        setState(() => out = sanitizeExceptionForUi(
              error: e,
              isArabic: l.isArabic,
            ));
        await _clearCookie();
        return false;
      }
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
            'This account is not registered as a driver. Please contact an admin.');
        await _clearCookie();
        return;
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => OperatorDashboardPage(base)),
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
              'This account is not registered as an operator. Please contact an admin.');
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
              'This account is not registered as an admin. Please contact a superadmin.');
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
    // On some Flutter Web setups, Navigator may not have an
    // active route to replace yet, so we use push instead of
    // pushReplacement to avoid assertion failures.
    Navigator.of(context).push(
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
    const allowAdvancedRelease = bool.fromEnvironment(
      'SHAMELL_ADVANCED_LOGIN_RELEASE',
      defaultValue: false,
    );
    final allowAdvanced = !kReleaseMode || allowAdvancedRelease;
    final hasSession = widget.hasSession || _hasSessionCookie;
    final showDeviceLoginOnboarding =
        !kIsWeb && !hasSession && !_hasBiometricEnrollment;
    final isMobilePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final payload = _deviceLoginQrPayload();

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
                    l.appTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: ShamellPalette.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chat_bubble_outline,
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
        if (showDeviceLoginOnboarding) ...[
          if (isMobilePlatform) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.isArabic ? 'مستخدم جديد؟' : 'New to Shamell?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l.isArabic
                          ? 'أنشئ معرّف Shamell جديد على هذا الجهاز (بدون رقم هاتف).'
                          : 'Create a new Shamell ID on this device (no phone number required).',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _busy ? null : _createNewAccount,
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: Text(
                        l.isArabic ? 'إنشاء معرّف جديد' : 'Create new ID',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.isArabic ? 'ربط حساب موجود' : 'Link an existing account',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.isArabic
                        ? 'اربط هذا الجهاز عبر رمز QR معتمد من جهاز Shamell آخر.'
                        : 'Link this device via a Device‑Login QR approved from another Shamell device.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _deviceLabelCtrl,
                    decoration: InputDecoration(
                      labelText: l.isArabic
                          ? 'اسم الجهاز (اختياري)'
                          : 'Device label (optional)',
                      prefixIcon: const Icon(Icons.devices_other_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                              _deviceLoginStarting ? null : _startDeviceLoginQr,
                          icon: const Icon(Icons.qr_code_2_outlined),
                          label: Text(l.isArabic ? 'بدء رمز QR' : 'Start QR'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (payload == null || _deviceLoginRedeeming)
                              ? null
                              : () => _tryRedeemDeviceLogin(fromPoll: false),
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(l.isArabic ? 'تحقق' : 'Check'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 240,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: theme.dividerColor),
                      ),
                      child: payload == null
                          ? SizedBox(
                              height: 200,
                              child: Center(
                                child: Text(
                                  l.isArabic
                                      ? 'ابدأ رمز QR لعرضه هنا.'
                                      : 'Start a QR to show it here.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.black87.withValues(alpha: .70),
                                  ),
                                ),
                              ),
                            )
                          : QrImageView(
                              data: payload,
                              version: QrVersions.auto,
                              size: 200,
                              backgroundColor: Colors.white,
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_deviceLoginToken != null)
                    Text(
                      l.isArabic
                          ? 'بانتظار المسح والموافقة على جهاز آخر…'
                          : 'Waiting for scan and approval on another device…',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: .70),
                      ),
                    ),
                  if (_deviceLoginStartedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        l.isArabic
                            ? 'ينتهي خلال دقائق قليلة.'
                            : 'Expires in a few minutes.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withValues(alpha: .60),
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton.icon(
          onPressed: _busy ? null : _signInWithBiometrics,
          icon: const Icon(Icons.fingerprint),
          label: Text(l.loginBiometricSignIn),
        ),
        const SizedBox(height: 12),
        if (!kIsWeb && !_biometricsAvailable)
          StatusBanner.error(
            l.loginBiometricRequired,
            dense: true,
          )
        else if (!_hasBiometricEnrollment && !hasSession)
          StatusBanner.info(
            l.loginDeviceNotEnrolled,
            dense: true,
          ),
        const SizedBox(height: 16),
        if (allowAdvanced)
          TextButton(
            onPressed: () {
              setState(() {
                _showAdvanced = !_showAdvanced;
              });
            },
            child: Text(
              l.isArabic ? 'خيارات متقدّمة' : 'Advanced options',
            ),
          ),
        if (allowAdvanced && _showAdvanced) ...[
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
                    _driverLogin = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              _DriverChip(
                onTap: () {
                  setState(() {
                    _loginMode = AppMode.user;
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
                    _driverLogin = false;
                  });
                },
              ),
              const SizedBox(width: 8),
              _RoleChip(
                mode: AppMode.admin,
                current: _loginMode,
                onTap: () {
                  setState(() {
                    _loginMode = AppMode.admin;
                    _driverLogin = false;
                  });
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (out.isNotEmpty) StatusBanner.info(out, dense: true),
        const SizedBox(height: 16),
        Text(
          l.loginQrHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: .70),
          ),
        ),
        const SizedBox(height: 8),
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
