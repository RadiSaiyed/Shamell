// Cycle 209 — Operator promo management page.
//
// Lists all promo codes (newest first) with status / usage. FAB
// opens a create dialog. Inline "Disable" action pauses a code
// without dropping its history.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'promo_api.dart';

class OperatorPromoManagementPage extends StatefulWidget {
  final String baseUrl;

  const OperatorPromoManagementPage({
    required this.baseUrl,
    super.key,
  });

  @override
  State<OperatorPromoManagementPage> createState() =>
      _OperatorPromoManagementPageState();
}

class _OperatorPromoManagementPageState
    extends State<OperatorPromoManagementPage> {
  late final PromoApi _api;
  List<Promo> _items = const <Promo>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = PromoApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final list = await _api.operatorList();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _showCreateDialog() async {
    if (!mounted) return;
    final isArabic = L10n.of(context).isArabic;
    final codeCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    String kind = 'percent';
    DateTime? expiresAt;

    final created = await showDialog<Promo?>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (innerCtx, setSheetState) {
        return AlertDialog(
          title: Text(isArabic ? 'كود خصم جديد' : 'New promo code'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[A-Za-z0-9_\-]')),
                      LengthLimitingTextInputFormatter(32),
                    ],
                    decoration: InputDecoration(
                      labelText: isArabic ? 'الكود' : 'Code',
                      hintText: 'FIRSTRIDE20',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: <ButtonSegment<String>>[
                            ButtonSegment<String>(
                              value: 'percent',
                              label:
                                  Text(isArabic ? 'نسبة %' : 'Percent'),
                              icon: const Icon(Icons.percent_rounded),
                            ),
                            ButtonSegment<String>(
                              value: 'fixed',
                              label:
                                  Text(isArabic ? 'مبلغ ثابت' : 'Fixed'),
                              icon: const Icon(Icons.payments_outlined),
                            ),
                          ],
                          selected: <String>{kind},
                          onSelectionChanged: (s) =>
                              setSheetState(() => kind = s.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: valueCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: kind == 'percent'
                          ? (isArabic
                              ? 'النسبة (1-100)'
                              : 'Percent (1-100)')
                          : (isArabic ? 'المبلغ (SYP)' : 'Amount (SYP)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLength: 240,
                    decoration: InputDecoration(
                      labelText:
                          isArabic ? 'الوصف (اختياري)' : 'Description (optional)',
                      border: const OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: maxCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      labelText: isArabic
                          ? 'الحد الأقصى للاستخدام (اختياري)'
                          : 'Max redemptions (optional)',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: innerCtx,
                        initialDate: expiresAt ??
                            DateTime.now().add(const Duration(days: 30)),
                        firstDate: DateTime.now().add(const Duration(days: 1)),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setSheetState(() => expiresAt = picked);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Theme.of(innerCtx).colorScheme.outline),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.event_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(expiresAt == null
                                ? (isArabic
                                    ? 'بدون انتهاء صلاحية'
                                    : 'No expiry')
                                : '${isArabic ? "ينتهي" : "Expires"}: ${expiresAt!.toIso8601String().substring(0, 10)}'),
                          ),
                          if (expiresAt != null)
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () =>
                                  setSheetState(() => expiresAt = null),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text(isArabic ? 'إلغاء' : 'Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final code = codeCtrl.text.trim();
                final rawValue = int.tryParse(valueCtrl.text.trim()) ?? 0;
                if (code.isEmpty || rawValue <= 0) {
                  ScaffoldMessenger.of(innerCtx).showSnackBar(SnackBar(
                    content: Text(isArabic
                        ? 'يرجى تعبئة الحقول'
                        : 'Please fill code + value'),
                  ));
                  return;
                }
                // For percent we accept human "20" and pass it as
                // basis-points (20 * 100 = 2000 bps = 20%). For
                // fixed the rider-facing field is in whole SYP so
                // multiply by 100 for cents.
                final boundedValue =
                    kind == 'percent' ? rawValue * 100 : rawValue * 100;
                final maxN = int.tryParse(maxCtrl.text.trim());
                try {
                  final p = await _api.operatorCreate(
                    code: code.toUpperCase(),
                    kind: kind,
                    value: boundedValue,
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    maxRedemptions: maxN,
                    expiresAtUtc: expiresAt,
                  );
                  if (innerCtx.mounted) Navigator.of(innerCtx).pop(p);
                } on PromoApiException catch (err) {
                  if (innerCtx.mounted) {
                    ScaffoldMessenger.of(innerCtx).showSnackBar(SnackBar(
                      content: Text(err.detail.isNotEmpty
                          ? err.detail
                          : (isArabic
                              ? 'فشل إنشاء الكود'
                              : 'Failed to create')),
                    ));
                  }
                }
              },
              icon: const Icon(Icons.add_rounded),
              label: Text(isArabic ? 'إنشاء' : 'Create'),
            ),
          ],
        );
      }),
    );
    if (created != null) {
      await _refresh();
    }
  }

  Future<void> _disable(Promo p) async {
    final isArabic = L10n.of(context).isArabic;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArabic ? 'تعطيل الكود؟' : 'Disable code?'),
        content: Text(isArabic
            ? 'سيتم منع الاستخدام الجديد. سجل الاستخدامات السابقة لن يُحذف.'
            : 'New redemptions will be blocked. Past history is preserved.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isArabic ? 'تعطيل' : 'Disable'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _api.operatorDisable(code: p.code);
    if (!mounted) return;
    await _refresh();
  }

  String _kindLabel(Promo p, {required bool isArabic}) {
    if (p.kind == 'percent') {
      return isArabic
          ? '${(p.value / 100).toStringAsFixed(0)}%'
          : '${(p.value / 100).toStringAsFixed(0)}% off';
    }
    return isArabic
        ? 'خصم ${(p.value / 100).toStringAsFixed(0)} ${p.currency}'
        : '${(p.value / 100).toStringAsFixed(0)} ${p.currency} off';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'أكواد الخصم' : 'Promo codes'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _refresh,
            tooltip: isArabic ? 'تحديث' : 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      const SizedBox(height: 80),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            isArabic
                                ? 'لا توجد أكواد بعد. اضغط ‎+‎ لإنشاء واحد.'
                                : 'No promo codes yet. Tap + to create one.',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (ctx, i) {
                      final p = _items[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: p.isActive
                                          ? const Color(0xFF388E3C)
                                              .withValues(alpha: .14)
                                          : Colors.grey.withValues(alpha: .14),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      p.code,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w800,
                                        color: p.isActive
                                            ? const Color(0xFF1B5E20)
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Theme.of(ctx)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: .12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _kindLabel(p, isArabic: isArabic),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Theme.of(ctx)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (p.isActive)
                                    TextButton.icon(
                                      onPressed: () => _disable(p),
                                      icon: const Icon(
                                          Icons.block_rounded,
                                          size: 16),
                                      label: Text(
                                          isArabic ? 'تعطيل' : 'Disable'),
                                    ),
                                ],
                              ),
                              if ((p.description ?? '').trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(p.description!,
                                      style: const TextStyle(
                                          color: Colors.black54)),
                                ),
                              const SizedBox(height: 6),
                              Row(
                                children: <Widget>[
                                  Icon(Icons.shopping_basket_outlined,
                                      size: 14,
                                      color: Colors.black54),
                                  const SizedBox(width: 4),
                                  Text(
                                    isArabic
                                        ? 'الاستخدامات ${p.redemptionCount}${p.maxRedemptions != null ? "/${p.maxRedemptions}" : ""}'
                                        : 'Used ${p.redemptionCount}${p.maxRedemptions != null ? "/${p.maxRedemptions}" : ""}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (p.expiresAt != null) ...[
                                    const SizedBox(width: 12),
                                    Icon(Icons.event_outlined,
                                        size: 14,
                                        color: Colors.black54),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${isArabic ? "ينتهي" : "Expires"} ${p.expiresAt!.substring(0, 10)}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                  if (!p.isActive) ...[
                                    const SizedBox(width: 12),
                                    Text(
                                      isArabic ? 'معطّل' : 'Disabled',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: Text(isArabic ? 'كود جديد' : 'New code'),
      ),
    );
  }
}
