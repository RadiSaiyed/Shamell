part of '../main.dart';

const Duration _accountCreateRequestTimeout = Duration(seconds: 15);

class SuperApp extends StatelessWidget {
  const SuperApp({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // Debug log to verify HomePage from this repo is running on device.
    assert(() {
      debugPrint('HOME_PAGE_BUILD: Shamell');
      return true;
    }());
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
    defaultValue: 'https://api.shamell.online',
  );
  return await getSessionCookieHeader(fallbackBase);
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
  @override
  Widget build(BuildContext context) {
    return const HomePage(lockedMode: AppMode.user);
  }
}

class LoginPage extends StatefulWidget {
  final bool hasSession;
  const LoginPage({super.key, this.hasSession = false});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SafeSetStateMixin<LoginPage> {
  final baseCtrl = TextEditingController(
    text: const String.fromEnvironment(
      'BASE_URL',
      defaultValue: 'https://api.shamell.online',
    ),
  );
  String out = '';
  bool _busy = false;
  bool _hasSessionCookie = false;
  bool _autoCreateKickoffScheduled = false;
  Timer? _autoCreateRetryTimer;

  @override
  void initState() {
    super.initState();
    _loadBase();
  }

  @override
  void dispose() {
    _autoCreateRetryTimer?.cancel();
    baseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBase() async {
    final fallbackBase = const String.fromEnvironment(
      'BASE_URL',
      defaultValue: 'https://api.shamell.online',
    ).trim();
    final fallbackHost = Uri.tryParse(fallbackBase)?.host ?? '';
    final hasReachableFallback = fallbackBase.isNotEmpty &&
        isSecureApiBaseUrl(fallbackBase) &&
        !isLocalhostHost(fallbackHost);

    try {
      final sp = await SharedPreferences.getInstance();
      final stored = (sp.getString('base_url') ?? '').trim();
      final host = Uri.tryParse(stored)?.host ?? '';
      final shouldPinToFallback = stored.isEmpty ||
          !isSecureApiBaseUrl(stored) ||
          (hasReachableFallback && stored != fallbackBase) ||
          (hasReachableFallback && isLocalhostHost(host));
      if (shouldPinToFallback) {
        baseCtrl.text = fallbackBase;
        try {
          await sp.setString('base_url', fallbackBase);
        } catch (_) {}
      } else {
        baseCtrl.text = stored;
      }
    } catch (_) {}
    await _maybeAutoCreateOnFirstLaunch();
  }

  bool _shouldAutoCreateNow() {
    if (kIsWeb) return false;
    final isMobilePlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!isMobilePlatform) return false;
    if (widget.hasSession || _hasSessionCookie) {
      return false;
    }
    return true;
  }

  Future<void> _maybeAutoCreateOnFirstLaunch() async {
    if (!mounted || _autoCreateKickoffScheduled || !_shouldAutoCreateNow()) {
      return;
    }
    _autoCreateKickoffScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _busy || !_shouldAutoCreateNow()) return;
      unawaited(_createNewAccount());
    });
  }

  void _scheduleAutoCreateRetry({
    Duration delay = const Duration(seconds: 4),
  }) {
    if (!mounted || !_shouldAutoCreateNow()) return;
    if (_autoCreateRetryTimer?.isActive == true) return;
    _autoCreateRetryTimer = Timer(delay, () {
      if (!mounted || _busy || !_shouldAutoCreateNow()) return;
      unawaited(_createNewAccount());
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

  String _accountCreateHttpError({
    required int statusCode,
    required String rawBody,
    required bool isArabic,
  }) {
    final detail = _extractApiDetail(rawBody).toLowerCase();
    if (detail.contains('account creation temporarily unavailable')) {
      return isArabic
          ? 'إنشاء حساب جديد معطّل على هذا الخادم حالياً.'
          : 'New account creation is currently disabled on this server.';
    }
    if (detail.contains('internal auth required')) {
      return isArabic
          ? 'هذا الخادم لا يسمح بإنشاء حسابات عامة.'
          : 'This server does not allow public account creation.';
    }
    if (statusCode == 404 && (detail.isEmpty || detail.contains('not found'))) {
      return isArabic
          ? 'هذا الخادم لا يدعم إنشاء حساب جديد حالياً.'
          : 'This server does not currently support new account creation.';
    }
    return sanitizeHttpError(
      statusCode: statusCode,
      rawBody: rawBody,
      isArabic: isArabic,
    );
  }

  bool _isAccountCreatePermanentFailure({
    required int statusCode,
    required String rawBody,
  }) {
    final detail = _extractApiDetail(rawBody).toLowerCase();
    if (detail.contains('account creation temporarily unavailable'))
      return true;
    if (detail.contains('internal auth required')) return true;
    if (statusCode == 404 && (detail.isEmpty || detail.contains('not found'))) {
      return true;
    }
    return false;
  }

  bool _isRetryableHttpStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 425 ||
        statusCode == 429 ||
        statusCode >= 500;
  }

  bool _isLikelyNetworkError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('socket') ||
        raw.contains('network') ||
        raw.contains('connection') ||
        raw.contains('timeout');
  }

  String _sanitizeLoginException({
    required Object error,
    required bool isArabic,
    String? baseUrl,
  }) {
    final fallback = sanitizeExceptionForUi(error: error, isArabic: isArabic);
    final raw = error.toString().trim().toLowerCase();
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

  Future<void> _createNewAccount() async {
    void setOutSafe(String message) {
      if (!mounted) return;
      setState(() => out = message);
    }

    final l = L10n.of(context);
    if (_busy) return;
    final base = baseCtrl.text.trim();
    if (base.isEmpty) {
      setOutSafe(
          l.isArabic ? 'عنوان الخادم مطلوب.' : 'Server URL is required.');
      return;
    }
    if (!isSecureApiBaseUrl(base)) {
      setOutSafe(l.isArabic
          ? 'يجب استخدام HTTPS (وفي وضع التطوير يُسمح بـ HTTP على localhost أو الشبكة المحلية).'
          : 'HTTPS is required (non-release builds also allow HTTP for localhost/LAN).');
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
          ? 'إنشاء معرّف جديد متاح فقط على iOS/Android.'
          : 'Creating a new ID is only supported on iOS/Android.');
      return;
    }

    setState(() {
      _busy = true;
      out =
          l.isArabic ? 'جارٍ إنشاء معرّف جديد…' : 'Creating a new Shamell ID…';
    });

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
    final challengeUri =
        Uri.parse('${base.trim()}/auth/account/create/challenge');
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
        ).timeout(_accountCreateRequestTimeout);
        if (chResp.statusCode == 404) {
          // Legacy dev servers may not have attestation endpoints.
          return true;
        }
        if (chResp.statusCode != 200) {
          if (_isRetryableHttpStatus(chResp.statusCode) &&
              !_isAccountCreatePermanentFailure(
                statusCode: chResp.statusCode,
                rawBody: chResp.body,
              )) {
            _scheduleAutoCreateRetry();
          }
          setOutSafe(_accountCreateHttpError(
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
            out =
                l.isArabic ? 'جارٍ التحقق من الجهاز…' : 'Solving attestation…';
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
        return http
            .post(
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
            )
            .timeout(_accountCreateRequestTimeout);
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
        if (_isRetryableHttpStatus(resp.statusCode) &&
            !_isAccountCreatePermanentFailure(
              statusCode: resp.statusCode,
              rawBody: resp.body,
            )) {
          _scheduleAutoCreateRetry();
        }
        setOutSafe(_accountCreateHttpError(
          statusCode: resp.statusCode,
          rawBody: resp.body,
          isArabic: l.isArabic,
        ));
        if (mounted) setState(() => _busy = false);
        return;
      }

      final sess =
          extractSessionTokenFromSetCookieHeader(resp.headers['set-cookie']);
      if (sess == null || sess.isEmpty) {
        setOutSafe(l.isArabic
            ? 'تعذّر استلام جلسة من الخادم.'
            : 'Could not obtain a server session.');
        if (mounted) setState(() => _busy = false);
        return;
      }
      await setSessionTokenForBaseUrl(base, sess);

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
      _autoCreateRetryTimer?.cancel();
    } catch (e) {
      setOutSafe(_sanitizeLoginException(
        error: e,
        isArabic: l.isArabic,
        baseUrl: base,
      ));
      if (mounted) setState(() => _busy = false);
      if (_isLikelyNetworkError(e)) {
        _scheduleAutoCreateRetry();
      }
    }
  }

  Future<void> _handlePostLoginNavigation() async {
    // Default: end-user app home only.
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HomePage(
          lockedMode: AppMode.user,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final hasSession = widget.hasSession || _hasSessionCookie;
    final needsAutoCreate = !kIsWeb && !hasSession;

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
        if (needsAutoCreate) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.isArabic ? 'إعداد تلقائي' : 'Automatic setup',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.isArabic
                        ? 'سيتم إنشاء معرّف Shamell جديد تلقائياً عند أول تشغيل.'
                        : 'A new Shamell ID is created automatically on first launch.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_busy)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          if (_busy) const SizedBox(height: 12),
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
