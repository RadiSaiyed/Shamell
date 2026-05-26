import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n.dart';

// Fallback prod base URL used when the surface dispatcher doesn't
// inject one. Carriers launching the standalone APK from the wild
// will hit this; in-app launches always pass a configured baseUrl.
const String _fallbackBaseUrl = 'https://api.shamell.online';

/// Phase-2 Carrier Console: a deliberately minimal landing screen
/// that proves the mobile → BFF → freight_service chain works on a
/// real device. Real fleet management UI (orgs, vehicles, trailers,
/// drivers, certificates) lands in Phase 3 once the BFF carrier
/// endpoints exist; that work copies the shape of `HotelAdminConsolePage`
/// (login flow + tabbed dashboard + SSE live updates + manual polling
/// fallback).
///
/// Rationale for shipping a scaffold this early:
/// - The CI pipeline (signed APK + Play Integrity + TLS pinning +
///   Hetzner publish) takes ~30 min and has many gotchas (we hit
///   ripgrep-missing, JDK 21, Firebase configs, variant allowlists).
///   Building the flavor end-to-end NOW, before there's much UI to
///   debug, keeps the operational debt small.
/// - The few pilot Spediteure can install the APK, hit the health
///   probe button, and confirm the backend is reachable from their
///   network/device. Useful sanity check before we ask them to
///   register fleet data.
class CarrierConsolePage extends StatefulWidget {
  final String? baseUrl;

  const CarrierConsolePage({super.key, this.baseUrl});

  @override
  State<CarrierConsolePage> createState() => _CarrierConsolePageState();
}

class _CarrierConsolePageState extends State<CarrierConsolePage> {
  bool _probing = false;
  String? _lastProbeResult;
  String? _lastProbeError;

  Future<void> _probeHealth() async {
    if (_probing) return;
    setState(() {
      _probing = true;
      _lastProbeResult = null;
      _lastProbeError = null;
    });
    final trimmed = (widget.baseUrl ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    final base = trimmed.isEmpty ? _fallbackBaseUrl : trimmed;
    final url = Uri.parse('$base/v1/freight/health');
    try {
      final resp = await http
          .get(url, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        // Pretty-print to confirm shape — operators expect
        // { status, service, env, migrations_applied }.
        try {
          final parsed = json.decode(resp.body) as Map<String, dynamic>;
          setState(() {
            _lastProbeResult =
                'HTTP ${resp.statusCode}\n${const JsonEncoder.withIndent('  ').convert(parsed)}';
          });
        } catch (_) {
          setState(() {
            _lastProbeResult = 'HTTP ${resp.statusCode}\n${resp.body}';
          });
        }
      } else {
        setState(() {
          _lastProbeError = 'HTTP ${resp.statusCode}\n${resp.body}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastProbeError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _probing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'سرتشات شحن (Carrier)' : 'SyrChat Carrier'),
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    color: Color(0xFF0F766E),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.isArabic ? 'وحدة الشاحن' : 'Carrier Console',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l.isArabic
                            ? 'مرحلة الإعداد — إدارة الأسطول قريباً'
                            : 'Scaffold build — fleet management coming soon',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.6),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.isArabic
                          ? 'تحقّق من الاتصال بالخادم'
                          : 'Backend connectivity check',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l.isArabic
                          ? 'يستدعي /v1/freight/health عبر بوابة سرتشات لإثبات وصول الجهاز إلى خدمة الشحن.'
                          : 'Calls /v1/freight/health through the SyrChat gateway to prove this device can reach the freight service.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.66),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _probing ? null : _probeHealth,
                      icon: _probing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.network_check_outlined),
                      label: Text(
                        l.isArabic ? 'فحص الاتصال' : 'Probe /v1/freight/health',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                      ),
                    ),
                    if (_lastProbeResult != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF07C160).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _lastProbeResult!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    if (_lastProbeError != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _lastProbeError!,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            height: 1.35,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l.isArabic ? 'قريباً' : 'Coming next',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _ComingSoonRow(
              icon: Icons.business_outlined,
              text: l.isArabic
                  ? 'إعداد الشركة + التحقّق KYC'
                  : 'Organization setup + KYC verification',
            ),
            _ComingSoonRow(
              icon: Icons.directions_bus_filled_outlined,
              text: l.isArabic
                  ? 'المركبات والمقطورات (مع المبرّدات وشهادات ATP)'
                  : 'Vehicles and trailers (with cooling units + ATP certs)',
            ),
            _ComingSoonRow(
              icon: Icons.badge_outlined,
              text: l.isArabic
                  ? 'السائقون مع شهادات BKF/ADR'
                  : 'Drivers with BKF/ADR certificates',
            ),
            _ComingSoonRow(
              icon: Icons.local_offer_outlined,
              text: l.isArabic
                  ? 'عروض الشحن وقبول الحجوزات'
                  : 'Load offers and booking accept',
            ),
            _ComingSoonRow(
              icon: Icons.thermostat_outlined,
              text: l.isArabic
                  ? 'تتبّع درجات الحرارة في الوقت الفعلي'
                  : 'Real-time temperature tracking',
            ),
          ],
        ),
      ),
    );
  }
}

class _ComingSoonRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ComingSoonRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
