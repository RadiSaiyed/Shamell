import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../main.dart' show LoginPage;
import '../account_privilege_store.dart';
import '../app_activity.dart';
import '../app_sounds.dart';
import '../../core/design_tokens.dart';
import '../../core/device_binding_reauth.dart';
import '../../core/l10n.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/http_error.dart';
import '../../core/safe_set_state.dart';
import '../../core/superapp_api.dart';
import 'payments_shell.dart';
import 'payments_attestation.dart' show shamellPaymentAmountMajorToCents;
import '../../core/history_page.dart';
import 'payments_send.dart' show PayActionButton;
import 'payments_platform_contracts.dart';
import '../../core/ui_kit.dart';
import '../../core/app_shell_widgets.dart' show AppBG;

bool _paymentsSnapshotHasWalletPermission(
  AccountPrivilegeSnapshot snapshot,
  String permission,
) {
  return snapshot.can(permission, product: 'wallet') ||
      snapshot.hasPermission(permission);
}

List<String> _paymentsOperatorAccessLabels(AccountPrivilegeSnapshot snapshot) {
  final labels = <String>[];
  if (snapshot.permissions.isNotEmpty) {
    if (_paymentsSnapshotHasWalletPermission(
        snapshot, 'wallet.operator.read')) {
      labels.add('Merchant POS');
    }
    if (_paymentsSnapshotHasWalletPermission(snapshot, 'cash.agent.read')) {
      labels.add('Cash agent');
    }
    return labels;
  }
  if (shamellHasPaymentsOperatorAccess(snapshot.roles)) {
    labels.add('Merchant POS');
  }
  if (shamellHasPaymentsCashAgentAccess(snapshot.roles)) {
    labels.add('Cash agent');
  }
  return labels;
}

String _paymentsAdminCreditIdempotencyKey() {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rnd = _paymentsIdempotencyRandom();
  final left = rnd
      .nextInt(_paymentsAdminCreditRandomMax)
      .toRadixString(36)
      .padLeft(7, '0');
  final right = rnd
      .nextInt(_paymentsAdminCreditRandomMax)
      .toRadixString(36)
      .padLeft(7, '0');
  return 'admin-credit-$ts-$left$right';
}

const int _paymentsAdminCreditRandomMax = 0x100000000;

Random _paymentsIdempotencyRandom() {
  try {
    return Random.secure();
  } catch (_) {
    return Random(DateTime.now().microsecondsSinceEpoch);
  }
}

List<String> _paymentsPrivilegeLabels(AccountPrivilegeSnapshot snapshot) {
  final labels = <String>[];
  if (snapshot.permissions.isNotEmpty) {
    if (_paymentsSnapshotHasWalletPermission(snapshot, 'wallet.admin.read')) {
      labels.add('Payments admin');
    }
    if (_paymentsSnapshotHasWalletPermission(snapshot, 'wallet.finance.read')) {
      labels.add('Payments finance');
    }
    if (_paymentsSnapshotHasWalletPermission(snapshot, 'wallet.credit.write')) {
      labels.add('Balance credit');
    }
    if (shamellHasPaymentsSuperadminSnapshotAccess(snapshot)) {
      labels.add('Guardrails');
    }
    return labels;
  }
  if (shamellHasPaymentsAdminAccess(snapshot.roles) || snapshot.isAdmin) {
    labels.add('Payments admin');
  }
  if (shamellHasPaymentsFinanceAccess(snapshot.roles)) {
    labels.add('Payments finance');
  }
  if (shamellHasPaymentsCreditAccess(snapshot.roles)) {
    labels.add('Balance credit');
  }
  if (shamellHasPaymentsSuperadminAccess(snapshot.roles) ||
      snapshot.isSuperadmin) {
    labels.add('Guardrails');
  }
  return labels;
}

class PaymentsMultiLevelPage extends StatefulWidget {
  final SuperappAPI api;
  const PaymentsMultiLevelPage({super.key, required this.api});

