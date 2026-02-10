part of '../main.dart';

class SuperApp extends StatelessWidget {
  const SuperApp({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    // Debug log to verify HomePage from this repo is running on device.
    debugPrint('HOME_PAGE_BUILD: Shamell');
    // WeChat-like light theme: flat surfaces + WeChat green accent.
    const wechatGreen = WeChatPalette.green;
    final baseBtnShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: wechatGreen,
        secondary: wechatGreen,
        surface: Colors.white,
        onSurface: Color(0xFF111111),
      ),
      scaffoldBackgroundColor: WeChatPalette.background,
      dividerColor: WeChatPalette.divider,
      dividerTheme: const DividerThemeData(
        color: WeChatPalette.divider,
        thickness: 0.5,
        space: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: wechatGreen,
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
        backgroundColor: wechatGreen,
        foregroundColor: Colors.white,
        shape: baseBtnShape,
        minimumSize: const Size.fromHeight(48),
      )),
      filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(wechatGreen),
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
            borderSide: BorderSide(color: wechatGreen, width: 2.0)),
        labelStyle: const TextStyle(color: Color(0xFF555555)),
        hintStyle: const TextStyle(color: Color(0xFF999999)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: WeChatPalette.divider)),
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
        primary: wechatGreen,
        secondary: wechatGreen,
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
        selectedItemColor: wechatGreen,
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
          backgroundColor: wechatGreen,
          foregroundColor: Colors.white,
          shape: baseBtnShape,
          minimumSize: const Size.fromHeight(48),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: const WidgetStatePropertyAll(wechatGreen),
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
          borderSide: BorderSide(color: wechatGreen, width: 2.0),
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
  static const List<String> _regionCodes = <String>[
    '+963',
    '+971',
    '+966',
  ];
  String _selectedDialCode = '+963';
  bool _superadminLogin = false;
  bool _driverLogin = false;
  bool _canBiometricLogin = false;
  bool _showAdvanced = false;
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
      String? detectedDialCode;
      String? localPhonePart;
      if (lastPhone != null && lastPhone.isNotEmpty) {
        final v = lastPhone.trim();
        for (final code in _regionCodes) {
          if (v.startsWith(code)) {
            detectedDialCode = code;
            localPhonePart = v.substring(code.length);
            break;
          }
        }
        phoneCtrl.text = localPhonePart ?? v;
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
          if (detectedDialCode != null && detectedDialCode.isNotEmpty) {
            _selectedDialCode = detectedDialCode!;
          }
        });
      }
    } catch (_) {}
  }

  String _normalizedPhone() {
    final raw = phoneCtrl.text.trim();
    if (raw.isEmpty) return raw;
    if (raw.startsWith('+')) return raw;
    final code = _selectedDialCode.trim();
    if (code.isEmpty) return raw;
    return '$code$raw';
  }

  Future<void> _request() async {
    setState(() => out = 'Requesting code…');
    final uri = Uri.parse('${baseCtrl.text.trim()}/auth/request_code');
    final resp = await http.post(uri,
        headers: await _hdr(json: true),
        body: jsonEncode({'phone': _normalizedPhone()}));
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
    final deviceId = await getOrCreateStableDeviceId();
    final resp = await http.post(uri,
        headers: await _hdr(json: true),
        body: jsonEncode({
          'phone': _normalizedPhone(),
          'code': codeCtrl.text.trim(),
          'name': nameCtrl.text.trim(),
          'device_id': deviceId,
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
        await sp.setString('last_login_phone', _normalizedPhone());
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
    final phone = _normalizedPhone();
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
        MaterialPageRoute(builder: (_) {
          final baseUri = Uri.tryParse(base);
          final uri = baseUri?.resolve('/taxi/driver') ??
              Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}/taxi/driver');
          return WeChatWebViewPage(initialUri: uri, baseUri: baseUri);
        }),
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
    final List<DropdownMenuItem<String>> regionItems = _regionCodes.map((code) {
      String country;
      switch (code) {
        case '+963':
          country = l.isArabic ? 'سوريا' : 'Syria';
          break;
        case '+971':
          country = l.isArabic ? 'الإمارات' : 'UAE';
          break;
        case '+966':
          country = l.isArabic ? 'السعودية' : 'Saudi Arabia';
          break;
        default:
          country = '';
      }
      final label = country.isEmpty ? code : '$code · $country';
      return DropdownMenuItem<String>(
        value: code,
        child: Text(label),
      );
    }).toList();
    final String currentDial = _regionCodes.contains(_selectedDialCode)
        ? _selectedDialCode
        : _regionCodes.first;

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
                      color: WeChatPalette.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chat_bubble_outline,
                    size: 32,
                    color: WeChatPalette.green,
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
        Row(
          children: [
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                initialValue: currentDial,
                items: regionItems,
                decoration: InputDecoration(
                  labelText: l.isArabic ? 'المقدمة' : 'Code',
                  prefixIcon: const Icon(Icons.flag_outlined),
                ),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedDialCode = value;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: l.loginPhone,
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
          onPressed: _request,
          icon: const Icon(Icons.sms),
          label: Text(l.loginRequestCode),
        ),
        const SizedBox(height: 16),
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
        if (_showAdvanced) ...[
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
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            keyboardType: TextInputType.name,
            decoration: InputDecoration(
              labelText: l.loginFullName,
              prefixIcon: const Icon(Icons.person_outline),
            ),
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
        const SizedBox(height: 8),
        Text(
          l.loginNoteDemo,
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
