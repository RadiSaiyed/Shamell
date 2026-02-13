import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'device_id.dart';
import 'http_error.dart';
import '../main.dart' show LoginPage;

class DevicesPage extends StatefulWidget {
  final String baseUrl;

  const DevicesPage({super.key, required this.baseUrl});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _devices = const [];
  String? _currentDeviceId;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCurrentDeviceId();
  }

  Future<Map<String, String>> _hdr() async {
    final h = <String, String>{};
    try {
      final cookie = await getSessionCookie() ?? '';
      if (cookie.isNotEmpty) {
        h['sa_cookie'] = cookie;
      }
    } catch (_) {}
    return h;
  }

  Future<void> _loadCurrentDeviceId() async {
    try {
      final id =
          await loadStableDeviceId() ?? await getOrCreateStableDeviceId();
      if (!mounted) return;
      setState(() => _currentDeviceId = id);
    } catch (_) {}
  }

  Future<void> _load() async {
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse('${widget.baseUrl}/auth/devices');
      final resp = await http.get(uri, headers: await _hdr());
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        setState(() {
          _error = sanitizeHttpError(
            statusCode: resp.statusCode,
            rawBody: resp.body,
            isArabic: isArabic,
          );
          _loading = false;
        });
        return;
      }
      final decoded = jsonDecode(resp.body);
      final list = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['devices'] is List) {
        for (final e in decoded['devices'] as List) {
          if (e is Map) {
            list.add(e.cast<String, dynamic>());
          }
        }
      }
      setState(() {
        _devices = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = isArabic ? 'تعذّر تحميل الأجهزة.' : 'Could not load devices.';
        _loading = false;
      });
    }
  }

  Uri _webDesktopUrl() {
    final base = widget.baseUrl.trim();
    final u = Uri.tryParse(base);
    if (u == null) return Uri.parse(base);
    final host = u.host.toLowerCase();
    // Local dev: keep the demo endpoint for quick testing.
    if (host == 'localhost' || host == '127.0.0.1') {
      return u.replace(path: '/auth/device_login_demo', queryParameters: {});
    }
    // Production/staging: derive the web origin from the API hostname.
    if (host.startsWith('api.')) {
      return Uri(
        scheme: 'https',
        host: 'online.${host.substring(4)}',
        path: '/',
      );
    }
    if (host.startsWith('staging-api.')) {
      return Uri(
        scheme: 'https',
        host: 'online.${host.substring('staging-api.'.length)}',
        path: '/',
      );
    }
    // Fallback: open the origin (best-effort).
    return u.replace(path: '/', queryParameters: {});
  }

  Future<void> _logoutThisDevice() async {
    try {
      String? cookie;
      try {
        final sp = await SharedPreferences.getInstance();
        cookie = await getSessionCookie();
        await clearSessionCookie();
        await sp.remove('chat.identity');
      } catch (_) {}
      final uri = Uri.parse('${widget.baseUrl}/auth/logout');
      await http.post(
        uri,
        headers: {
          if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
        },
      );
    } catch (_) {
      // Best-effort; ignore logout errors and still navigate back to login.
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              Icons.devices_other_outlined,
              size: 22,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              l.isArabic ? 'الأجهزة المرتبطة' : 'Linked devices',
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.isArabic
                      ? 'شامل ويب / سطح المكتب'
                      : 'Shamell Web / Desktop sessions',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l.isArabic
                      ? 'افتح رمز QR تسجيل الدخول من Shamell Web، امسحه ضوئياً عبر \"مسح\" في شامل، ثم أكّد تسجيل الدخول هنا. ستظهر الأجهزة المرتبطة بالأسفل.'
                      : 'Open a device login QR on Shamell Web, scan it via \"Scan\" in Shamell, then confirm the login here. Linked devices will appear below.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _devices.isEmpty && !_loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.devices_other_outlined,
                          size: 40,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .35),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l.isArabic
                              ? 'لا توجد أجهزة مرتبطة بهذا الحساب بعد.\nسجّل الدخول من شامل على جهاز آخر لرؤيته هنا.'
                              : 'No linked devices yet.\nSign in to Shamell on another device to see it here.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .6),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (ctx, i) {
                      final d = _devices[i];
                      final deviceId = (d['device_id'] ?? '').toString();
                      final deviceType = (d['device_type'] ?? '').toString();
                      final platform = (d['platform'] ?? '').toString();
                      final appVersion = (d['app_version'] ?? '').toString();
                      final lastIp = (d['last_ip'] ?? '').toString();
                      final ua = (d['user_agent'] ?? '').toString();
                      final lastSeen = (d['last_seen_at'] ?? '').toString();
                      final title = deviceType.isNotEmpty
                          ? deviceType
                          : (platform.isNotEmpty ? platform : 'Device');
                      final subtitle = <String>[
                        if (deviceId.isNotEmpty) deviceId,
                        if (appVersion.isNotEmpty) 'v$appVersion',
                        if (lastIp.isNotEmpty) lastIp,
                      ].join(' · ');
                      return ListTile(
                        leading: Icon(
                          Icons.devices_other_outlined,
                          color: deviceId == _currentDeviceId
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                        ),
                        title: Row(
                          children: [
                            Expanded(child: Text(title)),
                            if (deviceId == _currentDeviceId)
                              Padding(
                                padding: const EdgeInsets.only(left: 6.0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: .10),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    l.shamellDevicesThisDevice,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: .85),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (ua.isNotEmpty)
                              Text(
                                ua,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .6),
                                ),
                              ),
                            if (lastSeen.isNotEmpty)
                              Text(
                                lastSeen,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: .6),
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.logout,
                            color:
                                theme.colorScheme.error.withValues(alpha: .90),
                          ),
                          tooltip: l.isArabic
                              ? 'إزالة هذا الجهاز'
                              : 'Remove this device',
                          onPressed: deviceId == _currentDeviceId
                              ? null
                              : () => _remove(deviceId),
                        ),
                      );
                    },
                  ),
          ),
          if (_devices.length > 1 && _currentDeviceId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: Icon(
                    Icons.logout,
                    size: 18,
                    color: theme.colorScheme.error.withValues(alpha: .90),
                  ),
                  label: Text(
                    l.shamellDevicesLogoutOthers,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error.withValues(alpha: .90),
                    ),
                  ),
                  onPressed: () => _removeOthers(),
                ),
              ),
            ),
          if (_currentDeviceId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: Icon(
                    Icons.logout,
                    size: 18,
                    color: theme.colorScheme.error.withValues(alpha: .90),
                  ),
                  label: Text(
                    l.isArabic
                        ? 'تسجيل الخروج من هذا الجهاز'
                        : 'Log out from this device',
                  ),
                  onPressed: _logoutThisDevice,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.qr_code, size: 18),
                label: Text(
                  l.isArabic
                      ? 'فتح شامل ويب / سطح المكتب'
                      : 'Open Shamell Web / Desktop',
                ),
                onPressed: () async {
                  final url = _webDesktopUrl();
                  if (!await launchUrl(url,
                      mode: LaunchMode.externalApplication)) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          l.isArabic
                              ? 'تعذّر فتح شامل ويب.'
                              : 'Could not open Shamell Web.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _remove(String deviceId) async {
    final l = L10n.of(context);
    if (deviceId.isEmpty) return;
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/auth/devices/${Uri.encodeComponent(deviceId)}');
      final resp = await http.delete(uri, headers: await _hdr());
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تعذّر إزالة الجهاز.' : 'Failed to remove device.',
            ),
          ),
        );
      } else {
        await _load();
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تعذّر إزالة الجهاز.' : 'Failed to remove device.',
          ),
        ),
      );
    }
  }

  Future<void> _removeOthers() async {
    final l = L10n.of(context);
    final currentId = _currentDeviceId;
    if (currentId == null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.isArabic ? 'تأكيد' : 'Confirm'),
            content: Text(l.shamellDevicesLogoutOthersConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.shamellDialogCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.settingsSave),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    for (final d in _devices) {
      final deviceId = (d['device_id'] ?? '').toString();
      if (deviceId.isEmpty || deviceId == currentId) continue;
      await _remove(deviceId);
    }
  }
}
