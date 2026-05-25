// Cycle 175 — "My scheduled rides" page.
//
// Self-contained list + creation flow for future-pickup bookings.
// Wired in from a menu entry in the main passenger surface; the
// page handles its own data load, refresh, create, and cancel.
//
// Visual contract:
//   * Card per booking with status badge (scheduled / promoted /
//     cancelled / expired).
//   * "Cancel" inline action only on scheduled bookings.
//   * Pull-to-refresh + FAB to create a new one.

import 'dart:async';

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'scheduled_ride_api.dart';
import 'scheduled_ride_dialog.dart';

class MyScheduledRidesPage extends StatefulWidget {
  final String baseUrl;

  const MyScheduledRidesPage({
    required this.baseUrl,
    super.key,
  });

  @override
  State<MyScheduledRidesPage> createState() => _MyScheduledRidesPageState();
}

class _MyScheduledRidesPageState extends State<MyScheduledRidesPage> {
  late final ScheduledRideApi _api;
  List<ScheduledRide> _items = const <ScheduledRide>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = ScheduledRideApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final items = await _api.listMine();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _createNew() async {
    if (!mounted) return;
    final isArabic = L10n.of(context).isArabic;
    final pickupCtrl = TextEditingController();
    final destinationCtrl = TextEditingController();
    final form = await showDialog<_NewSchedulingTarget?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArabic ? 'حجز جديد' : 'New booking'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: pickupCtrl,
                decoration: InputDecoration(
                  labelText: isArabic ? 'نقطة الالتقاط' : 'Pickup address',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: destinationCtrl,
                decoration: InputDecoration(
                  labelText: isArabic ? 'الوجهة' : 'Destination',
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final p = pickupCtrl.text.trim();
              final d = destinationCtrl.text.trim();
              if (p.isEmpty || d.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(isArabic
                      ? 'يرجى تعبئة الحقول'
                      : 'Please fill both fields'),
                ));
                return;
              }
              Navigator.of(ctx)
                  .pop(_NewSchedulingTarget(pickup: p, destination: d));
            },
            child: Text(isArabic ? 'متابعة' : 'Continue'),
          ),
        ],
      ),
    );
    if (form == null || !mounted) return;
    final ride = await showScheduledRideDialog(
      context: context,
      api: _api,
      pickupText: form.pickup,
      destinationText: form.destination,
      isArabic: isArabic,
    );
    if (ride != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isArabic
            ? 'تم حجز الرحلة'
            : 'Trip scheduled'),
      ));
      await _refresh();
    }
  }

  Future<void> _cancel(ScheduledRide ride) async {
    if (!mounted) return;
    final isArabic = L10n.of(context).isArabic;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArabic ? 'إلغاء الحجز؟' : 'Cancel booking?'),
        content: Text(isArabic
            ? 'سيتم إلغاء الحجز بشكل دائم.'
            : 'This will permanently cancel the booking.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isArabic ? 'لا' : 'No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(isArabic ? 'إلغاء الحجز' : 'Cancel it'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _api.cancel(id: ride.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isArabic ? 'تم الإلغاء' : 'Cancelled'),
      ));
      await _refresh();
    } on ScheduledRideApiException catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err.detail.isNotEmpty
            ? err.detail
            : (isArabic ? 'فشل الإلغاء' : 'Cancel failed')),
      ));
    }
  }

  String _statusLabel(String status, {required bool isArabic}) {
    switch (status) {
      case 'scheduled':
        return isArabic ? 'مجدول' : 'Scheduled';
      case 'promoted':
        return isArabic ? 'جاري المطابقة' : 'Matching';
      case 'cancelled':
        return isArabic ? 'ملغى' : 'Cancelled';
      case 'expired':
        return isArabic ? 'منتهي' : 'Expired';
      default:
        return status;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case 'scheduled':
        return scheme.primary;
      case 'promoted':
        return const Color(0xFF388E3C);
      case 'cancelled':
      case 'expired':
        return Colors.black54;
      default:
        return scheme.outline;
    }
  }

  String _fmtIso(String iso, {required bool isArabic}) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$dd.$mm $hh:$mn';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'الرحلات المحجوزة' : 'Scheduled rides'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      const SizedBox(height: 64),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            isArabic
                                ? 'لا توجد رحلات محجوزة. اضغط ‎+‎ للحجز.'
                                : 'No scheduled rides yet. Tap + to book one.',
                            textAlign: TextAlign.center,
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
                      final r = _items[i];
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
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _statusColor(context, r.status)
                                          .withValues(alpha: .14),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _statusLabel(r.status, isArabic: isArabic)
                                          .toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: _statusColor(context, r.status),
                                        letterSpacing: .4,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    _fmtIso(r.scheduledPickupAt,
                                        isArabic: isArabic),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${r.pickupText} → ${r.destinationText}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              if ((r.notes ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  r.notes!,
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (r.isScheduled) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => _cancel(r),
                                    icon: const Icon(Icons.close_rounded,
                                        size: 16),
                                    label: Text(
                                        isArabic ? 'إلغاء' : 'Cancel'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNew,
        icon: const Icon(Icons.event_available_rounded),
        label: Text(isArabic ? 'حجز جديد' : 'New booking'),
      ),
    );
  }
}

class _NewSchedulingTarget {
  final String pickup;
  final String destination;
  const _NewSchedulingTarget({required this.pickup, required this.destination});
}
