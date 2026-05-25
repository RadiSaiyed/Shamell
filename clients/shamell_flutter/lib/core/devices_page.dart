import 'dart:convert';
import 'package:shamell_flutter/core/session_cookie_store.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'base_url.dart';
import 'device_binding_reauth.dart';
import 'l10n.dart';
import 'device_id.dart';
import 'forget_device_action.dart';
import 'shamell_empty_state.dart';
import 'http_error.dart';
import 'logout_wipe.dart';
import 'safe_set_state.dart';
import 'shamell_ui.dart';
import '../main.dart' show LoginPage;

const Duration _devicesRequestTimeout = Duration(seconds: 15);
const int _devicesPageSize = 50;

class _DevicesPageChunk {
  final List<Map<String, dynamic>> items;
  final bool hasMore;
  final String? nextBeforeLastSeenAt;
  final int? nextBeforeId;

  const _DevicesPageChunk({
    required this.items,
    required this.hasMore,
    required this.nextBeforeLastSeenAt,
    required this.nextBeforeId,
  });
}

class _DevicesPageHttpException implements Exception {
  final int statusCode;
  final String rawBody;

  const _DevicesPageHttpException(this.statusCode, this.rawBody);
}

enum _DeviceRemovalOutcome {
  removed,
  failed,
  stopFurtherActions,
}

