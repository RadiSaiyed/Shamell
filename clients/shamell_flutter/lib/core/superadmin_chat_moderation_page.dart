import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../main.dart' show LoginPage;
import 'app_shell_widgets.dart' show AppBG;
import 'base_url.dart';
import 'device_binding_reauth.dart';
import 'http_error.dart';
import 'l10n.dart';
import 'session_cookie_store.dart';

class SuperadminChatModerationPage extends StatefulWidget {
  final String baseUrl;
  final http.Client? httpClient;

  const SuperadminChatModerationPage({
    super.key,
    required this.baseUrl,
    this.httpClient,
  });

  @override
  State<SuperadminChatModerationPage> createState() =>
      _SuperadminChatModerationPageState();
}

class _SuperadminChatModerationPageState
    extends State<SuperadminChatModerationPage> {
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const List<String> _statuses = <String>[
    'open',
    'reviewing',
    'resolved',
    'dismissed',
  ];

  late final http.Client _http;
  late final bool _ownsHttpClient;
  String _statusFilter = 'open';
  bool _loading = false;
  String _status = '';
  List<Map<String, dynamic>> _reports = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _ownsHttpClient = widget.httpClient == null;
    _http = widget.httpClient ?? shamellHttpClient();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadReports();
    });
  }

  @override
  void dispose() {
    if (_ownsHttpClient) {
      _http.close();
    }
    super.dispose();
  }

  Uri? _reportsUri() => secureApiChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: const <String>['admin', 'chat', 'moderation', 'reports'],
        queryParameters: <String, String>{
          'status': _statusFilter,
          'limit': '100',
        },
      );

  Uri? _actionUri(String reportId) => secureApiChildUri(
        baseUrl: widget.baseUrl,
        pathSegments: <String>[
          'admin',
          'chat',
          'moderation',
          'reports',
          reportId,
          'action',
        ],
      );

  Future<void> _loadReports() async {
    final l = L10n.of(context);
    final uri = _reportsUri();
    if (uri == null) {
      setState(() {
        _status = l.isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
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
          _status = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(response.body);
      final next = <Map<String, dynamic>>[];
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) next.add(item.cast<String, dynamic>());
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _reports = next;
        _status = next.isEmpty
            ? (l.isArabic ? 'لا توجد بلاغات.' : 'No reports found.')
            : (l.isArabic ? 'تم تحميل البلاغات.' : 'Reports loaded.');
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

  Future<void> _updateReport(String reportId, String status) async {
    final l = L10n.of(context);
    final uri = _actionUri(reportId);
    if (uri == null) return;
    try {
      final response = await _http
          .post(
            uri,
            headers: {
              ...await shamellSessionHeadersForBaseUrl(widget.baseUrl),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'status': status}),
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
          _status = sanitizeHttpError(
            statusCode: response.statusCode,
            rawBody: response.body,
            isArabic: l.isArabic,
          );
        });
        return;
      }
      await _loadReports();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = sanitizeExceptionForUi(error: error, isArabic: l.isArabic);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: AppBG(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      l.isArabic ? 'بلاغات المحادثات' : 'Chat moderation',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _loading ? null : _loadReports,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  for (final status in _statuses)
                    ButtonSegment<String>(
                      value: status,
                      label: Text(status),
                    ),
                ],
                selected: {_statusFilter},
                onSelectionChanged: (selected) {
                  setState(() => _statusFilter = selected.first);
                  _loadReports();
                },
              ),
              if (_loading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_status, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 12),
              for (final report in _reports)
                _ReportCard(
                  report: report,
                  onReviewing: () => _updateReport(
                    (report['id'] ?? '').toString(),
                    'reviewing',
                  ),
                  onResolve: () => _updateReport(
                    (report['id'] ?? '').toString(),
                    'resolved',
                  ),
                  onDismiss: () => _updateReport(
                    (report['id'] ?? '').toString(),
                    'dismissed',
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final VoidCallback onReviewing;
  final VoidCallback onResolve;
  final VoidCallback onDismiss;

  const _ReportCard({
    required this.report,
    required this.onReviewing,
    required this.onResolve,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = (report['status'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.report_gmailerrorred_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (report['reason'] ?? '').toString(),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(label: Text(status)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Message: ${(report['message_id'] ?? '').toString()}'),
            Text(
                'Reporter: ${(report['reporter_device_id'] ?? '').toString()}'),
            if ((report['note'] ?? '').toString().trim().isNotEmpty)
              Text('Note: ${(report['note'] ?? '').toString()}'),
            Text('Created: ${(report['created_at'] ?? '').toString()}'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: status == 'reviewing' ? null : onReviewing,
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Reviewing'),
                ),
                FilledButton.icon(
                  onPressed: status == 'resolved' ? null : onResolve,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Resolve'),
                ),
                TextButton.icon(
                  onPressed: status == 'dismissed' ? null : onDismiss,
                  icon: const Icon(Icons.block),
                  label: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
