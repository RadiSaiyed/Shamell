import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n.dart';
import '../superapp_api.dart';

/// Host page for the **Hotels** mini-app.
///
/// Hotels is a generic, multi-tenant mini-program that lists hotel
/// partners (currently a single demo entry: **VENEZIA Hotel**). The
/// UI ships as HTML+CSS+JS under `assets/mini_apps/hotels/` and runs
/// in an in-app WebView, mirroring the [MiniGameWebViewPage] pattern.
///
/// Unlike Jump-Jump (sandboxed game, no host bridge), this mini-app
/// registers a JavaScript channel `ShamellHost` so it can hand off to
/// host modules — currently `openPayments` and `openChat`, both of
/// which route through [SuperappAPI.openMod]. Unknown actions are
/// ignored so a forward-compatible mini-app bundle can announce
/// future intents without crashing older hosts.
class HotelsMiniAppPage extends StatefulWidget {
  final SuperappAPI api;

  const HotelsMiniAppPage({super.key, required this.api});

  @override
  State<HotelsMiniAppPage> createState() => _HotelsMiniAppPageState();
}

class _HotelsMiniAppPageState extends State<HotelsMiniAppPage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
    ]);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF7F3EC))
      ..addJavaScriptChannel(
        'ShamellHost',
        onMessageReceived: _onHostMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
              _pushLocaleToMiniApp();
            }
          },
          onWebResourceError: (error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _loadError = error.description;
              });
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'file' || uri.scheme == 'about') {
              return NavigationDecision.navigate;
            }
            if (uri.scheme.isEmpty || uri.scheme == 'asset') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadFlutterAsset('assets/mini_apps/hotels/index.html');
  }

  void _onHostMessage(JavaScriptMessage message) {
    Map<String, dynamic>? parsed;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is Map<String, dynamic>) parsed = decoded;
    } catch (_) {
      return;
    }
    if (parsed == null) return;
    final action = parsed['action'];
    if (action is! String) return;
    switch (action) {
      case 'openPayments':
        widget.api.openMod('payments');
        break;
      case 'openChat':
        // Future: route via a chat-mod intent. For now, the messenger
        // entry point is reachable through the chat mod.
        widget.api.openMod('chat');
        break;
      case 'createBooking':
        final payload = parsed['payload'];
        if (payload is Map<String, dynamic>) {
          unawaited(_postBooking(payload));
        }
        break;
      case 'createOrder':
        final payload = parsed['payload'];
        if (payload is Map<String, dynamic>) {
          unawaited(_postOrder(payload));
        }
        break;
      case 'share':
        // Share intent stays inside the mini-app's own toast until a
        // host-level share surface is exposed via SuperappAPI.
        break;
      default:
        break;
    }
  }

  /// Reads the active app locale and hands it to the mini-app via the
  /// `__shamellSetLocale` JS hook defined in `assets/mini_apps/hotels/
  /// i18n.js`. Called once on first page-load; if the user switches
  /// language inside the app, the host re-pushes via the same channel
  /// the next time this page opens.
  void _pushLocaleToMiniApp() {
    final localeTag = Localizations.maybeLocaleOf(context)?.languageCode ?? 'de';
    final escaped = localeTag.replaceAll("'", "");
    _controller.runJavaScript(
      "if (window.__shamellSetLocale) { window.__shamellSetLocale('$escaped'); }",
    );
  }

  Uri? _hotelsServiceUri(String hotelId, String path) {
    final base = widget.api.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || hotelId.isEmpty) return null;
    return Uri.tryParse('$base/v1/hotels/$hotelId$path');
  }

  http.Client _httpClient() {
    final factory = widget.api.httpClientFactory;
    return factory != null ? factory() : http.Client();
  }

  /// Best-effort write-through of a booking to `shamell_hotels_service`.
  /// The mini-app has already shown a local confirmation by the time
  /// this fires, so failures only surface in logs — we don't pop a
  /// toast back into the WebView (would be confusing UX). The admin
  /// console sees the row on its next 12 s poll.
  Future<void> _postBooking(Map<String, dynamic> payload) async {
    final hotelId = payload['hotelId']?.toString() ?? '';
    final uri = _hotelsServiceUri(hotelId, '/bookings');
    if (uri == null) return;
    final amountMajor = (payload['amount'] as num?)?.toDouble() ?? 0;
    final body = jsonEncode({
      'room_id': payload['roomId'],
      'wallet_id': widget.api.walletId,
      'check_in': payload['checkIn'],
      'check_out': payload['checkOut'],
      'guests': payload['guests'],
      'amount_cents': (amountMajor * 100).round(),
      'currency': payload['currency'] ?? 'EUR',
      'reference': payload['ref'],
    });
    final client = _httpClient();
    try {
      final res = await client
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 400) {
        debugPrint(
          'hotels booking POST failed: HTTP ${res.statusCode} ${res.body}',
        );
      }
    } catch (e) {
      debugPrint('hotels booking POST error: $e');
    } finally {
      client.close();
    }
  }

  /// Best-effort write-through of a room-service order to
  /// `shamell_hotels_service`. Same UX contract as [_postBooking].
  Future<void> _postOrder(Map<String, dynamic> payload) async {
    final hotelId = payload['hotelId']?.toString() ?? '';
    final uri = _hotelsServiceUri(hotelId, '/orders');
    if (uri == null) return;
    final amountMajor = (payload['amount'] as num?)?.toDouble() ?? 0;
    final items = payload['items'];
    final body = jsonEncode({
      'wallet_id': widget.api.walletId,
      'items': items is List ? items : const [],
      'amount_cents': (amountMajor * 100).round(),
      'currency': payload['currency'] ?? 'EUR',
      'reference': payload['ref'],
    });
    final client = _httpClient();
    try {
      final res = await client
          .post(
            uri,
            headers: const {'content-type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode >= 400) {
        debugPrint(
          'hotels order POST failed: HTTP ${res.statusCode} ${res.body}',
        );
      }
    } catch (e) {
      debugPrint('hotels order POST error: $e');
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F3EC),
      appBar: AppBar(
        title: const Text('Hotels'),
        backgroundColor: const Color(0xFF0E3A53),
        foregroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Color(0xFFC9A96E),
                ),
              ),
            if (_loadError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hotel_outlined,
                          size: 56, color: Color(0xFFC9A96E)),
                      const SizedBox(height: 12),
                      Text(
                        l.isArabic
                            ? 'تعذّر تحميل البرنامج المصغّر.'
                            : 'Mini-Programm konnte nicht geladen werden.',
                        style: const TextStyle(
                          color: Color(0xFF0E3A53),
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        _loadError.toString(),
                        style: const TextStyle(
                          color: Color(0xFF0E3A53),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