@visibleForTesting
Uri? shamellDevicesWebDesktopUrl(String baseUrl) {
  final normalizedBase = normalizeSecureApiBaseUrl(baseUrl.trim());
  if (normalizedBase == null) return null;
  final u = Uri.parse(normalizedBase);
  final host = u.host.toLowerCase();
  // Local dev: use the device-login page (works in all envs) to bootstrap a browser session.
  if (isLocalhostHost(host)) {
    return u.replace(path: '/auth/device_login', queryParameters: null);
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
  // Fallback: open the canonical origin root only.
  return u.replace(path: '/', queryParameters: null, fragment: null);
}

class DevicesPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? client;

  const DevicesPage({super.key, required this.baseUrl, this.client});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage>
    with SafeSetStateMixin<DevicesPage> {
  bool _loading = true;
  bool _loadingMore = false;
  bool _deviceMutationInFlight = false;
  String? _error;
  List<Map<String, dynamic>> _devices = const [];
  String? _currentDeviceId;
  bool _hasMoreDevices = false;
  String? _beforeLastSeenAt;
  int? _beforeId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
    _loadCurrentDeviceId();
  }

  Future<Map<String, String>> _hdr() async {
    return shamellSessionHeadersForBaseUrl(widget.baseUrl);
  }

  Future<void> _loadCurrentDeviceId() async {
    try {
      final id = await loadStableDeviceId(baseUrlOverride: widget.baseUrl) ??
          await getOrCreateStableDeviceId(
            baseUrlOverride: widget.baseUrl,
          );
      if (!mounted) return;
      setState(() => _currentDeviceId = id);
    } catch (_) {}
  }

  String _deviceMergeKey(Map<String, dynamic> device) {
    final deviceId = (device['device_id'] ?? '').toString().trim();
    if (deviceId.isNotEmpty) return deviceId;
    final id = (device['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return 'id:$id';
    return jsonEncode(device);
  }

  List<Map<String, dynamic>> _mergeDevicePages(
    List<Map<String, dynamic>> existing,
    List<Map<String, dynamic>> incoming,
  ) {
    final merged = <String, Map<String, dynamic>>{};
    for (final item in existing) {
      merged[_deviceMergeKey(item)] = item;
    }
    for (final item in incoming) {
      merged[_deviceMergeKey(item)] = item;
    }
    return merged.values.toList(growable: false);
  }

  _DevicesPageChunk _devicesChunkFromItems(List<Map<String, dynamic>> items) {
    String? nextBeforeLastSeenAt;
    int? nextBeforeId;
    if (items.isNotEmpty) {
      final last = items.last;
      final lastSeenAt = (last['last_seen_at'] ?? '').toString().trim();
      final rawId = last['id'];
      final parsedId = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
      if (lastSeenAt.isNotEmpty && parsedId != null && parsedId > 0) {
        nextBeforeLastSeenAt = lastSeenAt;
        nextBeforeId = parsedId;
      }
    }
    final hasMore = items.length >= _devicesPageSize &&
        nextBeforeLastSeenAt != null &&
        nextBeforeId != null;
    return _DevicesPageChunk(
      items: items,
      hasMore: hasMore,
      nextBeforeLastSeenAt: nextBeforeLastSeenAt,
      nextBeforeId: nextBeforeId,
    );
  }

  Future<_DevicesPageChunk> _fetchDevicesPage({
    String? beforeLastSeenAt,
    int? beforeId,
  }) async {
    final queryParameters = <String, String>{
      'limit': '$_devicesPageSize',
    };
    if (beforeLastSeenAt != null && beforeId != null) {
      queryParameters['before_last_seen_at'] = beforeLastSeenAt;
      queryParameters['before_id'] = '$beforeId';
    }
    final uri = secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: const <String>['auth', 'devices'],
      queryParameters: queryParameters,
    );
    if (uri == null) {
      throw StateError('invalid server url');
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final resp = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_devicesRequestTimeout);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw _DevicesPageHttpException(resp.statusCode, resp.body);
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
      return _devicesChunkFromItems(list);
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _load() async {
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _loading = true;
      _error = null;
      _devices = const [];
      _hasMoreDevices = false;
      _beforeLastSeenAt = null;
      _beforeId = null;
    });
    try {
      final chunk = await _fetchDevicesPage();
      if (!mounted) return;
      setState(() {
        _devices = chunk.items;
        _hasMoreDevices = chunk.hasMore;
        _beforeLastSeenAt = chunk.nextBeforeLastSeenAt;
        _beforeId = chunk.nextBeforeId;
        _loading = false;
      });
    } on _DevicesPageHttpException catch (e) {
      if (!mounted) return;
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: e.statusCode,
        rawBody: e.rawBody,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() {
        _error = sanitizeHttpError(
          statusCode: e.statusCode,
          rawBody: e.rawBody,
          isArabic: isArabic,
        );
        _loading = false;
      });
    } on StateError {
      if (!mounted) return;
      setState(() {
        _error = isArabic ? 'تعذّر تحميل الأجهزة.' : 'Could not load devices.';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() {
        _error = isArabic ? 'تعذّر تحميل الأجهزة.' : 'Could not load devices.';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final isArabic = L10n.of(context).isArabic;
    final beforeLastSeenAt = _beforeLastSeenAt;
    final beforeId = _beforeId;
    if (_loading || _loadingMore || !_hasMoreDevices) return;
    if (beforeLastSeenAt == null || beforeId == null) {
      setState(() => _hasMoreDevices = false);
      return;
    }
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final chunk = await _fetchDevicesPage(
        beforeLastSeenAt: beforeLastSeenAt,
        beforeId: beforeId,
      );
      if (!mounted) return;
      setState(() {
        _devices = _mergeDevicePages(_devices, chunk.items);
        _hasMoreDevices = chunk.hasMore;
        _beforeLastSeenAt = chunk.nextBeforeLastSeenAt;
        _beforeId = chunk.nextBeforeId;
        _loadingMore = false;
      });
    } on _DevicesPageHttpException catch (e) {
      if (!mounted) return;
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: e.statusCode,
        rawBody: e.rawBody,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تعذّر تحميل أجهزة إضافية.'
                : 'Could not load more devices.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تعذّر تحميل أجهزة إضافية.'
                : 'Could not load more devices.',
          ),
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadAllDevicesSnapshot() async {
    var devices = List<Map<String, dynamic>>.from(_devices);
    var hasMore = _hasMoreDevices;
    var beforeLastSeenAt = _beforeLastSeenAt;
    var beforeId = _beforeId;
    while (hasMore && beforeLastSeenAt != null && beforeId != null) {
      final chunk = await _fetchDevicesPage(
        beforeLastSeenAt: beforeLastSeenAt,
        beforeId: beforeId,
      );
      devices = _mergeDevicePages(devices, chunk.items);
      hasMore = chunk.hasMore;
      beforeLastSeenAt = chunk.nextBeforeLastSeenAt;
      beforeId = chunk.nextBeforeId;
    }
    return devices;
  }

  bool _beginDeviceMutation() {
    if (_deviceMutationInFlight) return false;
    if (mounted) {
      setState(() => _deviceMutationInFlight = true);
    } else {
      _deviceMutationInFlight = true;
    }
    return true;
  }

  void _endDeviceMutation() {
    if (!_deviceMutationInFlight) return;
    if (mounted) {
      setState(() => _deviceMutationInFlight = false);
    } else {
      _deviceMutationInFlight = false;
    }
  }

  Future<void> _logoutThisDevice() async {
    if (!_beginDeviceMutation()) return;
    try {
      try {
        await bestEffortUnregisterCurrentChatPushToken(
          baseUrl: widget.baseUrl,
          client: widget.client,
        );
      } catch (_) {}
      try {
        final uri = secureApiChildUri(
          baseUrl: widget.baseUrl,
          pathSegments: const <String>['auth', 'logout'],
        );
        if (uri != null) {
          final client = shamellHttpClient();
          try {
            await client
                .post(
                  uri,
                  headers:
                      await shamellSessionHeadersForBaseUrl(widget.baseUrl),
                )
                .timeout(_devicesRequestTimeout);
          } finally {
            client.close();
          }
        }
      } catch (_) {}
      await wipeLocalAccountData(
        preserveDevicePrefs: true,
        baseUrlOverride: widget.baseUrl,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } finally {
      _endDeviceMutation();
    }
  }

  Future<void> _logoutForgetDevice() async {
    final l = L10n.of(context);
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.menuLogoutForgetDeviceConfirmTitle),
            content: Text(l.menuLogoutForgetDeviceConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.shamellDialogCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFA5151),
                  foregroundColor: Colors.white,
                ),
                child: Text(l.menuLogoutForgetDeviceConfirmAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    if (!_beginDeviceMutation()) return;

    try {
      String cookie = '';
      try {
        cookie = await getSessionCookieHeader(widget.baseUrl) ?? '';
      } catch (_) {}

      try {
        await bestEffortUnregisterCurrentChatPushToken(
          baseUrl: widget.baseUrl,
          client: widget.client,
        );
      } catch (_) {}

      final did = (_currentDeviceId ??
              (await loadStableDeviceId(baseUrlOverride: widget.baseUrl) ?? ''))
          .trim();
      try {
        await forgetDeviceOnServer(
          baseUrl: widget.baseUrl,
          deviceId: did,
          sessionCookie: cookie,
          isArabic: l.isArabic,
          client: widget.client,
        );
      } on ForgetDeviceException catch (e) {
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: e.statusCode ?? 401,
          rawBody: e.rawBody ?? e.message,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
        return;
      }

      try {
        final uri = secureApiChildUri(
          baseUrl: widget.baseUrl,
          pathSegments: const <String>['auth', 'logout'],
        );
        if (uri != null) {
          final client = shamellHttpClient();
          try {
            await client
                .post(
                  uri,
                  headers:
                      await shamellSessionHeadersForBaseUrl(widget.baseUrl),
                )
                .timeout(_devicesRequestTimeout);
          } finally {
            client.close();
          }
        }
      } catch (_) {}

      await wipeLocalForForgetDevice();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } finally {
      _endDeviceMutation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final dangerColor = theme.colorScheme.error.withValues(alpha: .92);

    Widget deviceRow(Map<String, dynamic> d) {
      final deviceId = (d['device_id'] ?? '').toString();
      final deviceType = (d['device_type'] ?? '').toString();
      final platform = (d['platform'] ?? '').toString();
      final appVersion = (d['app_version'] ?? '').toString();
      final lastIp = (d['last_ip'] ?? '').toString();
      final ua = (d['user_agent'] ?? '').toString();
      final lastSeen = (d['last_seen_at'] ?? '').toString();
      final isCurrent = deviceId == _currentDeviceId;
      final title = deviceType.isNotEmpty
          ? deviceType
          : (platform.isNotEmpty ? platform : 'Device');
      final subtitle = <String>[
        if (deviceId.isNotEmpty) deviceId,
        if (appVersion.isNotEmpty) 'v$appVersion',
        if (lastIp.isNotEmpty) lastIp,
      ].join(' · ');

      return ShamellListSection(
        margin: const EdgeInsets.only(bottom: 8),
        dividerIndent: 16,
        dividerEndIndent: 16,
        children: [
          ListTile(
            leading: ShamellLeadingIcon(
              icon: Icons.devices_other_outlined,
              background: isCurrent
                  ? ShamellPalette.green
                  : theme.colorScheme.onSurface.withValues(alpha: .12),
              foreground:
                  isCurrent ? Colors.white : theme.colorScheme.onSurface,
              size: 34,
              iconSize: 19,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCurrent)
                  Container(
                    margin: const EdgeInsetsDirectional.only(start: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: ShamellPalette.green.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l.shamellDevicesThisDevice,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: ShamellPalette.green,
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
                  ),
                if (lastSeen.isNotEmpty)
                  Text(
                    lastSeen,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            trailing: IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.logout_rounded, color: dangerColor),
              tooltip: l.isArabic ? 'إزالة هذا الجهاز' : 'Remove this device',
              onPressed: isCurrent || _deviceMutationInFlight
                  ? null
                  : () => _remove(deviceId),
            ),
          ),
        ],
      );
    }

    Widget actionRow({
      required IconData icon,
      required String label,
      required VoidCallback? onTap,
      Color? color,
    }) {
      final rowColor = color ?? theme.colorScheme.onSurface;
      return ListTile(
        leading: Icon(icon, size: 20, color: rowColor),
        title: Text(
          label,
          style: color == null ? null : TextStyle(color: rowColor),
        ),
        onTap: onTap,
      );
    }

    Future<void> openWebDesktop() async {
      final url = shamellDevicesWebDesktopUrl(widget.baseUrl);
      if (url == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'عنوان الخادم غير صالح لفتح سرتشات ويب.'
                  : 'Invalid server URL for SyrChat Web.',
            ),
          ),
        );
        return;
      }
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر فتح سرتشات ويب.'
                  : 'Could not open SyrChat Web.',
            ),
          ),
        );
      }
    }

    final footerRows = <Widget>[
      if (_devices.length > 1 && _currentDeviceId != null)
        actionRow(
          icon: Icons.logout_rounded,
          label: l.shamellDevicesLogoutOthers,
          color: dangerColor,
          onTap: _deviceMutationInFlight ? null : () => _removeOthers(),
        ),
      if (_currentDeviceId != null)
        actionRow(
          icon: Icons.logout_rounded,
          label: l.isArabic
              ? 'تسجيل الخروج من هذا الجهاز'
              : 'Log out from this device',
          color: dangerColor,
          onTap: _deviceMutationInFlight ? null : _logoutThisDevice,
        ),
      if (_currentDeviceId != null)
        actionRow(
          icon: Icons.delete_forever_outlined,
          label: l.menuLogoutForgetDevice,
          color: dangerColor,
          onTap: _deviceMutationInFlight ? null : _logoutForgetDevice,
        ),
      actionRow(
        icon: Icons.qr_code_rounded,
        label: l.isArabic
            ? 'فتح سرتشات ويب / سطح المكتب'
            : 'Open SyrChat Web / Desktop',
        color: ShamellPalette.green,
        onTap: () {
          openWebDesktop();
        },
      ),
    ];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'الأجهزة المرتبطة' : 'Linked devices',
        backgroundColor: bgColor,
      ),
      body: shamellSettingsListTheme(
        context,
        minLeadingWidth: 40,
        child: Column(
          children: [
            if (_loading || _deviceMutationInFlight)
              const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ShamellListSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                ListTile(
                  leading: const ShamellLeadingIcon(
                    icon: Icons.qr_code_rounded,
                    background: ShamellPalette.green,
                    size: 34,
                    iconSize: 19,
                  ),
                  title: Text(
                    l.isArabic
                        ? 'سرتشات ويب / سطح المكتب'
                        : 'SyrChat Web / Desktop sessions',
                  ),
                  subtitle: Text(
                    l.isArabic
                        ? 'افتح رمز QR تسجيل الدخول من SyrChat Web، امسحه ضوئياً عبر \"مسح\" في سرتشات، ثم أكّد تسجيل الدخول هنا.'
                        : 'Open a device login QR on SyrChat Web, scan it via \"Scan\" in SyrChat, then confirm the login here.',
                  ),
                ),
              ],
            ),
            Expanded(
              child: _devices.isEmpty && !_loading
                  ? Center(
                      child: ShamellEmptyState.empty(
                        icon: Icons.devices_other_outlined,
                        title: l.isArabic
                            ? 'لا توجد أجهزة بعد'
                            : 'No linked devices yet',
                        description: l.isArabic
                            ? 'سجّل الدخول من سرتشات على جهاز آخر لرؤيته هنا.'
                            : 'Sign in to SyrChat on another device to see it here.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      itemCount: _devices.length +
                          ((_hasMoreDevices || _loadingMore) ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (i >= _devices.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Center(
                              child: _loadingMore
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : TextButton(
                                      onPressed: _deviceMutationInFlight
                                          ? null
                                          : _loadMore,
                                      child: Text(
                                        l.isArabic
                                            ? 'تحميل المزيد'
                                            : 'Load more',
                                      ),
                                    ),
                            ),
                          );
                        }
                        return deviceRow(_devices[i]);
                      },
                    ),
            ),
            ShamellListSection(
              margin: const EdgeInsets.only(top: 4, bottom: 18),
              dividerIndent: 56,
              dividerEndIndent: 16,
              children: footerRows,
            ),
          ],
        ),
      ),
    );
  }

  Future<_DeviceRemovalOutcome> _remove(
    String deviceId, {
    bool reloadAfterSuccess = true,
    bool assumeMutationLock = false,
  }) async {
    final l = L10n.of(context);
    if (deviceId.isEmpty) return _DeviceRemovalOutcome.failed;
    if (!assumeMutationLock && !_beginDeviceMutation()) {
      return _DeviceRemovalOutcome.failed;
    }
    final uri = secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['auth', 'devices', deviceId],
    );
    if (uri == null) {
      if (!mounted) return _DeviceRemovalOutcome.failed;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.',
          ),
        ),
      );
      return _DeviceRemovalOutcome.failed;
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final resp = await httpClient
          .delete(uri, headers: await _hdr())
          .timeout(_devicesRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: resp.statusCode,
        rawBody: resp.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return _DeviceRemovalOutcome.stopFurtherActions;
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic ? 'تعذّر إزالة الجهاز.' : 'Failed to remove device.',
            ),
          ),
        );
        return _DeviceRemovalOutcome.failed;
      } else {
        if (reloadAfterSuccess) {
          await _load();
        }
        return _DeviceRemovalOutcome.removed;
      }
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return _DeviceRemovalOutcome.stopFurtherActions;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic ? 'تعذّر إزالة الجهاز.' : 'Failed to remove device.',
          ),
        ),
      );
      return _DeviceRemovalOutcome.failed;
    } finally {
      if (closeClient) {
        httpClient.close();
      }
      if (!assumeMutationLock) {
        _endDeviceMutation();
      }
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
    if (!_beginDeviceMutation()) return;
    try {
      List<Map<String, dynamic>> allDevices;
      try {
        allDevices = await _loadAllDevicesSnapshot();
      } on _DevicesPageHttpException catch (e) {
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: e.statusCode,
          rawBody: e.rawBody,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر تحميل بقية الأجهزة.'
                  : 'Could not load the remaining devices.',
            ),
          ),
        );
        return;
      } catch (e) {
        if (await shamellForceReauthIfCriticalDeviceBindingDrift(
          context,
          error: e,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذّر تحميل بقية الأجهزة.'
                  : 'Could not load the remaining devices.',
            ),
          ),
        );
        return;
      }
      var removedAny = false;
      for (final d in allDevices) {
        final deviceId = (d['device_id'] ?? '').toString();
        if (deviceId.isEmpty || deviceId == currentId) continue;
        final outcome = await _remove(
          deviceId,
          reloadAfterSuccess: false,
          assumeMutationLock: true,
        );
        if (outcome == _DeviceRemovalOutcome.stopFurtherActions) {
          return;
        }
        if (outcome == _DeviceRemovalOutcome.removed) {
          removedAny = true;
        }
      }
      if (removedAny) {
        await _load();
      }
    } finally {
      _endDeviceMutation();
    }
  }
}
