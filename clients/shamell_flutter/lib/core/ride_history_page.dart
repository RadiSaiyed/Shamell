// Cycle 181 + 183 — Ride history page + receipt-style detail.
//
// One page used by both rider and driver: a `historyKind` discriminator
// drives whether we fetch /me/rides/history or /me/rides/driver/history.
// Tapping an entry opens a receipt-style bottom sheet with the fare
// breakdown + rating + counterpart name (where allowed).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'format.dart';
import 'l10n.dart';
import 'ride_history_api.dart';

enum RideHistoryKind { rider, driver }

class RideHistoryPage extends StatefulWidget {
  final String baseUrl;
  final RideHistoryKind kind;

  const RideHistoryPage({
    required this.baseUrl,
    required this.kind,
    super.key,
  });

  @override
  State<RideHistoryPage> createState() => _RideHistoryPageState();
}

class _RideHistoryPageState extends State<RideHistoryPage> {
  late final RideHistoryApi _api;
  List<TripHistoryEntry> _items = const <TripHistoryEntry>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = RideHistoryApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final items = widget.kind == RideHistoryKind.rider
        ? await _api.rider()
        : await _api.driver();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String _statusLabel(String status, {required bool isArabic}) {
    switch (status) {
      case 'trip_completed':
        return isArabic ? 'مكتملة' : 'Completed';
      case 'canceled':
      case 'cancelled':
        return isArabic ? 'ملغاة' : 'Cancelled';
      case 'trip_in_progress':
      case 'trip_started':
        return isArabic ? 'قيد التنفيذ' : 'In progress';
      case 'driver_arriving':
        return isArabic ? 'السائق قادم' : 'Driver en route';
      case 'driver_arrived':
        return isArabic ? 'السائق وصل' : 'Driver arrived';
      case 'matching':
        return isArabic ? 'مطابقة' : 'Matching';
      case 'payment_failed':
        return isArabic ? 'فشل الدفع' : 'Payment failed';
      default:
        return status;
    }
  }

  Color _statusColor(BuildContext ctx, String status) {
    final scheme = Theme.of(ctx).colorScheme;
    switch (status) {
      case 'trip_completed':
        return const Color(0xFF2E7D32);
      case 'canceled':
      case 'cancelled':
        return Colors.black54;
      case 'payment_failed':
        return scheme.error;
      default:
        return scheme.primary;
    }
  }

  String _fmtIso(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final yy = local.year.toString().substring(2);
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd.$mm.$yy · $hh:$mn';
  }

  Future<void> _openReceipt(TripHistoryEntry trip) async {
    if (!mounted) return;
    final isArabic = L10n.of(context).isArabic;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * .72,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(ctx, trip.status)
                            .withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _statusLabel(trip.status, isArabic: isArabic)
                            .toUpperCase(),
                        style: TextStyle(
                          color: _statusColor(ctx, trip.status),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _fmtIso(trip.completedAt ?? trip.statusUpdatedAt),
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  isArabic ? 'إيصال الرحلة' : 'Trip receipt',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _receiptRow(
                  ctx,
                  label: isArabic ? 'الانطلاق' : 'Pickup',
                  value: trip.pickupLabel?.trim().isNotEmpty == true
                      ? trip.pickupLabel!
                      : trip.pickupText,
                ),
                _receiptRow(
                  ctx,
                  label: isArabic ? 'الوصول' : 'Destination',
                  value: trip.destinationLabel?.trim().isNotEmpty == true
                      ? trip.destinationLabel!
                      : trip.destinationText,
                ),
                _receiptRow(
                  ctx,
                  label: isArabic ? 'نوع الرحلة' : 'Ride class',
                  value: trip.rideClass,
                ),
                if ((trip.counterpartName ?? '').trim().isNotEmpty)
                  _receiptRow(
                    ctx,
                    label: isArabic ? 'السائق' : 'Driver',
                    value: trip.counterpartName!,
                  ),
                if ((trip.cancelReasonCode ?? '').trim().isNotEmpty)
                  _receiptRow(
                    ctx,
                    label: isArabic ? 'سبب الإلغاء' : 'Cancel reason',
                    value: trip.cancelReasonCode!,
                  ),
                const Divider(height: 28),
                _receiptRow(
                  ctx,
                  label: isArabic ? 'الأجرة' : 'Fare',
                  value: '${fmtCents(trip.fareEstimateCents)} SYP',
                  emphasis: true,
                ),
                if (trip.hasOwnRating) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Text(
                        isArabic ? 'تقييمك' : 'Your rating',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black54),
                      ),
                      const SizedBox(width: 12),
                      for (var i = 1; i <= 5; i++)
                        Icon(
                          i <= trip.ownRatingStars!
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 20,
                          color: i <= trip.ownRatingStars!
                              ? const Color(0xFFFFA000)
                              : Colors.black26,
                        ),
                    ],
                  ),
                  if ((trip.ownRatingComment ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '"${trip.ownRatingComment!}"',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.fingerprint_rounded,
                          size: 14, color: Colors.black45),
                      const SizedBox(width: 6),
                      Expanded(
                        child: SelectableText(
                          trip.rideId,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                        ),
                      ),
                      IconButton(
                        tooltip: isArabic ? 'نسخ' : 'Copy',
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: trip.rideId));
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content:
                                Text(isArabic ? 'تم النسخ' : 'Copied'),
                            duration: const Duration(seconds: 2),
                          ));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(BuildContext ctx,
      {required String label,
      required String value,
      bool emphasis = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasis ? 18 : 14,
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic
            ? (widget.kind == RideHistoryKind.driver
                ? 'سجل رحلات السائق'
                : 'سجل الرحلات')
            : (widget.kind == RideHistoryKind.driver
                ? 'Driver trip history'
                : 'Trip history')),
        actions: <Widget>[
          IconButton(
            tooltip: isArabic ? 'تحديث' : 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _refresh,
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
                                ? 'لا توجد رحلات سابقة بعد.'
                                : 'No past trips yet.',
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
                      final t = _items[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: () => _openReceipt(t),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: _statusColor(ctx, t.status)
                                            .withValues(alpha: .14),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        _statusLabel(t.status,
                                                isArabic: isArabic)
                                            .toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: _statusColor(ctx, t.status),
                                          letterSpacing: .4,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      _fmtIso(t.completedAt ?? t.statusUpdatedAt),
                                      style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${t.pickupText} → ${t.destinationText}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: <Widget>[
                                    Text(
                                      '${fmtCents(t.fareEstimateCents)} SYP',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Text(
                                      t.rideClass,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (t.hasOwnRating) ...[
                                      const Spacer(),
                                      const Icon(Icons.star_rounded,
                                          color: Color(0xFFFFA000), size: 16),
                                      const SizedBox(width: 2),
                                      Text(
                                        '${t.ownRatingStars}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: Color(0xFFB8860B),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