  @override
  State<PaymentsMultiLevelPage> createState() => _PaymentsMultiLevelPageState();
}

class _PaymentsMultiLevelPageState extends State<PaymentsMultiLevelPage>
    with SafeSetStateMixin<PaymentsMultiLevelPage> {
  bool _loading = true;
  String _error = '';

  String _phone = '';
  AccountPrivilegeSnapshot _privileges = AccountPrivilegeSnapshot.empty;
  List<String> _operatorScope = const [];

  String _walletId = '';
  int? _balanceCents;
  String _currency = 'SYP';
  int _recentCount = 0;
  String _creditTargetMode = 'shamell_id';
  final TextEditingController _creditTargetCtrl = TextEditingController();
  final TextEditingController _creditAmountCtrl =
      TextEditingController(text: '1000');
  final TextEditingController _creditReasonCtrl =
      TextEditingController(text: 'operator_credit');
  final TextEditingController _creditNoteCtrl = TextEditingController();
  bool _creditSubmitting = false;
  bool _creditHistoryLoading = false;
  String _creditResult = '';
  String _creditHistoryError = '';
  List<Map<String, dynamic>> _creditHistory = const [];
  Map<String, dynamic> _creditMetrics = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _creditTargetCtrl.dispose();
    _creditAmountCtrl.dispose();
    _creditReasonCtrl.dispose();
    _creditNoteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final uri = widget.api.uri('me/home_snapshot');
      final r = await widget.api.getUri(
        uri,
        headers: await widget.api.sessionHeaders(uri: uri),
      );
      if (!mounted) return;
      if (r.statusCode != 200) {
        if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
          context,
          statusCode: r.statusCode,
          rawBody: r.body,
          loginPageBuilder: (_) => const LoginPage(),
        )) {
          return;
        }
        setState(() {
          _error = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
      } else {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final privileges = accountPrivilegeSnapshotFromPayload(j);
        final ops = j['operator_domains'];
        final wallet = j['wallet'];
        final txns = j['txns'];
        setState(() {
          _phone = (j['phone'] ?? '').toString();
          _privileges = privileges;
          _operatorScope = privileges.operatorIds.isNotEmpty
              ? privileges.operatorIds
              : (ops is List
                  ? ops.map((e) => e.toString()).toList()
                  : const []);
          if (wallet is Map<String, dynamic>) {
            final id = (wallet['wallet_id'] ?? wallet['id'] ?? '').toString();
            _walletId = id;
            final cents = wallet['balance_cents'];
            if (cents is int) _balanceCents = cents;
            final cur = (wallet['currency'] ?? '').toString();
            if (cur.isNotEmpty) _currency = cur;
          }
          if (txns is List) {
            _recentCount = txns.length;
          }
        });
        if (shamellHasPaymentsCreditSnapshotAccess(privileges)) {
          await _loadAdminCreditHistory(showLoading: false);
        }
      }
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
        _error = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _openPayments() {
    if (_walletId.isEmpty) return;
    final did = widget.api.deviceId.trim().isNotEmpty
        ? widget.api.deviceId.trim()
        : 'payments-multi';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentsPage(
          widget.api.baseUrl,
          _walletId,
          did,
          initialCurrency: _currency,
        ),
      ),
    );
  }

  void _openHistory() {
    if (_walletId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HistoryPage(baseUrl: widget.api.baseUrl, walletId: _walletId),
      ),
    );
  }

  Future<void> _submitAdminCredit() async {
    if (!shamellHasPaymentsCreditSnapshotAccess(_privileges)) {
      return;
    }
    final target = _creditTargetCtrl.text.trim();
    final amountMajor =
        double.tryParse(_creditAmountCtrl.text.trim().replaceAll(',', '.'));
    final reason = _creditReasonCtrl.text.trim();
    final note = _creditNoteCtrl.text.trim();
    final isArabic = L10n.of(context).isArabic;
    if (target.isEmpty ||
        amountMajor == null ||
        amountMajor <= 0 ||
        reason.isEmpty) {
      setState(() {
        _creditResult = isArabic
            ? 'تحقق من الهدف والمبلغ والسبب.'
            : 'Check the target, amount and reason.';
      });
      return;
    }
    setState(() {
      _creditSubmitting = true;
      _creditResult = '...';
    });
    try {
      final amountCents = shamellPaymentAmountMajorToCents(amountMajor);
      final uri = widget.api.uri('payments/admin/credits');
      final body = <String, Object?>{
        _creditTargetMode: target,
        'amount_cents': amountCents,
        if (reason.isNotEmpty) 'reason': reason,
        if (note.isNotEmpty) 'note': note,
      };
      final headers = await widget.api.sessionHeaders(
        uri: uri,
        json: true,
        extra: <String, String>{
          'Idempotency-Key': _paymentsAdminCreditIdempotencyKey(),
        },
      );
      final r = await widget.api
          .postUri(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        setState(() {
          _creditResult = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(r.body);
      final walletId = decoded is Map ? (decoded['wallet_id'] ?? '') : '';
      final balance = decoded is Map ? decoded['balance_cents'] : null;
      final currency =
          decoded is Map ? (decoded['currency'] ?? _currency) : _currency;
      final status = decoded is Map ? (decoded['status'] ?? '') : '';
      unawaited(
        ShamellSoundEffects.play(
          status == 'pending_approval'
              ? ShamellSoundEffect.success
              : ShamellSoundEffect.moneyReceived,
        ),
      );
      shamellRecordAppActivity(
        baseUrl: widget.api.baseUrl,
        eventType: status == 'pending_approval'
            ? 'admin_credit_requested'
            : 'admin_credit_created',
        moduleId: 'payments',
        action: status == 'pending_approval'
            ? 'admin_credit_requested'
            : 'admin_credit_created',
        metadata: <String, Object?>{
          'amount_cents': amountCents,
          'target_mode': _creditTargetMode,
          'status': status.toString(),
        },
      );
      setState(() {
        _creditResult = status == 'pending_approval'
            ? (isArabic ? 'تم إرسال الطلب للموافقة.' : 'Approval requested.')
            : balance is int
                ? (isArabic
                    ? 'تمت الإضافة. الرصيد: ${fmtCents(balance)} $currency'
                    : 'Credited. Balance: ${fmtCents(balance)} $currency')
                : (isArabic ? 'تمت الإضافة.' : 'Credited.');
        if (walletId is String &&
            walletId.isNotEmpty &&
            walletId == _walletId) {
          _balanceCents = balance is int ? balance : _balanceCents;
          _currency = currency.toString();
        }
      });
      await _loadAdminCreditHistory(showLoading: false);
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      setState(() {
        _creditResult = sanitizeExceptionForUi(
          error: e,
          isArabic: isArabic,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _creditSubmitting = false);
      }
    }
  }

  Future<void> _loadAdminCreditHistory({bool showLoading = true}) async {
    if (!shamellHasPaymentsCreditSnapshotAccess(_privileges)) return;
    if (showLoading && mounted) {
      setState(() {
        _creditHistoryLoading = true;
        _creditHistoryError = '';
      });
    }
    try {
      final uri = widget.api.uri(
        'payments/admin/credits',
        query: const <String, String>{'limit': '8'},
      );
      final r = await widget.api
          .getUri(uri, headers: await widget.api.sessionHeaders(uri: uri))
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      if (r.statusCode < 200 || r.statusCode >= 300) {
        setState(() {
          _creditHistoryError = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: L10n.of(context).isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(r.body);
      final items = decoded is Map ? decoded['items'] : null;
      final metrics = decoded is Map ? decoded['metrics'] : null;
      setState(() {
        _creditHistory = items is List
            ? items
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
            : const [];
        _creditMetrics =
            metrics is Map ? Map<String, dynamic>.from(metrics) : const {};
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creditHistoryError = sanitizeExceptionForUi(
          error: e,
          isArabic: L10n.of(context).isArabic,
        );
      });
    } finally {
      if (mounted && showLoading) {
        setState(() => _creditHistoryLoading = false);
      }
    }
  }

  Future<void> _approveAdminCredit(String requestId) async {
    if (requestId.trim().isEmpty) return;
    final isArabic = L10n.of(context).isArabic;
    setState(() {
      _creditSubmitting = true;
      _creditResult = '...';
    });
    try {
      final uri = widget.api.uri('payments/admin/credits/$requestId/approve');
      final headers = await widget.api.sessionHeaders(
        uri: uri,
        json: true,
        extra: <String, String>{
          'Idempotency-Key': _paymentsAdminCreditIdempotencyKey(),
        },
      );
      final r = await widget.api
          .postUri(uri, headers: headers, body: jsonEncode(<String, Object?>{}))
          .timeout(const Duration(seconds: 15));
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: r.statusCode,
        rawBody: r.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return;
      }
      if (r.statusCode < 200 || r.statusCode >= 300) {
        setState(() {
          _creditResult = sanitizeHttpError(
            statusCode: r.statusCode,
            rawBody: r.body,
            isArabic: isArabic,
          );
        });
        return;
      }
      final decoded = jsonDecode(r.body);
      final balance = decoded is Map ? decoded['balance_cents'] : null;
      final currency =
          decoded is Map ? (decoded['currency'] ?? _currency) : _currency;
      final walletId = decoded is Map ? (decoded['wallet_id'] ?? '') : '';
      unawaited(ShamellSoundEffects.play(ShamellSoundEffect.moneyReceived));
      shamellRecordAppActivity(
        baseUrl: widget.api.baseUrl,
        eventType: 'admin_credit_approved',
        moduleId: 'payments',
        action: 'admin_credit_approved',
        metadata: <String, Object?>{'request_id': requestId},
      );
      setState(() {
        _creditResult = balance is int
            ? (isArabic
                ? 'تمت الموافقة. الرصيد: ${fmtCents(balance)} $currency'
                : 'Approved. Balance: ${fmtCents(balance)} $currency')
            : (isArabic ? 'تمت الموافقة.' : 'Approved.');
        if (walletId is String &&
            walletId.isNotEmpty &&
            walletId == _walletId) {
          _balanceCents = balance is int ? balance : _balanceCents;
          _currency = currency.toString();
        }
      });
      await _loadAdminCreditHistory(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creditResult = sanitizeExceptionForUi(
          error: e,
          isArabic: isArabic,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _creditSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    const bg = AppBG();
    final operatorLabels = _paymentsOperatorAccessLabels(_privileges);
    final privilegeLabels = _paymentsPrivilegeLabels(_privileges);
    final hasOperatorAccess = shamellHasPaymentsOperatorSnapshotAccess(
      _privileges,
    );
    final hasAdminAccess = shamellHasPaymentsAdminSnapshotAccess(_privileges);
    final hasCreditAccess = shamellHasPaymentsCreditSnapshotAccess(_privileges);
    final hasSuperadminAccess = shamellHasPaymentsSuperadminSnapshotAccess(
      _privileges,
    );
    final body = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                color: Tokens.colorPayments),
            const SizedBox(width: 8),
            const Text(
              'Payments – Enduser, Operator, Admin, Superadmin',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_phone.isNotEmpty)
          Text(
            'Phone: $_phone',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: .70),
            ),
          ),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        // Enduser section
        FormSection(
          title: l.isArabic ? 'المستخدم النهائي' : 'Enduser',
          subtitle: l.isArabic
              ? 'المحفظة الرئيسية والمدفوعات الأخيرة'
              : 'Main wallet and recent payments',
          children: [
            Text(
              _walletId.isEmpty
                  ? (l.isArabic
                      ? 'لم يتم إنشاء محفظة بعد'
                      : 'No wallet created yet')
                  : '${l.homeWallet}: $_walletId',
            ),
            const SizedBox(height: 4),
            Text(
              _balanceCents == null
                  ? (l.isArabic ? 'الرصيد غير معروف' : 'Balance unknown')
                  : '${fmtCents(_balanceCents!)} $_currency',
            ),
            const SizedBox(height: 4),
            Text(
              _recentCount == 0
                  ? (l.isArabic
                      ? 'لا توجد مدفوعات حديثة'
                      : 'No recent payments')
                  : (l.isArabic
                      ? '$_recentCount عملية حديثة'
                      : '$_recentCount recent payment(s)'),
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: PayActionButton(
                    icon: Icons.account_balance_wallet_outlined,
                    label: l.homePayments,
                    onTap: _walletId.isEmpty ? () {} : _openPayments,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PayActionButton(
                    icon: Icons.history,
                    label: l.viewAll,
                    onTap: _walletId.isEmpty ? () {} : _openHistory,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Operator section
        FormSection(
          title: l.isArabic ? 'المشغل (Payments)' : 'Operator (Payments)',
          subtitle: l.isArabic
              ? 'أدوار المشغل وMerchant POS'
              : 'Operator roles and merchant POS access',
          children: [
            Text(
              l.isArabic ? 'الأدوار' : 'Roles',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final label in operatorLabels)
                  Chip(
                    label: Text(label),
                    backgroundColor:
                        Tokens.colorPayments.withValues(alpha: .14),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: Tokens.colorPayments.withValues(alpha: .9),
                      ),
                    ),
                  ),
                if (!hasOperatorAccess)
                  Text(
                    l.isArabic
                        ? 'لا توجد أدوار مشغل Payments'
                        : 'No Payments operator roles for this phone',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .70),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l.isArabic
                  ? 'استخدم Merchant POS ولوحة المشغل لمتابعة المدفوعات للتجار.'
                  : 'Use Merchant POS and operator consoles to handle merchant payments.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Admin section
        FormSection(
          title: l.isArabic ? 'المدير (Payments)' : 'Admin (Payments)',
          subtitle: l.isArabic
              ? 'صلاحيات الإدارة وتقارير Ops Admin'
              : 'Admin rights and Ops Admin reports',
          children: [
            Text(
              hasAdminAccess
                  ? (l.isArabic
                      ? 'هذا الهاتف لديه صلاحيات المدير.'
                      : 'This phone has admin rights.')
                  : (l.isArabic
                      ? 'لا توجد صلاحيات المدير.'
                      : 'No admin rights for this phone.'),
            ),
            const SizedBox(height: 8),
            Text(
              l.isArabic
                  ? 'استخدم وحدة Ops Admin لتقارير Payments وعمليات التصدير.'
                  : 'Use the Ops Admin console for payments reporting and exports.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
            if (hasCreditAccess) ...[
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: 'shamell_id',
                    icon: Icon(Icons.badge_outlined),
                    label: Text('SyrChat ID'),
                  ),
                  ButtonSegment<String>(
                    value: 'wallet_id',
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    label: Text('Wallet ID'),
                  ),
                ],
                selected: <String>{_creditTargetMode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _creditTargetMode = selection.first;
                    _creditResult = '';
                  });
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _creditTargetCtrl,
                decoration: InputDecoration(
                  labelText: _creditTargetMode == 'wallet_id'
                      ? 'Wallet ID'
                      : 'SyrChat ID',
                  prefixIcon: Icon(_creditTargetMode == 'wallet_id'
                      ? Icons.account_balance_wallet_outlined
                      : Icons.badge_outlined),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _creditAmountCtrl,
                decoration: InputDecoration(
                  labelText: 'Amount ($_currency)',
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _creditReasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  prefixIcon: Icon(Icons.rule_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _creditNoteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _creditSubmitting ? null : _submitAdminCredit,
                  icon: _creditSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_card_outlined),
                  label: Text(l.isArabic ? 'إضافة رصيد' : 'Credit balance'),
                ),
              ),
              if (_creditResult.isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(_creditResult),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Credit history',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _creditHistoryLoading
                        ? null
                        : () => _loadAdminCreditHistory(),
                    icon: _creditHistoryLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (_creditMetrics.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '24h credited: ${fmtCents((_creditMetrics['credited_amount_cents'] as int?) ?? 0)} · Pending: ${_creditMetrics['pending_approval_count'] ?? 0}',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .70),
                  ),
                ),
              ],
              if (_creditHistoryError.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _creditHistoryError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_creditHistory.isEmpty && !_creditHistoryLoading) ...[
                const SizedBox(height: 6),
                Text(
                  'No credit requests yet.',
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .70),
                  ),
                ),
              ],
              for (final item in _creditHistory.take(5)) ...[
                const Divider(height: 18),
                _AdminCreditHistoryRow(
                  item: item,
                  onApprove: _creditSubmitting
                      ? null
                      : () {
                          final requestId =
                              (item['approval_request_id'] ?? '').toString();
                          _approveAdminCredit(requestId);
                        },
                ),
              ],
            ],
          ],
        ),
        const SizedBox(height: 16),
        // Superadmin section
        FormSection(
          title: 'Superadmin (Payments)',
          subtitle: l.isArabic
              ? 'تحكم كامل في الأدوار والحواجز المالية'
              : 'Full control over roles and guardrails',
          children: [
            Text(
              hasSuperadminAccess
                  ? 'Superadmin: full control over roles, guardrails and finance for Payments.'
                  : 'This phone is not Superadmin; Superadmin sees all roles and guardrails.',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              privilegeLabels.isEmpty
                  ? 'Payments privileges: none resolved'
                  : 'Payments privileges: ${privilegeLabels.join(", ")}',
            ),
            const SizedBox(height: 4),
            Text(
              _privileges.permissions.isEmpty
                  ? (_privileges.roles.isEmpty
                      ? 'Roles: none'
                      : 'Roles: ${_privileges.roles.join(", ")}')
                  : 'Permissions: ${_privileges.permissions.join(", ")}',
            ),
            const SizedBox(height: 4),
            Text(
              _operatorScope.isEmpty
                  ? 'Operator scope: none'
                  : 'Operator scope: ${_operatorScope.join(", ")}',
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: .70),
              ),
            ),
          ],
        ),
      ],
    );

    return DomainPageScaffold(
      background: bg,
      title: 'Payments',
      child: body,
      scrollable: false,
    );
  }
}

