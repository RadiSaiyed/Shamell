// Cycle 178 — Operator-side "Upcoming Scheduled Rides" page.
//
// Pulls the operator-only endpoint that lists every scheduled
// booking across all riders, sorted by pickup time ascending,
// so dispatch can plan capacity. Rider account_ids are returned
// by the BFF (operator role gates the endpoint) but the page
// only shows the last 8 chars to reduce shoulder-surfing risk.
//
// Live polling cadence: 30s (the queue moves on minute boundaries
// when the in-process promoter runs).

import 'dart:async';

import 'package:flutter/material.dart';

import 'l10n.dart';
import 'scheduled_ride_api.dart';

class OperatorScheduledRidesPage extends StatefulWidget {
  final String baseUrl;

  const OperatorScheduledRidesPage({
    required this.baseUrl,
    super.key,
  });

  @override
  State<OperatorScheduledRidesPage> createState() =>
      _OperatorScheduledRidesPageState();
}

class _OperatorScheduledRidesPageState
    extends State<OperatorScheduledRidesPage> {
  late final ScheduledRideApi _api;
  List<ScheduledRide> _items = const <ScheduledRide>[];
  bool _loading = true;
  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _api = ScheduledRideApi(baseUrl: widget.baseUrl);
    unawaited(_refresh());
    _poller = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_refresh(silent: true));
    });
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) setState(() => _loading = true);
    final items = await _api.operatorListUpcoming();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
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

  String _fmtPickup(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    final wd = <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
        [local.weekday % 7];
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mn = local.minute.toString().padLeft(2, '0');
    return '$wd $dd.$mm · $hh:$mn';
  }

  String _maskAccount(String id) {
    if (id.length <= 8) return id;
    return '…${id.substring(id.length - 8)}';
  }

  Duration _toLead(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return Duration.zero;
    return parsed.difference(DateTime.now());
  }

  String _leadLabel(String iso, {required bool isArabic}) {
    final lead = _toLead(iso);
    if (lead.isNegative) {
      final mins = (-lead).inMinutes;
      return isArabic ? 'فات منذ $mins د' : '$mins min ago';
    }
    if (lead.inMinutes < 60) {
      return isArabic ? 'خلال ${lead.inMinutes} د' : 'in ${lead.inMinutes} min';
    }
    if (lead.inHours < 48) {
      return isArabic ? 'خلال ${lead.inHours} س' : 'in ${lead.inHours}h';
    }
    return isArabic ? 'خلال ${lead.inDays} يوم' : 'in ${lead.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'الحجوزات القادمة' : 'Upcoming bookings'),
        actions: <Widget>[
          IconButton(
            tooltip: isArabic ? 'تحديث' : 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : () => _refresh(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
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
                                ? 'لا توجد حجوزات قادمة.'
                                : 'No upcoming bookings.',
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
                                    _fmtPickup(r.scheduledPickupAt),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${r.pickupText} → ${r.destinationText}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: <Widget>[
                                  Icon(Icons.person_outline,
                                      size: 14,
                                      color: Colors.black.withValues(alpha: .6)),
                                  const SizedBox(width: 4),
                                  Text(
                                    _maskAccount(r.riderAccountId),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(Icons.timer_outlined,
                                      size: 14,
                                      color: Colors.black.withValues(alpha: .6)),
                                  const SizedBox(width: 4),
                                  Text(
                                    _leadLabel(r.scheduledPickupAt,
                                        isArabic: isArabic),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Icon(Icons.directions_car_outlined,
                                      size: 14,
                                      color: Colors.black.withValues(alpha: .6)),
                                  const SizedBox(width: 4),
                                  Text(
                                    r.rideClass,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (r.promotedRideId != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${isArabic ? "رحلة" : "Ride"}: ${r.promotedRideId}',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Color(0xFF388E3C),
                                  ),
                                ),
                              ],
                              if ((r.notes ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${isArabic ? "ملاحظات" : "Notes"}: ${r.notes!}',
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
