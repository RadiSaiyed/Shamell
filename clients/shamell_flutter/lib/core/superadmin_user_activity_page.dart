import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../main.dart' show LoginPage;

import 'app_shell_widgets.dart' show AppBG;
import 'base_url.dart';
import 'device_binding_reauth.dart';
import 'http_error.dart';
import 'l10n.dart';
import 'safe_set_state.dart';
import 'session_cookie_store.dart';
import 'shamell_empty_state.dart';
import 'shamell_loading_shimmer.dart';

class SuperadminUserActivityPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? httpClient;

  const SuperadminUserActivityPage({
    super.key,
    required this.baseUrl,
    this.httpClient,
  });

  @override
  State<SuperadminUserActivityPage> createState() =>
      _SuperadminUserActivityPageState();
}

class _SuperadminUserActivityPageState extends State<SuperadminUserActivityPage>
    with SafeSetStateMixin<SuperadminUserActivityPage> {
  static const Duration _requestTimeout = Duration(seconds: 15);

  late final http.Client _http;
  late final bool _ownsHttpClient;
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _moduleCtrl = TextEditingController();
  final TextEditingController _actionCtrl = TextEditingController();
  final TextEditingController _currencyCtrl = TextEditingController();
  final TextEditingController _fromDateCtrl = TextEditingController();
  final TextEditingController _toDateCtrl = TextEditingController();

  String _eventFilter = '';
  bool _loading = false;
  bool _platformLoading = false;
  bool _dashboardsLoading = false;
  String _status = '';
  String _platformStatus = '';
  String _dashboardsStatus = '';
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];
  Map<String, dynamic>? _platformSummary;
  Map<String, dynamic>? _dashboardsOverview;
  Map<String, dynamic>? _officialAccountsDashboard;
  Map<String, dynamic>? _miniProgramsDashboard;
  Map<String, dynamic>? _stickersDashboard;
  Map<String, dynamic>? _cardsDashboard;
  Map<String, dynamic>? _greenPaketDashboard;
  Map<String, dynamic>? _discoverDashboard;
  Map<String, dynamic>? _favoritesDashboard;
  Map<String, dynamic>? _chatDashboard;
  Map<String, dynamic>? _contactsDashboard;
  Map<String, dynamic>? _momentsDashboard;
  Map<String, dynamic>? _channelsDashboard;

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? shamellHttpClient();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_loadActivity());
        unawaited(_loadPlatformSummary());
        unawaited(_loadDashboardsOverview());
      }
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _moduleCtrl.dispose();
    _actionCtrl.dispose();
    _currencyCtrl.dispose();
    _fromDateCtrl.dispose();
    _toDateCtrl.dispose();
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Uri? _activityUri() {
    final query = <String, String>{'limit': '100'};
    if (_eventFilter.isNotEmpty && _eventFilter != 'payment') {
      query['event_type'] = _eventFilter;
    }
    final username = _usernameCtrl.text.trim().toLowerCase();
    if (username.isNotEmpty) {
      query['username'] = username;
    }
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: const <String>['admin', 'user-activity'],
      queryParameters: query,
    );
  }

  Uri? _platformSummaryUri() {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: const <String>[
        'admin',
        'platform',
        'features',
        'summary',
      ],
      queryParameters: const <String, String>{'limit': '25'},
    );
  }

  Uri? _dashboardsOverviewUri() {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: const <String>['admin', 'dashboards', 'overview'],
    );
  }

  Uri? _dashboardDetailUri(String dashboardId) {
    return secureApiChildUri(
      baseUrl: widget.baseUrl,
      pathSegments: <String>['admin', 'dashboards', dashboardId],
    );
  }

  Future<void> _loadActivity() async {
    final l = L10n.of(context);
    final uri = _activityUri();
    if (uri == null) {
      setState(() {
        _status = l.isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
        _items = const <Map<String, dynamic>>[];
      });
      return;
    }
    setState(() {
      _loading = true;
      _status = '';
    });
    try {
      final response = await _http
          .get(
            uri,
            headers: await shamellSessionHeadersForBaseUrl(widget.baseUrl),
          )
          .timeout(_requestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: response.statusCode,
        rawBody: response.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _items = const <Map<String, dynamic>>[];
          _status = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(response.body);
      final nextItems = <Map<String, dynamic>>[];
      if (decoded is Map && decoded['items'] is List) {
        for (final item in decoded['items'] as List) {
          if (item is Map) {
            nextItems.add(item.cast<String, dynamic>());
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = nextItems;
        _status = nextItems.isEmpty
            ? (l.isArabic ? 'لا توجد أحداث.' : 'No activity events found.')
            : (l.isArabic
                ? 'تم تحميل نشاط المستخدمين.'
                : 'Loaded user activity.');
      });
    } catch (error) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: error,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = sanitizeExceptionForUi(error: error, isArabic: l.isArabic);
      });
    }
  }

  Future<void> _loadPlatformSummary() async {
    final l = L10n.of(context);
    final uri = _platformSummaryUri();
    if (uri == null) {
      setState(() {
        _platformStatus =
            l.isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
        _platformSummary = null;
      });
      return;
    }
    setState(() {
      _platformLoading = true;
      _platformStatus = '';
    });
    try {
      final response = await _http
          .get(
            uri,
            headers: await shamellSessionHeadersForBaseUrl(widget.baseUrl),
          )
          .timeout(_requestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: response.statusCode,
        rawBody: response.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _platformLoading = false;
          _platformSummary = null;
          _platformStatus = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _platformLoading = false;
        _platformSummary =
            decoded is Map ? decoded.cast<String, dynamic>() : null;
        _platformStatus = '';
      });
    } catch (error) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: error,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _platformLoading = false;
        _platformSummary = null;
        _platformStatus =
            sanitizeExceptionForUi(error: error, isArabic: l.isArabic);
      });
    }
  }

  Future<void> _loadDashboardsOverview() async {
    final l = L10n.of(context);
    final uri = _dashboardsOverviewUri();
    if (uri == null) {
      setState(() {
        _dashboardsStatus =
            l.isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
        _dashboardsOverview = null;
        _officialAccountsDashboard = null;
        _miniProgramsDashboard = null;
        _stickersDashboard = null;
        _cardsDashboard = null;
        _greenPaketDashboard = null;
        _discoverDashboard = null;
        _favoritesDashboard = null;
        _chatDashboard = null;
        _contactsDashboard = null;
        _momentsDashboard = null;
        _channelsDashboard = null;
      });
      return;
    }
    setState(() {
      _dashboardsLoading = true;
      _dashboardsStatus = '';
    });
    try {
      final headers = await shamellSessionHeadersForBaseUrl(widget.baseUrl);
      final response = await _http
          .get(
            uri,
            headers: headers,
          )
          .timeout(_requestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: response.statusCode,
        rawBody: response.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (!mounted) return;
        setState(() {
          _dashboardsLoading = false;
          _dashboardsOverview = null;
          _officialAccountsDashboard = null;
          _miniProgramsDashboard = null;
          _stickersDashboard = null;
          _cardsDashboard = null;
          _greenPaketDashboard = null;
          _discoverDashboard = null;
          _favoritesDashboard = null;
          _chatDashboard = null;
          _contactsDashboard = null;
          _momentsDashboard = null;
          _channelsDashboard = null;
          _dashboardsStatus = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(response.body);
      final detailResults = await Future.wait<Map<String, dynamic>?>([
        _loadDashboardDetail('official-accounts', headers),
        _loadDashboardDetail('mini-programs', headers),
        _loadDashboardDetail('stickers', headers),
        _loadDashboardDetail('cards', headers),
        _loadDashboardDetail('green-paket', headers),
        _loadDashboardDetail('discover', headers),
        _loadDashboardDetail('favorites', headers),
        _loadDashboardDetail('chat', headers),
        _loadDashboardDetail('contacts', headers),
        _loadDashboardDetail('moments', headers),
        _loadDashboardDetail('channels', headers),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboardsLoading = false;
        _dashboardsOverview =
            decoded is Map ? decoded.cast<String, dynamic>() : null;
        _officialAccountsDashboard = detailResults[0];
        _miniProgramsDashboard = detailResults[1];
        _stickersDashboard = detailResults[2];
        _cardsDashboard = detailResults[3];
        _greenPaketDashboard = detailResults[4];
        _discoverDashboard = detailResults[5];
        _favoritesDashboard = detailResults[6];
        _chatDashboard = detailResults[7];
        _contactsDashboard = detailResults[8];
        _momentsDashboard = detailResults[9];
        _channelsDashboard = detailResults[10];
        _dashboardsStatus = '';
      });
    } catch (error) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: error,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _dashboardsLoading = false;
        _dashboardsOverview = null;
        _officialAccountsDashboard = null;
        _miniProgramsDashboard = null;
        _stickersDashboard = null;
        _cardsDashboard = null;
        _greenPaketDashboard = null;
        _discoverDashboard = null;
        _favoritesDashboard = null;
        _chatDashboard = null;
        _contactsDashboard = null;
        _momentsDashboard = null;
        _channelsDashboard = null;
        _dashboardsStatus =
            sanitizeExceptionForUi(error: error, isArabic: l.isArabic);
      });
    }
  }

  Future<Map<String, dynamic>?> _loadDashboardDetail(
    String dashboardId,
    Map<String, String> headers,
  ) async {
    final uri = _dashboardDetailUri(dashboardId);
    if (uri == null) return null;
    try {
      final response = await _http
          .get(
            uri,
            headers: headers,
          )
          .timeout(_requestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: response.statusCode,
        rawBody: response.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (error) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: error,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return null;
      }
      return null;
    }
  }

  bool _isPaymentEvent(String eventType) {
    final value = eventType.trim().toLowerCase();
    return value.startsWith('payment_') || value.startsWith('admin_credit_');
  }

  DateTime? _parseDateFilter(String raw, {required bool endOfDay}) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    final local = parsed.isUtc ? parsed.toLocal() : parsed;
    if (!endOfDay) {
      return DateTime(local.year, local.month, local.day).toUtc();
    }
    return DateTime(local.year, local.month, local.day, 23, 59, 59, 999)
        .toUtc();
  }

  DateTime? _itemCreatedAt(Map<String, dynamic> item) {
    final raw = (item['created_at'] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  bool _metadataContainsCurrency(Map<String, dynamic> item, String currency) {
    final metadata = item['metadata'];
    if (metadata is! Map) return false;
    for (final entry in metadata.entries) {
      final key = entry.key.toString().toLowerCase();
      final value = entry.value.toString().toLowerCase();
      if ((key.contains('currency') || key.contains('cur')) &&
          value == currency.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  List<Map<String, dynamic>> get _visibleItems {
    final moduleFilter = _moduleCtrl.text.trim().toLowerCase();
    final actionFilter = _actionCtrl.text.trim().toLowerCase();
    final currencyFilter = _currencyCtrl.text.trim().toLowerCase();
    final fromDate = _parseDateFilter(_fromDateCtrl.text, endOfDay: false);
    final toDate = _parseDateFilter(_toDateCtrl.text, endOfDay: true);
    return _items.where((item) {
      final eventType = (item['event_type'] ?? '').toString().toLowerCase();
      if (_eventFilter == 'payment' && !_isPaymentEvent(eventType)) {
        return false;
      }
      if (moduleFilter.isNotEmpty &&
          !(item['module_id'] ?? '')
              .toString()
              .toLowerCase()
              .contains(moduleFilter)) {
        return false;
      }
      if (actionFilter.isNotEmpty &&
          !(item['action'] ?? '')
              .toString()
              .toLowerCase()
              .contains(actionFilter)) {
        return false;
      }
      if (currencyFilter.isNotEmpty &&
          !_metadataContainsCurrency(item, currencyFilter)) {
        return false;
      }
      final createdAt = _itemCreatedAt(item);
      if (fromDate != null &&
          createdAt != null &&
          createdAt.isBefore(fromDate)) {
        return false;
      }
      if (toDate != null && createdAt != null && createdAt.isAfter(toDate)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }

  String _csvCell(Object? value) {
    final raw = (value ?? '').toString();
    final escaped = raw.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _copyCsv(L10n l) async {
    final rows = <String>[
      [
        'id',
        'created_at',
        'event_type',
        'username',
        'account_id',
        'module_id',
        'action',
        'route',
        'metadata',
      ].map(_csvCell).join(','),
      for (final item in _visibleItems)
        [
          item['id'],
          item['created_at'],
          item['event_type'],
          item['username'],
          item['account_id'],
          item['module_id'],
          item['action'],
          item['route'],
          jsonEncode(item['metadata'] ?? const <String, Object?>{}),
        ].map(_csvCell).join(','),
    ];
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.isArabic ? 'تم نسخ CSV.' : 'CSV copied.'),
      ),
    );
  }

  String _eventTitle(String value, L10n l) {
    switch (value) {
      case 'signup':
        return l.isArabic ? 'تسجيل جديد' : 'Signup';
      case 'module_open':
        return l.isArabic ? 'فتح وحدة' : 'Module opened';
      case 'payment_transfer_sent':
      case 'payment_scan_transfer_sent':
      case 'payment_group_transfer_sent':
        return l.isArabic ? 'تحويل أموال' : 'Money transfer';
      case 'payment_request_accepted':
        return l.isArabic ? 'قبول طلب دفع' : 'Payment request accepted';
      case 'payment_requests_created':
        return l.isArabic ? 'إنشاء طلبات دفع' : 'Payment requests created';
      case 'payment_exchange_quote_created':
        return l.isArabic ? 'عرض صرف' : 'Exchange quote';
      default:
        return value.replaceAll('_', ' ');
    }
  }

  Color _eventColor(String value) {
    switch (value) {
      case 'signup':
        return const Color(0xFF0F766E);
      case 'module_open':
        return const Color(0xFF2563EB);
      case 'payment_transfer_sent':
      case 'payment_scan_transfer_sent':
      case 'payment_group_transfer_sent':
      case 'payment_request_accepted':
      case 'payment_requests_created':
      case 'payment_exchange_quote_created':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF475569);
    }
  }

  IconData _eventIcon(String value) {
    if (value == 'signup') return Icons.person_add_alt_1_outlined;
    if (_isPaymentEvent(value)) return Icons.account_balance_wallet_outlined;
    return Icons.touch_app_outlined;
  }

  String _identityLabel(Map<String, dynamic> item, L10n l) {
    for (final key in const <String>[
      'username',
      'shamell_user_id',
      'phone',
      'account_id',
    ]) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return l.isArabic ? 'مستخدم غير معروف' : 'Unknown user';
  }

  String _actionLabel(Map<String, dynamic> item) {
    final parts = <String>[];
    for (final key in const <String>['module_id', 'action', 'route']) {
      final value = (item[key] ?? '').toString().trim();
      if (value.isNotEmpty) parts.add(value);
    }
    return parts.join(' / ');
  }

  String _metadataLabel(Map<String, dynamic> item) {
    final metadata = item['metadata'];
    if (metadata is! Map || metadata.isEmpty) return '';
    final parts = <String>[];
    for (final entry in metadata.entries.take(3)) {
      final key = entry.key.toString();
      final value = entry.value.toString();
      if (key.trim().isEmpty || value.trim().isEmpty) continue;
      parts.add('$key: $value');
    }
    return parts.join('  ');
  }

  int _countEvent(List<Map<String, dynamic>> source, String eventType) {
    return source
        .where((item) => (item['event_type'] ?? '').toString() == eventType)
        .length;
  }

  int _countPayments(List<Map<String, dynamic>> source) {
    return source
        .where((item) => _isPaymentEvent((item['event_type'] ?? '').toString()))
        .length;
  }

  int _countUniqueUsers(List<Map<String, dynamic>> source) {
    return source
        .map((item) => _identityLabel(item, L10n.of(context)))
        .toSet()
        .length;
  }

  Widget _summaryTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _platformSummaryInt(String key) {
    final value = _platformSummary?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  List<Map<String, dynamic>> _platformSummaryList(String key) {
    final value = _platformSummary?[key];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  int _dashboardsOverviewInt(String key) {
    final value = _dashboardsOverview?[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  List<Map<String, dynamic>> _dashboardsOverviewList(String key) {
    final value = _dashboardsOverview?[key];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  Map<String, dynamic> get _controlIntelligence {
    final value = _dashboardsOverview?['control_intelligence'];
    return value is Map
        ? value.cast<String, dynamic>()
        : const <String, dynamic>{};
  }

  int _controlIntelligenceInt(String key) {
    final value = _controlIntelligence[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  List<Map<String, dynamic>> _controlIntelligenceList(String key) {
    final value = _controlIntelligence[key];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  Color _controlIntelligenceStatusColor(String status) {
    switch (status) {
      case 'action':
        return const Color(0xFFDC2626);
      case 'watch':
        return const Color(0xFFC2410C);
      default:
        return const Color(0xFF0F766E);
    }
  }

  Widget _controlIntelligencePanel(L10n l) {
    final intelligence = _controlIntelligence;
    if (intelligence.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final status = (intelligence['status'] ?? 'healthy').toString();
    final statusColor = _controlIntelligenceStatusColor(status);
    final lanes = _controlIntelligenceList('lanes');
    final priorities = _controlIntelligenceList('priorities');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, color: statusColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.isArabic ? 'ذكاء التحكم' : 'Control intelligence',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${_controlIntelligenceInt('operational_score')}',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l.isArabic
                ? '${_controlIntelligenceInt('attention_total')} إشارات اهتمام · ${_controlIntelligenceInt('source_authority_percent')}% سلطة أحداث'
                : '${_controlIntelligenceInt('attention_total')} attention signal(s) · ${_controlIntelligenceInt('source_authority_percent')}% event authority',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .72),
            ),
          ),
          if (lanes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: lanes.take(5).map((lane) {
                final laneStatus = (lane['status'] ?? 'healthy').toString();
                final laneColor = _controlIntelligenceStatusColor(laneStatus);
                final title = (lane['title'] ?? lane['id'] ?? '').toString();
                final count = (lane['signal_count'] ?? '0').toString();
                return Chip(
                  avatar: Icon(Icons.circle, size: 10, color: laneColor),
                  label: Text('$title · $count'),
                );
              }).toList(growable: false),
            ),
          ],
          if (priorities.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final priority in priorities.take(2))
              Text(
                '• ${(priority['title'] ?? '').toString()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .80),
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic> _dashboardMap(
    Map<String, dynamic>? dashboard,
    String key,
  ) {
    final value = dashboard?[key];
    return value is Map
        ? value.cast<String, dynamic>()
        : const <String, dynamic>{};
  }

  int _dashboardSummaryInt(Map<String, dynamic>? dashboard, String key) {
    final value = _dashboardMap(dashboard, 'summary')[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  List<Map<String, dynamic>> _dashboardList(
    Map<String, dynamic>? dashboard,
    String key,
  ) {
    final value = dashboard?[key];
    if (value is! List) return const <Map<String, dynamic>>[];
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList(growable: false);
  }

  int _dashboardLatestSeriesInt(
    Map<String, dynamic>? dashboard,
    String key,
  ) {
    final series = _dashboardList(dashboard, 'series_30d');
    if (series.isEmpty) return 0;
    final value = series.last[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  String _dashboardLatestSeriesDay(Map<String, dynamic>? dashboard) {
    final series = _dashboardList(dashboard, 'series_30d');
    if (series.isEmpty) return '';
    return (series.last['day'] ?? '').toString();
  }

  Widget _dashboardDetailFrame({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    Map<String, dynamic>? dashboard,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final authorityRows = _dashboardList(dashboard, 'source_authorities_30d');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.78),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.12),
                foregroundColor: color,
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (authorityRows.isNotEmpty) ...[
            _dashboardAuthorityChips(authorityRows, L10n.of(context)),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }

  IconData _dashboardAuthorityIcon(String source) {
    if (source == 'server_authoritative') {
      return Icons.verified_user_outlined;
    }
    if (source == 'client_authenticated') {
      return Icons.phone_android_outlined;
    }
    return Icons.help_outline;
  }

  String _dashboardAuthorityLabel(String source, L10n l) {
    if (source == 'server_authoritative') {
      return l.isArabic ? 'الخادم' : 'Server';
    }
    if (source == 'client_authenticated') {
      return l.isArabic ? 'العميل' : 'Client';
    }
    return l.isArabic ? 'قديم/غير معروف' : 'Legacy/unknown';
  }

  Widget _dashboardAuthorityChips(
    List<Map<String, dynamic>> authorities,
    L10n l,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: authorities.take(4).map((item) {
        final source = (item['source_authority'] ?? '').toString();
        final count = (item['event_count'] ?? '0').toString();
        return Chip(
          avatar: Icon(_dashboardAuthorityIcon(source), size: 16),
          label: Text('${_dashboardAuthorityLabel(source, l)} · $count'),
        );
      }).toList(growable: false),
    );
  }

  IconData _miniProgramManifestAuthorityIcon(String authority) {
    if (authority == 'server_released_bundle') {
      return Icons.cloud_done_outlined;
    }
    if (authority == 'server_native_manifest') {
      return Icons.widgets_outlined;
    }
    if (authority == 'server_review_pending') {
      return Icons.fact_check_outlined;
    }
    if (authority == 'server_restricted') {
      return Icons.lock_outline;
    }
    return Icons.help_outline;
  }

  String _miniProgramManifestAuthorityLabel(String authority, L10n l) {
    switch (authority) {
      case 'server_released_bundle':
        return l.isArabic ? 'حزمة خادم' : 'Server bundle';
      case 'server_native_manifest':
        return l.isArabic ? 'بيان خادم' : 'Server native';
      case 'server_review_pending':
        return l.isArabic ? 'مراجعة' : 'Review pending';
      case 'server_changes_requested':
        return l.isArabic ? 'تغييرات' : 'Changes';
      case 'server_rejected':
        return l.isArabic ? 'مرفوض' : 'Rejected';
      case 'server_restricted':
        return l.isArabic ? 'مقيّد' : 'Restricted';
      case 'server_draft':
        return l.isArabic ? 'مسودة' : 'Draft';
      case 'local_fallback':
        return l.isArabic ? 'محلي' : 'Local fallback';
      default:
        return l.isArabic ? 'قديم/غير معروف' : 'Legacy/unknown';
    }
  }

  Widget _miniProgramManifestAuthorityChips(
    List<Map<String, dynamic>> authorities,
    L10n l,
  ) {
    if (authorities.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: authorities.take(5).map((item) {
        final authority = (item['manifest_authority'] ?? '').toString();
        final count = (item['event_count'] ?? '0').toString();
        return Chip(
          avatar: Icon(_miniProgramManifestAuthorityIcon(authority), size: 16),
          label: Text(
            '${_miniProgramManifestAuthorityLabel(authority, l)} · $count',
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _dashboardFeatureChips(
    List<Map<String, dynamic>> features,
    L10n l,
  ) {
    if (features.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: features.take(6).map((item) {
        final feature = (item['feature_key'] ?? '').toString();
        final action = (item['action'] ?? '').toString();
        final count = (item['event_count'] ?? '0').toString();
        final title = [
          if (feature.isNotEmpty) feature.replaceAll('_', ' '),
          if (action.isNotEmpty) action.replaceAll('_', ' '),
        ].join(' / ');
        return Chip(
          avatar: const Icon(Icons.query_stats_outlined, size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              title.isEmpty ? count : '$title · $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  IconData _momentsVisibilityIcon(String scope) {
    switch (scope) {
      case 'public':
        return Icons.public_outlined;
      case 'friends':
        return Icons.group_outlined;
      case 'tag':
        return Icons.sell_outlined;
      case 'friends_except':
        return Icons.group_remove_outlined;
      case 'only_me':
      case 'private':
        return Icons.lock_outline;
      default:
        return Icons.help_outline;
    }
  }

  String _momentsVisibilityLabel(String scope, L10n l) {
    switch (scope) {
      case 'public':
        return l.isArabic ? 'عام' : 'Public';
      case 'friends':
        return l.isArabic ? 'الأصدقاء' : 'Friends';
      case 'tag':
        return l.isArabic ? 'وسم خاص' : 'Tagged';
      case 'friends_except':
        return l.isArabic ? 'أصدقاء باستثناء' : 'Friends except';
      case 'only_me':
      case 'private':
        return l.isArabic ? 'أنا فقط' : 'Only me';
      default:
        return l.isArabic ? 'غير معروف' : 'Unknown';
    }
  }

  Widget _momentsVisibilityChips(
    List<Map<String, dynamic>> breakdown,
    L10n l,
  ) {
    if (breakdown.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: breakdown.take(6).map((item) {
        final scope = (item['visibility_scope'] ?? '').toString();
        final count = (item['event_count'] ?? '0').toString();
        return Chip(
          avatar: Icon(_momentsVisibilityIcon(scope), size: 16),
          label: Text('${_momentsVisibilityLabel(scope, l)} · $count'),
        );
      }).toList(growable: false),
    );
  }

  Widget _momentsMiniProgramEmbedChips(
    List<Map<String, dynamic>> embeds,
    L10n l,
  ) {
    if (embeds.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: embeds.take(6).map((item) {
        final id = (item['mini_program_id'] ?? '').toString().trim();
        final title = (item['title_en'] ?? '').toString().trim();
        final label = title.isNotEmpty
            ? title
            : (id.isNotEmpty
                ? id
                : (l.isArabic ? 'برنامج مصغّر' : 'Mini Program'));
        final embeds30d = (item['embeds_30d'] ?? '0').toString();
        final authors = (item['unique_authors_30d'] ?? '0').toString();
        return Chip(
          avatar: const Icon(Icons.widgets_outlined, size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              l.isArabic
                  ? '$label · $embeds30d تضمين · $authors مؤلف'
                  : '$label · $embeds30d embeds · $authors authors',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _momentsDashboardPanel(L10n l) {
    if (_momentsDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_momentsDashboard);
    final features = _dashboardList(_momentsDashboard, 'features_30d');
    final visibilityBreakdown =
        _dashboardList(_momentsDashboard, 'visibility_breakdown');
    final miniProgramEmbeds =
        _dashboardList(_momentsDashboard, 'mini_program_embeds');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة اللحظات' : 'Moments control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic ? 'خصوصية وتفاعل' : 'Privacy and engagement')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.photo_library_outlined,
      color: const Color(0xFF0F766E),
      dashboard: _momentsDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'منشورات ٣٠ي' : 'Posts 30d',
              value: _dashboardSummaryInt(_momentsDashboard, 'posts_30d')
                  .toString(),
              icon: Icons.add_photo_alternate_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مؤلفون نشطون' : 'Active authors',
              value:
                  _dashboardSummaryInt(_momentsDashboard, 'active_authors_30d')
                      .toString(),
              icon: Icons.groups_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'إعجابات' : 'Likes',
              value: _dashboardSummaryInt(_momentsDashboard, 'likes_total')
                  .toString(),
              icon: Icons.favorite_border,
              color: const Color(0xFFBE123C),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'تعليقات' : 'Comments',
              value: _dashboardSummaryInt(_momentsDashboard, 'comments_total')
                  .toString(),
              icon: Icons.mode_comment_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'وسوم خاصة' : 'Tagged privacy',
              value: _dashboardSummaryInt(_momentsDashboard, 'tag_scoped_posts')
                  .toString(),
              icon: Icons.sell_outlined,
              color: const Color(0xFF059669),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'بلاغات' : 'Reports',
              value: _dashboardSummaryInt(_momentsDashboard, 'reports_total')
                  .toString(),
              icon: Icons.report_gmailerrorred_outlined,
              color: const Color(0xFFDC2626),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'عام' : 'Public',
              value: _dashboardSummaryInt(_momentsDashboard, 'public_posts')
                  .toString(),
              icon: Icons.public_outlined,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'محمي' : 'Protected',
              value: _dashboardSummaryInt(_momentsDashboard, 'protected_posts')
                  .toString(),
              icon: Icons.privacy_tip_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'برامج مصغرة ٣٠ي' : 'Mini Programs 30d',
              value: _dashboardSummaryInt(
                _momentsDashboard,
                'mini_program_posts_30d',
              ).toString(),
              icon: Icons.apps_outlined,
              color: const Color(0xFF07C160),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'تضمينات البرامج' : 'MP embeds',
              value:
                  _dashboardSummaryInt(_momentsDashboard, 'mini_program_posts')
                      .toString(),
              icon: Icons.widgets_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'برامج اليوم' : 'MP today',
              value: _dashboardLatestSeriesInt(
                _momentsDashboard,
                'mini_program_posts',
              ).toString(),
              icon: Icons.widgets_outlined,
              color: const Color(0xFF07C160),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'تفاعل اليوم' : 'Engage today',
              value: _dashboardLatestSeriesInt(
                _momentsDashboard,
                'engagement_events',
              ).toString(),
              icon: Icons.bolt_outlined,
              color: const Color(0xFFEA580C),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'خصوصية اليوم' : 'Privacy today',
              value: _dashboardLatestSeriesInt(
                _momentsDashboard,
                'privacy_events',
              ).toString(),
              icon: Icons.lock_outline,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'الأمان اليوم' : 'Safety today',
              value: _dashboardLatestSeriesInt(
                _momentsDashboard,
                'safety_events',
              ).toString(),
              icon: Icons.shield_outlined,
              color: const Color(0xFFDC2626),
            ),
          ],
        ),
        if (miniProgramEmbeds.isNotEmpty) ...[
          const SizedBox(height: 10),
          _momentsMiniProgramEmbedChips(miniProgramEmbeds, l),
        ],
        if (visibilityBreakdown.isNotEmpty) ...[
          const SizedBox(height: 10),
          _momentsVisibilityChips(visibilityBreakdown, l),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _officialAccountsTopChips(
    List<Map<String, dynamic>> accounts,
    L10n l,
  ) {
    if (accounts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: accounts.take(6).map((item) {
        final name = (item['official_name'] ?? '').toString().trim();
        final id = (item['official_account_id'] ?? '').toString().trim();
        final label = name.isNotEmpty
            ? name
            : (id.isNotEmpty
                ? id
                : (l.isArabic ? 'حساب رسمي' : 'Official account'));
        final followers = (item['followers'] ?? '0').toString();
        final feedItems = (item['feed_items'] ?? '0').toString();
        return Chip(
          avatar: const Icon(Icons.verified_outlined, size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              '$label · $followers follows · $feedItems posts',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _officialAccountsDashboardPanel(L10n l) {
    if (_officialAccountsDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_officialAccountsDashboard);
    final accounts = _dashboardList(_officialAccountsDashboard, 'top_accounts');
    final features = _dashboardList(_officialAccountsDashboard, 'features_30d');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة الحسابات الرسمية' : 'Official accounts control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic ? 'متابعة ومنشورات وقوالب' : 'Follows, feed, templates')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.verified_outlined,
      color: const Color(0xFF0891B2),
      dashboard: _officialAccountsDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حسابات موثقة' : 'Verified accounts',
              value: _dashboardSummaryInt(
                _officialAccountsDashboard,
                'verified_accounts',
              ).toString(),
              icon: Icons.verified_user_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'متابعون' : 'Follows',
              value: _dashboardSummaryInt(
                _officialAccountsDashboard,
                'follows_total',
              ).toString(),
              icon: Icons.how_to_reg_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'منشورات ٣٠ي' : 'Feed items 30d',
              value: _dashboardSummaryInt(
                _officialAccountsDashboard,
                'feed_items_30d',
              ).toString(),
              icon: Icons.article_outlined,
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'قوالب غير مقروءة' : 'Unread templates',
              value: _dashboardSummaryInt(
                _officialAccountsDashboard,
                'template_unread_total',
              ).toString(),
              icon: Icons.mark_email_unread_outlined,
              color: const Color(0xFFEA580C),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حملات نشطة' : 'Active campaigns',
              value: _dashboardSummaryInt(
                _officialAccountsDashboard,
                'active_campaigns',
              ).toString(),
              icon: Icons.card_giftcard_outlined,
              color: const Color(0xFF16A34A),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'صامتة' : 'Muted follows',
              value: _dashboardSummaryInt(
                _officialAccountsDashboard,
                'muted_follows',
              ).toString(),
              icon: Icons.notifications_off_outlined,
              color: const Color(0xFF64748B),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'زيارة اليوم' : 'Profile today',
              value: _dashboardLatestSeriesInt(
                _officialAccountsDashboard,
                'profile_view_events',
              ).toString(),
              icon: Icons.badge_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'قراءات اليوم' : 'Feed today',
              value: _dashboardLatestSeriesInt(
                _officialAccountsDashboard,
                'feed_view_events',
              ).toString(),
              icon: Icons.auto_stories_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: 10),
          _officialAccountsTopChips(accounts, l),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _miniProgramsTopChips(
    List<Map<String, dynamic>> programs,
    L10n l,
  ) {
    if (programs.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: programs.take(6).map((item) {
        final title = (item['title_en'] ?? '').toString().trim();
        final appId = (item['app_id'] ?? '').toString().trim();
        final label = title.isNotEmpty
            ? title
            : (appId.isNotEmpty
                ? appId
                : (l.isArabic ? 'برنامج مصغر' : 'Mini program'));
        final opens = (item['shelf_opens'] ?? '0').toString();
        final users = (item['shelf_users'] ?? '0').toString();
        final authority = (item['manifest_authority'] ?? '').toString();
        final authorityLabel = authority.isEmpty
            ? ''
            : _miniProgramManifestAuthorityLabel(authority, l);
        final parts = <String>[
          '$opens opens',
          '$users users',
          if (authorityLabel.isNotEmpty) authorityLabel,
        ];
        return Chip(
          avatar: const Icon(Icons.widgets_outlined, size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              '$label · ${parts.join(' · ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _miniProgramsDashboardPanel(L10n l) {
    if (_miniProgramsDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_miniProgramsDashboard);
    final programs = _dashboardList(_miniProgramsDashboard, 'top_programs');
    final features = _dashboardList(_miniProgramsDashboard, 'features_30d');
    final manifestAuthorities =
        _dashboardList(_miniProgramsDashboard, 'manifest_authorities_30d');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة البرامج المصغرة' : 'Mini programs control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic ? 'السجل والمراجعة والرف' : 'Registry, review, shelf')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.widgets_outlined,
      color: const Color(0xFF7C3AED),
      dashboard: _miniProgramsDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'منشورة' : 'Published',
              value: _dashboardSummaryInt(
                _miniProgramsDashboard,
                'published_programs',
              ).toString(),
              icon: Icons.cloud_done_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'قيد المراجعة' : 'Review queue',
              value: _dashboardSummaryInt(
                _miniProgramsDashboard,
                'review_queue',
              ).toString(),
              icon: Icons.fact_check_outlined,
              color: const Color(0xFFDC2626),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'إصدارات' : 'Versions',
              value: _dashboardSummaryInt(
                _miniProgramsDashboard,
                'versions_total',
              ).toString(),
              icon: Icons.new_releases_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مثبتة على الرف' : 'Pinned shelf',
              value: _dashboardSummaryInt(
                _miniProgramsDashboard,
                'pinned_shelf_items',
              ).toString(),
              icon: Icons.push_pin_outlined,
              color: const Color(0xFF059669),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'فتح ٣٠ي' : 'Opens 30d',
              value: _dashboardSummaryInt(
                _miniProgramsDashboard,
                'open_events_30d',
              ).toString(),
              icon: Icons.open_in_new_outlined,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'إصدارات مرئية' : 'Seen releases',
              value: _dashboardSummaryInt(
                _miniProgramsDashboard,
                'seen_releases',
              ).toString(),
              icon: Icons.visibility_outlined,
              color: const Color(0xFFEA580C),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'فتح اليوم' : 'Open today',
              value: _dashboardLatestSeriesInt(
                _miniProgramsDashboard,
                'open_events',
              ).toString(),
              icon: Icons.bolt_outlined,
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مراجعة اليوم' : 'Review today',
              value: _dashboardLatestSeriesInt(
                _miniProgramsDashboard,
                'review_events',
              ).toString(),
              icon: Icons.rule_outlined,
              color: const Color(0xFFDC2626),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حزم خادم ٣٠ي' : 'Bundle opens 30d',
              value: _dashboardSummaryInt(
                _miniProgramsDashboard,
                'open_server_bundle_events_30d',
              ).toString(),
              icon: Icons.cloud_done_outlined,
              color: const Color(0xFF0D9488),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'بيان خادم ٣٠ي' : 'Native opens 30d',
              value: _dashboardSummaryInt(
                _miniProgramsDashboard,
                'open_server_native_events_30d',
              ).toString(),
              icon: Icons.widgets_outlined,
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
        if (manifestAuthorities.isNotEmpty) ...[
          const SizedBox(height: 10),
          _miniProgramManifestAuthorityChips(manifestAuthorities, l),
        ],
        if (programs.isNotEmpty) ...[
          const SizedBox(height: 10),
          _miniProgramsTopChips(programs, l),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _stickerPackChips(List<Map<String, dynamic>> packs, L10n l) {
    if (packs.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: packs.take(6).map((item) {
        final title = (item['title_en'] ?? '').toString().trim();
        final id = (item['pack_id'] ?? '').toString().trim();
        final label = title.isNotEmpty
            ? title
            : (id.isNotEmpty ? id : (l.isArabic ? 'حزمة' : 'Pack'));
        final users = (item['install_users'] ?? '0').toString();
        final items = (item['item_count'] ?? '0').toString();
        return Chip(
          avatar: const Icon(Icons.emoji_emotions_outlined, size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              '$label · $users installs · $items items',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _stickersDashboardPanel(L10n l) {
    if (_stickersDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_stickersDashboard);
    final packs = _dashboardList(_stickersDashboard, 'top_packs');
    final features = _dashboardList(_stickersDashboard, 'features_30d');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة الملصقات' : 'Stickers control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic
              ? 'المتجر والحزم والحقوق'
              : 'Store, packs, entitlements')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.emoji_emotions_outlined,
      color: const Color(0xFFDB2777),
      dashboard: _stickersDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حزم مفعلة' : 'Enabled packs',
              value: _dashboardSummaryInt(_stickersDashboard, 'enabled_packs')
                  .toString(),
              icon: Icons.storefront_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مميزة' : 'Featured',
              value: _dashboardSummaryInt(_stickersDashboard, 'featured_packs')
                  .toString(),
              icon: Icons.star_outline,
              color: const Color(0xFFB45309),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'ملصقات' : 'Items',
              value: _dashboardSummaryInt(_stickersDashboard, 'items_total')
                  .toString(),
              icon: Icons.collections_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'تثبيتات' : 'Installs',
              value: _dashboardSummaryInt(_stickersDashboard, 'installs_total')
                  .toString(),
              icon: Icons.download_done_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'مستخدمون ٣٠ي' : 'Active 30d',
              value: _dashboardSummaryInt(
                _stickersDashboard,
                'active_users_30d',
              ).toString(),
              icon: Icons.people_alt_outlined,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'أحداث ٣٠ي' : 'Events 30d',
              value:
                  _dashboardSummaryInt(_stickersDashboard, 'store_events_30d')
                      .toString(),
              icon: Icons.query_stats_outlined,
              color: const Color(0xFFDB2777),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'تثبيت اليوم' : 'Installs today',
              value: _dashboardLatestSeriesInt(_stickersDashboard, 'installs')
                  .toString(),
              icon: Icons.bolt_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'شراء اليوم' : 'Purchase today',
              value: _dashboardLatestSeriesInt(
                _stickersDashboard,
                'purchase_events',
              ).toString(),
              icon: Icons.shopping_bag_outlined,
              color: const Color(0xFFDB2777),
            ),
          ],
        ),
        if (packs.isNotEmpty) ...[
          const SizedBox(height: 10),
          _stickerPackChips(packs, l),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _cardOfferChips(List<Map<String, dynamic>> offers, L10n l) {
    if (offers.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: offers.take(6).map((item) {
        final title = (item['title_en'] ?? '').toString().trim();
        final id = (item['offer_id'] ?? '').toString().trim();
        final label = title.isNotEmpty
            ? title
            : (id.isNotEmpty ? id : (l.isArabic ? 'عرض' : 'Offer'));
        final holders = (item['holder_count'] ?? '0').toString();
        final redeems = (item['redeemed_count'] ?? '0').toString();
        return Chip(
          avatar: const Icon(Icons.local_offer_outlined, size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              '$label · $holders holders · $redeems redeemed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _cardsDashboardPanel(L10n l) {
    if (_cardsDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_cardsDashboard);
    final offers = _dashboardList(_cardsDashboard, 'top_offers');
    final kinds = _dashboardList(_cardsDashboard, 'kinds');
    final features = _dashboardList(_cardsDashboard, 'features_30d');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة البطاقات والعروض' : 'Cards control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic ? 'قسائم وبطاقات وحقوق' : 'Coupons, cards, redemption')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.local_offer_outlined,
      color: const Color(0xFF0F766E),
      dashboard: _cardsDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'عروض نشطة' : 'Active offers',
              value: _dashboardSummaryInt(_cardsDashboard, 'active_offers')
                  .toString(),
              icon: Icons.confirmation_number_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مميزة' : 'Featured',
              value: _dashboardSummaryInt(_cardsDashboard, 'featured_offers')
                  .toString(),
              icon: Icons.star_outline,
              color: const Color(0xFFB45309),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'محفوظة' : 'Claimed',
              value: _dashboardSummaryInt(_cardsDashboard, 'claimed_total')
                  .toString(),
              icon: Icons.wallet_membership_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مستخدمة' : 'Redeemed',
              value: _dashboardSummaryInt(_cardsDashboard, 'redeemed_total')
                  .toString(),
              icon: Icons.task_alt_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حاملو بطاقات' : 'Cardholders',
              value:
                  _dashboardSummaryInt(_cardsDashboard, 'cardholder_accounts')
                      .toString(),
              icon: Icons.people_alt_outlined,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'أحداث ٣٠ي' : 'Events 30d',
              value: _dashboardSummaryInt(_cardsDashboard, 'card_events_30d')
                  .toString(),
              icon: Icons.query_stats_outlined,
              color: const Color(0xFFBE123C),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حفظ اليوم' : 'Claims today',
              value: _dashboardLatestSeriesInt(_cardsDashboard, 'claims')
                  .toString(),
              icon: Icons.bolt_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'استخدام اليوم' : 'Redeems today',
              value: _dashboardLatestSeriesInt(_cardsDashboard, 'redeems')
                  .toString(),
              icon: Icons.redeem_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        if (offers.isNotEmpty) ...[
          const SizedBox(height: 10),
          _cardOfferChips(offers, l),
        ],
        if (kinds.isNotEmpty) ...[
          const SizedBox(height: 10),
          _simpleCountChips(
            items: kinds,
            labelKey: 'kind',
            countKey: 'offer_count',
            icon: Icons.category_outlined,
          ),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _greenPaketCampaignChips(
    List<Map<String, dynamic>> campaigns,
    L10n l,
  ) {
    if (campaigns.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: campaigns.take(6).map((item) {
        final title = (item['title'] ?? '').toString().trim();
        final id = (item['campaign_id'] ?? item['id'] ?? '').toString().trim();
        final label = title.isNotEmpty
            ? title
            : (id.isNotEmpty ? id : (l.isArabic ? 'حملة' : 'Campaign'));
        final issued = (item['packets_issued'] ?? '0').toString();
        final claimed = (item['packets_claimed'] ?? '0').toString();
        return Chip(
          avatar: const Icon(Icons.card_giftcard_outlined, size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              '$label · $issued issued · $claimed claimed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _greenPaketDashboardPanel(L10n l) {
    if (_greenPaketDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_greenPaketDashboard);
    final campaigns = _dashboardList(_greenPaketDashboard, 'top_campaigns');
    final features = _dashboardList(_greenPaketDashboard, 'features_30d');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة Green Paket' : 'Green Paket control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic
              ? 'حملات ومدفوعات اجتماعية'
              : 'Campaigns and social pay')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.card_giftcard_outlined,
      color: const Color(0xFF16A34A),
      dashboard: _greenPaketDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حملات نشطة' : 'Active campaigns',
              value: _dashboardSummaryInt(
                _greenPaketDashboard,
                'campaigns_active',
              ).toString(),
              icon: Icons.campaign_outlined,
              color: const Color(0xFF16A34A),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'حسابات نشطة' : 'Active officials',
              value: _dashboardSummaryInt(
                _greenPaketDashboard,
                'active_officials',
              ).toString(),
              icon: Icons.verified_outlined,
              color: const Color(0xFF0891B2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حزم ٣٠ي' : 'Packets 30d',
              value: _dashboardSummaryInt(
                _greenPaketDashboard,
                'campaign_packets_30d',
              ).toString(),
              icon: Icons.outbox_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مطالبات ٣٠ي' : 'Claims 30d',
              value: _dashboardSummaryInt(
                _greenPaketDashboard,
                'claims_30d',
              ).toString(),
              icon: Icons.payments_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'إدارة ٣٠ي' : 'Admin 30d',
              value: _dashboardSummaryInt(
                _greenPaketDashboard,
                'admin_events_30d',
              ).toString(),
              icon: Icons.manage_accounts_outlined,
              color: const Color(0xFFB45309),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مشاركات اللحظات' : 'Moment shares',
              value: _dashboardSummaryInt(
                _greenPaketDashboard,
                'moments_shares_30d',
              ).toString(),
              icon: Icons.photo_library_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حزم اليوم' : 'Packets today',
              value: _dashboardLatestSeriesInt(
                _greenPaketDashboard,
                'packets',
              ).toString(),
              icon: Icons.card_giftcard_outlined,
              color: const Color(0xFF16A34A),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مطالبات اليوم' : 'Claims today',
              value: _dashboardLatestSeriesInt(
                _greenPaketDashboard,
                'claims',
              ).toString(),
              icon: Icons.task_alt_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        if (campaigns.isNotEmpty) ...[
          const SizedBox(height: 10),
          _greenPaketCampaignChips(campaigns, l),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _simpleCountChips({
    required List<Map<String, dynamic>> items,
    required String labelKey,
    required String countKey,
    required IconData icon,
    int maxItems = 6,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.take(maxItems).map((item) {
        final label = (item[labelKey] ?? '').toString().replaceAll('_', ' ');
        final count = (item[countKey] ?? '0').toString();
        return Chip(
          avatar: Icon(icon, size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text(
              label.isEmpty ? count : '$label · $count',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _discoverDashboardPanel(L10n l) {
    if (_discoverDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_discoverDashboard);
    final segments = _dashboardList(_discoverDashboard, 'profile_segments');
    final features = _dashboardList(_discoverDashboard, 'features_30d');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة الاكتشاف' : 'Discover control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic ? 'بحث وقريبون' : 'Search and People Nearby')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.travel_explore_outlined,
      color: const Color(0xFF2563EB),
      dashboard: _discoverDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'بحث ٣٠ي' : 'Search 30d',
              value: _dashboardSummaryInt(
                _discoverDashboard,
                'global_search_events_30d',
              ).toString(),
              icon: Icons.search_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'قريبون ٣٠ي' : 'Nearby 30d',
              value: _dashboardSummaryInt(
                _discoverDashboard,
                'nearby_search_events_30d',
              ).toString(),
              icon: Icons.explore_outlined,
              color: const Color(0xFF059669),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'مرئية' : 'Visible profiles',
              value: _dashboardSummaryInt(
                _discoverDashboard,
                'nearby_visible_profiles',
              ).toString(),
              icon: Icons.location_on_outlined,
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'محددة الموقع' : 'Located profiles',
              value: _dashboardSummaryInt(
                _discoverDashboard,
                'nearby_located_profiles',
              ).toString(),
              icon: Icons.my_location_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'بحث اليوم' : 'Search today',
              value: _dashboardLatestSeriesInt(
                _discoverDashboard,
                'global_search_events',
              ).toString(),
              icon: Icons.query_stats_outlined,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'تحديثات اليوم' : 'Profiles today',
              value: _dashboardLatestSeriesInt(
                _discoverDashboard,
                'nearby_profile_events',
              ).toString(),
              icon: Icons.person_pin_circle_outlined,
              color: const Color(0xFFB45309),
            ),
          ],
        ),
        if (segments.isNotEmpty) ...[
          const SizedBox(height: 10),
          _simpleCountChips(
            items: segments,
            labelKey: 'segment',
            countKey: 'profile_count',
            icon: Icons.people_alt_outlined,
          ),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _favoritesDashboardPanel(L10n l) {
    if (_favoritesDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_favoritesDashboard);
    final kinds = _dashboardList(_favoritesDashboard, 'kinds');
    final sources = _dashboardList(_favoritesDashboard, 'sources');
    final features = _dashboardList(_favoritesDashboard, 'features_30d');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة المحفوظات' : 'Favorites control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic ? 'عناصر محفوظة ورف موحد' : 'Saved items and shelf')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.bookmarks_outlined,
      color: const Color(0xFF047857),
      dashboard: _favoritesDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'محفوظات' : 'Saved items',
              value: _dashboardSummaryInt(
                _favoritesDashboard,
                'favorites_total',
              ).toString(),
              icon: Icons.bookmarks_outlined,
              color: const Color(0xFF047857),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'حسابات تحفظ' : 'Saving accounts',
              value: _dashboardSummaryInt(
                _favoritesDashboard,
                'saving_accounts',
              ).toString(),
              icon: Icons.people_alt_outlined,
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حفظ ٣٠ي' : 'Save events 30d',
              value: _dashboardSummaryInt(
                _favoritesDashboard,
                'save_events_30d',
              ).toString(),
              icon: Icons.add_circle_outline,
              color: const Color(0xFF059669),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'فتح ٣٠ي' : 'Open events 30d',
              value: _dashboardSummaryInt(
                _favoritesDashboard,
                'open_events_30d',
              ).toString(),
              icon: Icons.open_in_new_outlined,
              color: const Color(0xFF0891B2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حفظ اليوم' : 'Saved today',
              value: _dashboardLatestSeriesInt(
                _favoritesDashboard,
                'save_events',
              ).toString(),
              icon: Icons.star_border_outlined,
              color: const Color(0xFFB45309),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'حذف اليوم' : 'Deleted today',
              value: _dashboardLatestSeriesInt(
                _favoritesDashboard,
                'delete_events',
              ).toString(),
              icon: Icons.delete_outline,
              color: const Color(0xFFDC2626),
            ),
          ],
        ),
        if (kinds.isNotEmpty) ...[
          const SizedBox(height: 10),
          _simpleCountChips(
            items: kinds,
            labelKey: 'kind',
            countKey: 'item_count',
            icon: Icons.category_outlined,
          ),
        ],
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 10),
          _simpleCountChips(
            items: sources,
            labelKey: 'source_module',
            countKey: 'item_count',
            icon: Icons.source_outlined,
          ),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _chatDashboardPanel(L10n l) {
    if (_chatDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_chatDashboard);
    final segments = _dashboardList(_chatDashboard, 'segments');
    final features = _dashboardList(_chatDashboard, 'features_30d');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة الدردشة' : 'Chat control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic ? 'تثبيت وكتم ومحادثات' : 'Pins, mutes, conversations')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.chat_bubble_outline,
      color: const Color(0xFF0F766E),
      dashboard: _chatDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'تفضيلات فردية' : 'Conversation prefs',
              value: _dashboardSummaryInt(
                _chatDashboard,
                'conversation_prefs_total',
              ).toString(),
              icon: Icons.forum_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'تفضيلات مجموعات' : 'Group prefs',
              value: _dashboardSummaryInt(
                _chatDashboard,
                'group_prefs_total',
              ).toString(),
              icon: Icons.groups_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'مثبتة' : 'Pinned chats',
              value: _dashboardSummaryInt(
                _chatDashboard,
                'pinned_conversations',
              ).toString(),
              icon: Icons.push_pin_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مكتومة' : 'Muted chats',
              value: _dashboardSummaryInt(
                _chatDashboard,
                'muted_conversations',
              ).toString(),
              icon: Icons.notifications_off_outlined,
              color: const Color(0xFF64748B),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'أحداث ٣٠ي' : 'Prefs 30d',
              value: _dashboardSummaryInt(
                _chatDashboard,
                'chat_pref_events_30d',
              ).toString(),
              icon: Icons.tune_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مجموعات مثبتة' : 'Pinned groups',
              value: _dashboardSummaryInt(
                _chatDashboard,
                'pinned_groups',
              ).toString(),
              icon: Icons.group_work_outlined,
              color: const Color(0xFFB45309),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'فردي اليوم' : 'Conversations today',
              value: _dashboardLatestSeriesInt(
                _chatDashboard,
                'conversation_events',
              ).toString(),
              icon: Icons.bolt_outlined,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مجموعات اليوم' : 'Groups today',
              value: _dashboardLatestSeriesInt(
                _chatDashboard,
                'group_events',
              ).toString(),
              icon: Icons.bolt_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        if (segments.isNotEmpty) ...[
          const SizedBox(height: 10),
          _simpleCountChips(
            items: segments,
            labelKey: 'segment',
            countKey: 'item_count',
            icon: Icons.tune_outlined,
          ),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _contactsDashboardPanel(L10n l) {
    if (_contactsDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_contactsDashboard);
    final tags = _dashboardList(_contactsDashboard, 'tags');
    final segments = _dashboardList(_contactsDashboard, 'segments');
    final features = _dashboardList(_contactsDashboard, 'features_30d');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة جهات الاتصال' : 'Contacts control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic ? 'دعوات ووسوم اجتماعية' : 'Invites and social graph')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.contacts_outlined,
      color: const Color(0xFF0891B2),
      dashboard: _contactsDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'جهات نشطة' : 'Active contacts',
              value: _dashboardSummaryInt(
                _contactsDashboard,
                'active_contact_edges',
              ).toString(),
              icon: Icons.contacts_outlined,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'حسابات' : 'Contact accounts',
              value: _dashboardSummaryInt(
                _contactsDashboard,
                'contact_owner_accounts',
              ).toString(),
              icon: Icons.people_alt_outlined,
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'دعوات نشطة' : 'Active invites',
              value: _dashboardSummaryInt(
                _contactsDashboard,
                'active_invites',
              ).toString(),
              icon: Icons.person_add_alt_outlined,
              color: const Color(0xFF059669),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'استخدام الدعوات' : 'Invite uses',
              value: _dashboardSummaryInt(
                _contactsDashboard,
                'invite_uses_total',
              ).toString(),
              icon: Icons.how_to_reg_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'وسوم' : 'Friend tags',
              value: _dashboardSummaryInt(
                _contactsDashboard,
                'friend_tags_total',
              ).toString(),
              icon: Icons.sell_outlined,
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'أصدقاء موسومون' : 'Tagged pairs',
              value: _dashboardSummaryInt(
                _contactsDashboard,
                'tagged_friend_pairs',
              ).toString(),
              icon: Icons.group_work_outlined,
              color: const Color(0xFFB45309),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'جهات اليوم' : 'Contacts today',
              value: _dashboardLatestSeriesInt(
                _contactsDashboard,
                'contact_edges',
              ).toString(),
              icon: Icons.bolt_outlined,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'وسوم اليوم' : 'Tags today',
              value: _dashboardLatestSeriesInt(
                _contactsDashboard,
                'friend_tags_events',
              ).toString(),
              icon: Icons.bolt_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          _simpleCountChips(
            items: tags,
            labelKey: 'tag',
            countKey: 'pair_count',
            icon: Icons.sell_outlined,
          ),
        ],
        if (segments.isNotEmpty) ...[
          const SizedBox(height: 10),
          _simpleCountChips(
            items: segments,
            labelKey: 'segment',
            countKey: 'item_count',
            icon: Icons.account_tree_outlined,
          ),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _channelsTopAccountChips(
    List<Map<String, dynamic>> accounts,
    L10n l,
  ) {
    if (accounts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: accounts.take(6).map((item) {
        final name = (item['official_name'] ?? '').toString().trim();
        final id = (item['official_account_id'] ?? '').toString().trim();
        final label = name.isNotEmpty
            ? name
            : (id.isNotEmpty
                ? id
                : (l.isArabic ? 'حساب رسمي' : 'Official account'));
        final views = (item['views'] ?? '0').toString();
        final followers = (item['followers'] ?? '0').toString();
        return Chip(
          avatar: const Icon(Icons.verified_outlined, size: 16),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text(
              '$label · $views views · $followers follows',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _channelsDashboardPanel(L10n l) {
    if (_channelsDashboard == null) return const SizedBox.shrink();
    final latestDay = _dashboardLatestSeriesDay(_channelsDashboard);
    final features = _dashboardList(_channelsDashboard, 'features_30d');
    final accounts = _dashboardList(_channelsDashboard, 'top_accounts');
    return _dashboardDetailFrame(
      title: l.isArabic ? 'لوحة القنوات' : 'Channels control',
      subtitle: latestDay.isEmpty
          ? (l.isArabic ? 'نشر ومتابعة' : 'Publishing and follows')
          : (l.isArabic ? 'آخر يوم $latestDay' : 'Latest day $latestDay'),
      icon: Icons.video_collection_outlined,
      color: const Color(0xFF0891B2),
      dashboard: _channelsDashboard,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'عناصر ٣٠ي' : 'Items 30d',
              value: _dashboardSummaryInt(_channelsDashboard, 'items_30d')
                  .toString(),
              icon: Icons.upload_file_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'حسابات نشطة' : 'Active officials',
              value: _dashboardSummaryInt(
                _channelsDashboard,
                'active_officials_30d',
              ).toString(),
              icon: Icons.verified_user_outlined,
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'مشاهدات' : 'Views',
              value: _dashboardSummaryInt(_channelsDashboard, 'views_total')
                  .toString(),
              icon: Icons.visibility_outlined,
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'متابعون' : 'Follows',
              value: _dashboardSummaryInt(_channelsDashboard, 'follows_total')
                  .toString(),
              icon: Icons.subscriptions_outlined,
              color: const Color(0xFF0891B2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'هدايا' : 'Gift coins',
              value:
                  _dashboardSummaryInt(_channelsDashboard, 'gift_coins_total')
                      .toString(),
              icon: Icons.volunteer_activism_outlined,
              color: const Color(0xFFBE123C),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'بث مباشر' : 'Live items',
              value: _dashboardSummaryInt(_channelsDashboard, 'live_items')
                  .toString(),
              icon: Icons.live_tv_outlined,
              color: const Color(0xFFEA580C),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'نشر اليوم' : 'Publish today',
              value: _dashboardLatestSeriesInt(
                _channelsDashboard,
                'publish_events',
              ).toString(),
              icon: Icons.cloud_upload_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'تفاعل اليوم' : 'Engage today',
              value: _dashboardLatestSeriesInt(
                _channelsDashboard,
                'engagement_events',
              ).toString(),
              icon: Icons.bolt_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: 10),
          _channelsTopAccountChips(accounts, l),
        ],
        if (features.isNotEmpty) ...[
          const SizedBox(height: 10),
          _dashboardFeatureChips(features, l),
        ],
      ],
    );
  }

  Widget _platformSummaryPanel(L10n l) {
    final modules = _platformSummaryList('modules');
    final topModules = modules.take(4).map((item) {
      final label = (item['module_id'] ?? '').toString().replaceAll('_', ' ');
      final count = (item['event_count'] ?? '0').toString();
      return Chip(
        avatar: const Icon(Icons.apps_outlined, size: 16),
        label: Text('$label $count'),
      );
    }).toList(growable: false);
    final sourceAuthorities = _platformSummaryList('source_authorities');
    final sourceChips = sourceAuthorities.take(3).map((item) {
      final label =
          (item['source_authority'] ?? '').toString().replaceAll('_', ' ');
      final count = (item['event_count'] ?? '0').toString();
      return Chip(
        avatar: const Icon(Icons.verified_user_outlined, size: 16),
        label: Text('$label $count'),
      );
    }).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'المنصة' : 'Platform',
              value: _platformSummaryInt('total_events').toString(),
              icon: Icons.dashboard_customize_outlined,
              color: const Color(0xFF0EA5E9),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'البرامج المصغرة' : 'Mini programs',
              value: _platformSummaryInt('mini_program_events').toString(),
              icon: Icons.widgets_outlined,
              color: const Color(0xFF16A34A),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'من الخادم' : 'Server authority',
              value:
                  _platformSummaryInt('server_authoritative_events').toString(),
              icon: Icons.verified_user_outlined,
              color: const Color(0xFF047857),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'من العميل' : 'Client authenticated',
              value:
                  _platformSummaryInt('client_authenticated_events').toString(),
              icon: Icons.phone_android_outlined,
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
        if (_platformLoading ||
            _platformStatus.isNotEmpty ||
            topModules.isNotEmpty ||
            sourceChips.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (_platformLoading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_platformStatus.isNotEmpty)
            Text(
              _platformStatus,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...topModules,
                ...sourceChips,
              ],
            ),
        ],
      ],
    );
  }

  Widget _dashboardsOverviewPanel(L10n l) {
    final dashboards = _dashboardsOverviewList('dashboards');
    if (_dashboardsOverview == null &&
        !_dashboardsLoading &&
        _dashboardsStatus.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final dashboardChips = dashboards.take(12).map((item) {
      final title = (item['title'] ?? item['id'] ?? '').toString();
      final status = (item['status'] ?? '').toString();
      return Chip(
        avatar: const Icon(Icons.dashboard_customize_outlined, size: 16),
        label: Text(status.isEmpty ? title : '$title · $status'),
      );
    }).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _controlIntelligencePanel(l),
        if (_controlIntelligence.isNotEmpty) const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حسابات رسمية' : 'Official accounts',
              value: _dashboardsOverviewInt('official_accounts').toString(),
              icon: Icons.verified_outlined,
              color: const Color(0xFF0891B2),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'حملات نشطة' : 'Active campaigns',
              value: _dashboardsOverviewInt('green_paket_campaigns_active')
                  .toString(),
              icon: Icons.card_giftcard_outlined,
              color: const Color(0xFF16A34A),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'متابعون رسميون' : 'Official follows',
              value: _dashboardsOverviewInt('official_follows').toString(),
              icon: Icons.person_add_alt_outlined,
              color: const Color(0xFF0D9488),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'إشعارات غير مقروءة' : 'Unread templates',
              value:
                  _dashboardsOverviewInt('official_template_unread').toString(),
              icon: Icons.notifications_active_outlined,
              color: const Color(0xFF9333EA),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'زيارات الحسابات ٣٠ي' : 'Profile views 30d',
              value: _dashboardsOverviewInt('official_profile_view_events_30d')
                  .toString(),
              icon: Icons.badge_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'قراءات المنشورات ٣٠ي' : 'Feed views 30d',
              value: _dashboardsOverviewInt('official_feed_view_events_30d')
                  .toString(),
              icon: Icons.article_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'برامج منشورة' : 'Published mini programs',
              value:
                  _dashboardsOverviewInt('mini_programs_published').toString(),
              icon: Icons.widgets_outlined,
              color: const Color(0xFF7C3AED),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'أحداث ٣٠ يوم' : 'Events 30d',
              value: _dashboardsOverviewInt('platform_events_30d').toString(),
              icon: Icons.query_stats_outlined,
              color: const Color(0xFFEA580C),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'أحداث الخادم ٣٠ي' : 'Server events 30d',
              value: _dashboardsOverviewInt('server_authoritative_events_30d')
                  .toString(),
              icon: Icons.verified_user_outlined,
              color: const Color(0xFF047857),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'أحداث العميل ٣٠ي' : 'Client events 30d',
              value: _dashboardsOverviewInt('client_authenticated_events_30d')
                  .toString(),
              icon: Icons.phone_android_outlined,
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'قيد المراجعة' : 'Review queue',
              value: _dashboardsOverviewInt('mini_programs_review_queue')
                  .toString(),
              icon: Icons.fact_check_outlined,
              color: const Color(0xFFDC2626),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'لحظات محمية' : 'Protected moments',
              value:
                  _dashboardsOverviewInt('moments_protected_posts').toString(),
              icon: Icons.privacy_tip_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'تفاعل اللحظات ٣٠ي' : 'Moments engage 30d',
              value: _dashboardsOverviewInt('moments_engagement_events_30d')
                  .toString(),
              icon: Icons.favorite_border,
              color: const Color(0xFFBE123C),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'بلاغات اللحظات' : 'Moment reports',
              value: _dashboardsOverviewInt('moments_reports').toString(),
              icon: Icons.report_gmailerrorred_outlined,
              color: const Color(0xFFDC2626),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'نشر اللحظات ٣٠ي' : 'Moment posts 30d',
              value: _dashboardsOverviewInt('moments_create_events_30d')
                  .toString(),
              icon: Icons.add_photo_alternate_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'أمان اللحظات ٣٠ي' : 'Moment safety 30d',
              value: _dashboardsOverviewInt('moments_safety_events_30d')
                  .toString(),
              icon: Icons.shield_outlined,
              color: const Color(0xFF9333EA),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'برامج مثبتة' : 'Pinned mini programs',
              value: _dashboardsOverviewInt('mini_program_shelf_pinned')
                  .toString(),
              icon: Icons.push_pin_outlined,
              color: const Color(0xFF059669),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'رف البرامج ٣٠ي' : 'Shelf events 30d',
              value: _dashboardsOverviewInt(
                'mini_program_shelf_events_30d',
              ).toString(),
              icon: Icons.dashboard_customize_outlined,
              color: const Color(0xFF2563EB),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'إصدارات شوهدت' : 'Seen releases',
              value: _dashboardsOverviewInt('mini_program_seen_releases')
                  .toString(),
              icon: Icons.verified_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'رؤية الإصدارات ٣٠ي' : 'Release seen 30d',
              value: _dashboardsOverviewInt(
                'mini_program_release_seen_events_30d',
              ).toString(),
              icon: Icons.new_releases_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'إصدارات منشورة' : 'Released versions',
              value: _dashboardsOverviewInt('mini_program_released_versions')
                  .toString(),
              icon: Icons.cloud_done_outlined,
              color: const Color(0xFF0D9488),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'فتح البرامج ٣٠ي' : 'Mini opens 30d',
              value: _dashboardsOverviewInt('mini_program_open_events_30d')
                  .toString(),
              icon: Icons.open_in_new_outlined,
              color: const Color(0xFF0891B2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'حزم ملصقات' : 'Sticker packs',
              value: _dashboardsOverviewInt('sticker_packs_enabled').toString(),
              icon: Icons.emoji_emotions_outlined,
              color: const Color(0xFFDB2777),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'ملصقات ٣٠ي' : 'Sticker events 30d',
              value: _dashboardsOverviewInt('sticker_events_30d').toString(),
              icon: Icons.query_stats_outlined,
              color: const Color(0xFF0891B2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'عروض نشطة' : 'Active cards',
              value: _dashboardsOverviewInt('card_offers_active').toString(),
              icon: Icons.local_offer_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'البطاقات ٣٠ي' : 'Card events 30d',
              value: _dashboardsOverviewInt('cards_events_30d').toString(),
              icon: Icons.query_stats_outlined,
              color: const Color(0xFFBE123C),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'عناصر القنوات' : 'Channel items',
              value: _dashboardsOverviewInt('channels_items').toString(),
              icon: Icons.video_collection_outlined,
              color: const Color(0xFF7C2D12),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'متابعو القنوات' : 'Channel follows',
              value: _dashboardsOverviewInt('channels_follows').toString(),
              icon: Icons.subscriptions_outlined,
              color: const Color(0xFF0891B2),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'القنوات ٣٠ي' : 'Channels 30d',
              value: _dashboardsOverviewInt('channels_events_30d').toString(),
              icon: Icons.play_circle_outline,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label:
                  l.isArabic ? 'تفاعل القنوات ٣٠ي' : 'Channel engagement 30d',
              value: _dashboardsOverviewInt(
                'channel_engagement_events_30d',
              ).toString(),
              icon: Icons.volunteer_activism_outlined,
              color: const Color(0xFFBE123C),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'نشر القنوات ٣٠ي' : 'Channel publish 30d',
              value: _dashboardsOverviewInt('channel_publish_events_30d')
                  .toString(),
              icon: Icons.upload_file_outlined,
              color: const Color(0xFF0F766E),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'بث القنوات ٣٠ي' : 'Channel live 30d',
              value:
                  _dashboardsOverviewInt('channel_live_events_30d').toString(),
              icon: Icons.live_tv_outlined,
              color: const Color(0xFF7C3AED),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'البحث ٣٠ي' : 'Search 30d',
              value:
                  _dashboardsOverviewInt('global_search_events_30d').toString(),
              icon: Icons.search_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'القريبون ٣٠ي' : 'Nearby 30d',
              value: _dashboardsOverviewInt(
                'people_nearby_search_events_30d',
              ).toString(),
              icon: Icons.explore_outlined,
              color: const Color(0xFF059669),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'ملفات قريبة مرئية' : 'Visible nearby',
              value:
                  _dashboardsOverviewInt('nearby_visible_profiles').toString(),
              icon: Icons.location_on_outlined,
              color: const Color(0xFF7E22CE),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'اكتشاف ٣٠ي' : 'Discover 30d',
              value: _dashboardsOverviewInt('discover_events_30d').toString(),
              icon: Icons.travel_explore_outlined,
              color: const Color(0xFFB45309),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'متابعة رسمية ٣٠ي' : 'Follow flow 30d',
              value: _dashboardsOverviewInt(
                'official_follow_events_30d',
              ).toString(),
              icon: Icons.how_to_reg_outlined,
              color: const Color(0xFF0284C7),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'قوالب رسمية ٣٠ي' : 'Templates 30d',
              value: _dashboardsOverviewInt(
                'official_template_message_events_30d',
              ).toString(),
              icon: Icons.mark_email_read_outlined,
              color: const Color(0xFFC2410C),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'أوضاع الإشعار ٣٠ي' : 'Notify modes 30d',
              value: _dashboardsOverviewInt(
                'official_notification_events_30d',
              ).toString(),
              icon: Icons.notifications_none_outlined,
              color: const Color(0xFF64748B),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'حسابات رسمية ٣٠ي' : 'Official events 30d',
              value: _dashboardsOverviewInt(
                'official_account_events_30d',
              ).toString(),
              icon: Icons.verified_user_outlined,
              color: const Color(0xFF0369A1),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'إدارة الحملات ٣٠ي' : 'Campaign admin 30d',
              value: _dashboardsOverviewInt(
                'green_paket_campaign_admin_events_30d',
              ).toString(),
              icon: Icons.manage_accounts_outlined,
              color: const Color(0xFFB45309),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مراجعة البرامج ٣٠ي' : 'Review events 30d',
              value: _dashboardsOverviewInt(
                'mini_program_review_events_30d',
              ).toString(),
              icon: Icons.rule_outlined,
              color: const Color(0xFF4F46E5),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'خصوصية اللحظات ٣٠ي' : 'Moments privacy 30d',
              value: _dashboardsOverviewInt(
                'moments_privacy_events_30d',
              ).toString(),
              icon: Icons.lock_outline,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'مزامنة الوسوم ٣٠ي' : 'Tag sync 30d',
              value: _dashboardsOverviewInt(
                'friend_tags_sync_events_30d',
              ).toString(),
              icon: Icons.sell_outlined,
              color: const Color(0xFF059669),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'العناصر المحفوظة' : 'Saved items',
              value: _dashboardsOverviewInt('superapp_favorites').toString(),
              icon: Icons.bookmarks_outlined,
              color: const Color(0xFF047857),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'المفضلة ٣٠ي' : 'Favorites events 30d',
              value: _dashboardsOverviewInt('favorites_events_30d').toString(),
              icon: Icons.star_border_outlined,
              color: const Color(0xFFB45309),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _summaryTile(
              label: l.isArabic ? 'دردشات مثبتة' : 'Pinned chats',
              value: _dashboardsOverviewInt('chat_pinned_conversations')
                  .toString(),
              icon: Icons.push_pin_outlined,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 10),
            _summaryTile(
              label: l.isArabic ? 'إعدادات الدردشة ٣٠ي' : 'Chat prefs 30d',
              value: _dashboardsOverviewInt('chat_pref_events_30d').toString(),
              icon: Icons.tune_outlined,
              color: const Color(0xFF0F766E),
            ),
          ],
        ),
        if (_officialAccountsDashboard != null) ...[
          const SizedBox(height: 10),
          _officialAccountsDashboardPanel(l),
        ],
        if (_miniProgramsDashboard != null) ...[
          const SizedBox(height: 10),
          _miniProgramsDashboardPanel(l),
        ],
        if (_stickersDashboard != null) ...[
          const SizedBox(height: 10),
          _stickersDashboardPanel(l),
        ],
        if (_cardsDashboard != null) ...[
          const SizedBox(height: 10),
          _cardsDashboardPanel(l),
        ],
        if (_greenPaketDashboard != null) ...[
          const SizedBox(height: 10),
          _greenPaketDashboardPanel(l),
        ],
        if (_discoverDashboard != null) ...[
          const SizedBox(height: 10),
          _discoverDashboardPanel(l),
        ],
        if (_favoritesDashboard != null) ...[
          const SizedBox(height: 10),
          _favoritesDashboardPanel(l),
        ],
        if (_chatDashboard != null) ...[
          const SizedBox(height: 10),
          _chatDashboardPanel(l),
        ],
        if (_contactsDashboard != null) ...[
          const SizedBox(height: 10),
          _contactsDashboardPanel(l),
        ],
        if (_momentsDashboard != null) ...[
          const SizedBox(height: 10),
          _momentsDashboardPanel(l),
        ],
        if (_channelsDashboard != null) ...[
          const SizedBox(height: 10),
          _channelsDashboardPanel(l),
        ],
        if (_dashboardsLoading ||
            _dashboardsStatus.isNotEmpty ||
            dashboardChips.isNotEmpty) ...[
          const SizedBox(height: 10),
          if (_dashboardsLoading)
            const LinearProgressIndicator(minHeight: 2)
          else if (_dashboardsStatus.isNotEmpty)
            Text(
              _dashboardsStatus,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: dashboardChips,
            ),
        ],
      ],
    );
  }

  Widget _filterBar(L10n l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            segments: <ButtonSegment<String>>[
              ButtonSegment<String>(
                value: '',
                label: Text(l.isArabic ? 'الكل' : 'All'),
                icon: const Icon(Icons.all_inclusive),
              ),
              ButtonSegment<String>(
                value: 'signup',
                label: Text(l.isArabic ? 'تسجيل' : 'Signups'),
                icon: const Icon(Icons.person_add_alt_1_outlined),
              ),
              ButtonSegment<String>(
                value: 'module_open',
                label: Text(l.isArabic ? 'أفعال' : 'Actions'),
                icon: const Icon(Icons.touch_app_outlined),
              ),
              ButtonSegment<String>(
                value: 'payment',
                label: Text(l.isArabic ? 'دفع' : 'Payments'),
                icon: const Icon(Icons.account_balance_wallet_outlined),
              ),
            ],
            selected: <String>{_eventFilter},
            onSelectionChanged: (selection) {
              setState(() {
                _eventFilter = selection.first;
              });
              _loadActivity();
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _usernameCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: l.isArabic ? 'اسم المستخدم' : 'Username',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _loadActivity(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: l.isArabic ? 'تحديث' : 'Refresh',
              onPressed: _loading ? null : _loadActivity,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final fieldWidth = constraints.maxWidth < 560
                ? constraints.maxWidth
                : (constraints.maxWidth - 16) / 3;
            Widget field({
              required TextEditingController controller,
              required String label,
              required IconData icon,
            }) {
              return SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: label,
                    prefixIcon: Icon(icon),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => setState(() {}),
                ),
              );
            }

            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                field(
                  controller: _moduleCtrl,
                  label: l.isArabic ? 'الوحدة' : 'Module',
                  icon: Icons.apps_outlined,
                ),
                field(
                  controller: _actionCtrl,
                  label: l.isArabic ? 'الإجراء' : 'Action',
                  icon: Icons.touch_app_outlined,
                ),
                field(
                  controller: _currencyCtrl,
                  label: l.isArabic ? 'العملة' : 'Currency',
                  icon: Icons.payments_outlined,
                ),
                field(
                  controller: _fromDateCtrl,
                  label: l.isArabic ? 'من تاريخ' : 'From date',
                  icon: Icons.date_range_outlined,
                ),
                field(
                  controller: _toDateCtrl,
                  label: l.isArabic ? 'إلى تاريخ' : 'To date',
                  icon: Icons.event_outlined,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _visibleItems.isEmpty ? null : () => _copyCsv(l),
              icon: const Icon(Icons.download_outlined),
              label: Text(l.isArabic ? 'تصدير CSV' : 'Export CSV'),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _moduleCtrl.clear();
                  _actionCtrl.clear();
                  _currencyCtrl.clear();
                  _fromDateCtrl.clear();
                  _toDateCtrl.clear();
                });
              },
              icon: const Icon(Icons.clear_all),
              label: Text(l.isArabic ? 'مسح الفلاتر' : 'Clear filters'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _activityTile(Map<String, dynamic> item, L10n l) {
    final eventType = (item['event_type'] ?? '').toString();
    final color = _eventColor(eventType);
    final action = _actionLabel(item);
    final metadata = _metadataLabel(item);
    final createdAt = (item['created_at'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          child: Icon(_eventIcon(eventType)),
        ),
        title: Text(
          _identityLabel(item, l),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  _eventTitle(eventType, l),
                  if (action.isNotEmpty) action,
                  if (createdAt.isNotEmpty) createdAt,
                ].join(' - '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        trailing: Text(
          '#${item['id'] ?? ''}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final visibleItems = _visibleItems;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'نشاط المستخدمين' : 'User activity'),
      ),
      body: AppBG(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait<void>([
                _loadActivity(),
                _loadPlatformSummary(),
                _loadDashboardsOverview(),
              ]);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  l.isArabic
                      ? 'عمليات التسجيل وأفعال التطبيق'
                      : 'Signups and app actions',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _summaryTile(
                      label: l.isArabic ? 'تسجيلات' : 'Signups',
                      value: _countEvent(visibleItems, 'signup').toString(),
                      icon: Icons.person_add_alt_1_outlined,
                      color: const Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      label: l.isArabic ? 'أفعال' : 'Actions',
                      value:
                          _countEvent(visibleItems, 'module_open').toString(),
                      icon: Icons.touch_app_outlined,
                      color: const Color(0xFF2563EB),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _summaryTile(
                      label: l.isArabic ? 'دفع' : 'Payments',
                      value: _countPayments(visibleItems).toString(),
                      icon: Icons.account_balance_wallet_outlined,
                      color: const Color(0xFF7C3AED),
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      label: l.isArabic ? 'مستخدمون' : 'Users',
                      value: _countUniqueUsers(visibleItems).toString(),
                      icon: Icons.people_alt_outlined,
                      color: const Color(0xFF475569),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _platformSummaryPanel(l),
                const SizedBox(height: 10),
                _dashboardsOverviewPanel(l),
                const SizedBox(height: 16),
                _filterBar(l),
                const SizedBox(height: 12),
                if (_status.isNotEmpty)
                  Text(
                    _status,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _items.isEmpty ? theme.colorScheme.error : null,
                    ),
                  ),
                const SizedBox(height: 12),
                if (_loading && visibleItems.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: ShamellSkeletonList(itemCount: 4),
                  )
                else if (visibleItems.isEmpty)
                  ShamellEmptyState.noResults(
                    title: l.isArabic
                        ? 'لا توجد أحداث مطابقة'
                        : 'No matching activity yet',
                    description: l.isArabic
                        ? 'جرّب تعديل الفلاتر أو نطاق البحث.'
                        : 'Try adjusting your filters or search range.',
                  )
                else
                  for (final item in visibleItems) _activityTile(item, l),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