class _AdminCreditHistoryRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onApprove;

  const _AdminCreditHistoryRow({
    required this.item,
    required this.onApprove,
  });

  @override
  Widget build(BuildContext context) {
    final status = (item['status'] ?? '').toString();
    final amount = item['amount_cents'];
    final currency = (item['currency'] ?? '').toString();
    final target = (item['shamell_id'] ??
            item['account_id'] ??
            item['wallet_id'] ??
            item['approval_request_id'] ??
            '')
        .toString();
    final reason = (item['reason'] ?? '').toString();
    final createdAt = (item['created_at'] ?? '').toString();
    final pending = status == 'pending_approval';
    final amountLabel = amount is int
        ? '${fmtCents(amount)}${currency.isEmpty ? '' : ' $currency'}'
        : '-';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              pending
                  ? Icons.pending_actions_outlined
                  : Icons.check_circle_outline,
              size: 20,
              color: pending
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$amountLabel · ${status.isEmpty ? 'unknown' : status}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (pending)
              OutlinedButton.icon(
                onPressed: onApprove,
                icon: const Icon(Icons.verified_user_outlined, size: 18),
                label: const Text('Approve'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [target, reason, createdAt]
              .where((value) => value.isNotEmpty)
              .join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: .70),
          ),
        ),
      ],
    );
  }
}
