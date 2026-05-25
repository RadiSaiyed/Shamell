import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'format.dart';
import 'l10n.dart';
import 'payments/payments_idempotency.dart';
import 'session_cookie_store.dart';
import 'wechat_ui.dart';

class GreenPaketPage extends StatefulWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final String? groupId;
  final String? initialMessage;
  final String? initialGreenPaketId;
  final FutureOr<void> Function(Map<String, dynamic> packet)? onIssued;
  final http.Client? client;

  const GreenPaketPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    this.groupId,
    this.initialMessage,
    this.initialGreenPaketId,
    this.onIssued,
    this.client,
  });

  @override
  State<GreenPaketPage> createState() => _GreenPaketPageState();
}

class _GreenPaketPageState extends State<GreenPaketPage> {
  static const Duration _timeout = Duration(seconds: 15);

  late final TextEditingController _amountCtrl;
  late final TextEditingController _countCtrl;
  late final TextEditingController _messageCtrl;

  String _mode = 'random';
  int _expiresHours = 24;
  bool _busy = false;
  String _error = '';
  Map<String, dynamic>? _packet;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: '10.00');
    _countCtrl = TextEditingController(text: '3');
    _messageCtrl = TextEditingController(
      text: (widget.initialMessage ?? '').trim().isNotEmpty
          ? widget.initialMessage!.trim()
          : 'For the group',
    );
    final initialId = (widget.initialGreenPaketId ?? '').trim();
    if (initialId.isNotEmpty) {
      _packet = <String, dynamic>{'green_paket_id': initialId};
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refresh());
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _countCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  Uri _uri(String path) {
    final base = widget.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<Map<String, String>> _headers({bool jsonBody = true}) async {
    final headers = await shamellSessionHeadersForBaseUrl(
      widget.baseUrl,
      json: jsonBody,
    );
    final deviceId = widget.deviceId.trim();
    if (deviceId.isNotEmpty) headers['X-Device-ID'] = deviceId;
    return headers;
  }

  int? _amountCents() {
    final raw = _amountCtrl.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(raw);
    if (amount == null || !amount.isFinite || amount <= 0) return null;
    return (amount * 100).round();
  }

  int? _count() {
    final value = int.tryParse(_countCtrl.text.trim());
    if (value == null || value < 1 || value > 100) return null;
    return value;
  }

  String _errorMessage(Object error) {
    final text = error.toString().trim();
    if (text.startsWith('Exception: ')) return text.substring(11);
    return text.isEmpty ? 'Request failed' : text;
  }

  dynamic _decode(String body) {
    if (body.trim().isEmpty) return null;
    return jsonDecode(body);
  }

  Future<Map<String, dynamic>> _requestPacket(
    Future<http.Response> Function(http.Client client) request,
  ) async {
    final client = widget.client ?? http.Client();
    final closeClient = widget.client == null;
    try {
      final response = await request(client).timeout(_timeout);
      final decoded = _decode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? (decoded['error'] ?? decoded['message'] ?? response.body)
                .toString()
            : response.body;
        throw Exception(message.trim().isEmpty ? 'Request failed' : message);
      }
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return <String, dynamic>{};
    } finally {
      if (closeClient) client.close();
    }
  }

  Future<void> _issue() async {
    final amountCents = _amountCents();
    final count = _count();
    if (amountCents == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (count == null) {
      setState(() => _error = 'Recipients must be between 1 and 100.');
      return;
    }
    if (amountCents < count) {
      setState(() => _error = 'Amount must cover at least 0.01 per recipient.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final headers = await _headers();
      headers['Idempotency-Key'] = newPaymentsIdempotencyKey('green-paket');
      final packet = await _requestPacket(
        (client) => client.post(
          _uri('/payments/green-pakets/issue'),
          headers: headers,
          body: jsonEncode(<String, dynamic>{
            'creator_wallet_id': widget.walletId,
            'total_amount_cents': amountCents,
            'count': count,
            'mode': _mode,
            'message': _messageCtrl.text.trim(),
            'group_id': (widget.groupId ?? '').trim().isNotEmpty
                ? widget.groupId!.trim()
                : 'discover:green_paket',
            'expires_in_secs': _expiresHours * 3600,
          }),
        ),
      );
      if (!mounted) return;
      setState(() => _packet = packet);
      await widget.onIssued?.call(packet);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final id = (_packet?['green_paket_id'] ?? _packet?['id'] ?? '').toString();
    if (id.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final packet = await _requestPacket(
        (client) async => client.get(
          _uri('/payments/green-pakets/status/${Uri.encodeComponent(id)}'),
          headers: await _headers(jsonBody: false),
        ),
      );
      if (!mounted) return;
      setState(() => _packet = packet);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _claimForPreview() async {
    final id = (_packet?['green_paket_id'] ?? _packet?['id'] ?? '').toString();
    if (id.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final headers = await _headers();
      headers['Idempotency-Key'] =
          newPaymentsIdempotencyKey('green-paket-claim');
      final packet = await _requestPacket(
        (client) => client.post(
          _uri('/payments/green-pakets/claim'),
          headers: headers,
          body: jsonEncode(<String, dynamic>{'green_paket_id': id}),
        ),
      );
      if (!mounted) return;
      setState(() => _packet = packet);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isAr = l.isArabic;
    final theme = Theme.of(context);
    final bg = theme.brightness == Brightness.dark
        ? const Color(0xFF0F172A)
        : WeChatPalette.background;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(isAr ? 'الحزمة الخضراء' : 'Green Paket'),
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _HeroPanel(walletId: widget.walletId),
            const SizedBox(height: 14),
            _Section(
              title: isAr ? 'إرسال حزمة' : 'Create Green Paket',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _TextBox(
                          controller: _amountCtrl,
                          label: isAr ? 'المبلغ' : 'Amount',
                          icon: Icons.payments_outlined,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9\.,]'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: _TextBox(
                          controller: _countCtrl,
                          label: isAr ? 'العدد' : 'Count',
                          icon: Icons.groups_2_outlined,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _TextBox(
                    controller: _messageCtrl,
                    label: isAr ? 'رسالة قصيرة' : 'Message',
                    icon: Icons.chat_bubble_outline,
                    maxLength: 160,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ModeChip(
                        label: isAr ? 'عشوائي' : 'Random split',
                        selected: _mode == 'random',
                        onSelected: () => setState(() => _mode = 'random'),
                      ),
                      _ModeChip(
                        label: isAr ? 'متساو' : 'Equal split',
                        selected: _mode == 'fixed',
                        onSelected: () => setState(() => _mode = 'fixed'),
                      ),
                      _ModeChip(
                        label: isAr ? '24 ساعة' : '24h',
                        selected: _expiresHours == 24,
                        onSelected: () => setState(() => _expiresHours = 24),
                      ),
                      _ModeChip(
                        label: isAr ? '7 أيام' : '7d',
                        selected: _expiresHours == 168,
                        onSelected: () => setState(() => _expiresHours = 168),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _issue,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.redeem_outlined),
                    label: Text(isAr ? 'إنشاء الحزمة' : 'Create Green Paket'),
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_packet != null) ...[
              const SizedBox(height: 14),
              _PacketStatus(
                packet: _packet!,
                onRefresh: _busy ? null : _refresh,
                onClaim: _busy ? null : _claimForPreview,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  final String walletId;

  const _HeroPanel({required this.walletId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    final isAr = l.isArabic;
    final wallet = walletId.trim().isEmpty
        ? (isAr ? 'لا توجد محفظة' : 'No wallet linked')
        : walletId;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F766E),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F766E).withValues(alpha: .18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.redeem_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAr ? 'Green Paket' : 'Green Paket',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isAr
                          ? 'هدايا دفع اجتماعية للمجموعات والحملات'
                          : 'Social payment gifts for groups and campaigns',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: .86),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: .16)),
            ),
            child: Text(
              wallet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _TextBox extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;

  const _TextBox({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        counterText: '',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      selectedColor: const Color(0xFFE3F6EF),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF0F766E) : null,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color:
            selected ? const Color(0xFF0F766E) : Theme.of(context).dividerColor,
      ),
    );
  }
}

class _PacketStatus extends StatelessWidget {
  final Map<String, dynamic> packet;
  final VoidCallback? onRefresh;
  final VoidCallback? onClaim;

  const _PacketStatus({
    required this.packet,
    this.onRefresh,
    this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L10n.of(context);
    final isAr = l.isArabic;
    final id = (packet['green_paket_id'] ?? packet['id'] ?? '').toString();
    final status = (packet['status'] ?? 'active').toString();
    final total = packet['total_amount_cents'] ?? packet['total_amount'] ?? 0;
    final claimed = packet['claimed_amount_cents'] ?? 0;
    final count = (packet['total_count'] ?? 0).toString();
    final claimedCount = (packet['claimed_count'] ?? 0).toString();
    final amountCents = packet['amount_cents'];
    return _Section(
      title: isAr ? 'حالة الحزمة' : 'Green Paket status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(label: isAr ? 'الحالة' : 'Status', value: status),
              _Metric(
                  label: isAr ? 'الإجمالي' : 'Total', value: fmtCents(total)),
              _Metric(
                label: isAr ? 'المطالب به' : 'Claimed',
                value: fmtCents(claimed),
              ),
              _Metric(
                label: isAr ? 'المستلمون' : 'Recipients',
                value: '$claimedCount/$count',
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (amountCents != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F6EF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isAr
                    ? 'تم استلام ${fmtCents(amountCents)}'
                    : 'Claimed ${fmtCents(amountCents)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF0F766E),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(height: 12),
          SelectableText(
            id,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(isAr ? 'تحديث' : 'Refresh'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onClaim,
                  icon: const Icon(Icons.download_done_outlined),
                  label: Text(isAr ? 'تجربة الاستلام' : 'Preview claim'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;

  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 142,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
