import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'core/design_tokens.dart';
import 'taxi_operator.dart';
import 'bus_operator.dart';
import 'agriculture_operator.dart';
import 'livestock_operator.dart';
import 'commerce_operator.dart';
import 'superadmin_dashboard.dart';

Future<String?> _getCookie() async {
  final sp = await SharedPreferences.getInstance();
  return sp.getString('sa_cookie');
}

Future<void> _setCookie(String v) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setString('sa_cookie', v);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OpsAdminApp());
}

class OpsAdminApp extends StatelessWidget {
  const OpsAdminApp({super.key});
  @override
  Widget build(BuildContext context) {
    final baseBtnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: Tokens.lightOnSurface,
        secondary: Tokens.lightOnSurface,
        surface: Tokens.lightSurface,
        onSurface: Tokens.lightOnSurface,
      ),
      textTheme: GoogleFonts.interTextTheme().apply(bodyColor: Tokens.lightOnSurface, displayColor: Tokens.lightOnSurface),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: Tokens.lightOnSurface,
        foregroundColor: Tokens.lightSurface,
        shape: baseBtnShape,
        minimumSize: const Size.fromHeight(40),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Tokens.lightBorder),
        foregroundColor: Tokens.lightOnSurface,
        shape: baseBtnShape,
        minimumSize: const Size.fromHeight(40),
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Tokens.lightSurfaceAlt,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tokens.lightBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tokens.lightBorder)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Tokens.lightFocus, width: 1.4)),
        labelStyle: TextStyle(color: Tokens.lightOnSurface.withValues(alpha: .92)),
        hintStyle: TextStyle(color: Tokens.lightOnSurface.withValues(alpha: .60)),
      ),
      cardTheme: CardThemeData(
        color: Tokens.lightSurfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Tokens.lightBorder)),
        elevation: 0,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Tokens.lightOnSurface),
        foregroundColor: Tokens.lightOnSurface,
        iconTheme: IconThemeData(color: Tokens.lightOnSurface),
        systemOverlayStyle: SystemUiOverlayStyle(statusBarBrightness: Brightness.light, statusBarIconBrightness: Brightness.dark, statusBarColor: Colors.transparent),
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Tokens.primary,
        secondary: Tokens.accent,
        surface: Tokens.surface,
        onSurface: Tokens.onSurface,
      ),
      textTheme: GoogleFonts.interTextTheme().apply(bodyColor: Tokens.onSurface, displayColor: Tokens.onSurface),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        elevation: 6,
        shadowColor: Colors.black87,
        backgroundColor: Tokens.primary,
        foregroundColor: Tokens.onPrimary,
        shape: baseBtnShape,
        minimumSize: const Size.fromHeight(40),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        side: BorderSide(color: Colors.white.withValues(alpha: .22)),
        foregroundColor: Tokens.onSurface,
        shape: baseBtnShape,
        minimumSize: const Size.fromHeight(40),
      )),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tokens.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Tokens.border)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Tokens.focus, width: 1.4)),
        labelStyle: TextStyle(color: Tokens.onSurface.withValues(alpha: .92)),
        hintStyle: TextStyle(color: Tokens.onSurface.withValues(alpha: .72)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: .08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Tokens.border)),
        elevation: 8,
        shadowColor: Colors.black87,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Tokens.onSurface),
        foregroundColor: Tokens.onSurface,
        iconTheme: IconThemeData(color: Tokens.onSurface),
        systemOverlayStyle: SystemUiOverlayStyle(statusBarBrightness: Brightness.dark, statusBarIconBrightness: Brightness.light, statusBarColor: Colors.transparent),
      ),
    );

    return MaterialApp(
      title: 'Ops Admin',
      themeMode: ThemeMode.system,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: const LoginGate(),
    );
  }
}

class LoginGate extends StatefulWidget {
  const LoginGate({super.key});
  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  String? _cookie;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _cookie = await _getCookie();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_cookie != null && _cookie!.isNotEmpty) {
      return const _Home();
    }
    return const LoginPage();
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
  final phoneCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String out = '';

  @override
  void initState() {
    super.initState();
    _loadLast();
  }

  Future<void> _loadLast() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final b = sp.getString('ops_base_url');
      if (b != null && b.isNotEmpty) {
        final v = b.trim();
        // Ignore legacy dev defaults so the new
        // monolith port (8080) is used automatically.
        if (!(v.contains('localhost:5003') ||
              v.contains('127.0.0.1:5003') ||
              v.contains('localhost:8000') ||
              v.contains('127.0.0.1:8000'))) {
          baseCtrl.text = v;
        }
      }
      final p = sp.getString('ops_phone');
      if (p != null && p.isNotEmpty) phoneCtrl.text = p;
    } catch (_) {}
  }

  Future<void> _request() async {
    setState(() => out = '...');
    try {
      final uri = Uri.parse('${baseCtrl.text.trim()}/auth/request_code');
      final resp = await http.post(
        uri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'phone': phoneCtrl.text.trim()}),
      );
      setState(() => out = '${resp.statusCode}: ${resp.body}');
      try {
        final j = jsonDecode(resp.body);
        final code = (j['code'] ?? '').toString();
        codeCtrl.text = code;
        if (code.isNotEmpty && mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Demo OTP'),
              content: SelectableText(
                code,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('OTP copied')),
                    );
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
      } catch (_) {}
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }

  Future<void> _verify() async {
    setState(() => out = '...');
    try {
      final uri = Uri.parse('${baseCtrl.text.trim()}/auth/verify');
      final resp = await http.post(
        uri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'phone': phoneCtrl.text.trim(),
          'code': codeCtrl.text.trim(),
        }),
      );
      try {
        final sc = resp.headers['set-cookie'];
        if (sc != null) {
          final m = RegExp(r'sa_session=([^;]+)').firstMatch(sc);
          if (m != null) {
            await _setCookie('sa_session=${m.group(1)}');
          }
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() => out = '${resp.statusCode}: ${resp.body}');
      if (resp.statusCode == 200) {
        try {
          final sp = await SharedPreferences.getInstance();
          await sp.setString('ops_base_url', baseCtrl.text.trim());
          await sp.setString('ops_phone', phoneCtrl.text.trim());
        } catch (_) {}
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const _Home()),
        );
      }
    } catch (e) {
      setState(() => out = 'error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ops Login'), backgroundColor: Colors.transparent),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Ops Admin', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (+963…)',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _request,
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Request code'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Code (6 digits)',
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _verify,
                  icon: const Icon(Icons.login),
                  label: const Text('Verify'),
                ),
                const SizedBox(height: 16),
                if (out.isNotEmpty) SelectableText(out),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ops Admin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Welcome to Ops Admin.'),
          const SizedBox(height: 12),
          const Text('The neutral theme (Light/Dark) is active.'),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              title: const Text('Taxi – Operator'),
              subtitle: const Text('Manage drivers, view rides, triage complaints'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TaxiOperatorPage())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Bus – Operator'),
              subtitle: const Text('Manage cities, operators, routes, trips, booking, boarding'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BusOperatorPage())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Agriculture – Operator'),
              subtitle: const Text('View listings (cached), check health'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgricultureOperatorPage())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Livestock – Operator'),
              subtitle: const Text('View listings (cached), check health'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LivestockOperatorPage())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Commerce – Operator'),
              subtitle: const Text('View products (cached), check health'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CommerceOperatorPage())),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Superadmin – Quality & Guardrails'),
              subtitle: const Text('Upstreams, Guardrails, Latenzmetriken auf einen Blick'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuperadminDashboardPage())),
            ),
          ),
        ],
      ),
    );
  }
}
