import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n.dart';
import '../superapp_api.dart';
import 'hotels_operator_session.dart';

/// Login surface for hotel-staff. Posts to
/// `POST /v1/hotels/operator/login` on the BFF, persists the bearer
/// token via [HotelsOperatorSessionStore] on success, and pops back
/// to the admin console with `true` so it can re-load.
///
/// Visual language matches the warm SyrChat hotel palette (deep
/// rose / cream / bronze) so the staff console feels like one app
/// with the guest-facing mini-app.
class HotelsOperatorLoginPage extends StatefulWidget {
  final SuperappAPI api;
  final HotelsOperatorSessionStore store;
  final String initialHotelHint;

  const HotelsOperatorLoginPage({
    super.key,
    required this.api,
    required this.store,
    this.initialHotelHint = 'VENEZIA',
  });

  @override
  State<HotelsOperatorLoginPage> createState() =>
      _HotelsOperatorLoginPageState();
}

class _HotelsOperatorLoginPageState extends State<HotelsOperatorLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _loginCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = L10n.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final base = widget.api.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base/v1/hotels/operator/login');
    final factory = widget.api.httpClientFactory;
    final client = factory != null ? factory() : http.Client();
    try {
      final res = await client
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'login_id': _loginCtrl.text.trim(),
              'password': _passwordCtrl.text,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is! Map) {
          setState(() {
            _error = l.isArabic ? 'استجابة غير متوقعة' : 'Unexpected response';
            _busy = false;
          });
          return;
        }
        final session =
            HotelsOperatorSession.fromLoginResponse(decoded.cast<String, dynamic>());
        if (session == null) {
          setState(() {
            _error = l.isArabic ? 'استجابة غير صالحة' : 'Invalid response';
            _busy = false;
          });
          return;
        }
        await widget.store.save(session);
        if (!mounted) return;
        Navigator.of(context).pop<HotelsOperatorSession>(session);
        return;
      }
      String msg;
      switch (res.statusCode) {
        case 401:
          msg = l.isArabic
              ? 'اسم تسجيل الدخول أو كلمة المرور غير صحيحة'
              : 'Invalid login_id or password';
          break;
        case 403:
          msg = l.isArabic
              ? 'هذا الحساب معطّل'
              : 'Account disabled';
          break;
        case 400:
          msg = l.isArabic
              ? 'بيانات تسجيل الدخول غير مكتملة'
              : 'Login form incomplete';
          break;
        default:
          msg = 'HTTP ${res.statusCode}';
      }
      setState(() {
        _error = msg;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F1),
      appBar: AppBar(
        title: Text(l.isArabic ? 'دخول مشغّل الفندق' : 'Hotel Operator Login'),
        backgroundColor: const Color(0xFFFFF8F1),
        elevation: 0,
        foregroundColor: const Color(0xFF3B2214),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              color: Colors.white.withValues(alpha: .9),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFE8D7C5)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.hotel_outlined,
                          size: 48, color: Color(0xFF9A3412)),
                      const SizedBox(height: 16),
                      Text(
                        l.isArabic
                            ? 'لوحة تحكم ${widget.initialHotelHint}'
                            : '${widget.initialHotelHint} Admin Console',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF3B2214),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l.isArabic
                            ? 'سجّل دخول لإدارة الحجوزات وخدمة الغرف'
                            : 'Sign in to manage bookings and room service',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B4B3A),
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _loginCtrl,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l.isArabic ? 'اسم الدخول' : 'Login ID',
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) {
                          if ((v ?? '').trim().isEmpty) {
                            return l.isArabic ? 'مطلوب' : 'Required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: l.isArabic ? 'كلمة المرور' : 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscure ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) {
                            return l.isArabic ? 'مطلوب' : 'Required';
                          }
                          return null;
                        },
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.error_outline,
                                size: 18, color: Color(0xFFB91C1C)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xFFB91C1C)),
                              ),
                            ),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF9A3412),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _busy ? null : _submit,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.login),
                        label: Text(l.isArabic ? 'دخول' : 'Sign in'),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        l.isArabic
                            ? 'تواصل مع مسؤول الفندق لاستعادة بيانات الدخول.'
                            : 'Contact your hotel admin to recover credentials.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8A6B58),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
