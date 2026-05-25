import 'dart:async';

import 'package:flutter/material.dart';

import '../app_sounds.dart';
import '../design_tokens.dart';
import '../format.dart';
import '../l10n.dart';
import '../safe_set_state.dart';
import '../shamell_loading_shimmer.dart';
import '../shamell_phase_strip.dart';
import '../status_banner.dart';
import '../wechat_ui.dart';
import 'coach_mobility_api.dart';
import 'coach_ops_feature_widgets.dart';
import 'coach_platform_contracts.dart';

const Set<String> _coachMiniProgramSyriaRouteLocationKeys = <String>{
  'damascus',
  'damascus central',
  'damascus bus station',
  'دمشق',
  'محطة دمشق المركزية',
  'homs',
  'homs gateway',
  'homs bus station',
  'حمص',
  'aleppo',
  'aleppo terminal',
  'aleppo central bus terminal',
  'حلب',
  'محطة حلب المركزية',
  'latakia',
  'latakia bus station',
  'اللاذقية',
};

String _coachMiniProgramLocationKey(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .join(' ');
}

bool coachMiniProgramSupportsSyriaSearchLocation(String? raw) {
  final normalized = (raw ?? '').trim();
  if (normalized.isEmpty) {
    return false;
  }
  return _coachMiniProgramSyriaRouteLocationKeys
      .contains(_coachMiniProgramLocationKey(normalized));
}

String? coachMiniProgramNormalizeSyrianSearchLocation(String? raw) {
  final normalized = (raw ?? '').trim();
  if (normalized.isEmpty) {
    return null;
  }
  return coachMiniProgramSupportsSyriaSearchLocation(normalized)
      ? normalized
      : null;
}

String coachMiniProgramSyriaRouteHint({required bool isArabic}) {
  return isArabic
      ? 'هذا الميني برنامج مخصص حالياً للرحلات بين المدن داخل سوريا فقط. المدن المدعومة في البحث حالياً: دمشق، حمص، حلب، اللاذقية.'
      : 'This mini program currently supports Syria-only intercity routes. Search currently supports Damascus, Homs, Aleppo, and Latakia.';
}

String coachMiniProgramSyriaRouteSearchError({required bool isArabic}) {
  return isArabic
      ? 'البحث متاح حالياً فقط لرحلات سوريا بين دمشق وحمص وحلب واللاذقية.'
      : 'Search is currently limited to Syria routes between Damascus, Homs, Aleppo, and Latakia.';
}

enum _CoachBusMiniTab { plan, trips, tickets }

enum _CoachJourneyBoardSortMode { departure, fastest, cheapest }

String _coachMiniProgramCompactDate(String raw) {
  final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(raw);
  return match?.group(1) ?? raw;
}

String _coachMiniProgramCompactTime(String raw) {
  final match = RegExp(r'T(\d{2}:\d{2})').firstMatch(raw);
  return match?.group(1) ?? raw;
}

DateTime? _coachMiniProgramParseDateOnly(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) {
    return null;
  }
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) {
    return null;
  }
  return DateTime(year, month, day);
}

String _coachMiniProgramDateOnlyValue(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String _coachMiniProgramWeekdayLabel(DateTime date, bool isArabic) {
  if (isArabic) {
    const weekdays = <String>[
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    return weekdays[date.weekday - 1];
  }
  const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return weekdays[date.weekday - 1];
}

String _coachMiniProgramRelativeDateLabel(int offsetDays, bool isArabic) {
  switch (offsetDays) {
    case 0:
      return isArabic ? 'اليوم' : 'Today';
    case 1:
      return isArabic ? 'غداً' : 'Tomorrow';
    case 2:
      return isArabic ? 'بعد الغد' : 'Day after';
    default:
      return isArabic ? 'خلال $offsetDays أيام' : 'In $offsetDays days';
  }
}

String _coachMiniProgramDepartureSummary(String raw, bool isArabic) {
  final date = _coachMiniProgramParseDateOnly(raw);
  if (date == null) {
    return raw;
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final offsetDays = target.difference(today).inDays;
  final relativeLabel = offsetDays >= 0 && offsetDays <= 2
      ? _coachMiniProgramRelativeDateLabel(offsetDays, isArabic)
      : _coachMiniProgramWeekdayLabel(target, isArabic);
  return '$relativeLabel • ${_coachMiniProgramDateOnlyValue(target)}';
}

String _coachMiniProgramJourneyWindow(
    String departureAtIso, String arrivalAtIso) {
  return '${_coachMiniProgramCompactTime(departureAtIso)} - ${_coachMiniProgramCompactTime(arrivalAtIso)}';
}

String _coachMiniProgramCompactDateTime(String raw) {
  final date = _coachMiniProgramCompactDate(raw);
  final time = _coachMiniProgramCompactTime(raw);
  if (date == raw && time == raw) {
    return raw;
  }
  if (date == raw) {
    return time;
  }
  if (time == raw) {
    return date;
  }
  return '$date • $time';
}

String _coachMiniProgramCompactDateTimeRange(
  String departureAtIso,
  String arrivalAtIso,
) {
  final departureDate = _coachMiniProgramCompactDate(departureAtIso);
  final arrivalDate = _coachMiniProgramCompactDate(arrivalAtIso);
  if (departureDate == arrivalDate) {
    return '$departureDate • ${_coachMiniProgramJourneyWindow(departureAtIso, arrivalAtIso)}';
  }
  return '${_coachMiniProgramCompactDateTime(departureAtIso)} - ${_coachMiniProgramCompactDateTime(arrivalAtIso)}';
}

String _coachMiniProgramDurationLabel(int durationMinutes, bool isArabic) {
  final hours = durationMinutes ~/ 60;
  final minutes = durationMinutes % 60;
  if (hours <= 0) {
    return isArabic ? '$minutes د' : '${minutes}m';
  }
  if (minutes == 0) {
    return isArabic ? '$hours س' : '${hours}h';
  }
  return isArabic ? '$hours س $minutes د' : '${hours}h ${minutes}m';
}

String _coachMiniProgramTransferLabel(int transferCount, bool isArabic) {
  if (transferCount <= 0) {
    return isArabic ? 'مباشر' : 'Direct';
  }
  if (transferCount == 1) {
    return isArabic ? 'تبديل واحد' : '1 change';
  }
  return isArabic ? '$transferCount تبديلات' : '$transferCount changes';
}

String _coachMiniProgramTravelerCountLabel(int passengers, bool isArabic) {
  if (isArabic) {
    if (passengers == 1) {
      return 'مسافر واحد';
    }
    if (passengers == 2) {
      return 'مسافران';
    }
    return '$passengers مسافرين';
  }
  if (passengers == 1) {
    return '1 traveler';
  }
  return '$passengers travelers';
}

String _coachMiniProgramTabLabel(_CoachBusMiniTab tab, bool isArabic) {
  switch (tab) {
    case _CoachBusMiniTab.plan:
      return isArabic ? 'التخطيط' : 'Plan';
    case _CoachBusMiniTab.trips:
      return isArabic ? 'الرحلات' : 'Trips';
    case _CoachBusMiniTab.tickets:
      return isArabic ? 'التذاكر' : 'Tickets';
  }
}

String _coachMiniProgramJourneyBoardSortLabel(
  _CoachJourneyBoardSortMode mode,
  bool isArabic,
) {
  switch (mode) {
    case _CoachJourneyBoardSortMode.departure:
      return isArabic ? 'المغادرة' : 'Departure';
    case _CoachJourneyBoardSortMode.fastest:
      return isArabic ? 'الأسرع' : 'Fastest';
    case _CoachJourneyBoardSortMode.cheapest:
      return isArabic ? 'الأرخص' : 'Cheapest';
  }
}

String _coachMiniProgramLocalizedCityName(String city, bool isArabic) {
  if (!isArabic) {
    return city;
  }
  switch (_coachMiniProgramLocationKey(city)) {
    case 'damascus':
      return 'دمشق';
    case 'homs':
      return 'حمص';
    case 'aleppo':
      return 'حلب';
    case 'latakia':
      return 'اللاذقية';
    default:
      return city;
  }
}

String _coachMiniProgramJourneyStepStatusLabel(
  _CoachJourneyStepState state,
  bool isArabic,
) {
  switch (state) {
    case _CoachJourneyStepState.complete:
      return isArabic ? 'مكتمل' : 'Complete';
    case _CoachJourneyStepState.active:
      return isArabic ? 'الحالة الحالية' : 'Current';
    case _CoachJourneyStepState.pending:
      return isArabic ? 'لاحقاً' : 'Later';
  }
}

class _CoachRoutePreset {
  final String from;
  final String to;

  const _CoachRoutePreset({
    required this.from,
    required this.to,
  });
}

const List<_CoachRoutePreset> _coachMiniProgramRoutePresets =
    <_CoachRoutePreset>[
  _CoachRoutePreset(from: 'Damascus', to: 'Aleppo'),
  _CoachRoutePreset(from: 'Damascus', to: 'Homs'),
  _CoachRoutePreset(from: 'Homs', to: 'Aleppo'),
  _CoachRoutePreset(from: 'Damascus', to: 'Latakia'),
];

enum _CoachJourneyStepState { complete, active, pending }

String _coachMiniProgramRefundKindLabel(CoachRefundKind kind, bool isArabic) {
  switch (kind) {
    case CoachRefundKind.refundCredit:
      return isArabic ? 'رصيد سفر' : 'Travel credit';
    case CoachRefundKind.originalPayment:
      return isArabic ? 'الدفعة الأصلية' : 'Original payment';
  }
}

String _coachMiniProgramPaymentMethodLabel(
    String paymentMethod, bool isArabic) {
  switch (paymentMethod) {
    case 'wallet_credit':
      return isArabic ? 'رصيد المحفظة' : 'Wallet credit';
    case 'split_tender':
      return isArabic ? 'دفع مختلط' : 'Split tender';
    case 'card':
    default:
      return isArabic ? 'بطاقة' : 'Card';
  }
}

String _coachMiniProgramBookingStateLabel(
  CoachBookingLifecycleState state,
  bool isArabic,
) {
  switch (state) {
    case CoachBookingLifecycleState.searchResulted:
      return isArabic ? 'تم إيجاد الرحلة' : 'Journey found';
    case CoachBookingLifecycleState.offerCreated:
      return isArabic ? 'تم إنشاء العرض' : 'Offer created';
    case CoachBookingLifecycleState.holdCreated:
      return isArabic ? 'تم إنشاء الحجز المؤقت' : 'Hold created';
    case CoachBookingLifecycleState.paymentPending:
      return isArabic ? 'بانتظار الدفع' : 'Payment pending';
    case CoachBookingLifecycleState.paymentAuthorized:
      return isArabic ? 'تم اعتماد الدفع' : 'Payment authorized';
    case CoachBookingLifecycleState.bookingPending:
      return isArabic ? 'الحجز قيد المعالجة' : 'Booking pending';
    case CoachBookingLifecycleState.ticketed:
      return isArabic ? 'تم إصدار التذاكر' : 'Ticketed';
    case CoachBookingLifecycleState.partiallyTicketed:
      return isArabic ? 'تم إصدار جزء من التذاكر' : 'Partially ticketed';
    case CoachBookingLifecycleState.cancelled:
      return isArabic ? 'ملغي' : 'Cancelled';
    case CoachBookingLifecycleState.refundRequested:
      return isArabic ? 'تم طلب الاسترداد' : 'Refund requested';
    case CoachBookingLifecycleState.refundApproved:
      return isArabic ? 'تمت الموافقة على الاسترداد' : 'Refund approved';
    case CoachBookingLifecycleState.refunded:
      return isArabic ? 'تم الاسترداد' : 'Refunded';
    case CoachBookingLifecycleState.boarded:
      return isArabic ? 'تم الصعود' : 'Boarded';
    case CoachBookingLifecycleState.noShow:
      return isArabic ? 'لم يحضر' : 'No-show';
  }
}

String _coachMiniProgramHoldStatusLabel(CoachHoldStatus status, bool isArabic) {
  switch (status) {
    case CoachHoldStatus.active:
      return isArabic ? 'نشط' : 'Active';
    case CoachHoldStatus.expired:
      return isArabic ? 'منتهي' : 'Expired';
    case CoachHoldStatus.converted:
      return isArabic ? 'تم تحويله' : 'Converted';
    case CoachHoldStatus.released:
      return isArabic ? 'تم تحريره' : 'Released';
  }
}

String _coachMiniProgramRiderCategoryLabel(
  CoachPassengerRiderCategory category,
  bool isArabic,
) {
  switch (category) {
    case CoachPassengerRiderCategory.adult:
      return isArabic ? 'بالغ' : 'Adult';
    case CoachPassengerRiderCategory.child:
      return isArabic ? 'طفل' : 'Child';
    case CoachPassengerRiderCategory.student:
      return isArabic ? 'طالب' : 'Student';
    case CoachPassengerRiderCategory.senior:
      return isArabic ? 'كبير سن' : 'Senior';
  }
}

String _coachMiniProgramTicketStatusLabel(
  CoachTicketStatus status,
  bool isArabic,
) {
  switch (status) {
    case CoachTicketStatus.active:
      return isArabic ? 'صالحة' : 'Active';
    case CoachTicketStatus.voided:
      return isArabic ? 'ملغاة' : 'Voided';
    case CoachTicketStatus.used:
      return isArabic ? 'مستخدمة' : 'Used';
  }
}

String _coachMiniProgramScanStatusLabel(
  CoachBoardingScanStatus status,
  bool isArabic,
) {
  switch (status) {
    case CoachBoardingScanStatus.scanned:
      return isArabic ? 'تم المسح' : 'Scanned';
    case CoachBoardingScanStatus.denied:
      return isArabic ? 'مرفوض' : 'Denied';
    case CoachBoardingScanStatus.duplicate:
      return isArabic ? 'مكرر' : 'Duplicate';
    case CoachBoardingScanStatus.revoked:
      return isArabic ? 'ملغى' : 'Revoked';
    case CoachBoardingScanStatus.noShow:
      return isArabic ? 'لم يحضر' : 'No-show';
  }
}

String _coachMiniProgramBoardingStateLabel(
  CoachManifestBoardingState? state,
  bool isArabic,
) {
  switch (state) {
    case CoachManifestBoardingState.notBoarded:
      return isArabic ? 'جاهزة للصعود' : 'Ready to board';
    case CoachManifestBoardingState.boarded:
      return isArabic ? 'تم الصعود' : 'Boarded';
    case CoachManifestBoardingState.denied:
      return isArabic ? 'مرفوضة عند الصعود' : 'Boarding denied';
    case CoachManifestBoardingState.duplicateAttempt:
      return isArabic ? 'محاولة مكررة' : 'Duplicate scan';
    case CoachManifestBoardingState.revoked:
      return isArabic ? 'ألغيت' : 'Revoked';
    case CoachManifestBoardingState.noShow:
      return isArabic ? 'لم يحضر' : 'No-show';
    case null:
      return isArabic ? 'جاهزة للفحص' : 'Ready for inspection';
  }
}

String _coachMiniProgramIntegrationModeLabel(
  CoachOperatorIntegrationMode mode,
  bool isArabic,
) {
  switch (mode) {
    case CoachOperatorIntegrationMode.feed:
      return isArabic ? 'عبر التغذية' : 'Feed';
    case CoachOperatorIntegrationMode.api:
      return 'API';
    case CoachOperatorIntegrationMode.hybrid:
      return isArabic ? 'هجين' : 'Hybrid';
  }
}

String _coachMiniProgramAmenityLabel(String raw, bool isArabic) {
  switch (raw.trim().toLowerCase()) {
    case 'wifi':
      return isArabic ? 'واي فاي' : 'Wi-Fi';
    case 'power_outlet':
      return isArabic ? 'مقبس كهرباء' : 'Power outlet';
    case 'toilet':
      return isArabic ? 'دورة مياه' : 'WC';
    default:
      return raw.replaceAll('_', ' ');
  }
}

String _coachMiniProgramLiveRunningLabel(
  CoachJourneyLiveSnapshot live,
  bool isArabic,
) {
  if (!live.tripUpdatesFresh) {
    return isArabic ? 'التحديث المباشر قديم' : 'Live feed stale';
  }
  if (live.delayMinutes <= 0) {
    return isArabic ? 'في الموعد' : 'On time';
  }
  return isArabic ? '+${live.delayMinutes} د' : '+${live.delayMinutes} min';
}

String _coachMiniProgramSeatAvailabilityLabel(
  int seatsAvailable,
  bool lowAvailability,
  bool isArabic,
) {
  if (lowAvailability) {
    return isArabic ? 'مقاعد قليلة' : 'Few seats left';
  }
  return isArabic ? '$seatsAvailable مقاعد' : '$seatsAvailable seats';
}

String _coachMiniProgramTicketReadinessLabel(int ticketCount, bool isArabic) {
  if (ticketCount <= 0) {
    return isArabic ? 'لم تصدر بعد' : 'Not issued yet';
  }
  if (ticketCount == 1) {
    return isArabic ? 'بطاقة صعود جاهزة' : 'Boarding pass ready';
  }
  return isArabic ? '$ticketCount تذاكر جاهزة' : '$ticketCount tickets ready';
}

String _coachMiniProgramPassengerPreviewLabel(
  List<CoachPassengerManifest> manifests,
  bool isArabic,
) {
  if (manifests.isEmpty) {
    return isArabic ? 'الأسماء قيد الإضافة' : 'Passenger names pending';
  }
  final first = manifests.first.displayName;
  final extraCount = manifests.length - 1;
  if (extraCount <= 0) {
    return first;
  }
  return '$first +$extraCount';
}

String _coachMiniProgramManifestProgressLabel(
  int boardedCount,
  int manifestCount,
  bool isArabic,
) {
  if (isArabic) {
    return '$boardedCount/$manifestCount صعدوا';
  }
  return '$boardedCount/$manifestCount boarded';
}

String _coachMiniProgramFeedKindLabel(String raw, bool isArabic) {
  switch (raw.trim().toLowerCase()) {
    case 'gtfs_rt_trip_updates':
      return isArabic ? 'تحديثات الرحلة' : 'Trip updates';
    case 'gtfs_rt_vehicle_positions':
      return isArabic ? 'مواقع المركبات' : 'Vehicle positions';
    case 'siri':
      return 'SIRI';
    default:
      return raw;
  }
}

String _coachMiniProgramStatusWord(String raw, bool isArabic) {
  switch (raw.trim().toLowerCase()) {
    case 'ok':
      return isArabic ? 'جيد' : 'OK';
    case 'fresh':
      return isArabic ? 'حديث' : 'Fresh';
    case 'degraded':
      return isArabic ? 'متراجع' : 'Degraded';
    case 'missing':
      return isArabic ? 'مفقود' : 'Missing';
    case 'authorized':
      return isArabic ? 'معتمد' : 'Authorized';
    case 'failed':
      return isArabic ? 'فشل' : 'Failed';
    case 'reissued':
      return isArabic ? 'أعيد الإصدار' : 'Reissued';
    case 'payment_failed':
      return isArabic ? 'فشل الدفع' : 'Payment failed';
    case 'completed':
      return isArabic ? 'مكتمل' : 'Completed';
    case 'resolve_payment_failure':
      return isArabic ? 'حل مشكلة الدفع' : 'Resolve payment failure';
    case 'refund_credit':
      return isArabic ? 'رصيد سفر' : 'Travel credit';
    case 'original_payment':
      return isArabic ? 'طريقة الدفع الأصلية' : 'Original payment';
    default:
      return raw;
  }
}

String _coachMiniProgramCompensationActionLabel(String raw, bool isArabic) {
  switch (raw.trim().toLowerCase()) {
    case 'retry_collection_or_raise_support_case':
      return isArabic
          ? 'أعد التحصيل أو ارفع حالة دعم'
          : 'Retry collection or raise support case';
    default:
      return raw.replaceAll('_', ' ');
  }
}

VoidCallback? _coachMiniProgramHandleTap(VoidCallback? callback) {
  if (callback == null) {
    return null;
  }
  return () {
    FocusManager.instance.primaryFocus?.unfocus();
    callback();
  };
}

String _coachMiniProgramBooleanRequirementLabel(bool required, bool isArabic) {
  if (required) {
    return isArabic ? 'مطلوب' : 'Required';
  }
  return isArabic ? 'غير مطلوب' : 'Not required';
}

class _CoachLiquidGlassPanel extends StatelessWidget {
  final Widget child;
  final Color? tint;
  final EdgeInsetsGeometry padding;

  const _CoachLiquidGlassPanel({
    required this.child,
    this.tint,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final base = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surface;
    final background = tint == null
        ? base
        : Color.alphaBlend(
            tint!.withValues(alpha: isDark ? .08 : .06),
            base,
          );
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .42 : .82),
          width: .8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? .20 : .06),
            blurRadius: 14,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class MobilityHubPage extends StatelessWidget {
  final VoidCallback onOpenRide;
  final VoidCallback? onOpenCoach;

  const MobilityHubPage({
    super.key,
    required this.onOpenRide,
    this.onOpenCoach,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0F172A)
          : WeChatPalette.background,
      appBar: AppBar(
        title: Text(isArabic ? 'مركز التنقّل' : 'Mobility hub'),
        surfaceTintColor: Colors.transparent,
      ),
      body: ColoredBox(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF0F172A)
            : WeChatPalette.background,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              isArabic
                  ? 'اختر خدمة التنقّل داخل SyrChat.'
                  : 'Choose the mobility service inside SyrChat.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _MobilitySurfaceCard(
              title: isArabic ? 'تاكسي' : 'Taxi',
              subtitle: isArabic
                  ? 'رحلات فورية، تتبع مباشر، ودعم يوم الرحلة.'
                  : 'Instant rides, live tracking, and trip-day support.',
              icon: Icons.local_taxi_outlined,
              tint: const Color(0xFF0EA5E9),
              buttonLabel: isArabic ? 'افتح التاكسي' : 'Open taxi',
              onTap: onOpenRide,
            ),
            if (onOpenCoach != null) ...[
              const SizedBox(height: 12),
              _MobilitySurfaceCard(
                title: isArabic ? 'الحافلات بين المدن' : 'Coach bus',
                subtitle: isArabic
                    ? 'بحث وحجز وتذاكر للرحلات بين المدن داخل سوريا.'
                    : 'Search, booking, and tickets for Syria intercity routes.',
                icon: Icons.directions_bus_outlined,
                tint: Tokens.colorBus,
                buttonLabel: isArabic ? 'افتح الحافلات' : 'Open coach',
                onTap: onOpenCoach!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MobilitySurfaceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final String buttonLabel;
  final VoidCallback onTap;

  const _MobilitySurfaceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CoachLiquidGlassPanel(
      tint: Color.alphaBlend(tint.withValues(alpha: .10), scheme.surface),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: tint, size: 24),
          ),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _coachMiniProgramHandleTap(onTap),
            icon: const Icon(Icons.arrow_forward),
            label: Text(buttonLabel),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CoachBusMiniProgramPage extends StatefulWidget {
  final String baseUrl;
  final CoachMobilityApi? apiOverride;
  final String? initialFrom;
  final String? initialTo;
  final String? initialDepartureDate;
  final int initialPassengers;

  const CoachBusMiniProgramPage({
    super.key,
    required this.baseUrl,
    this.apiOverride,
    this.initialFrom,
    this.initialTo,
    this.initialDepartureDate,
    this.initialPassengers = 1,
  });

  @override
  State<CoachBusMiniProgramPage> createState() =>
      _CoachBusMiniProgramPageState();
}

class _CoachBusMiniProgramPageState extends State<CoachBusMiniProgramPage>
    with SafeSetStateMixin<CoachBusMiniProgramPage> {
  late final CoachMobilityApi _api =
      widget.apiOverride ?? CoachMobilityApi(baseUrl: widget.baseUrl);
  late final TextEditingController _fromController;
  late final TextEditingController _toController;
  late final TextEditingController _departureDateController;
  late final TextEditingController _contactEmailController;
  final List<TextEditingController> _passengerIdControllers =
      <TextEditingController>[];
  final List<TextEditingController> _passengerGivenNameControllers =
      <TextEditingController>[];
  final List<TextEditingController> _passengerFamilyNameControllers =
      <TextEditingController>[];
  final List<TextEditingController> _passengerNationalityControllers =
      <TextEditingController>[];
  final List<CoachPassengerRiderCategory> _passengerCategories =
      <CoachPassengerRiderCategory>[];
  final List<TextEditingController> _preferredSeatControllers =
      <TextEditingController>[];

  CoachPlatformBootstrap? _bootstrap;
  String? _bootstrapError;
  bool _bootstrapLoading = true;
  CoachBookingShelfResponse? _bookingShelf;
  String? _bookingShelfError;
  bool _bookingShelfLoading = true;

  bool _searching = false;
  String? _searchError;
  CoachJourneySearchResponse? _searchResponse;
  CoachJourneyOption? _selectedJourney;
  CoachOffer? _selectedOffer;
  CoachHold? _previewHold;
  CoachBooking? _previewBooking;
  List<CoachPassengerManifest> _previewPassengerManifests =
      const <CoachPassengerManifest>[];
  List<CoachTicketCoupon> _previewTickets = const <CoachTicketCoupon>[];
  CoachCompensationState? _compensation;
  String? _commandNote;
  String? _previewError;
  bool _previewLoading = false;
  int _passengers = 1;
  String _paymentMethod = 'card';
  bool _deliverWalletPass = true;
  bool _deliverPdf = true;
  bool _deliverEmail = false;
  _CoachBusMiniTab _activeTab = _CoachBusMiniTab.plan;
  _CoachJourneyBoardSortMode _journeyBoardSortMode =
      _CoachJourneyBoardSortMode.departure;
  bool _journeyBoardDirectOnly = false;

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController(
      text: coachMiniProgramNormalizeSyrianSearchLocation(widget.initialFrom) ??
          'Damascus',
    );
    _toController = TextEditingController(
      text: coachMiniProgramNormalizeSyrianSearchLocation(widget.initialTo) ??
          'Aleppo',
    );
    _departureDateController = TextEditingController(
      text: widget.initialDepartureDate ?? _defaultDepartureDate(),
    );
    _contactEmailController = TextEditingController();
    _passengers = widget.initialPassengers.clamp(1, 9);
    _syncPassengerDraftControllers();
    _loadBootstrap();
    _loadBookingShelf();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    _departureDateController.dispose();
    _contactEmailController.dispose();
    for (final controller in _passengerIdControllers) {
      controller.dispose();
    }
    for (final controller in _passengerGivenNameControllers) {
      controller.dispose();
    }
    for (final controller in _passengerFamilyNameControllers) {
      controller.dispose();
    }
    for (final controller in _passengerNationalityControllers) {
      controller.dispose();
    }
    for (final controller in _preferredSeatControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String _defaultDepartureDate() {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day).add(
      const Duration(days: 1),
    );
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> _loadBootstrap() async {
    setState(() {
      _bootstrapLoading = true;
      _bootstrapError = null;
    });
    try {
      final bootstrap = await _api.bootstrap();
      setState(() {
        _bootstrap = bootstrap;
      });
    } catch (error) {
      setState(() {
        _bootstrapError = error.toString();
      });
    } finally {
      setState(() {
        _bootstrapLoading = false;
      });
    }
  }

  Future<void> _loadBookingShelf() async {
    setState(() {
      _bookingShelfLoading = true;
      _bookingShelfError = null;
    });
    try {
      final bookingShelf = await _api.listBookings();
      final filteredBookings = bookingShelf.bookings
          .where(
            (entry) =>
                coachMiniProgramSupportsSyriaSearchLocation(
                    entry.journey.from) &&
                coachMiniProgramSupportsSyriaSearchLocation(entry.journey.to),
          )
          .toList(growable: false);
      setState(() {
        _bookingShelf = CoachBookingShelfResponse(
          summary: _deriveBookingShelfSummary(filteredBookings),
          bookings: filteredBookings,
        );
      });
    } catch (error) {
      setState(() {
        _bookingShelfError = error.toString();
      });
    } finally {
      setState(() {
        _bookingShelfLoading = false;
      });
    }
  }

  Future<void> _runSearch() async {
    final l = L10n.of(context);
    final from = _fromController.text.trim();
    final to = _toController.text.trim();
    if (!coachMiniProgramSupportsSyriaSearchLocation(from) ||
        !coachMiniProgramSupportsSyriaSearchLocation(to)) {
      setState(() {
        _searchError = coachMiniProgramSyriaRouteSearchError(
          isArabic: l.isArabic,
        );
        _searchResponse = null;
        _clearSelectedCommerceState();
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
      _previewError = null;
    });
    try {
      final response = await _api.search(
        from: _fromController.text,
        to: _toController.text,
        departureDate: _departureDateController.text,
        passengers: _passengers,
      );
      setState(() {
        _searchResponse = response;
        _clearSelectedCommerceState();
      });
    } catch (error) {
      setState(() {
        _searchError = error.toString();
      });
    } finally {
      setState(() {
        _searching = false;
      });
    }
  }

  void _syncPassengerDraftControllers() {
    while (_passengerIdControllers.length < _passengers) {
      final index = _passengerIdControllers.length + 1;
      _passengerIdControllers.add(TextEditingController(text: 'pax_$index'));
    }
    while (_passengerIdControllers.length > _passengers) {
      _passengerIdControllers.removeLast().dispose();
    }
    while (_passengerGivenNameControllers.length < _passengers) {
      _passengerGivenNameControllers.add(TextEditingController());
    }
    while (_passengerGivenNameControllers.length > _passengers) {
      _passengerGivenNameControllers.removeLast().dispose();
    }
    while (_passengerFamilyNameControllers.length < _passengers) {
      _passengerFamilyNameControllers.add(TextEditingController());
    }
    while (_passengerFamilyNameControllers.length > _passengers) {
      _passengerFamilyNameControllers.removeLast().dispose();
    }
    while (_passengerNationalityControllers.length < _passengers) {
      _passengerNationalityControllers.add(TextEditingController());
    }
    while (_passengerNationalityControllers.length > _passengers) {
      _passengerNationalityControllers.removeLast().dispose();
    }
    while (_passengerCategories.length < _passengers) {
      _passengerCategories.add(CoachPassengerRiderCategory.adult);
    }
    while (_passengerCategories.length > _passengers) {
      _passengerCategories.removeLast();
    }
    while (_preferredSeatControllers.length < _passengers) {
      _preferredSeatControllers.add(TextEditingController());
    }
    while (_preferredSeatControllers.length > _passengers) {
      _preferredSeatControllers.removeLast().dispose();
    }
  }

  void _clearSelectedCommerceState() {
    _selectedJourney = null;
    _selectedOffer = null;
    _previewHold = null;
    _previewBooking = null;
    _previewPassengerManifests = const <CoachPassengerManifest>[];
    _previewTickets = const <CoachTicketCoupon>[];
    _compensation = null;
    _commandNote = null;
    _previewError = null;
  }

  void _handleSearchDraftEdited() {
    setState(() {
      _searchResponse = null;
      _searchError = null;
      _clearSelectedCommerceState();
    });
  }

  void _setPassengers(int value) {
    final normalized = value.clamp(1, 9);
    if (normalized == _passengers) {
      return;
    }
    setState(() {
      _passengers = normalized;
      _searchResponse = null;
      _searchError = null;
      _clearSelectedCommerceState();
      _syncPassengerDraftControllers();
    });
  }

  void _swapRoute() {
    final from = _fromController.text;
    final to = _toController.text;
    setState(() {
      _fromController.text = to;
      _toController.text = from;
      _searchResponse = null;
      _searchError = null;
      _clearSelectedCommerceState();
    });
  }

  bool _matchesRoutePreset(_CoachRoutePreset preset, bool isArabic) {
    final fromLabel = _coachMiniProgramLocalizedCityName(preset.from, isArabic);
    final toLabel = _coachMiniProgramLocalizedCityName(preset.to, isArabic);
    return _coachMiniProgramLocationKey(_fromController.text) ==
            _coachMiniProgramLocationKey(fromLabel) &&
        _coachMiniProgramLocationKey(_toController.text) ==
            _coachMiniProgramLocationKey(toLabel);
  }

  void _applyRoutePreset(_CoachRoutePreset preset, bool isArabic) {
    final fromLabel = _coachMiniProgramLocalizedCityName(preset.from, isArabic);
    final toLabel = _coachMiniProgramLocalizedCityName(preset.to, isArabic);
    if (_matchesRoutePreset(preset, isArabic)) {
      return;
    }
    setState(() {
      _fromController.text = fromLabel;
      _toController.text = toLabel;
      _searchResponse = null;
      _searchError = null;
      _clearSelectedCommerceState();
    });
  }

  void _setDepartureDateValue(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == _departureDateController.text) {
      return;
    }
    setState(() {
      _departureDateController.text = normalized;
      _searchResponse = null;
      _searchError = null;
      _clearSelectedCommerceState();
    });
  }

  String _departureDateOffsetValue(int offsetDays) {
    final now = DateTime.now();
    final date = DateTime(now.year, now.month, now.day).add(
      Duration(days: offsetDays),
    );
    return _coachMiniProgramDateOnlyValue(date);
  }

  bool _departureDateMatchesOffset(int offsetDays) {
    return _departureDateController.text.trim() ==
        _departureDateOffsetValue(offsetDays);
  }

  void _setActiveTab(int index) {
    final tab = _CoachBusMiniTab.values[index];
    if (tab == _activeTab) {
      return;
    }
    setState(() {
      _activeTab = tab;
    });
  }

  List<CoachJourneyOption> _journeyBoardJourneys(
    CoachJourneySearchResponse response,
  ) {
    final journeys = response.journeys
        .where(
          (journey) => !_journeyBoardDirectOnly || journey.transferCount == 0,
        )
        .toList(growable: true);
    journeys.sort((left, right) {
      final primaryComparison = switch (_journeyBoardSortMode) {
        _CoachJourneyBoardSortMode.departure =>
          left.departureAtIso.compareTo(right.departureAtIso),
        _CoachJourneyBoardSortMode.fastest =>
          left.durationMinutes.compareTo(right.durationMinutes),
        _CoachJourneyBoardSortMode.cheapest =>
          left.priceFromMinorUnits.compareTo(right.priceFromMinorUnits),
      };
      if (primaryComparison != 0) {
        return primaryComparison;
      }
      final departureComparison =
          left.departureAtIso.compareTo(right.departureAtIso);
      if (departureComparison != 0) {
        return departureComparison;
      }
      final priceComparison =
          left.priceFromMinorUnits.compareTo(right.priceFromMinorUnits);
      if (priceComparison != 0) {
        return priceComparison;
      }
      return left.journeyId.compareTo(right.journeyId);
    });
    return journeys;
  }

  void _clearSelectedCommerceStateIfHidden(
    List<CoachJourneyOption> visibleJourneys,
  ) {
    final selectedJourney = _selectedJourney;
    if (selectedJourney == null) {
      return;
    }
    final stillVisible = visibleJourneys.any(
      (journey) => journey.journeyId == selectedJourney.journeyId,
    );
    if (!stillVisible) {
      _clearSelectedCommerceState();
    }
  }

  void _setJourneyBoardSortMode(_CoachJourneyBoardSortMode mode) {
    if (mode == _journeyBoardSortMode) {
      return;
    }
    setState(() {
      _journeyBoardSortMode = mode;
    });
  }

  void _setJourneyBoardDirectOnly(bool value) {
    if (value == _journeyBoardDirectOnly) {
      return;
    }
    setState(() {
      _journeyBoardDirectOnly = value;
      final response = _searchResponse;
      if (response != null) {
        _clearSelectedCommerceStateIfHidden(_journeyBoardJourneys(response));
      }
    });
  }

  List<String> _collectPassengerIds() {
    final ids = <String>[];
    final seen = <String>{};
    for (final controller in _passengerIdControllers) {
      final value = controller.text.trim();
      if (value.isEmpty) {
        throw const FormatException('Passenger IDs are required.');
      }
      if (!seen.add(value)) {
        throw const FormatException('Passenger IDs must be unique.');
      }
      ids.add(value);
    }
    return ids;
  }

  List<String> _collectPreferredSeatNumbers() {
    final seats = <String>[];
    final seen = <String>{};
    for (final controller in _preferredSeatControllers) {
      final value = controller.text.trim();
      if (value.isEmpty) {
        continue;
      }
      if (!seen.add(value.toUpperCase())) {
        throw const FormatException('Preferred seats must be unique.');
      }
      seats.add(value);
    }
    return seats;
  }

  List<CoachPassengerManifest> _collectPassengerManifests() {
    final passengerIds = _collectPassengerIds();
    final manifests = <CoachPassengerManifest>[];
    for (var index = 0; index < passengerIds.length; index++) {
      final givenName = _passengerGivenNameControllers[index].text.trim();
      final familyName = _passengerFamilyNameControllers[index].text.trim();
      final nationality =
          _passengerNationalityControllers[index].text.trim().toUpperCase();
      if (givenName.isEmpty || familyName.isEmpty) {
        throw const FormatException('Passenger names are required.');
      }
      if (nationality.isNotEmpty &&
          !RegExp(r'^[A-Z]{2}$').hasMatch(nationality)) {
        throw const FormatException(
          'Nationality codes must use 2 Latin letters.',
        );
      }
      manifests.add(
        CoachPassengerManifest(
          passengerId: passengerIds[index],
          givenName: givenName,
          familyName: familyName,
          riderCategory: _passengerCategories[index],
          nationalityCode: nationality.isEmpty ? null : nationality,
        ),
      );
    }
    return manifests;
  }

  String? _normalizedContactEmail() {
    final value = _contactEmailController.text.trim();
    if (value.isEmpty) {
      return null;
    }
    return value;
  }

  List<String> _selectedDeliveryChannels() {
    final channels = <String>[];
    if (_deliverWalletPass) {
      channels.add('wallet_pass');
    }
    if (_deliverPdf) {
      channels.add('pdf');
    }
    if (_deliverEmail) {
      channels.add('email');
    }
    if (channels.isEmpty) {
      throw const FormatException(
          'Select at least one ticket delivery channel.');
    }
    if (channels.contains('email') && (_normalizedContactEmail() == null)) {
      throw const FormatException('Email delivery requires a contact email.');
    }
    return channels;
  }

  Future<void> _selectJourney(CoachJourneyOption journey) async {
    setState(() {
      _selectedJourney = journey;
      _selectedOffer = journey.bestOffer;
      _previewHold = null;
      _previewBooking = null;
      _previewTickets = const <CoachTicketCoupon>[];
      _compensation = null;
      _commandNote = null;
      _previewError = null;
    });
  }

  Future<void> _refreshOffer() async {
    final selectedJourney = _selectedJourney;
    if (selectedJourney == null) return;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final offer = await _api.getOffer(
        offerId: selectedJourney.bestOffer.offerId,
        passengers: _passengers,
      );
      setState(() {
        _selectedOffer = offer;
      });
    } catch (error) {
      setState(() {
        _previewError = error.toString();
      });
    } finally {
      setState(() {
        _previewLoading = false;
      });
    }
  }

  Future<void> _createHoldForSelectedJourney() async {
    final selectedJourney = _selectedJourney;
    if (selectedJourney == null) return;
    final selectedOffer = _selectedOffer ?? selectedJourney.bestOffer;
    late final List<String> passengerIds;
    late final List<String> preferredSeatNumbers;
    try {
      passengerIds = _collectPassengerIds();
      preferredSeatNumbers = _collectPreferredSeatNumbers();
    } on FormatException catch (error) {
      setState(() {
        _previewError = error.message;
      });
      return;
    }
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final holdDraft = await _api.createHold(
        offerId: selectedOffer.offerId,
        passengers: _passengers,
        passengerIds: passengerIds,
        preferredSeatNumbers: preferredSeatNumbers,
      );
      setState(() {
        _selectedOffer = holdDraft.offer;
        _previewHold = holdDraft.hold;
        _previewBooking = null;
        _previewPassengerManifests = const <CoachPassengerManifest>[];
        _previewTickets = const <CoachTicketCoupon>[];
        _compensation = null;
        _commandNote =
            'Hold ${holdDraft.hold.holdId} • TTL ${holdDraft.holdTtlSeconds}s';
      });
    } catch (error) {
      setState(() {
        _previewError = error.toString();
      });
    } finally {
      setState(() {
        _previewLoading = false;
      });
    }
  }

  Future<void> _createBookingForSelectedJourney() async {
    final selectedJourney = _selectedJourney;
    if (selectedJourney == null) return;
    final selectedOffer = _selectedOffer ?? selectedJourney.bestOffer;
    late final List<String> passengerIds;
    late final List<String> preferredSeatNumbers;
    late final List<CoachPassengerManifest> passengerManifests;
    try {
      passengerIds = _collectPassengerIds();
      preferredSeatNumbers = _collectPreferredSeatNumbers();
      passengerManifests = _collectPassengerManifests();
    } on FormatException catch (error) {
      setState(() {
        _previewError = error.message;
      });
      return;
    }
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final bookingDraft = await _api.createBooking(
        offerId: selectedOffer.offerId,
        holdId: _previewHold?.holdId,
        passengers: _passengers,
        passengerIds: passengerIds,
        preferredSeatNumbers: preferredSeatNumbers,
        passengerManifests: passengerManifests,
        paymentMethod: _paymentMethod,
        contactEmail: _normalizedContactEmail(),
        acceptTerms: true,
      );
      setState(() {
        _selectedOffer = bookingDraft.offer;
        _previewHold = bookingDraft.hold ?? _previewHold;
        _previewBooking = bookingDraft.booking;
        _previewPassengerManifests = bookingDraft.passengerManifests.isEmpty
            ? passengerManifests
            : bookingDraft.passengerManifests;
        _previewTickets = const <CoachTicketCoupon>[];
        _compensation = bookingDraft.compensation;
        _commandNote =
            'Booking ${bookingDraft.booking.bookingId} • ${_coachMiniProgramStatusWord(bookingDraft.payment.status, false)}';
      });
    } catch (error) {
      setState(() {
        _previewError = error.toString();
      });
    } finally {
      setState(() {
        _previewLoading = false;
      });
    }
  }

  Future<void> _issueTicketsForSelectedJourney() async {
    final selectedJourney = _selectedJourney;
    final previewBooking = _previewBooking;
    if (selectedJourney == null || previewBooking == null) {
      setState(() {
        _previewError = 'Create booking before issuing tickets.';
      });
      return;
    }
    final selectedOffer = _selectedOffer ?? selectedJourney.bestOffer;
    late final List<String> passengerIds;
    late final List<CoachPassengerManifest> passengerManifests;
    late final List<String> deliveryChannels;
    try {
      passengerIds = _collectPassengerIds();
      passengerManifests = _collectPassengerManifests();
      deliveryChannels = _selectedDeliveryChannels();
    } on FormatException catch (error) {
      setState(() {
        _previewError = error.message;
      });
      return;
    }
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final ticketing = await _api.issueTickets(
        bookingId: previewBooking.bookingId,
        offerId: selectedOffer.offerId,
        holdId: _previewHold?.holdId,
        passengerIds: passengerIds,
        passengerManifests: passengerManifests,
        deliveryChannels: deliveryChannels,
      );
      unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentSent));
      setState(() {
        _previewBooking = ticketing.booking;
        _previewPassengerManifests = ticketing.passengerManifests.isEmpty
            ? passengerManifests
            : ticketing.passengerManifests;
        _previewTickets = ticketing.tickets;
        _compensation = ticketing.compensation;
        _commandNote =
            'Ticketing ${ticketing.booking.bookingId} • ${ticketing.deliveryChannels.join(', ')}';
      });
    } catch (error) {
      setState(() {
        _previewError = error.toString();
      });
    } finally {
      setState(() {
        _previewLoading = false;
      });
    }
  }

  String _moneyLabel(int minorUnits, String currency) {
    return '${fmtCents(minorUnits)} $currency';
  }

  String _localizedRouteLabel(String from, String to, bool isArabic) {
    final localizedFrom =
        _coachMiniProgramLocalizedCityName(from.trim(), isArabic);
    final localizedTo = _coachMiniProgramLocalizedCityName(to.trim(), isArabic);
    return '$localizedFrom → $localizedTo';
  }

  List<CoachTicketCoupon> _allKnownTickets() {
    final ticketEntries = _savedTicketEntries();
    return <CoachTicketCoupon>[
      ..._previewTickets,
      for (final entry in ticketEntries) ...entry.tickets,
    ];
  }

  Widget _buildShellBoard(BuildContext context, bool isArabic) {
    final routeLabel = _localizedRouteLabel(
      _fromController.text,
      _toController.text,
      isArabic,
    );
    final nextEntry = _nextUpcomingBookingEntry();
    final bookingSummary = _bookingShelf?.summary;
    final ticketEntries = _savedTicketEntries();
    final allTickets = _allKnownTickets();
    final readyTicketCount = allTickets
        .where((ticket) => ticket.status == CoachTicketStatus.active)
        .length;
    final walletPassCount = allTickets
        .where((ticket) => ticket.artifactByKind('wallet_pass') != null)
        .length;
    final pdfCount = allTickets
        .where((ticket) => ticket.artifactByKind('pdf') != null)
        .length;

    final tabBoardSubtitle = switch (_activeTab) {
      _CoachBusMiniTab.plan => isArabic
          ? 'ابحث أولاً ثم قارن الرحلات وأكمل الحجز أو الإصدار.'
          : 'Search first, compare departures, then move into hold, booking, and issuance.',
      _CoachBusMiniTab.trips => isArabic
          ? 'احتفظ بالرحلات القادمة جاهزة ليوم السفر والتنقّل المباشر.'
          : 'Keep upcoming bookings ready for travel day and jump into live running.',
      _CoachBusMiniTab.tickets => isArabic
          ? 'أبقِ التذاكر الصالحة والوسائط الجاهزة للعرض في مكان واحد.'
          : 'Keep valid tickets, wallet passes, and PDFs ready to show in one place.',
    };

    late final String primaryLabel;
    late final String primaryTitle;
    late final String primarySubtitle;
    late final List<Widget> metrics;

    switch (_activeTab) {
      case _CoachBusMiniTab.plan:
        final selectedJourney = _selectedJourney;
        primaryLabel = isArabic ? 'المسار الحالي' : 'Current route';
        primaryTitle = routeLabel;
        primarySubtitle = selectedJourney == null
            ? '${_coachMiniProgramDepartureSummary(_departureDateController.text, isArabic)} • ${_coachMiniProgramTravelerCountLabel(_passengers, isArabic)}'
            : '${_coachMiniProgramCompactDateTimeRange(selectedJourney.departureAtIso, selectedJourney.arrivalAtIso)} • ${_moneyLabel(selectedJourney.priceFromMinorUnits, selectedJourney.currency)}';
        metrics = <Widget>[
          _CoachMetricChip(
            icon: Icons.calendar_today_outlined,
            label: isArabic ? 'المغادرة' : 'Departure',
            value: _coachMiniProgramDepartureSummary(
              _departureDateController.text,
              isArabic,
            ),
          ),
          _CoachMetricChip(
            icon: Icons.people_outline,
            label: isArabic ? 'المسافرون' : 'Travelers',
            value: '$_passengers',
          ),
          if (selectedJourney != null)
            _CoachMetricChip(
              icon: Icons.route_outlined,
              label: isArabic ? 'الرحلة المختارة' : 'Selected',
              value: _coachMiniProgramTransferLabel(
                selectedJourney.transferCount,
                isArabic,
              ),
            ),
        ];
      case _CoachBusMiniTab.trips:
        primaryLabel = isArabic ? 'المغادرة التالية' : 'Next departure';
        primaryTitle = nextEntry == null
            ? (isArabic ? 'لا توجد رحلات محفوظة بعد' : 'No saved trips yet')
            : _localizedRouteLabel(
                nextEntry.journey.from,
                nextEntry.journey.to,
                isArabic,
              );
        primarySubtitle = nextEntry == null
            ? (isArabic
                ? 'ابدأ من التخطيط لحفظ رحلة وإظهارها في يوم السفر.'
                : 'Start from Plan to save a booking and bring it into the travel-day view.')
            : '${_coachMiniProgramCompactDateTimeRange(nextEntry.journey.departureAtIso, nextEntry.journey.arrivalAtIso)} • ${nextEntry.journey.statusLabel}';
        metrics = <Widget>[
          _CoachMetricChip(
            icon: Icons.upcoming_outlined,
            label: isArabic ? 'القادمة' : 'Upcoming',
            value: '${bookingSummary?.upcomingCount ?? 0}',
          ),
          _CoachMetricChip(
            icon: Icons.confirmation_num_outlined,
            label: isArabic ? 'المُصدّرة' : 'Ticketed',
            value: '${bookingSummary?.ticketedCount ?? 0}',
          ),
          _CoachMetricChip(
            icon: Icons.warning_amber_outlined,
            label: isArabic ? 'تحتاج إجراء' : 'Needs action',
            value: '${bookingSummary?.needsActionCount ?? 0}',
          ),
        ];
      case _CoachBusMiniTab.tickets:
        final readyEntry = ticketEntries.isEmpty ? null : ticketEntries.first;
        primaryLabel = _previewTickets.isNotEmpty
            ? (isArabic ? 'آخر تذكرة مصدّرة' : 'Latest issued ticket')
            : (isArabic ? 'جاهزة للعرض' : 'Ready to show');
        primaryTitle = _previewTickets.isNotEmpty
            ? routeLabel
            : readyEntry == null
                ? (isArabic ? 'لا توجد تذاكر بعد' : 'No tickets yet')
                : _localizedRouteLabel(
                    readyEntry.journey.from,
                    readyEntry.journey.to,
                    isArabic,
                  );
        primarySubtitle = _previewTickets.isNotEmpty
            ? (_selectedJourney == null
                ? (isArabic
                    ? 'من جلسة الإصدار الحالية.'
                    : 'From the current issuance session.')
                : '${_coachMiniProgramCompactDateTimeRange(_selectedJourney!.departureAtIso, _selectedJourney!.arrivalAtIso)} • ${_previewTickets.length} ${isArabic ? 'تذكرة' : 'tickets'}')
            : readyEntry == null
                ? (isArabic
                    ? 'أكمل الحجز أو الإصدار من تبويب التخطيط لإظهار التذاكر هنا.'
                    : 'Complete booking or ticket issuance from Plan to surface ready passes here.')
                : '${_coachMiniProgramCompactDateTimeRange(readyEntry.journey.departureAtIso, readyEntry.journey.arrivalAtIso)} • ${readyEntry.tickets.length} ${isArabic ? 'تذكرة' : 'tickets'}';
        metrics = <Widget>[
          _CoachMetricChip(
            icon: Icons.confirmation_num_outlined,
            label: isArabic ? 'التذاكر' : 'Tickets',
            value: '${allTickets.length}',
          ),
          _CoachMetricChip(
            icon: Icons.check_circle_outline,
            label: isArabic ? 'جاهزة' : 'Ready',
            value: '$readyTicketCount',
          ),
          _CoachMetricChip(
            icon: Icons.wallet_outlined,
            label: isArabic ? 'المحفظة / PDF' : 'Wallet / PDF',
            value: '$walletPassCount / $pdfCount',
          ),
        ];
    }

    return _CoachLiquidGlassPanel(
      tint: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Tokens.colorBus.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.directions_bus_outlined,
                  color: Tokens.colorBus,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'لوحة سفر الحافلات' : 'Coach travel board',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tabBoardSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: WeChatPalette.searchFill,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: .8),
                  ),
                ),
                child: Text(
                  _coachMiniProgramTabLabel(_activeTab, isArabic),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? WeChatPalette.searchFillDark
                  : WeChatPalette.searchFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: .8),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.route_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primaryLabel,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        primaryTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        primarySubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 360;
              final buttonWidth = narrow
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: buttonWidth,
                    child: _CoachMiniQuickActionButton(
                      selected: _activeTab == _CoachBusMiniTab.plan,
                      icon: Icons.search_outlined,
                      label: isArabic ? 'ابحث' : 'Find trip',
                      onPressed: () =>
                          _setActiveTab(_CoachBusMiniTab.plan.index),
                    ),
                  ),
                  SizedBox(
                    width: buttonWidth,
                    child: _CoachMiniQuickActionButton(
                      selected: _activeTab == _CoachBusMiniTab.trips,
                      icon: Icons.luggage_outlined,
                      label: isArabic ? 'رحلاتي' : 'My trips',
                      onPressed: () =>
                          _setActiveTab(_CoachBusMiniTab.trips.index),
                    ),
                  ),
                  SizedBox(
                    width: buttonWidth,
                    child: _CoachMiniQuickActionButton(
                      selected: _activeTab == _CoachBusMiniTab.tickets,
                      icon: Icons.confirmation_num_outlined,
                      label: isArabic ? 'تذاكري' : 'My tickets',
                      onPressed: () =>
                          _setActiveTab(_CoachBusMiniTab.tickets.index),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var index = 0; index < metrics.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  metrics[index],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final isArabic = l.isArabic;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pageBackground =
        isDark ? const Color(0xFF0F172A) : WeChatPalette.background;
    final chipTheme = theme.chipTheme.copyWith(
      backgroundColor:
          isDark ? WeChatPalette.searchFillDark : WeChatPalette.searchFill,
      selectedColor: Tokens.colorBus.withValues(alpha: .14),
      side: BorderSide(color: theme.dividerColor.withValues(alpha: .75)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: theme.textTheme.bodyMedium,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
    return Theme(
      data: theme.copyWith(chipTheme: chipTheme),
      child: Scaffold(
        backgroundColor: pageBackground,
        appBar: AppBar(
          title: Text(isArabic ? 'الحافلات بين المدن' : 'Coach bus'),
          surfaceTintColor: Colors.transparent,
        ),
        body: ColoredBox(
          color: pageBackground,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: _buildShellBoard(context, isArabic),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: KeyedSubtree(
                      key: ValueKey<_CoachBusMiniTab>(_activeTab),
                      child: switch (_activeTab) {
                        _CoachBusMiniTab.plan =>
                          _buildPlanTab(context, isArabic),
                        _CoachBusMiniTab.trips =>
                          _buildTripsTab(context, isArabic),
                        _CoachBusMiniTab.tickets =>
                          _buildTicketsTab(context, isArabic),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: .8),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? .22 : .06),
                  blurRadius: 14,
                  spreadRadius: -8,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: NavigationBar(
                height: 66,
                indicatorColor: Tokens.colorBus.withValues(alpha: .16),
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                selectedIndex: _activeTab.index,
                onDestinationSelected: _setActiveTab,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.search_outlined),
                    selectedIcon: const Icon(Icons.search),
                    label: isArabic ? 'خطّط' : 'Plan',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.luggage_outlined),
                    selectedIcon: const Icon(Icons.luggage),
                    label: isArabic ? 'رحلاتي' : 'Trips',
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.confirmation_num_outlined),
                    selectedIcon: const Icon(Icons.confirmation_num),
                    label: isArabic ? 'التذاكر' : 'Tickets',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanTab(BuildContext context, bool isArabic) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        28 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        _buildHeader(context, isArabic),
        const SizedBox(height: 12),
        // Phase indicator: tells the user which of the three booking
        // steps (Search → Choose → Book) is active. The Plan tab is a
        // single scroll, which is friendly on small phones but easy to
        // lose orientation in once results are loaded. The indicator
        // makes the next action visually obvious and dampens the
        // "where am I in the flow?" question.
        _buildPlanStepIndicator(context, isArabic),
        const SizedBox(height: 16),
        _buildSearchPanel(context, isArabic),
        const SizedBox(height: 16),
        _buildResultsPanel(context, isArabic),
        if (_selectedJourney != null) ...[
          const SizedBox(height: 16),
          _buildSelectedJourneyPanel(context, isArabic),
        ],
      ],
    );
  }

  /// 0 = Search (no results yet), 1 = Choose (results shown), 2 = Book
  /// (a journey has been selected). The selected journey panel is the
  /// terminal step in the Plan flow; any tab beyond that lives on the
  /// Trips tab.
  int _planActiveStep() {
    if (_selectedJourney != null) {
      return 2;
    }
    if (_searchResponse != null) {
      return 1;
    }
    return 0;
  }

  Widget _buildPlanStepIndicator(BuildContext context, bool isArabic) {
    final active = _planActiveStep();
    final steps = <ShamellPhaseStep>[
      ShamellPhaseStep(
        icon: Icons.search_rounded,
        label: isArabic ? 'البحث' : 'Search',
        accent: Tokens.colorBus,
      ),
      ShamellPhaseStep(
        icon: Icons.list_alt_rounded,
        label: isArabic ? 'الاختيار' : 'Choose',
        accent: Tokens.colorBus,
      ),
      ShamellPhaseStep(
        icon: Icons.confirmation_num_outlined,
        label: isArabic ? 'الحجز' : 'Book',
        accent: Tokens.colorBus,
      ),
    ];
    return ShamellPhaseStrip(
      steps: steps,
      activeIndex: active,
      // Inline-in-ListView variant gets the soft surface card so the
      // strip reads as a distinct band; AppBar.bottom callers leave it
      // off because the AppBar itself already provides the chrome.
      showBackgroundCard: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      semanticsLabel: isArabic
          ? 'خطوة ${active + 1} من ${steps.length}: ${steps[active].label}'
          : 'Step ${active + 1} of ${steps.length}: ${steps[active].label}',
    );
  }

  Widget _buildTripsTab(BuildContext context, bool isArabic) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        28 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        _buildTripsHeader(context, isArabic),
        const SizedBox(height: 16),
        CoachPassengerNotificationPanel(
          impactedPassengers: _bookingShelf?.summary.upcomingCount ?? 0,
          contextLabel: isArabic ? 'رحلاتي' : 'My coach trips',
        ),
        const SizedBox(height: 16),
        _buildPassengerTimelinePanel(context, isArabic),
        const SizedBox(height: 16),
        _buildBookingShelfPanel(context, isArabic),
        const SizedBox(height: 16),
        _buildPassengerRecoveryPanel(context, isArabic),
        const SizedBox(height: 16),
        _buildPassengerNotificationsInbox(context, isArabic),
      ],
    );
  }

  Widget _buildTicketsTab(BuildContext context, bool isArabic) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        28 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        _buildTicketsHeader(context, isArabic),
        const SizedBox(height: 16),
        _buildPassengerTimelinePanel(context, isArabic),
        const SizedBox(height: 16),
        _buildTicketsPanel(context, isArabic),
        const SizedBox(height: 16),
        _buildPassengerRecoveryPanel(context, isArabic),
        const SizedBox(height: 16),
        _buildPassengerNotificationsInbox(context, isArabic),
      ],
    );
  }

  CoachTimelinePanel _buildPassengerTimelinePanel(
    BuildContext context,
    bool isArabic,
  ) {
    final entry = _nextUpcomingBookingEntry() ??
        (_bookingShelf?.bookings.isEmpty ?? true
            ? null
            : _bookingShelf!.bookings.first);
    final booking = _previewBooking ?? entry?.booking;
    final journey = entry?.journey;
    final tickets = _previewTickets.isNotEmpty
        ? _previewTickets
        : (entry?.tickets ?? const <CoachTicketCoupon>[]);
    final firstTicket = tickets.isEmpty ? null : tickets.first;
    return CoachTimelinePanel(
      title: isArabic ? 'خط رحلة الحافلة' : 'Coach trip timeline',
      events: <CoachTimelineEvent>[
        CoachTimelineEvent(
          icon: Icons.search_outlined,
          title: isArabic ? 'تم اختيار الرحلة' : 'Trip selected',
          detail: _selectedJourney == null && journey == null
              ? (isArabic ? 'اختر رحلة أولاً.' : 'Choose a trip first.')
              : journey == null
                  ? _localizedRouteLabel(
                      _fromController.text,
                      _toController.text,
                      isArabic,
                    )
                  : _localizedRouteLabel(journey.from, journey.to, isArabic),
          timeLabel: journey == null
              ? _departureDateController.text
              : _coachMiniProgramCompactTime(journey.departureAtIso),
          done: _selectedJourney != null || journey != null,
        ),
        CoachTimelineEvent(
          icon: Icons.payments_outlined,
          title: isArabic ? 'الحجز والدفع' : 'Booking and payment',
          detail: booking == null
              ? (isArabic ? 'لم يبدأ الحجز بعد.' : 'Booking has not started.')
              : '${booking.bookingId} • ${_coachMiniProgramBookingStateLabel(booking.state, isArabic)}',
          timeLabel: booking == null
              ? '-'
              : _coachMiniProgramCompactTime(booking.createdAtIso),
          done: booking != null,
        ),
        CoachTimelineEvent(
          icon: Icons.confirmation_num_outlined,
          title: isArabic ? 'التذاكر' : 'Tickets',
          detail: tickets.isEmpty
              ? (isArabic ? 'لا توجد تذاكر بعد.' : 'No tickets issued yet.')
              : '${tickets.length} ${isArabic ? 'تذكرة' : 'ticket(s)'} ready.',
          timeLabel: firstTicket == null
              ? '-'
              : _coachMiniProgramCompactTime(firstTicket.issuedAtIso),
          done: tickets.isNotEmpty,
        ),
        CoachTimelineEvent(
          icon: Icons.qr_code_scanner,
          title: isArabic ? 'الصعود' : 'Boarding',
          detail: firstTicket?.boardingState == null
              ? (isArabic
                  ? 'تظهر حالة الصعود بعد المسح.'
                  : 'Boarding state appears after scan.')
              : _coachMiniProgramBoardingStateLabel(
                  firstTicket!.boardingState!,
                  isArabic,
                ),
          timeLabel: journey == null
              ? '-'
              : _coachMiniProgramCompactTime(journey.departureAtIso),
          done: firstTicket?.boardingState != null,
        ),
      ],
    );
  }

  CoachRecoveryFlowPanel _buildPassengerRecoveryPanel(
    BuildContext context,
    bool isArabic,
  ) {
    final entry = _nextUpcomingBookingEntry() ??
        (_bookingShelf?.bookings.isEmpty ?? true
            ? null
            : _bookingShelf!.bookings.first);
    final journey = entry?.journey;
    final routeLabel = journey == null
        ? (isArabic ? 'رحلات الحافلة المحفوظة' : 'Saved coach trips')
        : _localizedRouteLabel(journey.from, journey.to, isArabic);
    return CoachRecoveryFlowPanel(
      title: isArabic ? 'استرداد الرحلة' : 'Trip recovery',
      routeLabel: routeLabel,
      impactedPassengers: entry?.booking.passengerCount ??
          _bookingShelf?.summary.needsActionCount ??
          0,
      rebookingOptions: <String>[
        if (journey != null) '${journey.from} -> ${journey.to} next departure',
        'Same operator standby seat',
        'Any partner coach',
      ],
      compensationLabel:
          isArabic ? 'رصيد أو قسيمة تأخير' : 'Delay voucher or wallet refund',
    );
  }

  CoachNotificationsInboxPanel _buildPassengerNotificationsInbox(
    BuildContext context,
    bool isArabic,
  ) {
    final entry = _nextUpcomingBookingEntry() ??
        (_bookingShelf?.bookings.isEmpty ?? true
            ? null
            : _bookingShelf!.bookings.first);
    final journey = entry?.journey;
    final booking = entry?.booking ?? _previewBooking;
    final firstTicket = entry?.tickets.isEmpty ?? true
        ? (_previewTickets.isEmpty ? null : _previewTickets.first)
        : entry!.tickets.first;
    return CoachNotificationsInboxPanel(
      items: <CoachNotificationInboxItem>[
        CoachNotificationInboxItem(
          title: isArabic ? 'تحديث الرحلة' : 'Trip update',
          audience: journey == null
              ? (isArabic ? 'رحلاتي' : 'My trips')
              : _localizedRouteLabel(journey.from, journey.to, isArabic),
          status: journey == null ? 'Pending' : 'Delivered',
          timeLabel: journey == null
              ? '-'
              : _coachMiniProgramCompactTime(journey.departureAtIso),
          icon: Icons.departure_board_outlined,
        ),
        CoachNotificationInboxItem(
          title: isArabic ? 'تأكيد الحجز' : 'Booking receipt',
          audience:
              booking?.bookingId ?? (isArabic ? 'لا يوجد حجز' : 'No booking'),
          status: booking == null ? 'Pending' : 'Opened',
          timeLabel: booking == null
              ? '-'
              : _coachMiniProgramCompactTime(booking.createdAtIso),
          icon: Icons.receipt_long_outlined,
        ),
        CoachNotificationInboxItem(
          title: isArabic ? 'إصدار التذكرة' : 'Ticket delivery',
          audience: firstTicket?.ticketId ??
              (isArabic ? 'لا توجد تذكرة' : 'No ticket'),
          status: firstTicket == null ? 'Pending' : 'Delivered',
          timeLabel: firstTicket == null
              ? '-'
              : _coachMiniProgramCompactTime(firstTicket.issuedAtIso),
          icon: Icons.confirmation_num_outlined,
        ),
      ],
    );
  }

  Widget _buildTripsHeader(BuildContext context, bool isArabic) {
    final bookingShelf = _bookingShelf;
    final nextEntry = _nextUpcomingBookingEntry();
    return _CoachLiquidGlassPanel(
      tint: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'رحلات اليوم والرحلات المحفوظة' : 'Trips and travel day',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'اعرض الرحلات القادمة، افتح الرحلة المباشرة، وادخل إلى تغيير الرحلة أو الاسترداد.'
                : 'See upcoming coach trips, open live running information, and jump into change or refund flows.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CoachMetricChip(
                icon: Icons.upcoming_outlined,
                label: isArabic ? 'القادمة' : 'Upcoming',
                value: '${bookingShelf?.summary.upcomingCount ?? 0}',
              ),
              _CoachMetricChip(
                icon: Icons.confirmation_num_outlined,
                label: isArabic ? 'المُصدّرة' : 'Ticketed',
                value: '${bookingShelf?.summary.ticketedCount ?? 0}',
              ),
              _CoachMetricChip(
                icon: Icons.warning_amber_outlined,
                label: isArabic ? 'تحتاج إجراء' : 'Needs action',
                value: '${bookingShelf?.summary.needsActionCount ?? 0}',
              ),
            ],
          ),
          if (nextEntry != null) ...[
            const SizedBox(height: 14),
            _CoachSectionHeader(
              title: isArabic ? 'المغادرة التالية' : 'Next departure',
              subtitle: isArabic
                  ? 'أقرب رحلة محفوظة مع ملخص سريع ليوم السفر.'
                  : 'Closest saved trip with a compact travel-day summary.',
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 84,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _coachMiniProgramCompactTime(
                            nextEntry.journey.departureAtIso,
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _coachMiniProgramCompactTime(
                            nextEntry.journey.arrivalAtIso,
                          ),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _coachMiniProgramCompactDate(
                            nextEntry.journey.departureAtIso,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${nextEntry.journey.from} → ${nextEntry.journey.to}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${nextEntry.journey.operatorName} • ${nextEntry.booking.bookingId}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text(nextEntry.journey.statusLabel)),
                            Chip(
                              label: Text(
                                _coachMiniProgramBookingStateLabel(
                                  nextEntry.booking.state,
                                  isArabic,
                                ),
                              ),
                            ),
                            Chip(
                              label: Text(
                                '${isArabic ? 'التذاكر' : 'Tickets'} ${nextEntry.tickets.length}',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketsHeader(BuildContext context, bool isArabic) {
    final ticketEntries = _savedTicketEntries();
    final savedTicketCount = ticketEntries.fold<int>(
        0, (count, entry) => count + entry.tickets.length);
    final totalTicketCount = savedTicketCount + _previewTickets.length;
    final allTickets = <CoachTicketCoupon>[
      ..._previewTickets,
      for (final entry in ticketEntries) ...entry.tickets,
    ];
    final activeTicketCount = allTickets
        .where((ticket) => ticket.status == CoachTicketStatus.active)
        .length;
    final walletPassCount = allTickets
        .where((ticket) => ticket.artifactByKind('wallet_pass') != null)
        .length;
    final pdfCount = allTickets
        .where((ticket) => ticket.artifactByKind('pdf') != null)
        .length;
    final readyEntry = ticketEntries.isEmpty ? null : ticketEntries.first;
    final highlightTitle = _previewTickets.isNotEmpty
        ? (isArabic ? 'آخر تذكرة مصدّرة' : 'Latest issued ticket')
        : (isArabic ? 'جاهزة للعرض' : 'Ready to show');
    final highlightSubtitle = _previewTickets.isNotEmpty
        ? (_selectedJourney == null
            ? (isArabic
                ? 'من جلسة الإصدار الحالية.'
                : 'From the current issuance session.')
            : '${_fromController.text.trim()} → ${_toController.text.trim()} • ${_coachMiniProgramJourneyWindow(_selectedJourney!.departureAtIso, _selectedJourney!.arrivalAtIso)}')
        : (readyEntry == null
            ? null
            : '${readyEntry.journey.from} → ${readyEntry.journey.to} • ${_coachMiniProgramCompactDateTimeRange(readyEntry.journey.departureAtIso, readyEntry.journey.arrivalAtIso)}');
    return _CoachLiquidGlassPanel(
      tint: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'التذاكر والوسائط' : 'Tickets and delivery',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'اعرض آخر التذاكر المصدّرة والملفات الجاهزة للمحفظة أو PDF.'
                : 'Review the latest issued tickets, boarding artifacts, and delivery channels in one place.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CoachMetricChip(
                icon: Icons.confirmation_num_outlined,
                label: isArabic ? 'التذاكر' : 'Tickets',
                value: '$totalTicketCount',
              ),
              _CoachMetricChip(
                icon: Icons.check_circle_outline,
                label: isArabic ? 'جاهزة' : 'Ready',
                value: '$activeTicketCount',
              ),
              _CoachMetricChip(
                icon: Icons.wallet_outlined,
                label: isArabic ? 'المحفظة / PDF' : 'Wallet / PDF',
                value: '$walletPassCount / $pdfCount',
              ),
            ],
          ),
          if (highlightSubtitle != null) ...[
            const SizedBox(height: 14),
            _CoachSectionHeader(
              title: highlightTitle,
              subtitle: isArabic
                  ? 'أقرب تذكرة صالحة أو آخر إصدار جاهز للعرض.'
                  : 'Closest valid ticket or the latest issued pass ready for display.',
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    highlightTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    highlightSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          _previewTickets.isNotEmpty
                              ? '${isArabic ? 'الجلسة' : 'Session'} ${_previewTickets.length}'
                              : '${isArabic ? 'التذاكر' : 'Tickets'} ${readyEntry!.tickets.length}',
                        ),
                      ),
                      if (_previewTickets.isEmpty && readyEntry != null)
                        Chip(label: Text(readyEntry.journey.statusLabel)),
                      if (walletPassCount > 0)
                        Chip(
                          label: Text(
                            '${isArabic ? 'محفظة' : 'Wallet'} $walletPassCount',
                          ),
                        ),
                      if (pdfCount > 0) Chip(label: Text('PDF $pdfCount')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: _previewTickets.isNotEmpty
                        ? _coachMiniProgramHandleTap(() {
                            setState(() {
                              _activeTab = _CoachBusMiniTab.plan;
                            });
                          })
                        : readyEntry == null
                            ? null
                            : _coachMiniProgramHandleTap(
                                () => _openBookingShelfDetails(
                                  readyEntry,
                                  isArabic,
                                ),
                              ),
                    icon: Icon(
                      _previewTickets.isNotEmpty
                          ? Icons.receipt_long_outlined
                          : Icons.confirmation_num_outlined,
                    ),
                    label: Text(
                      _previewTickets.isNotEmpty
                          ? (isArabic
                              ? 'افتح مسودة الإصدار'
                              : 'Open issuance draft')
                          : (isArabic ? 'اعرض التذكرة' : 'Show ticket'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketsPanel(BuildContext context, bool isArabic) {
    final bookingShelf = _bookingShelf;
    final ticketEntries = _savedTicketEntries();
    if (_bookingShelfLoading &&
        bookingShelf == null &&
        _previewTickets.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: LinearProgressIndicator(),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_previewTickets.isNotEmpty) ...[
          _CoachSectionHeader(
            title: isArabic ? 'آخر إصدار' : 'Latest issuance',
            subtitle: isArabic
                ? 'التذكرة التي تم إصدارها في هذه الجلسة.'
                : 'The ticket pass issued in the current session.',
          ),
          const SizedBox(height: 8),
          _CoachTicketSummaryCard(
            title: isArabic ? 'آخر إصدار' : 'Latest issuance',
            subtitle: _selectedJourney == null
                ? (isArabic ? 'من الجلسة الحالية' : 'From current session')
                : '${_fromController.text.trim()} → ${_toController.text.trim()} • ${_coachMiniProgramJourneyWindow(_selectedJourney!.departureAtIso, _selectedJourney!.arrivalAtIso)}',
            tickets: _previewTickets,
            isArabic: isArabic,
            passengerDisplayNames: {
              for (final passenger in _previewPassengerManifests)
                passenger.passengerId: passenger.displayName,
            },
            actionLabel:
                isArabic ? 'افتح المسودة التجارية' : 'Open booking draft',
            onPressed: () {
              setState(() {
                _activeTab = _CoachBusMiniTab.plan;
              });
            },
          ),
          const SizedBox(height: 12),
        ],
        if (_bookingShelfError != null) ...[
          StatusBanner.warning(_bookingShelfError!),
          const SizedBox(height: 12),
        ],
        if (ticketEntries.isEmpty && _previewTickets.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                isArabic
                    ? 'لا توجد تذاكر محفوظة أو مصدّرة بعد.'
                    : 'No saved or issued tickets yet.',
              ),
            ),
          )
        else ...[
          if (ticketEntries.isNotEmpty) ...[
            _CoachSectionHeader(
              title: isArabic ? 'التذاكر المحفوظة' : 'Saved tickets',
              subtitle: isArabic
                  ? 'جميع التذاكر الجاهزة للعرض أو المراجعة لاحقاً.'
                  : 'All ticket passes ready to show or review later.',
            ),
            const SizedBox(height: 8),
          ],
          for (final entry in ticketEntries) ...[
            _CoachTicketSummaryCard(
              title: '${entry.journey.from} → ${entry.journey.to}',
              subtitle:
                  '${entry.journey.operatorName} • ${_coachMiniProgramCompactDate(entry.journey.departureAtIso)} • ${_coachMiniProgramJourneyWindow(entry.journey.departureAtIso, entry.journey.arrivalAtIso)}',
              tickets: entry.tickets,
              isArabic: isArabic,
              passengerDisplayNames: {
                for (final passenger in entry.passengerManifests)
                  passenger.passengerId: passenger.displayName,
              },
              actionLabel: entry.tickets.isEmpty
                  ? (isArabic ? 'راجع الحجز' : 'Review booking')
                  : (isArabic ? 'افتح التذكرة' : 'Open ticket'),
              onPressed: () => _openBookingShelfDetails(entry, isArabic),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ],
    );
  }

  Widget _buildBookingShelfPanel(BuildContext context, bool isArabic) {
    if (_bookingShelfLoading && _bookingShelf == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My coach trips'),
              SizedBox(height: 12),
              LinearProgressIndicator(),
            ],
          ),
        ),
      );
    }
    if (_bookingShelf == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'رحلاتي بالحافلة' : 'My coach trips',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              if (_bookingShelfError != null)
                StatusBanner.error(_bookingShelfError!)
              else
                Text(
                  isArabic
                      ? 'لا توجد حجوزات محفوظة حتى الآن.'
                      : 'No saved coach bookings yet.',
                ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _bookingShelfLoading
                    ? null
                    : _coachMiniProgramHandleTap(_loadBookingShelf),
                icon: const Icon(Icons.refresh),
                label: Text(isArabic ? 'تحديث الرحلات' : 'Refresh trips'),
              ),
            ],
          ),
        ),
      );
    }
    final bookingShelf = _bookingShelf!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isArabic ? 'رحلاتي بالحافلة' : 'My coach trips',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              onPressed: _bookingShelfLoading
                  ? null
                  : _coachMiniProgramHandleTap(_loadBookingShelf),
              icon: const Icon(Icons.refresh),
              tooltip: isArabic ? 'تحديث الرحلات' : 'Refresh trips',
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          isArabic
              ? 'حجوزات قابلة للوصول السريع تماماً مثل رفّ الرحلات في تطبيقات النقل.'
              : 'A compact shelf for upcoming trips, travel-day status, and ticket actions.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (_bookingShelfLoading) ...[
          const SizedBox(height: 10),
          const LinearProgressIndicator(),
        ],
        if (_bookingShelfError != null) ...[
          const SizedBox(height: 10),
          StatusBanner.warning(_bookingShelfError!),
        ],
        const SizedBox(height: 10),
        if (bookingShelf.bookings.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                isArabic
                    ? 'لا توجد حجوزات محفوظة بعد.'
                    : 'No saved coach bookings yet.',
              ),
            ),
          )
        else
          for (final entry in bookingShelf.bookings) ...[
            _CoachBookingShelfCard(
              entry: entry,
              moneyLabel: _moneyLabel,
              isArabic: isArabic,
              onOpenDetails: () => _openBookingShelfDetails(entry, isArabic),
              onOpenLiveJourney: () => _openJourneyLiveSheet(entry, isArabic),
              onOpenChange: entry.offer.changeable &&
                      entry.booking.state == CoachBookingLifecycleState.ticketed
                  ? () => _openChangeSheet(entry, isArabic)
                  : null,
              onOpenRefund: entry.offer.refundable &&
                      entry.booking.state == CoachBookingLifecycleState.ticketed
                  ? () => _openRefundSheet(entry, isArabic)
                  : null,
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  CoachBookingShelfEntry? _nextUpcomingBookingEntry() {
    final bookings = _bookingShelf?.bookings;
    if (bookings == null || bookings.isEmpty) {
      return null;
    }
    CoachBookingShelfEntry? nextEntry;
    for (final entry in bookings) {
      if (nextEntry == null ||
          entry.journey.departureAtIso
                  .compareTo(nextEntry.journey.departureAtIso) <
              0) {
        nextEntry = entry;
      }
    }
    return nextEntry;
  }

  List<CoachBookingShelfEntry> _savedTicketEntries() {
    final entries =
        (_bookingShelf?.bookings ?? const <CoachBookingShelfEntry>[])
            .where((entry) => entry.tickets.isNotEmpty)
            .toList(growable: false);
    final sorted = entries.toList(growable: true)
      ..sort(
        (left, right) =>
            left.journey.departureAtIso.compareTo(right.journey.departureAtIso),
      );
    return sorted;
  }

  CoachBookingShelfSummary _deriveBookingShelfSummary(
    List<CoachBookingShelfEntry> bookings,
  ) {
    final ticketedCount = bookings
        .where((entry) =>
            entry.booking.state == CoachBookingLifecycleState.ticketed)
        .length;
    final needsActionCount = bookings
        .where(
          (entry) =>
              entry.booking.state ==
                  CoachBookingLifecycleState.bookingPending ||
              entry.booking.state ==
                  CoachBookingLifecycleState.partiallyTicketed ||
              entry.booking.state == CoachBookingLifecycleState.refundRequested,
        )
        .length;
    return CoachBookingShelfSummary(
      upcomingCount: bookings.length,
      ticketedCount: ticketedCount,
      needsActionCount: needsActionCount,
    );
  }

  void _applyRefundRequestToShelf(
      CoachRefundRequestResult result, bool isArabic) {
    final bookingShelf = _bookingShelf;
    if (bookingShelf == null) {
      return;
    }
    final updatedBookings = bookingShelf.bookings.map((entry) {
      if (entry.booking.bookingId != result.booking.bookingId) {
        return entry;
      }
      return CoachBookingShelfEntry(
        journey: CoachBookedJourneySummary(
          journeyId: entry.journey.journeyId,
          operatorName: entry.journey.operatorName,
          from: entry.journey.from,
          to: entry.journey.to,
          departureAtIso: entry.journey.departureAtIso,
          arrivalAtIso: entry.journey.arrivalAtIso,
          statusLabel: isArabic ? 'تم طلب الاسترداد' : 'Refund requested',
        ),
        offer: entry.offer,
        hold: entry.hold,
        booking: result.booking,
        passengerManifests: entry.passengerManifests,
        tickets: entry.tickets,
      );
    }).toList(growable: false);
    setState(() {
      _bookingShelf = CoachBookingShelfResponse(
        summary: _deriveBookingShelfSummary(updatedBookings),
        bookings: updatedBookings,
      );
    });
  }

  Future<void> _openBookingShelfDetails(
    CoachBookingShelfEntry entry,
    bool isArabic,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final seatSummary = entry.hold?.seatAssignments
                .map((seat) => '${seat.passengerId}: ${seat.seatNumber}')
                .join(', ') ??
            '-';
        final passengerDisplayNames = <String, String>{
          for (final passenger in entry.passengerManifests)
            passenger.passengerId: passenger.displayName,
        };
        final passengerPreview = _coachMiniProgramPassengerPreviewLabel(
          entry.passengerManifests,
          isArabic,
        );
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isArabic
                        ? 'تفاصيل الرحلة والتذكرة'
                        : 'Trip and ticket detail',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 84,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _coachMiniProgramCompactTime(
                                      entry.journey.departureAtIso,
                                    ),
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _coachMiniProgramCompactTime(
                                      entry.journey.arrivalAtIso,
                                    ),
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _coachMiniProgramCompactDate(
                                      entry.journey.departureAtIso,
                                    ),
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${entry.journey.from} → ${entry.journey.to}',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${entry.journey.operatorName} • ${entry.booking.bookingId}',
                                    style:
                                        Theme.of(context).textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Chip(
                                          label:
                                              Text(entry.journey.statusLabel)),
                                      Chip(
                                        label: Text(
                                          _coachMiniProgramBookingStateLabel(
                                            entry.booking.state,
                                            isArabic,
                                          ),
                                        ),
                                      ),
                                      Chip(
                                        label: Text(
                                          '${isArabic ? 'التذاكر' : 'Tickets'} ${entry.tickets.length}',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CoachMetricChip(
                        icon: Icons.people_alt_outlined,
                        label: isArabic ? 'المسافرون' : 'Passengers',
                        value: '${entry.passengerManifests.length}',
                      ),
                      _CoachMetricChip(
                        icon: Icons.confirmation_num_outlined,
                        label: isArabic ? 'التذاكر' : 'Tickets',
                        value: '${entry.tickets.length}',
                      ),
                      _CoachMetricChip(
                        icon: Icons.event_seat_outlined,
                        label: isArabic ? 'المقاعد' : 'Seats',
                        value: seatSummary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CoachSectionHeader(
                          title: isArabic ? 'لوحة الرحلة' : 'Travel board',
                          subtitle: isArabic
                              ? 'الحالة الحالية، الجاهزية، والركاب في ملخص واحد.'
                              : 'Current state, readiness, and passengers in one calm travel summary.',
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _CoachJourneyFactChip(
                              icon: Icons.departure_board_outlined,
                              label: entry.journey.statusLabel,
                              highlighted: entry.tickets.isNotEmpty,
                            ),
                            _CoachJourneyFactChip(
                              icon: Icons.receipt_long_outlined,
                              label: _coachMiniProgramBookingStateLabel(
                                entry.booking.state,
                                isArabic,
                              ),
                            ),
                            _CoachJourneyFactChip(
                              icon: Icons.confirmation_num_outlined,
                              label: _coachMiniProgramTicketReadinessLabel(
                                entry.tickets.length,
                                isArabic,
                              ),
                              highlighted: entry.tickets.isNotEmpty,
                            ),
                            _CoachJourneyFactChip(
                              icon: Icons.event_seat_outlined,
                              label: seatSummary == '-'
                                  ? (isArabic
                                      ? 'المقاعد لاحقاً'
                                      : 'Seats later')
                                  : seatSummary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${isArabic ? 'الركاب' : 'Passengers'}: $passengerPreview',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${isArabic ? 'الإجمالي' : 'Total'}: ${_moneyLabel(entry.booking.totalMinorUnits, entry.booking.currency)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CoachSectionHeader(
                    title: isArabic ? 'مرجع الرحلة' : 'Trip reference',
                    subtitle: isArabic
                        ? 'الجدول، المرجع التجاري، ووضع الحجز الحالي.'
                        : 'Schedule, commercial reference, and current booking state.',
                  ),
                  const SizedBox(height: 8),
                  _PreviewTile(
                    title: isArabic ? 'الرحلة والحجز' : 'Journey and booking',
                    lines: [
                      '${entry.journey.from} → ${entry.journey.to}',
                      '${entry.journey.operatorName} • ${entry.journey.journeyId}',
                      _coachMiniProgramCompactDateTimeRange(
                        entry.journey.departureAtIso,
                        entry.journey.arrivalAtIso,
                      ),
                      entry.booking.bookingId,
                      '${isArabic ? 'الحالة' : 'State'}: ${_coachMiniProgramBookingStateLabel(entry.booking.state, isArabic)}',
                      '${isArabic ? 'الإجمالي' : 'Total'}: ${_moneyLabel(entry.booking.totalMinorUnits, entry.booking.currency)}',
                      '${isArabic ? 'المقاعد' : 'Seats'}: $seatSummary',
                      if ((entry.booking.operatorBookingReference ?? '')
                          .isNotEmpty)
                        '${isArabic ? 'مرجع المشغل' : 'Operator ref'}: ${entry.booking.operatorBookingReference}',
                    ],
                  ),
                  if (entry.passengerManifests.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _CoachSectionHeader(
                      title: isArabic ? 'بيان المسافرين' : 'Passenger manifest',
                      subtitle: isArabic
                          ? 'الأسماء كما ستظهر في التذاكر.'
                          : 'Travelers as they appear on the issued tickets.',
                    ),
                    const SizedBox(height: 8),
                    _PreviewTile(
                      title: isArabic ? 'المسافرون' : 'Passengers',
                      lines: [
                        for (final passenger in entry.passengerManifests)
                          '${passenger.passengerId}: ${passenger.displayName} • ${_coachMiniProgramRiderCategoryLabel(passenger.riderCategory, isArabic)}${passenger.nationalityCode == null ? '' : ' • ${passenger.nationalityCode}'}',
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  _CoachSectionHeader(
                    title: isArabic ? 'وثائق السفر' : 'Travel documents',
                    subtitle: isArabic
                        ? 'قسائم الإصدار ووسائط التسليم الجاهزة للعرض أو الفحص.'
                        : 'Issued coupons and delivery artifacts ready for display or inspection.',
                  ),
                  const SizedBox(height: 8),
                  if (entry.tickets.isEmpty)
                    _PreviewTile(
                      title: isArabic ? 'التذاكر' : 'Tickets',
                      lines: <String>[
                        isArabic
                            ? 'لا توجد تذاكر مصدّرة بعد.'
                            : 'No issued tickets yet.',
                      ],
                    )
                  else
                    for (var index = 0;
                        index < entry.tickets.length;
                        index++) ...[
                      _CoachIssuedTicketCard(
                        ticket: entry.tickets[index],
                        isArabic: isArabic,
                        passengerDisplayName: passengerDisplayNames[
                            entry.tickets[index].passengerId],
                        artifactLabels: _ticketArtifactLabels(
                          entry.tickets[index],
                          isArabic,
                        ),
                        artifactSummary: _ticketArtifactsSummary(
                          entry.tickets[index],
                          isArabic,
                        ),
                      ),
                      if (index < entry.tickets.length - 1)
                        const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _ticketArtifactsSummary(CoachTicketCoupon ticket, bool isArabic) {
    final parts = <String>[];
    if (ticket.qrPayloadRef != null && ticket.qrPayloadRef!.isNotEmpty) {
      parts.add('QR ${ticket.qrPayloadRef}');
    }
    final walletArtifact = ticket.artifactByKind('wallet_pass');
    if (walletArtifact != null) {
      parts.add(
        '${isArabic ? 'محفظة' : 'Wallet'} ${walletArtifact.downloadPath}',
      );
    }
    final pdfArtifact = ticket.artifactByKind('pdf');
    if (pdfArtifact != null) {
      parts.add('PDF ${pdfArtifact.downloadPath}');
    }
    return parts.join(' • ');
  }

  List<String> _ticketArtifactLabels(CoachTicketCoupon ticket, bool isArabic) {
    final labels = <String>[];
    if (ticket.qrPayloadRef != null && ticket.qrPayloadRef!.isNotEmpty) {
      labels.add('QR');
    }
    if (ticket.artifactByKind('wallet_pass') != null) {
      labels.add(isArabic ? 'محفظة' : 'Wallet');
    }
    if (ticket.artifactByKind('pdf') != null) {
      labels.add('PDF');
    }
    return labels;
  }

  String _ticketSummaryLine(CoachTicketCoupon ticket, bool isArabic) {
    final parts = <String>[
      '${ticket.passengerId}: ${ticket.ticketId}',
      ticket.operatorTicketReference ?? '-',
    ];
    final artifactSummary = _ticketArtifactsSummary(ticket, isArabic);
    if (artifactSummary.isNotEmpty) {
      parts.add(artifactSummary);
    }
    return parts.join(' • ');
  }

  Future<void> _openJourneyLiveSheet(
    CoachBookingShelfEntry entry,
    bool isArabic,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: _CoachJourneyLiveSheet(
            api: _api,
            entry: entry,
            isArabic: isArabic,
            moneyLabel: _moneyLabel,
          ),
        );
      },
    );
  }

  Future<void> _openRefundSheet(
    CoachBookingShelfEntry entry,
    bool isArabic,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: _CoachRefundSheet(
            api: _api,
            entry: entry,
            isArabic: isArabic,
            moneyLabel: _moneyLabel,
            onRefundRequested: (result) {
              _applyRefundRequestToShelf(result, isArabic);
            },
          ),
        );
      },
    );
  }

  Future<void> _openChangeSheet(
    CoachBookingShelfEntry entry,
    bool isArabic,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: _CoachChangeSheet(
            api: _api,
            entry: entry,
            isArabic: isArabic,
            moneyLabel: _moneyLabel,
            onReissued: (_) {
              _loadBookingShelf();
            },
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool isArabic) {
    if (_bootstrapLoading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        ),
      );
    }
    if (_bootstrapError != null) {
      return StatusBanner.error(
        isArabic
            ? 'تعذر تحميل إعدادات الحافلات.'
            : 'Coach platform config could not be loaded.',
      );
    }
    final bootstrap = _bootstrap;
    if (bootstrap == null) {
      return const SizedBox.shrink();
    }
    final totalFeeds = bootstrap.operatorFeedHealth.length;
    final healthyFeeds =
        bootstrap.operatorFeedHealth.where((entry) => entry.isHealthy).length;
    final degradedOperators = bootstrap.operatorFeedHealth
        .where((entry) => !entry.isHealthy)
        .map((entry) => entry.operatorName)
        .toSet()
        .toList(growable: false);
    return _CoachLiquidGlassPanel(
      tint: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Tokens.colorBus.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.directions_bus_outlined,
                  color: Tokens.colorBus,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic
                          ? 'تخطيط رحلات الحافلات بين المدن'
                          : 'Intercity coach trip planning',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArabic
                          ? 'واجهة أقرب إلى تطبيقات النقل العام: بحث أولاً، ثم الرحلات، ثم التذاكر.'
                          : 'A public-transport style layout: plan first, then trips, then tickets.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final boundary in bootstrap.commercialBoundaries)
                Chip(label: Text(boundary)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CoachMetricChip(
                icon: Icons.data_usage_outlined,
                label: isArabic ? 'الإصدار' : 'Version',
                value: bootstrap.version,
              ),
              _CoachMetricChip(
                icon: Icons.graphic_eq_outlined,
                label: isArabic ? 'الزمن الحقيقي' : 'Realtime target',
                value: '${bootstrap.tripUpdatesFreshnessSeconds}s',
              ),
              if (totalFeeds > 0)
                _CoachMetricChip(
                  icon: Icons.cloud_done_outlined,
                  label: isArabic ? 'صحة التغذيات' : 'Feed health',
                  value: '$healthyFeeds / $totalFeeds',
                ),
            ],
          ),
          if (degradedOperators.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'تنبيه تشغيلي: ${degradedOperators.join('، ')}'
                  : 'Operational warning: ${degradedOperators.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.orange.shade800,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchPanel(BuildContext context, bool isArabic) {
    final routeSummary =
        '${_fromController.text.trim()} → ${_toController.text.trim()}';
    return _CoachLiquidGlassPanel(
      tint: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isArabic ? 'ابحث عن رحلة' : 'Search journey',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: _coachMiniProgramHandleTap(_swapRoute),
                tooltip: isArabic ? 'اعكس الاتجاه' : 'Swap route',
                icon: const Icon(Icons.swap_vert),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            coachMiniProgramSyriaRouteHint(isArabic: isArabic),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CoachMetricChip(
                icon: Icons.route_outlined,
                label: isArabic ? 'المسار' : 'Route',
                value: routeSummary,
              ),
              _CoachMetricChip(
                icon: Icons.calendar_today_outlined,
                label: isArabic ? 'السفر' : 'Departure',
                value: _coachMiniProgramDepartureSummary(
                  _departureDateController.text,
                  isArabic,
                ),
              ),
              _CoachMetricChip(
                icon: Icons.people_alt_outlined,
                label: isArabic ? 'المسافرون' : 'Travelers',
                value: _coachMiniProgramTravelerCountLabel(
                  _passengers,
                  isArabic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CoachSectionHeader(
            title: isArabic ? 'مسارات سريعة' : 'Quick routes',
            subtitle: isArabic
                ? 'املأ أشهر مسارات سوريا بضغطة واحدة.'
                : 'Fill common Syria corridors with one tap.',
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth >= 640;
              final tileWidth = useTwoColumns
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in _coachMiniProgramRoutePresets)
                    SizedBox(
                      width: tileWidth,
                      child: _CoachRoutePresetCard(
                        title:
                            '${_coachMiniProgramLocalizedCityName(preset.from, isArabic)} → ${_coachMiniProgramLocalizedCityName(preset.to, isArabic)}',
                        subtitle: isArabic
                            ? 'املأ المسار مباشرة'
                            : 'Fill route instantly',
                        selected: _matchesRoutePreset(preset, isArabic),
                        onPressed: () => _applyRoutePreset(preset, isArabic),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? WeChatPalette.searchFillDark
                  : WeChatPalette.searchFill,
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: .6),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _fromController,
                    onChanged: (_) => _handleSearchDraftEdited(),
                    decoration: InputDecoration(
                      labelText: isArabic ? 'من' : 'From',
                      prefixIcon: const Icon(Icons.trip_origin),
                      hintText: isArabic
                          ? 'دمشق / حمص / حلب / اللاذقية'
                          : 'Damascus / Homs / Aleppo / Latakia',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: .6),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: _toController,
                    onChanged: (_) => _handleSearchDraftEdited(),
                    decoration: InputDecoration(
                      labelText: isArabic ? 'إلى' : 'To',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      hintText: isArabic
                          ? 'دمشق / حمص / حلب / اللاذقية'
                          : 'Damascus / Homs / Aleppo / Latakia',
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final offsetDays in <int>[0, 1, 2])
                ChoiceChip(
                  label: Text(
                    _coachMiniProgramRelativeDateLabel(offsetDays, isArabic),
                  ),
                  selected: _departureDateMatchesOffset(offsetDays),
                  onSelected: (_) => _setDepartureDateValue(
                    _departureDateOffsetValue(offsetDays),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackControls = constraints.maxWidth < 380;
              final dateField = TextField(
                controller: _departureDateController,
                onChanged: (_) => _handleSearchDraftEdited(),
                decoration: InputDecoration(
                  labelText: isArabic ? 'تاريخ السفر' : 'Departure date',
                  prefixIcon: const Icon(Icons.calendar_today_outlined),
                  hintText: 'YYYY-MM-DD',
                ),
              );
              final passengerControl = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? WeChatPalette.searchFillDark
                      : WeChatPalette.searchFill,
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: .6),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isArabic ? 'المسافرون' : 'Passengers',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        Text(
                          '$_passengers',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _passengers > 1
                          ? _coachMiniProgramHandleTap(
                              () => _setPassengers(_passengers - 1),
                            )
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      onPressed: _passengers < 9
                          ? _coachMiniProgramHandleTap(
                              () => _setPassengers(_passengers + 1),
                            )
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              );
              if (stackControls) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dateField,
                    const SizedBox(height: 10),
                    passengerControl,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: dateField),
                  const SizedBox(width: 10),
                  Expanded(child: passengerControl),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                _searching ? null : _coachMiniProgramHandleTap(_runSearch),
            icon: _searching
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(isArabic ? 'ابحث' : 'Search'),
            style: FilledButton.styleFrom(
              backgroundColor: WeChatPalette.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          if (_searchError != null) ...[
            const SizedBox(height: 10),
            StatusBanner.error(_searchError!),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsPanel(BuildContext context, bool isArabic) {
    final response = _searchResponse;
    if (_searching) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: ShamellSkeletonList(itemCount: 4),
        ),
      );
    }
    if (response == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isArabic ? 'النتائج' : 'Results',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? 'أدخل المسار والتاريخ لتحميل العروض.'
                    : 'Enter route and date to load coach offers.',
              ),
            ],
          ),
        ),
      );
    }
    final boardJourneys = _journeyBoardJourneys(response);
    final showingFilteredJourneyCount =
        boardJourneys.length != response.journeys.length;
    final lowestVisibleFare = boardJourneys.isEmpty
        ? null
        : boardJourneys.map((journey) => journey.priceFromMinorUnits).reduce(
              (current, next) => current < next ? current : next,
            );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${response.from} → ${response.to}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_coachMiniProgramDepartureSummary(response.departureDate, isArabic)} • ${_coachMiniProgramTravelerCountLabel(response.passengers, isArabic)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(
                        showingFilteredJourneyCount
                            ? (isArabic
                                ? '${boardJourneys.length} من ${response.journeys.length} رحلات'
                                : '${boardJourneys.length} of ${response.journeys.length} trips')
                            : (isArabic
                                ? '${response.journeys.length} رحلات'
                                : '${response.journeys.length} trips'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _CoachMetricChip(
                      icon: Icons.alt_route_outlined,
                      label: isArabic ? 'مباشرة' : 'Direct',
                      value:
                          '${boardJourneys.where((journey) => journey.transferCount == 0).length}',
                    ),
                    if (lowestVisibleFare != null)
                      _CoachMetricChip(
                        icon: Icons.sell_outlined,
                        label: isArabic ? 'أفضل سعر' : 'Best fare',
                        value: _moneyLabel(
                          lowestVisibleFare,
                          boardJourneys.first.currency,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .96),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant
                  .withValues(alpha: .5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoachSectionHeader(
                title: isArabic ? 'أدوات اللوحة' : 'Board tools',
                subtitle: isArabic
                    ? 'رتّب لوحة الرحلات أو احصرها بالمباشر فقط قبل فتح المسودة.'
                    : 'Sort the departure board or keep it on direct trips only before opening the draft.',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in _CoachJourneyBoardSortMode.values)
                    ChoiceChip(
                      label: Text(
                        _coachMiniProgramJourneyBoardSortLabel(mode, isArabic),
                      ),
                      selected: _journeyBoardSortMode == mode,
                      onSelected: (_) => _setJourneyBoardSortMode(mode),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    label: Text(isArabic ? 'مباشرة فقط' : 'Direct only'),
                    selected: _journeyBoardDirectOnly,
                    onSelected: _setJourneyBoardDirectOnly,
                  ),
                  if (showingFilteredJourneyCount)
                    Chip(
                      label: Text(
                        isArabic
                            ? '${boardJourneys.length} معروضة'
                            : '${boardJourneys.length} shown',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CoachSectionHeader(
          title: isArabic ? 'لوحة الرحلات' : 'Departure board',
          subtitle: isArabic
              ? 'قارن الزمن الفعلي، التبديلات، والسعة قبل فتح مسودة الحجز.'
              : 'Compare live running, transfers, and capacity before opening the booking draft.',
        ),
        const SizedBox(height: 10),
        if (boardJourneys.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                isArabic
                    ? 'لا توجد رحلات تطابق أدوات اللوحة الحالية.'
                    : 'No journeys match the current board tools.',
              ),
            ),
          )
        else
          for (final journey in boardJourneys) ...[
            _CoachJourneyCard(
              journey: journey,
              fromLabel: response.from,
              toLabel: response.to,
              selected: identical(journey, _selectedJourney),
              moneyLabel: _moneyLabel,
              isArabic: isArabic,
              onTap: () => _selectJourney(journey),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _buildSelectedJourneyPanel(BuildContext context, bool isArabic) {
    final selectedJourney = _selectedJourney!;
    final selectedOffer = _selectedOffer ?? selectedJourney.bestOffer;
    final previewWalletPassCount = _previewTickets
        .where((ticket) => ticket.artifactByKind('wallet_pass') != null)
        .length;
    final previewPdfCount = _previewTickets
        .where((ticket) => ticket.artifactByKind('pdf') != null)
        .length;
    final progressSteps = <({
      int step,
      String title,
      String subtitle,
      _CoachJourneyStepState state
    })>[
      (
        step: 1,
        title: isArabic ? 'العرض' : 'Offer',
        subtitle: isArabic ? 'تم اختيار الرحلة' : 'Journey selected',
        state: _CoachJourneyStepState.complete,
      ),
      (
        step: 2,
        title: isArabic ? 'التثبيت' : 'Hold',
        subtitle: _previewHold != null
            ? (isArabic ? 'تم تثبيت المقاعد' : 'Seats held')
            : selectedOffer.holdSupported
                ? (isArabic ? 'اختياري قبل الدفع' : 'Optional before payment')
                : (isArabic ? 'غير متاح' : 'Unavailable'),
        state: _previewHold != null
            ? _CoachJourneyStepState.complete
            : _previewBooking == null
                ? _CoachJourneyStepState.active
                : _CoachJourneyStepState.pending,
      ),
      (
        step: 3,
        title: isArabic ? 'الحجز' : 'Booking',
        subtitle: _previewBooking != null
            ? (isArabic ? 'تم إنشاء الحجز' : 'Booking created')
            : (isArabic ? 'ينتظر التأكيد' : 'Awaiting confirmation'),
        state: _previewBooking != null
            ? _CoachJourneyStepState.complete
            : _previewHold != null ||
                    (_previewHold == null && !selectedOffer.holdSupported)
                ? _CoachJourneyStepState.active
                : _CoachJourneyStepState.pending,
      ),
      (
        step: 4,
        title: isArabic ? 'التذاكر' : 'Tickets',
        subtitle: _previewTickets.isNotEmpty
            ? (isArabic ? 'تم الإصدار' : 'Issued')
            : (isArabic ? 'جاهزة للإصدار' : 'Ready to issue'),
        state: _previewTickets.isNotEmpty
            ? _CoachJourneyStepState.complete
            : _previewBooking != null
                ? _CoachJourneyStepState.active
                : _CoachJourneyStepState.pending,
      ),
    ];
    final canCreateHold = !_previewLoading &&
        selectedOffer.holdSupported &&
        _previewHold == null &&
        _previewBooking == null;
    final canCreateBooking = !_previewLoading && _previewBooking == null;
    final canIssueTickets =
        !_previewLoading && _previewBooking != null && _previewTickets.isEmpty;
    late final String recommendedTitle;
    late final String recommendedSubtitle;
    late final String recommendedActionLabel;
    late final IconData recommendedActionIcon;
    late final VoidCallback? recommendedOnPressed;
    late final List<String> recommendedBadges;
    final secondaryActions = <Widget>[
      _CoachActionListButton(
        title: isArabic ? 'حدّث السعر' : 'Refresh offer',
        subtitle: isArabic
            ? 'أعد تحميل العرض التجاري الحالي قبل المتابعة.'
            : 'Reload the current commercial offer before you continue.',
        icon: Icons.refresh,
        onPressed: _previewLoading ? null : _refreshOffer,
      ),
    ];

    if (_previewTickets.isNotEmpty) {
      recommendedTitle =
          isArabic ? 'التذاكر جاهزة للعرض' : 'Tickets ready to show';
      recommendedSubtitle = isArabic
          ? 'تم إصدار التذاكر ويمكنك فتح تبويب التذاكر أو مراجعة ناتج الجلسة.'
          : 'The tickets are issued. Open the Tickets tab or review the latest session output.';
      recommendedActionLabel = isArabic ? 'افتح التذاكر' : 'Open tickets';
      recommendedActionIcon = Icons.confirmation_num_outlined;
      recommendedOnPressed = () {
        setState(() {
          _activeTab = _CoachBusMiniTab.tickets;
        });
      };
      recommendedBadges = <String>[
        '${isArabic ? 'التذاكر' : 'Tickets'} ${_previewTickets.length}',
        '${isArabic ? 'المحفظة / PDF' : 'Wallet / PDF'} $previewWalletPassCount / $previewPdfCount',
      ];
    } else if (_previewBooking != null) {
      recommendedTitle =
          isArabic ? 'أصدر تذاكر المسافرين' : 'Issue passenger tickets';
      recommendedSubtitle = isArabic
          ? 'الحجز جاهز الآن. أكمل الإصدار لتجهيز المحفظة وPDF والبريد.'
          : 'The booking is ready. Finish ticketing to prepare wallet, PDF, and email delivery.';
      recommendedActionLabel = isArabic ? 'أصدر التذاكر' : 'Issue tickets';
      recommendedActionIcon = Icons.confirmation_num_outlined;
      recommendedOnPressed =
          canIssueTickets ? _issueTicketsForSelectedJourney : null;
      recommendedBadges = <String>[
        _previewBooking!.bookingId,
        _coachMiniProgramBookingStateLabel(_previewBooking!.state, isArabic),
      ];
    } else if (_previewHold != null) {
      recommendedTitle = isArabic
          ? 'حوّل الحجز المؤقت إلى حجز'
          : 'Turn the seat hold into a booking';
      recommendedSubtitle = isArabic
          ? 'المقاعد مثبتة. أكمل الحجز التجاري قبل الإصدار.'
          : 'The seats are reserved. Complete the commercial booking before ticketing.';
      recommendedActionLabel = isArabic ? 'أنشئ الحجز' : 'Create booking';
      recommendedActionIcon = Icons.receipt_long_outlined;
      recommendedOnPressed =
          canCreateBooking ? _createBookingForSelectedJourney : null;
      recommendedBadges = <String>[
        _previewHold!.holdId,
        '${isArabic ? 'المقاعد' : 'Seats'} ${_previewHold!.seatAssignments.length}',
      ];
    } else if (selectedOffer.holdSupported) {
      recommendedTitle =
          isArabic ? 'ثبّت المقاعد أولاً' : 'Reserve seats first';
      recommendedSubtitle = isArabic
          ? 'ابدأ بحجز مؤقت قصير قبل إنشاء الحجز والدفع.'
          : 'Start with a short hold before creating the booking and charging payment.';
      recommendedActionLabel = isArabic ? 'أنشئ الحجز المؤقت' : 'Create hold';
      recommendedActionIcon = Icons.event_seat_outlined;
      recommendedOnPressed =
          canCreateHold ? _createHoldForSelectedJourney : null;
      recommendedBadges = <String>[
        isArabic ? 'الحجز المؤقت متاح' : 'Hold available',
        '${isArabic ? 'المسافرون' : 'Travelers'} $_passengers',
      ];
      secondaryActions.add(
        _CoachActionListButton(
          title: isArabic ? 'أنشئ الحجز' : 'Create booking',
          subtitle: isArabic
              ? 'تجاوز الحجز المؤقت وانتقل مباشرة إلى سجل الحجز.'
              : 'Skip the hold and go straight to the booking record.',
          icon: Icons.receipt_long_outlined,
          onPressed: _createBookingForSelectedJourney,
        ),
      );
    } else {
      recommendedTitle =
          isArabic ? 'أكمل الحجز مباشرة' : 'Continue straight to booking';
      recommendedSubtitle = isArabic
          ? 'هذه الرحلة لا تدعم الحجز المؤقت، لذا انتقل مباشرة إلى الحجز.'
          : 'This journey does not support holds, so the booking can be created directly.';
      recommendedActionLabel = isArabic ? 'أنشئ الحجز' : 'Create booking';
      recommendedActionIcon = Icons.receipt_long_outlined;
      recommendedOnPressed =
          canCreateBooking ? _createBookingForSelectedJourney : null;
      recommendedBadges = <String>[
        isArabic ? 'بدون حجز مؤقت' : 'No hold',
        '${isArabic ? 'المسافرون' : 'Travelers'} $_passengers',
      ];
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isArabic ? 'مسودة الحجز والتذكرة' : 'Booking and ticket draft',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _coachMiniProgramCompactTime(
                            selectedJourney.departureAtIso,
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _coachMiniProgramCompactTime(
                            selectedJourney.arrivalAtIso,
                          ),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _coachMiniProgramDurationLabel(
                            selectedJourney.durationMinutes,
                            isArabic,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_fromController.text.trim()} → ${_toController.text.trim()}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_coachMiniProgramCompactDate(selectedJourney.departureAtIso)} • ${_coachMiniProgramTransferLabel(selectedJourney.transferCount, isArabic)}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${selectedJourney.operatorName} • ${selectedJourney.journeyId}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text(
                                selectedOffer.holdSupported
                                    ? (isArabic
                                        ? 'الحجز المؤقت متاح'
                                        : 'Hold available')
                                    : (isArabic ? 'بدون حجز مؤقت' : 'No hold'),
                              ),
                            ),
                            Chip(
                              label: Text(
                                selectedOffer.changeable
                                    ? (isArabic ? 'قابل للتغيير' : 'Changeable')
                                    : (isArabic
                                        ? 'غير قابل للتغيير'
                                        : 'Not changeable'),
                              ),
                            ),
                            Chip(
                              label: Text(
                                selectedOffer.refundable
                                    ? (isArabic
                                        ? 'قابل للاسترداد'
                                        : 'Refundable')
                                    : (isArabic
                                        ? 'غير قابل للاسترداد'
                                        : 'Not refundable'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _moneyLabel(
                          selectedOffer.totalMinorUnits,
                          selectedOffer.currency,
                        ),
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Tokens.colorBus,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isArabic
                            ? 'العرض ${selectedOffer.offerId}'
                            : 'Offer ${selectedOffer.offerId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _CoachMetricChip(
                  icon: Icons.people_alt_outlined,
                  label: isArabic ? 'المسافرون' : 'Travelers',
                  value: '$_passengers',
                ),
                _CoachMetricChip(
                  icon: Icons.event_seat_outlined,
                  label: isArabic ? 'المقاعد' : 'Seats left',
                  value: '${selectedJourney.seatsAvailable}',
                ),
                _CoachMetricChip(
                  icon: Icons.alt_route_outlined,
                  label: isArabic ? 'الخدمة' : 'Service',
                  value: _coachMiniProgramTransferLabel(
                    selectedJourney.transferCount,
                    isArabic,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CoachSectionHeader(
              title: isArabic ? 'تقدم الرحلة' : 'Journey progress',
              subtitle: isArabic
                  ? 'حالة العرض، التثبيت، الحجز، وإصدار التذاكر تبقى مرئية أثناء الإعداد.'
                  : 'Offer, hold, booking, and ticketing stay visible while you prepare the trip.',
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 860
                    ? 4
                    : constraints.maxWidth >= 520
                        ? 2
                        : 1;
                final spacing = columns == 1 ? 0.0 : 8.0;
                final tileWidth = columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - (spacing * (columns - 1))) /
                        columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: 8,
                  children: [
                    for (final step in progressSteps)
                      SizedBox(
                        width: tileWidth,
                        child: _CoachJourneyStepCard(
                          stepNumber: step.step,
                          title: step.title,
                          subtitle: step.subtitle,
                          state: step.state,
                          statusLabel: _coachMiniProgramJourneyStepStatusLabel(
                            step.state,
                            isArabic,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            _CoachSectionHeader(
              title: isArabic ? 'إعداد الرحلة' : 'Travel setup',
              subtitle: isArabic
                  ? 'أدخل بيانات الحجز كما في صفحات تفاصيل الرحلة في تطبيقات النقل.'
                  : 'Prepare booking data in a tighter trip-detail layout.',
            ),
            const SizedBox(height: 8),
            _PreviewTile(
              title: isArabic ? 'الملخص التشغيلي' : 'Commercial summary',
              lines: [
                isArabic
                    ? 'صالح حتى ${_coachMiniProgramCompactDateTime(selectedOffer.expiresAtIso)}'
                    : 'Valid until ${_coachMiniProgramCompactDateTime(selectedOffer.expiresAtIso)}',
                isArabic
                    ? 'الدفع: ${_coachMiniProgramPaymentMethodLabel(_paymentMethod, isArabic)}'
                    : 'Payment: ${_coachMiniProgramPaymentMethodLabel(_paymentMethod, isArabic)}',
                isArabic
                    ? 'المقاعد المتاحة: ${selectedJourney.seatsAvailable}'
                    : 'Seats available: ${selectedJourney.seatsAvailable}',
              ],
            ),
            const SizedBox(height: 12),
            _CheckoutDraftCard(
              isArabic: isArabic,
              contactEmailController: _contactEmailController,
              paymentMethod: _paymentMethod,
              onPaymentMethodChanged: (value) {
                if (value == null) {
                  return;
                }
                setState(() {
                  _paymentMethod = value;
                });
              },
              passengerIdControllers: _passengerIdControllers,
              passengerGivenNameControllers: _passengerGivenNameControllers,
              passengerFamilyNameControllers: _passengerFamilyNameControllers,
              passengerNationalityControllers: _passengerNationalityControllers,
              passengerCategories: _passengerCategories,
              onPassengerCategoryChanged: (index, category) {
                setState(() {
                  _passengerCategories[index] = category;
                });
              },
              preferredSeatControllers: _preferredSeatControllers,
              deliverWalletPass: _deliverWalletPass,
              deliverPdf: _deliverPdf,
              deliverEmail: _deliverEmail,
              onDeliverWalletPassChanged: (value) {
                setState(() {
                  _deliverWalletPass = value;
                });
              },
              onDeliverPdfChanged: (value) {
                setState(() {
                  _deliverPdf = value;
                });
              },
              onDeliverEmailChanged: (value) {
                setState(() {
                  _deliverEmail = value;
                });
              },
            ),
            const SizedBox(height: 12),
            _CoachSectionHeader(
              title: isArabic ? 'الخطوة الموصى بها' : 'Recommended next step',
              subtitle: isArabic
                  ? 'إبراز الإجراء التالي الأنسب بدل إظهار كل الأوامر كأنها متساوية.'
                  : 'Keep the next best action prominent instead of treating every control equally.',
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Tokens.colorBus.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          recommendedActionIcon,
                          color: Tokens.colorBus,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recommendedTitle,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              recommendedSubtitle,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final badge in recommendedBadges)
                        Chip(label: Text(badge)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _coachMiniProgramHandleTap(recommendedOnPressed),
                    icon: Icon(recommendedActionIcon),
                    label: Text(recommendedActionLabel),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _CoachSectionHeader(
              title: isArabic ? 'عناصر التحكم الأخرى' : 'Other controls',
              subtitle: isArabic
                  ? 'تظل أدوات التحديث أو المسار البديل متاحة دون أن تنافس الخطوة الأساسية.'
                  : 'Refresh and alternative control paths stay available without competing with the main step.',
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                for (var index = 0;
                    index < secondaryActions.length;
                    index++) ...[
                  secondaryActions[index],
                  if (index < secondaryActions.length - 1)
                    const SizedBox(height: 8),
                ],
              ],
            ),
            if (_previewHold != null ||
                _previewBooking != null ||
                _previewPassengerManifests.isNotEmpty ||
                _compensation != null ||
                _previewTickets.isNotEmpty) ...[
              const SizedBox(height: 14),
              _CoachSectionHeader(
                title: isArabic ? 'مخرجات الجلسة' : 'Session output',
                subtitle: isArabic
                    ? 'النتيجة الأخيرة للحجز، التذاكر، أو التعويض.'
                    : 'Latest result for hold, booking, ticketing, or compensation.',
              ),
            ],
            if (_previewLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_previewError != null) ...[
              const SizedBox(height: 12),
              StatusBanner.error(_previewError!),
            ],
            if ((_commandNote ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              StatusBanner.info(_commandNote!),
            ],
            if (_previewHold != null) ...[
              const SizedBox(height: 14),
              _PreviewTile(
                title: isArabic ? 'الحجز المؤقت' : 'Hold',
                lines: [
                  _previewHold!.holdId,
                  '${isArabic ? 'الحالة' : 'Status'}: ${_coachMiniProgramHoldStatusLabel(_previewHold!.status, isArabic)}',
                  '${isArabic ? 'المقاعد' : 'Seats'}: ${_previewHold!.seatAssignments.map((seat) => seat.seatNumber).join(', ')}',
                ],
              ),
            ],
            if (_previewBooking != null) ...[
              const SizedBox(height: 12),
              _PreviewTile(
                title: isArabic ? 'الحجز' : 'Booking',
                lines: [
                  _previewBooking!.bookingId,
                  '${isArabic ? 'الحالة' : 'State'}: ${_coachMiniProgramBookingStateLabel(_previewBooking!.state, isArabic)}',
                  '${isArabic ? 'الإجمالي' : 'Total'}: ${_moneyLabel(_previewBooking!.totalMinorUnits, _previewBooking!.currency)}',
                  '${isArabic ? 'الدفع' : 'Payment'}: ${_coachMiniProgramPaymentMethodLabel(_paymentMethod, isArabic)}',
                ],
              ),
            ],
            if (_previewPassengerManifests.isNotEmpty) ...[
              const SizedBox(height: 12),
              _PreviewTile(
                title: isArabic ? 'المسافرون' : 'Passengers',
                lines: [
                  for (final passenger in _previewPassengerManifests)
                    '${passenger.passengerId}: ${passenger.displayName} • ${_coachMiniProgramRiderCategoryLabel(passenger.riderCategory, isArabic)}${passenger.nationalityCode == null ? '' : ' • ${passenger.nationalityCode}'}',
                ],
              ),
            ],
            if (_compensation != null) ...[
              const SizedBox(height: 12),
              _PreviewTile(
                title: isArabic ? 'التعويض' : 'Compensation',
                lines: [
                  '${isArabic ? 'الحالة' : 'State'}: ${_compensation!.state}',
                  '${isArabic ? 'الإجراء' : 'Action'}: ${_coachMiniProgramCompensationActionLabel(_compensation!.action, isArabic)}',
                  '${isArabic ? 'الطابور' : 'Queue'}: ${_compensation!.supportQueue}',
                ],
              ),
            ],
            if (_previewTickets.isNotEmpty) ...[
              const SizedBox(height: 12),
              _PreviewTile(
                title: isArabic ? 'التذاكر' : 'Tickets',
                lines: [
                  for (final ticket in _previewTickets)
                    _ticketSummaryLine(ticket, isArabic),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _CoachMetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? WeChatPalette.searchFillDark : WeChatPalette.searchFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              Text(value, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoachSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _CoachSectionHeader({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _CoachRoutePresetCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onPressed;

  const _CoachRoutePresetCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: _coachMiniProgramHandleTap(onPressed),
      style: FilledButton.styleFrom(
        backgroundColor: selected
            ? Tokens.colorBus.withValues(alpha: .12)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: .35),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        shadowColor: Colors.transparent,
        padding: const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            selected ? Icons.check_circle : Icons.chevron_right,
            color: selected
                ? Tokens.colorBus
                : Theme.of(context).colorScheme.outline,
          ),
        ],
      ),
    );
  }
}

class _CoachJourneyStepCard extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String subtitle;
  final String statusLabel;
  final _CoachJourneyStepState state;

  const _CoachJourneyStepCard({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = switch (state) {
      _CoachJourneyStepState.complete => Tokens.colorBus.withValues(alpha: .12),
      _CoachJourneyStepState.active => Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: .55),
      _CoachJourneyStepState.pending => Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: .3),
    };
    final leadingIcon = switch (state) {
      _CoachJourneyStepState.complete => const Icon(
          Icons.check,
          size: 16,
          color: Tokens.colorBus,
        ),
      _CoachJourneyStepState.active => Text(
          '$stepNumber',
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Tokens.colorBus),
        ),
      _CoachJourneyStepState.pending => Text(
          '$stepNumber',
          style: Theme.of(context).textTheme.labelLarge,
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .75),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: leadingIcon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child:
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(statusLabel, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CoachJourneyFactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;

  const _CoachJourneyFactChip({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFFFFF3C4)
            : isDark
                ? WeChatPalette.searchFillDark
                : WeChatPalette.searchFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Tokens.colorBus),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _CoachActionListButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onPressed;

  const _CoachActionListButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonal(
        onPressed: _coachMiniProgramHandleTap(onPressed),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Tokens.colorBus),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachDecisionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amountLabel;
  final IconData icon;
  final List<String> badgeLabels;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onPressed;
  final bool loading;

  const _CoachDecisionCard({
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.icon,
    this.badgeLabels = const <String>[],
    required this.actionLabel,
    required this.actionIcon,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Tokens.colorBus.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Tokens.colorBus, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                amountLabel,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Tokens.colorBus),
              ),
            ],
          ),
          if (badgeLabels.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final badge in badgeLabels) Chip(label: Text(badge)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _coachMiniProgramHandleTap(onPressed),
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(actionIcon),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _CoachTicketSummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<CoachTicketCoupon> tickets;
  final bool isArabic;
  final Map<String, String> passengerDisplayNames;
  final String actionLabel;
  final VoidCallback onPressed;

  const _CoachTicketSummaryCard({
    required this.title,
    required this.subtitle,
    required this.tickets,
    required this.isArabic,
    this.passengerDisplayNames = const <String, String>{},
    required this.actionLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final primaryTicket = tickets.isEmpty ? null : tickets.first;
    final additionalTicketCount = tickets.isEmpty ? 0 : tickets.length - 1;
    final activeTicketCount = tickets
        .where((ticket) => ticket.status == CoachTicketStatus.active)
        .length;
    final walletPassCount = tickets
        .where((ticket) => ticket.artifactByKind('wallet_pass') != null)
        .length;
    final pdfCount =
        tickets.where((ticket) => ticket.artifactByKind('pdf') != null).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Chip(label: Text('${tickets.length}')),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CoachSectionHeader(
                    title: isArabic ? 'لوحة التذكرة' : 'Ticket wallet board',
                    subtitle: isArabic
                        ? 'جاهزية العرض، وسائط التسليم، والركاب في ملخص واحد.'
                        : 'Show readiness, delivery artifacts, and passengers in one pass-style summary.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CoachJourneyFactChip(
                        icon: Icons.confirmation_num_outlined,
                        label: _coachMiniProgramTicketReadinessLabel(
                          activeTicketCount,
                          isArabic,
                        ),
                        highlighted: activeTicketCount > 0,
                      ),
                      _CoachJourneyFactChip(
                        icon: Icons.people_alt_outlined,
                        label: isArabic
                            ? '${tickets.length} ركاب'
                            : '${tickets.length} passengers',
                      ),
                      if (walletPassCount > 0)
                        _CoachJourneyFactChip(
                          icon: Icons.wallet_outlined,
                          label:
                              '${isArabic ? 'محفظة' : 'Wallet'} $walletPassCount',
                        ),
                      if (pdfCount > 0)
                        _CoachJourneyFactChip(
                          icon: Icons.picture_as_pdf_outlined,
                          label: 'PDF $pdfCount',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (tickets.isEmpty) ...[
              const SizedBox(height: 10),
              Text(
                isArabic
                    ? 'لا توجد تذاكر مصدّرة بعد.'
                    : 'No issued tickets yet.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            ] else ...[
              const SizedBox(height: 12),
              _CoachIssuedTicketCard(
                ticket: primaryTicket!,
                isArabic: isArabic,
                passengerDisplayName:
                    passengerDisplayNames[primaryTicket.passengerId],
                artifactLabels: [
                  if (primaryTicket.qrPayloadRef != null &&
                      primaryTicket.qrPayloadRef!.isNotEmpty)
                    'QR',
                  if (primaryTicket.artifactByKind('wallet_pass') != null)
                    isArabic ? 'محفظة' : 'Wallet',
                  if (primaryTicket.artifactByKind('pdf') != null) 'PDF',
                ],
                artifactSummary: [
                  '${isArabic ? 'أُصدرت' : 'Issued'} ${_coachMiniProgramCompactDateTime(primaryTicket.issuedAtIso)}',
                  if (primaryTicket.qrPayloadRef != null &&
                      primaryTicket.qrPayloadRef!.isNotEmpty)
                    'QR ${primaryTicket.qrPayloadRef}',
                  if (primaryTicket.artifactByKind('wallet_pass') != null)
                    '${isArabic ? 'محفظة' : 'Wallet'} ${primaryTicket.artifactByKind('wallet_pass')!.downloadPath}',
                  if (primaryTicket.artifactByKind('pdf') != null)
                    'PDF ${primaryTicket.artifactByKind('pdf')!.downloadPath}',
                ].join(' • '),
              ),
              if (additionalTicketCount > 0) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    isArabic
                        ? '+$additionalTicketCount تذاكر إضافية في هذه الرحلة'
                        : '+$additionalTicketCount more tickets on this trip',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              for (var index = 1;
                  index < tickets.length && index < 3;
                  index++) ...[
                _CoachIssuedTicketCard(
                  ticket: tickets[index],
                  isArabic: isArabic,
                  passengerDisplayName:
                      passengerDisplayNames[tickets[index].passengerId],
                  artifactLabels: [
                    if (tickets[index].qrPayloadRef != null &&
                        tickets[index].qrPayloadRef!.isNotEmpty)
                      'QR',
                    if (tickets[index].artifactByKind('wallet_pass') != null)
                      isArabic ? 'محفظة' : 'Wallet',
                    if (tickets[index].artifactByKind('pdf') != null) 'PDF',
                  ],
                  artifactSummary: [
                    if (tickets[index].qrPayloadRef != null &&
                        tickets[index].qrPayloadRef!.isNotEmpty)
                      'QR ${tickets[index].qrPayloadRef}',
                    if (tickets[index].artifactByKind('wallet_pass') != null)
                      '${isArabic ? 'محفظة' : 'Wallet'} ${tickets[index].artifactByKind('wallet_pass')!.downloadPath}',
                    if (tickets[index].artifactByKind('pdf') != null)
                      'PDF ${tickets[index].artifactByKind('pdf')!.downloadPath}',
                  ].join(' • '),
                ),
                if (index < tickets.length - 1 && index < 2)
                  const SizedBox(height: 8),
              ],
            ],
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _coachMiniProgramHandleTap(onPressed),
              icon: const Icon(Icons.arrow_forward),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachIssuedTicketCard extends StatelessWidget {
  final CoachTicketCoupon ticket;
  final bool isArabic;
  final String? passengerDisplayName;
  final List<String> artifactLabels;
  final String artifactSummary;

  const _CoachIssuedTicketCard({
    required this.ticket,
    required this.isArabic,
    this.passengerDisplayName,
    required this.artifactLabels,
    required this.artifactSummary,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedPassengerLabel = (passengerDisplayName ?? '').trim().isEmpty
        ? ticket.passengerId
        : passengerDisplayName!.trim();
    final boardingLabel =
        _coachMiniProgramBoardingStateLabel(ticket.boardingState, isArabic);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .45),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Tokens.colorBus.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.confirmation_num_outlined,
                  color: Tokens.colorBus,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.ticketId,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${isArabic ? 'المسافر' : 'Passenger'} $resolvedPassengerLabel',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(
                  _coachMiniProgramTicketStatusLabel(ticket.status, isArabic),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CoachJourneyFactChip(
                icon: Icons.qr_code_2_outlined,
                label: boardingLabel,
                highlighted:
                    ticket.boardingState == CoachManifestBoardingState.boarded,
              ),
              for (final label in artifactLabels)
                _CoachJourneyFactChip(
                  icon: switch (label) {
                    'QR' => Icons.qr_code_2_outlined,
                    'PDF' => Icons.picture_as_pdf_outlined,
                    _ => Icons.wallet_outlined,
                  },
                  label: label,
                ),
            ],
          ),
          if ((ticket.operatorTicketReference ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${isArabic ? 'مرجع المشغل' : 'Operator ref'}: ${ticket.operatorTicketReference}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (artifactSummary.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              artifactSummary,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _CoachJourneyCard extends StatelessWidget {
  final CoachJourneyOption journey;
  final String fromLabel;
  final String toLabel;
  final bool selected;
  final String Function(int minorUnits, String currency) moneyLabel;
  final bool isArabic;
  final VoidCallback onTap;

  const _CoachJourneyCard({
    required this.journey,
    required this.fromLabel,
    required this.toLabel,
    required this.selected,
    required this.moneyLabel,
    required this.isArabic,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Tokens.colorBus
        : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .5);
    final amenityLabels = journey.amenities
        .take(3)
        .map((amenity) => _coachMiniProgramAmenityLabel(amenity, isArabic))
        .toList(growable: false);
    final reviewLabel = selected
        ? (isArabic ? 'محدد' : 'Selected')
        : (isArabic ? 'راجع' : 'Review');
    return InkWell(
      onTap: _coachMiniProgramHandleTap(onTap),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
          color: Theme.of(context).colorScheme.surface,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 86,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _coachMiniProgramCompactTime(journey.departureAtIso),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _coachMiniProgramCompactTime(journey.arrivalAtIso),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _coachMiniProgramCompactDate(journey.departureAtIso),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _coachMiniProgramDurationLabel(
                          journey.durationMinutes,
                          isArabic,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$fromLabel → $toLabel',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${journey.operatorName} • ${journey.journeyId}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _CoachJourneyFactChip(
                            icon: Icons.alt_route_outlined,
                            label: _coachMiniProgramTransferLabel(
                              journey.transferCount,
                              isArabic,
                            ),
                          ),
                          _CoachJourneyFactChip(
                            icon: Icons.graphic_eq_outlined,
                            label: _coachMiniProgramLiveRunningLabel(
                              journey.live,
                              isArabic,
                            ),
                            highlighted: journey.live.delayMinutes > 0 ||
                                !journey.live.tripUpdatesFresh,
                          ),
                          _CoachJourneyFactChip(
                            icon: Icons.event_seat_outlined,
                            label: _coachMiniProgramSeatAvailabilityLabel(
                              journey.seatsAvailable,
                              journey.lowAvailability,
                              isArabic,
                            ),
                            highlighted: journey.lowAvailability,
                          ),
                          _CoachJourneyFactChip(
                            icon: Icons.sync_alt_outlined,
                            label: _coachMiniProgramIntegrationModeLabel(
                              journey.integrationMode,
                              isArabic,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      moneyLabel(
                        journey.priceFromMinorUnits,
                        journey.currency,
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Tokens.colorBus,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? Tokens.colorBus.withValues(alpha: .12)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        reviewLabel,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: selected
                                      ? Tokens.colorBus
                                      : Theme.of(context).colorScheme.onSurface,
                                ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (amenityLabels.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .25),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final amenity in amenityLabels)
                      _CoachJourneyFactChip(
                        icon: Icons.checkroom_outlined,
                        label: amenity,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .25),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle_outline
                        : Icons.receipt_long_outlined,
                    color: Tokens.colorBus,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected
                              ? (isArabic
                                  ? 'هذه هي الرحلة النشطة في المسودة'
                                  : 'This journey is active in the draft')
                              : (isArabic
                                  ? 'راجع العرض قبل فتح المسودة'
                                  : 'Review offer before opening the draft'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _coachMiniProgramCompactDateTimeRange(
                            journey.departureAtIso,
                            journey.arrivalAtIso,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected ? Icons.check : Icons.chevron_right,
                    color: selected
                        ? Tokens.colorBus
                        : Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoachBookingShelfCard extends StatelessWidget {
  final CoachBookingShelfEntry entry;
  final String Function(int minorUnits, String currency) moneyLabel;
  final bool isArabic;
  final VoidCallback onOpenDetails;
  final VoidCallback onOpenLiveJourney;
  final VoidCallback? onOpenChange;
  final VoidCallback? onOpenRefund;

  const _CoachBookingShelfCard({
    required this.entry,
    required this.moneyLabel,
    required this.isArabic,
    required this.onOpenDetails,
    required this.onOpenLiveJourney,
    required this.onOpenChange,
    required this.onOpenRefund,
  });

  @override
  Widget build(BuildContext context) {
    final seatSummary =
        entry.hold?.seatAssignments.map((seat) => seat.seatNumber).join(', ') ??
            '-';
    final title = '${entry.journey.from} → ${entry.journey.to}';
    final actionLabel = entry.tickets.isEmpty
        ? (isArabic ? 'راجع الحجز' : 'Review booking')
        : (isArabic ? 'افتح التذكرة' : 'Open ticket');
    final bookingStateLabel =
        _coachMiniProgramBookingStateLabel(entry.booking.state, isArabic);
    final passengerPreview = _coachMiniProgramPassengerPreviewLabel(
      entry.passengerManifests,
      isArabic,
    );
    final ticketPreview = entry.tickets.isEmpty
        ? (isArabic ? 'لا توجد أرقام تذاكر بعد.' : 'No ticket numbers yet.')
        : entry.tickets.map((ticket) => ticket.ticketId).join(', ');
    final travelDayActions = <Widget>[
      if (onOpenChange != null)
        _CoachActionListButton(
          title: isArabic ? 'غيّر الرحلة' : 'Change trip',
          subtitle: isArabic
              ? 'ابحث عن مغادرة بديلة وأعد الإصدار.'
              : 'Move to another departure and reissue.',
          icon: Icons.swap_horiz_outlined,
          onPressed: onOpenChange!,
        ),
      if (onOpenRefund != null)
        _CoachActionListButton(
          title: isArabic ? 'خيارات الاسترداد' : 'Refund options',
          subtitle: isArabic
              ? 'راجع الأهلية ورسوم الاسترداد.'
              : 'Review refund eligibility and fees.',
          icon: Icons.undo_outlined,
          onPressed: onOpenRefund!,
        ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _coachMiniProgramCompactTime(
                          entry.journey.departureAtIso,
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _coachMiniProgramCompactTime(
                          entry.journey.arrivalAtIso,
                        ),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _coachMiniProgramCompactDate(
                          entry.journey.departureAtIso,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${entry.journey.operatorName} • ${entry.journey.journeyId}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${isArabic ? 'الحجز' : 'Booking'} ${entry.booking.bookingId} • ${_coachMiniProgramBookingStateLabel(entry.booking.state, isArabic)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${isArabic ? 'الإجمالي' : 'Total'}: ${moneyLabel(entry.booking.totalMinorUnits, entry.booking.currency)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                Chip(label: Text(entry.journey.statusLabel)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .3),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CoachSectionHeader(
                    title: isArabic ? 'لوحة الرحلة' : 'Travel board',
                    subtitle: isArabic
                        ? 'الحالة الحالية، جاهزية التذاكر، والركاب في نظرة واحدة.'
                        : 'Current state, boarding readiness, and passengers at a glance.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CoachJourneyFactChip(
                        icon: Icons.departure_board_outlined,
                        label: entry.journey.statusLabel,
                        highlighted: entry.tickets.isNotEmpty,
                      ),
                      _CoachJourneyFactChip(
                        icon: Icons.receipt_long_outlined,
                        label: bookingStateLabel,
                      ),
                      _CoachJourneyFactChip(
                        icon: Icons.confirmation_num_outlined,
                        label: _coachMiniProgramTicketReadinessLabel(
                          entry.tickets.length,
                          isArabic,
                        ),
                        highlighted: entry.tickets.isNotEmpty,
                      ),
                      _CoachJourneyFactChip(
                        icon: Icons.event_seat_outlined,
                        label: seatSummary == '-'
                            ? (isArabic ? 'المقاعد لاحقاً' : 'Seats later')
                            : seatSummary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${isArabic ? 'المسافرون' : 'Passengers'}: $passengerPreview',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isArabic ? 'التذاكر' : 'Tickets'}: $ticketPreview',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 560;
                final primaryAction = FilledButton.icon(
                  onPressed: _coachMiniProgramHandleTap(onOpenDetails),
                  icon: Icon(
                    entry.tickets.isEmpty
                        ? Icons.receipt_long_outlined
                        : Icons.confirmation_num_outlined,
                  ),
                  label: Text(actionLabel),
                );
                final liveAction = FilledButton.tonalIcon(
                  onPressed: _coachMiniProgramHandleTap(onOpenLiveJourney),
                  icon: const Icon(Icons.departure_board_outlined),
                  label: Text(isArabic ? 'رحلة اليوم' : 'Live journey'),
                );
                if (stacked) {
                  return Column(
                    children: [
                      SizedBox(width: double.infinity, child: primaryAction),
                      const SizedBox(height: 8),
                      SizedBox(width: double.infinity, child: liveAction),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: primaryAction),
                    const SizedBox(width: 8),
                    Expanded(child: liveAction),
                  ],
                );
              },
            ),
            if (travelDayActions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _CoachSectionHeader(
                title: isArabic ? 'إجراءات يوم السفر' : 'Travel day actions',
                subtitle: isArabic
                    ? 'التغيير أو الاسترداد يبقيان قريبين من الرحلة الحالية.'
                    : 'Change and refund stay close to the current trip.',
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    for (var index = 0;
                        index < travelDayActions.length;
                        index++)
                      Column(
                        children: [
                          travelDayActions[index],
                          if (index < travelDayActions.length - 1)
                            Divider(
                              height: 1,
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: .45),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachJourneyLiveSheet extends StatefulWidget {
  final CoachMobilityApi api;
  final CoachBookingShelfEntry entry;
  final bool isArabic;
  final String Function(int minorUnits, String currency) moneyLabel;

  const _CoachJourneyLiveSheet({
    required this.api,
    required this.entry,
    required this.isArabic,
    required this.moneyLabel,
  });

  @override
  State<_CoachJourneyLiveSheet> createState() => _CoachJourneyLiveSheetState();
}

class _CoachJourneyLiveSheetState extends State<_CoachJourneyLiveSheet> {
  CoachJourneyLiveResponse? _response;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          await widget.api.getJourneyLive(widget.entry.journey.journeyId);
      if (!mounted) return;
      setState(() {
        _response = response;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _isoLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '-';
    return _coachMiniProgramCompactDateTime(value);
  }

  List<String> _ticketArtifactLabels(CoachTicketCoupon ticket) {
    return <String>[
      if (ticket.qrPayloadRef != null && ticket.qrPayloadRef!.isNotEmpty) 'QR',
      if (ticket.artifactByKind('wallet_pass') != null)
        widget.isArabic ? 'محفظة' : 'Wallet',
      if (ticket.artifactByKind('pdf') != null) 'PDF',
    ];
  }

  String _ticketArtifactsSummary(CoachTicketCoupon ticket) {
    final parts = <String>[
      '${widget.isArabic ? 'أُصدرت' : 'Issued'} ${_coachMiniProgramCompactDateTime(ticket.issuedAtIso)}',
    ];
    if (ticket.qrPayloadRef != null && ticket.qrPayloadRef!.isNotEmpty) {
      parts.add('QR ${ticket.qrPayloadRef}');
    }
    final walletArtifact = ticket.artifactByKind('wallet_pass');
    if (walletArtifact != null) {
      parts.add(
        '${widget.isArabic ? 'محفظة' : 'Wallet'} ${walletArtifact.downloadPath}',
      );
    }
    final pdfArtifact = ticket.artifactByKind('pdf');
    if (pdfArtifact != null) {
      parts.add('PDF ${pdfArtifact.downloadPath}');
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final response = _response;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isArabic ? 'رحلة اليوم' : 'Live journey',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.entry.journey.from} → ${widget.entry.journey.to}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.entry.booking.bookingId} • ${widget.entry.journey.operatorName}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(label: Text(widget.entry.journey.statusLabel)),
                      Chip(
                        label: Text(
                          '${widget.isArabic ? 'الإجمالي' : 'Total'} ${widget.moneyLabel(widget.entry.booking.totalMinorUnits, widget.entry.booking.currency)}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              StatusBanner.error(_error!),
              const SizedBox(height: 12),
            ],
            if (!_loading && response == null)
              OutlinedButton.icon(
                onPressed: _coachMiniProgramHandleTap(_load),
                icon: const Icon(Icons.refresh),
                label: Text(widget.isArabic ? 'أعد المحاولة' : 'Retry'),
              ),
            if (response != null) ...[
              _CoachSectionHeader(
                title: widget.isArabic ? 'لوحة يوم السفر' : 'Travel day board',
                subtitle: widget.isArabic
                    ? 'البوابة، المركبة، وتقدم الصعود لهذه الرحلة.'
                    : 'Gate, vehicle, and boarding progress for this departure.',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 84,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _coachMiniProgramCompactTime(
                              response.trip.departureAtIso,
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _coachMiniProgramCompactTime(
                              response.trip.arrivalAtIso,
                            ),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _coachMiniProgramCompactDate(
                              response.trip.departureAtIso,
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${response.journey.from} → ${response.journey.to}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${response.trip.operatorName} • ${response.trip.tripId}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              Chip(label: Text(response.journey.statusLabel)),
                              Chip(
                                label: Text(
                                  '${widget.isArabic ? 'الصعود' : 'Boarding'} ${_coachMiniProgramJourneyWindow(response.trip.boardingOpensAtIso, response.trip.boardingClosesAtIso)}',
                                ),
                              ),
                              Chip(
                                label: Text(
                                  _coachMiniProgramBookingStateLabel(
                                    response.booking.state,
                                    widget.isArabic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _CoachSectionHeader(
                title: widget.isArabic ? 'لوحة التشغيل' : 'Operations board',
                subtitle: widget.isArabic
                    ? 'البوابة، المركبة، والتقدم التشغيلي في نظرة واحدة.'
                    : 'Gate, vehicle, and boarding progress in one operational view.',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CoachJourneyFactChip(
                          icon: Icons.departure_board_outlined,
                          label: response.trip.gateLabel,
                        ),
                        _CoachJourneyFactChip(
                          icon: Icons.directions_bus_outlined,
                          label: response.trip.vehicleLabel,
                        ),
                        _CoachJourneyFactChip(
                          icon: Icons.people_alt_outlined,
                          label: _coachMiniProgramManifestProgressLabel(
                            response.trip.boardedCount,
                            response.trip.manifestCount,
                            widget.isArabic,
                          ),
                          highlighted: response.trip.boardedCount > 0,
                        ),
                        _CoachJourneyFactChip(
                          icon: Icons.hourglass_bottom_outlined,
                          label:
                              '${widget.isArabic ? 'بانتظار' : 'Waiting'} ${response.trip.pendingCount}',
                        ),
                        _CoachJourneyFactChip(
                          icon: Icons.block_outlined,
                          label:
                              '${widget.isArabic ? 'مرفوض' : 'Denied'} ${response.trip.deniedCount}',
                          highlighted: response.trip.deniedCount > 0,
                        ),
                        _CoachJourneyFactChip(
                          icon: Icons.person_off_outlined,
                          label:
                              '${widget.isArabic ? 'لم يحضر' : 'No-show'} ${response.trip.noShowCount}',
                          highlighted: response.trip.noShowCount > 0,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${widget.isArabic ? 'الصعود' : 'Boarding'} ${_coachMiniProgramJourneyWindow(response.trip.boardingOpensAtIso, response.trip.boardingClosesAtIso)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.isArabic ? 'الحجز' : 'Booking'} ${response.booking.bookingId} • ${_coachMiniProgramBookingStateLabel(response.booking.state, widget.isArabic)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.isArabic ? 'الإجمالي' : 'Total'}: ${widget.moneyLabel(response.booking.totalMinorUnits, response.booking.currency)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _CoachSectionHeader(
                title: widget.isArabic
                    ? 'المسافرون والتذاكر'
                    : 'Passengers and tickets',
                subtitle: widget.isArabic
                    ? 'بيان الركاب والتذاكر الجاهزة للفحص أو العرض.'
                    : 'Manifest and ticket passes ready for inspection.',
              ),
              const SizedBox(height: 8),
              _PreviewTile(
                title: widget.isArabic ? 'المسافرون' : 'Passengers',
                lines: response.passengerManifests.isEmpty
                    ? <String>[
                        widget.isArabic
                            ? 'لا يوجد بيان ركاب محفوظ بعد.'
                            : 'No saved passenger manifest yet.',
                      ]
                    : response.passengerManifests
                        .map(
                          (passenger) =>
                              '${passenger.displayName} • ${_coachMiniProgramRiderCategoryLabel(passenger.riderCategory, widget.isArabic)}${passenger.nationalityCode == null ? '' : ' • ${passenger.nationalityCode}'}',
                        )
                        .toList(growable: false),
              ),
              const SizedBox(height: 12),
              if (response.tickets.isEmpty)
                _PreviewTile(
                  title: widget.isArabic ? 'التذاكر' : 'Tickets',
                  lines: <String>[
                    widget.isArabic
                        ? 'لم يتم إصدار التذاكر بعد.'
                        : 'Tickets have not been issued yet.',
                  ],
                )
              else ...[
                for (var index = 0;
                    index < response.tickets.length && index < 2;
                    index++) ...[
                  _CoachIssuedTicketCard(
                    ticket: response.tickets[index],
                    isArabic: widget.isArabic,
                    passengerDisplayName: response.passengerManifests
                        .where(
                          (passenger) =>
                              passenger.passengerId ==
                              response.tickets[index].passengerId,
                        )
                        .map((passenger) => passenger.displayName)
                        .join(),
                    artifactLabels: _ticketArtifactLabels(
                      response.tickets[index],
                    ),
                    artifactSummary: _ticketArtifactsSummary(
                      response.tickets[index],
                    ),
                  ),
                  if (index < response.tickets.length - 1 && index < 1)
                    const SizedBox(height: 8),
                ],
                if (response.tickets.length > 2) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      widget.isArabic
                          ? '+${response.tickets.length - 2} تذاكر إضافية في هذه الرحلة'
                          : '+${response.tickets.length - 2} more tickets on this trip',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              _CoachSectionHeader(
                title: widget.isArabic ? 'أحداث المحطة' : 'Platform events',
                subtitle: widget.isArabic
                    ? 'آخر المسوحات وحالة المزامنة التشغيلية.'
                    : 'Latest scans and operating feed status.',
              ),
              const SizedBox(height: 8),
              if (response.recentEvents.isEmpty)
                _PreviewTile(
                  title: widget.isArabic ? 'آخر الأحداث' : 'Recent events',
                  lines: <String>[
                    widget.isArabic
                        ? 'لا توجد أحداث صعود حتى الآن.'
                        : 'No boarding events yet.',
                  ],
                )
              else
                for (var index = 0;
                    index < response.recentEvents.length;
                    index++) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: .3),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_isoLabel(response.recentEvents[index].capturedAtIso)} • ${_coachMiniProgramScanStatusLabel(response.recentEvents[index].scanStatus, widget.isArabic)}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.isArabic ? 'التذكرة' : 'Ticket'} ${response.recentEvents[index].ticketId}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if ((response.recentEvents[index].note ?? '')
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            response.recentEvents[index].note!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (index < response.recentEvents.length - 1)
                    const SizedBox(height: 8),
                ],
              if (response.operatorFeedHealth.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isArabic ? 'تغذيات التشغيل' : 'Operator health',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final feed in response.operatorFeedHealth)
                            _CoachJourneyFactChip(
                              icon: Icons.graphic_eq_outlined,
                              label:
                                  '${_coachMiniProgramFeedKindLabel(feed.feedKind, widget.isArabic)} ${_coachMiniProgramStatusWord(feed.syncStatus, widget.isArabic)}/${_coachMiniProgramStatusWord(feed.freshnessStatus, widget.isArabic)}',
                              highlighted: feed.syncStatus != 'ok' ||
                                  feed.freshnessStatus != 'fresh',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachChangeSheet extends StatefulWidget {
  final CoachMobilityApi api;
  final CoachBookingShelfEntry entry;
  final bool isArabic;
  final String Function(int minorUnits, String currency) moneyLabel;
  final ValueChanged<CoachSelfServiceReissueResult> onReissued;

  const _CoachChangeSheet({
    required this.api,
    required this.entry,
    required this.isArabic,
    required this.moneyLabel,
    required this.onReissued,
  });

  @override
  State<_CoachChangeSheet> createState() => _CoachChangeSheetState();
}

class _CoachChangeSheetState extends State<_CoachChangeSheet> {
  late final TextEditingController _reasonController;
  late final TextEditingController _seatNumbersController;
  CoachChangeOptionsResponse? _options;
  CoachSelfServiceReissueResult? _reissueResult;
  String _paymentMethod = 'card';
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController(
      text:
          widget.isArabic ? 'الانتقال إلى وقت آخر' : 'move to midday departure',
    );
    _seatNumbersController = TextEditingController(text: '5A, 5B');
    _loadOptions();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _seatNumbersController.dispose();
    super.dispose();
  }

  List<String>? _preferredSeatNumbers() {
    final normalized = _seatNumbersController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return normalized.isEmpty ? null : normalized;
  }

  bool _isDirectReissueOption(CoachChangeOption option) =>
      option.totalDueMinorUnits == 0;

  bool _requiresPayment(CoachChangeOption option) =>
      option.totalDueMinorUnits > 0;

  bool _isCompletedReissue(CoachSelfServiceReissueResult result) =>
      result.changeRequest.status == 'reissued' &&
      result.nextAction == 'completed';

  bool _isPaymentFailedReissue(CoachSelfServiceReissueResult result) =>
      result.changeRequest.status == 'payment_failed' ||
      result.payment?.status == 'failed';

  bool _canResolvePaymentFailure(CoachSelfServiceReissueResult result) =>
      _isPaymentFailedReissue(result) &&
      result.nextAction == 'resolve_payment_failure';

  List<String> _deliveryChannels() => const <String>['wallet_pass', 'pdf'];

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final options =
          await widget.api.getChangeOptions(widget.entry.booking.bookingId);
      setState(() {
        _options = options;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _submitRebook(CoachChangeOption option) async {
    setState(() {
      _submitting = true;
      _error = null;
      _reissueResult = null;
    });
    try {
      final result = await widget.api.selfServiceReissue(
        bookingId: widget.entry.booking.bookingId,
        targetOfferId: option.targetOfferId,
        preferredSeatNumbers: _preferredSeatNumbers(),
        deliveryChannels: _deliveryChannels(),
        paymentMethod: _requiresPayment(option) ? _paymentMethod : null,
        reason: _reasonController.text.trim(),
      );
      if (_isCompletedReissue(result)) {
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentSent));
        widget.onReissued(result);
      }
      setState(() {
        _reissueResult = result;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _resolvePaymentFailure() async {
    final result = _reissueResult;
    if (result == null || !_canResolvePaymentFailure(result)) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final resolved = await widget.api.resolveReissuePaymentFailure(
        bookingId: widget.entry.booking.bookingId,
        paymentMethod: _paymentMethod,
        deliveryChannels: _deliveryChannels(),
      );
      if (_isCompletedReissue(resolved)) {
        unawaited(ShamellSoundEffects.play(ShamellSoundEffect.paymentSent));
        widget.onReissued(resolved);
      }
      setState(() {
        _reissueResult = resolved;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _options;
    final payableOptionCount =
        options?.eligibility.options.where(_requiresPayment).length ?? 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isArabic ? 'خيارات تغيير الرحلة' : 'Change trip options',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.entry.journey.from} → ${widget.entry.journey.to}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.entry.booking.bookingId} • ${widget.entry.journey.operatorName}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _coachMiniProgramCompactDateTimeRange(
                      widget.entry.journey.departureAtIso,
                      widget.entry.journey.arrivalAtIso,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          '${widget.isArabic ? 'الحالة' : 'State'} ${_coachMiniProgramBookingStateLabel(widget.entry.booking.state, widget.isArabic)}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${widget.isArabic ? 'الإجمالي' : 'Total'} ${widget.moneyLabel(widget.entry.booking.totalMinorUnits, widget.entry.booking.currency)}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              StatusBanner.error(_error!),
              const SizedBox(height: 12),
            ],
            if (options != null) ...[
              _CoachSectionHeader(
                title: widget.isArabic ? 'لوحة التغيير' : 'Change board',
                subtitle: widget.isArabic
                    ? 'قابلية التغيير، آخر موعد، والبدائل الظاهرة لهذه الرحلة.'
                    : 'Changeability, cutoff, and the visible alternatives for this trip.',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CoachJourneyFactChip(
                      icon: Icons.receipt_long_outlined,
                      label: _coachMiniProgramBookingStateLabel(
                        options.booking.state,
                        widget.isArabic,
                      ),
                    ),
                    _CoachJourneyFactChip(
                      icon: Icons.schedule_outlined,
                      label: options.eligibility.changeCutoffAtIso == null
                          ? (widget.isArabic ? 'بدون موعد نهائي' : 'No cutoff')
                          : '${widget.isArabic ? 'حتى' : 'Until'} ${_coachMiniProgramCompactDateTime(options.eligibility.changeCutoffAtIso!)}',
                      highlighted: !options.eligibility.changeable,
                    ),
                    _CoachJourneyFactChip(
                      icon: Icons.alt_route_outlined,
                      label:
                          '${widget.isArabic ? 'بدائل' : 'Alternatives'} ${options.eligibility.options.length}',
                    ),
                    _CoachJourneyFactChip(
                      icon: Icons.payments_outlined,
                      label:
                          '${widget.isArabic ? 'تحتاج دفعاً' : 'Need payment'} $payableOptionCount',
                      highlighted: payableOptionCount > 0,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _CoachSectionHeader(
                title: widget.isArabic ? 'إعداد التغيير' : 'Change setup',
                subtitle: widget.isArabic
                    ? 'اختر المقاعد الجديدة، السبب، وطريقة الدفع عند الحاجة.'
                    : 'Choose new seats, a reason, and payment when needed.',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _seatNumbersController,
                      decoration: InputDecoration(
                        labelText: widget.isArabic
                            ? 'المقاعد المفضلة الجديدة'
                            : 'New preferred seats',
                        hintText: '5A, 5B',
                        prefixIcon: const Icon(Icons.event_seat_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reasonController,
                      decoration: InputDecoration(
                        labelText:
                            widget.isArabic ? 'سبب التغيير' : 'Change reason',
                        prefixIcon: const Icon(Icons.notes_outlined),
                      ),
                    ),
                    if (options.eligibility.options.any(_requiresPayment)) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration: InputDecoration(
                          labelText: widget.isArabic
                              ? 'طريقة الدفع'
                              : 'Payment method',
                          prefixIcon: const Icon(Icons.payments_outlined),
                        ),
                        items: <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(
                            value: 'card',
                            child: Text(widget.isArabic ? 'بطاقة' : 'Card'),
                          ),
                          DropdownMenuItem<String>(
                            value: 'wallet_credit',
                            child: Text(
                              widget.isArabic
                                  ? 'رصيد المحفظة'
                                  : 'Wallet credit',
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'split_tender',
                            child: Text(
                              widget.isArabic ? 'دفع مختلط' : 'Split tender',
                            ),
                          ),
                        ],
                        onChanged: _submitting
                            ? null
                            : (value) {
                                if (value == null || value.isEmpty) return;
                                setState(() {
                                  _paymentMethod = value;
                                });
                              },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!options.eligibility.changeable)
                StatusBanner.warning(
                  options.eligibility.reason ??
                      (widget.isArabic
                          ? 'هذا الحجز غير مؤهل للتغيير الذاتي.'
                          : 'This booking is not eligible for self-service changes.'),
                )
              else ...[
                _CoachSectionHeader(
                  title: widget.isArabic
                      ? 'البدائل المتاحة'
                      : 'Available alternatives',
                  subtitle: widget.isArabic
                      ? 'قارن الوقت والمبلغ المستحق ثم أعد الإصدار.'
                      : 'Compare timing and due amount before reissuing.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CoachMetricChip(
                      icon: Icons.alt_route_outlined,
                      label: widget.isArabic ? 'البدائل' : 'Alternatives',
                      value: '${options.eligibility.options.length}',
                    ),
                    _CoachMetricChip(
                      icon: Icons.payments_outlined,
                      label: widget.isArabic ? 'تحتاج دفعاً' : 'Need payment',
                      value:
                          '${options.eligibility.options.where(_requiresPayment).length}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final option in options.eligibility.options) ...[
                  _CoachDecisionCard(
                    title:
                        '${_coachMiniProgramCompactTime(option.departureAtIso)} - ${_coachMiniProgramCompactTime(option.arrivalAtIso)}',
                    subtitle:
                        '${option.journeyId} • ${_coachMiniProgramCompactDate(option.departureAtIso)}',
                    amountLabel: option.totalDueMinorUnits == 0
                        ? (widget.isArabic ? 'بدون فرق' : 'No extra fare')
                        : widget.moneyLabel(
                            option.totalDueMinorUnits,
                            option.currency,
                          ),
                    icon: Icons.swap_horiz_outlined,
                    badgeLabels: <String>[
                      '${widget.isArabic ? 'فرق السعر' : 'Fare diff'} ${widget.moneyLabel(option.fareDifferenceMinorUnits, option.currency)}',
                      '${widget.isArabic ? 'رسوم التغيير' : 'Change fee'} ${widget.moneyLabel(option.changeFeeMinorUnits, option.currency)}',
                      option.seatMapAvailable
                          ? (widget.isArabic
                              ? 'خريطة المقاعد متاحة'
                              : 'Seat map available')
                          : (widget.isArabic
                              ? 'بدون خريطة مقاعد'
                              : 'No seat map'),
                      '${widget.isArabic ? 'صالح حتى' : 'Valid until'} ${_coachMiniProgramCompactDateTime(option.expiresAtIso)}',
                    ],
                    actionLabel: _isDirectReissueOption(option)
                        ? (widget.isArabic ? 'أعد الإصدار الآن' : 'Reissue now')
                        : (widget.isArabic
                            ? 'ادفع وأعد الإصدار'
                            : 'Pay and reissue'),
                    actionIcon: Icons.swap_horiz_outlined,
                    onPressed: _submitting ? null : () => _submitRebook(option),
                    loading: _submitting,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
            if (_reissueResult != null) ...[
              const SizedBox(height: 12),
              if (_isCompletedReissue(_reissueResult!))
                StatusBanner.success(
                  widget.isArabic
                      ? 'تمت إعادة إصدار التذاكر.'
                      : 'Tickets reissued.',
                )
              else if (_isPaymentFailedReissue(_reissueResult!))
                StatusBanner.error(
                  widget.isArabic
                      ? 'تعذر تحصيل الدفع لهذا التغيير.'
                      : 'Payment could not be collected for this change.',
                )
              else
                StatusBanner.warning(
                  widget.isArabic
                      ? 'تم تسجيل التغيير لكنه ما زال يحتاج متابعة.'
                      : 'The change was recorded but still needs follow-up.',
                ),
              const SizedBox(height: 12),
              _CoachSectionHeader(
                title:
                    widget.isArabic ? 'نتيجة إعادة الإصدار' : 'Reissue result',
                subtitle: widget.isArabic
                    ? 'الحالة النهائية للدفع والتذاكر الجديدة.'
                    : 'Final state for payment and replacement tickets.',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CoachJourneyFactChip(
                      icon: Icons.swap_horiz_outlined,
                      label: _coachMiniProgramStatusWord(
                        _reissueResult!.changeRequest.status,
                        widget.isArabic,
                      ),
                      highlighted: _isCompletedReissue(_reissueResult!),
                    ),
                    _CoachJourneyFactChip(
                      icon: Icons.arrow_forward_outlined,
                      label: _coachMiniProgramStatusWord(
                        _reissueResult!.nextAction,
                        widget.isArabic,
                      ),
                    ),
                    if (_reissueResult!.payment != null)
                      _CoachJourneyFactChip(
                        icon: Icons.payments_outlined,
                        label:
                            '${_coachMiniProgramStatusWord(_reissueResult!.payment!.status, widget.isArabic)} • ${_coachMiniProgramPaymentMethodLabel(_reissueResult!.payment!.method, widget.isArabic)}',
                        highlighted:
                            _reissueResult!.payment!.status == 'authorized',
                      ),
                    _CoachJourneyFactChip(
                      icon: Icons.confirmation_num_outlined,
                      label:
                          '${widget.isArabic ? 'تذاكر' : 'Tickets'} ${_reissueResult!.tickets.length}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _PreviewTile(
                title: widget.isArabic ? 'إعادة الإصدار' : 'Reissue',
                lines: [
                  _reissueResult!.changeRequest.changeRequestId,
                  '${widget.isArabic ? 'حالة التغيير' : 'Change status'}: ${_coachMiniProgramStatusWord(_reissueResult!.changeRequest.status, widget.isArabic)}',
                  '${widget.isArabic ? 'العرض الجديد' : 'Target offer'}: ${_reissueResult!.changeRequest.targetOfferId}',
                  '${widget.isArabic ? 'القنوات' : 'Delivery'}: ${_reissueResult!.deliveryChannels.join(', ')}',
                  if (_reissueResult!.payment != null)
                    '${widget.isArabic ? 'الدفع' : 'Payment'}: ${_coachMiniProgramStatusWord(_reissueResult!.payment!.status, widget.isArabic)} • ${_coachMiniProgramPaymentMethodLabel(_reissueResult!.payment!.method, widget.isArabic)} • ${widget.moneyLabel(_reissueResult!.payment!.chargedMinorUnits, _reissueResult!.payment!.currency)}',
                  '${widget.isArabic ? 'التعويض' : 'Compensation'}: ${_coachMiniProgramCompensationActionLabel(_reissueResult!.compensation.action, widget.isArabic)}',
                  if ((_reissueResult!.compensation.reason ?? '').isNotEmpty)
                    '${widget.isArabic ? 'السبب' : 'Reason'}: ${_reissueResult!.compensation.reason}',
                  '${widget.isArabic ? 'التذاكر الجديدة' : 'New tickets'}: ${_reissueResult!.tickets.map((ticket) => ticket.ticketId).join(', ')}',
                  '${widget.isArabic ? 'التالي' : 'Next action'}: ${_coachMiniProgramStatusWord(_reissueResult!.nextAction, widget.isArabic)}',
                ],
              ),
              if (_canResolvePaymentFailure(_reissueResult!)) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _submitting
                      ? null
                      : _coachMiniProgramHandleTap(_resolvePaymentFailure),
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_outlined),
                  label: Text(widget.isArabic
                      ? 'أعد محاولة التحصيل وإعادة الإصدار'
                      : 'Retry collection and reissue'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CoachRefundSheet extends StatefulWidget {
  final CoachMobilityApi api;
  final CoachBookingShelfEntry entry;
  final bool isArabic;
  final String Function(int minorUnits, String currency) moneyLabel;
  final ValueChanged<CoachRefundRequestResult> onRefundRequested;

  const _CoachRefundSheet({
    required this.api,
    required this.entry,
    required this.isArabic,
    required this.moneyLabel,
    required this.onRefundRequested,
  });

  @override
  State<_CoachRefundSheet> createState() => _CoachRefundSheetState();
}

class _CoachRefundSheetState extends State<_CoachRefundSheet> {
  late final TextEditingController _reasonController;
  CoachRefundEligibilityResponse? _eligibility;
  CoachRefundRequestResult? _result;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController(
      text: widget.isArabic ? 'تغيير خطط السفر' : 'customer changed plans',
    );
    _loadEligibility();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadEligibility() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final eligibility =
          await widget.api.getRefundEligibility(widget.entry.booking.bookingId);
      setState(() {
        _eligibility = eligibility;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _submitRefund(CoachRefundOption option) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.api.requestRefund(
        bookingId: widget.entry.booking.bookingId,
        refundKind: option.kind,
        ticketIds: widget.entry.tickets
            .map((ticket) => ticket.ticketId)
            .toList(growable: false),
        reason: _reasonController.text.trim(),
      );
      unawaited(ShamellSoundEffects.play(ShamellSoundEffect.success));
      widget.onRefundRequested(result);
      setState(() {
        _result = result;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
      });
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  String _refundButtonLabel(CoachRefundOption option) {
    if (widget.isArabic) {
      return option.kind == CoachRefundKind.refundCredit
          ? 'اطلب رصيد سفر'
          : 'اطلب ردًا للدفعة الأصلية';
    }
    return option.kind == CoachRefundKind.refundCredit
        ? 'Request travel credit'
        : 'Request original payment refund';
  }

  @override
  Widget build(BuildContext context) {
    final eligibility = _eligibility;
    final recommendedKindLabel =
        eligibility?.eligibility.recommendedKind == null
            ? null
            : _coachMiniProgramRefundKindLabel(
                eligibility!.eligibility.recommendedKind!,
                widget.isArabic,
              );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isArabic ? 'خيارات الاسترداد' : 'Refund options',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.entry.journey.from} → ${widget.entry.journey.to}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.entry.booking.bookingId} • ${widget.entry.journey.operatorName}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _coachMiniProgramCompactDateTimeRange(
                      widget.entry.journey.departureAtIso,
                      widget.entry.journey.arrivalAtIso,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        label: Text(
                          '${widget.isArabic ? 'الحالة' : 'State'} ${_coachMiniProgramBookingStateLabel(widget.entry.booking.state, widget.isArabic)}',
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${widget.isArabic ? 'التذاكر' : 'Tickets'} ${widget.entry.tickets.length}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) ...[
              StatusBanner.error(_error!),
              const SizedBox(height: 12),
            ],
            if (eligibility != null) ...[
              _CoachSectionHeader(
                title: widget.isArabic ? 'لوحة الاسترداد' : 'Refund board',
                subtitle: widget.isArabic
                    ? 'حالة الاسترداد، آخر موعد، والخيار الموصى به لهذه الرحلة.'
                    : 'Refund state, cutoff, and the recommended path for this trip.',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CoachJourneyFactChip(
                      icon: Icons.receipt_long_outlined,
                      label: _coachMiniProgramBookingStateLabel(
                        eligibility.booking.state,
                        widget.isArabic,
                      ),
                    ),
                    _CoachJourneyFactChip(
                      icon: Icons.schedule_outlined,
                      label: eligibility.eligibility.refundCutoffAtIso == null
                          ? (widget.isArabic ? 'بدون موعد نهائي' : 'No cutoff')
                          : '${widget.isArabic ? 'حتى' : 'Until'} ${_coachMiniProgramCompactDateTime(eligibility.eligibility.refundCutoffAtIso!)}',
                      highlighted: !eligibility.eligibility.refundable,
                    ),
                    _CoachJourneyFactChip(
                      icon: Icons.undo_outlined,
                      label:
                          '${widget.isArabic ? 'خيارات' : 'Options'} ${eligibility.eligibility.options.length}',
                    ),
                    _CoachJourneyFactChip(
                      icon: Icons.gpp_good_outlined,
                      label: _coachMiniProgramBooleanRequirementLabel(
                        eligibility.eligibility.ticketsVoidRequired,
                        widget.isArabic,
                      ),
                    ),
                    if (recommendedKindLabel != null)
                      _CoachJourneyFactChip(
                        icon: Icons.recommend_outlined,
                        label: recommendedKindLabel,
                        highlighted: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _CoachSectionHeader(
                title: widget.isArabic ? 'إعداد الاسترداد' : 'Refund setup',
                subtitle: widget.isArabic
                    ? 'راجع الأهلية ثم اختر نوع الاسترداد المناسب.'
                    : 'Review eligibility and choose the right refund path.',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TextField(
                  controller: _reasonController,
                  decoration: InputDecoration(
                    labelText:
                        widget.isArabic ? 'سبب الاسترداد' : 'Refund reason',
                    prefixIcon: const Icon(Icons.notes_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!eligibility.eligibility.refundable)
                StatusBanner.warning(
                  eligibility.eligibility.reason ??
                      (widget.isArabic
                          ? 'هذه الحجز غير مؤهل للاسترداد الذاتي.'
                          : 'This booking is not eligible for self-service refunds.'),
                )
              else ...[
                _CoachSectionHeader(
                  title: widget.isArabic
                      ? 'خيارات الاسترداد المتاحة'
                      : 'Available refund options',
                  subtitle: widget.isArabic
                      ? 'قارن المبلغ والرسوم قبل إرسال الطلب.'
                      : 'Compare amount and fees before submitting.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CoachMetricChip(
                      icon: Icons.undo_outlined,
                      label: widget.isArabic ? 'الخيارات' : 'Options',
                      value: '${eligibility.eligibility.options.length}',
                    ),
                    if (eligibility.eligibility.recommendedKind != null)
                      _CoachMetricChip(
                        icon: Icons.recommend_outlined,
                        label: widget.isArabic ? 'الموصى به' : 'Recommended',
                        value: _coachMiniProgramRefundKindLabel(
                          eligibility.eligibility.recommendedKind!,
                          widget.isArabic,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final option in eligibility.eligibility.options) ...[
                  _CoachDecisionCard(
                    title: option.label,
                    subtitle: _coachMiniProgramRefundKindLabel(
                      option.kind,
                      widget.isArabic,
                    ),
                    amountLabel: widget.moneyLabel(
                      option.refundMinorUnits,
                      option.currency,
                    ),
                    icon: Icons.undo_outlined,
                    badgeLabels: <String>[
                      if (eligibility.eligibility.recommendedKind ==
                          option.kind)
                        (widget.isArabic ? 'موصى به' : 'Recommended'),
                      '${widget.isArabic ? 'الرسوم' : 'Fee'} ${widget.moneyLabel(option.feeMinorUnits, option.currency)}',
                      '${widget.isArabic ? 'الانتهاء' : 'Expiry'} ${option.expiresAtIso == null ? '-' : _coachMiniProgramCompactDateTime(option.expiresAtIso!)}',
                    ],
                    actionLabel: _refundButtonLabel(option),
                    actionIcon: Icons.undo_outlined,
                    onPressed: _submitting ? null : () => _submitRefund(option),
                    loading: _submitting,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              StatusBanner.success(
                widget.isArabic
                    ? 'تم إرسال طلب الاسترداد.'
                    : 'Refund request submitted.',
              ),
              const SizedBox(height: 12),
              _CoachSectionHeader(
                title: widget.isArabic ? 'نتيجة الطلب' : 'Refund result',
                subtitle: widget.isArabic
                    ? 'تم تسجيل الطلب والإجراء التالي ظاهر أدناه.'
                    : 'The request has been recorded and the next step is shown below.',
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: .3),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CoachJourneyFactChip(
                      icon: Icons.undo_outlined,
                      label: _coachMiniProgramStatusWord(
                        coachRefundKindWireValue(
                          _result!.refundRequest.selectedKind,
                        ),
                        widget.isArabic,
                      ),
                      highlighted: true,
                    ),
                    _CoachJourneyFactChip(
                      icon: Icons.payments_outlined,
                      label: widget.moneyLabel(
                        _result!.refundRequest.requestedMinorUnits,
                        _result!.refundRequest.currency,
                      ),
                    ),
                    _CoachJourneyFactChip(
                      icon: Icons.arrow_forward_outlined,
                      label: _coachMiniProgramStatusWord(
                        _result!.nextAction,
                        widget.isArabic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _PreviewTile(
                title: widget.isArabic ? 'طلب الاسترداد' : 'Refund request',
                lines: [
                  _result!.refundRequest.refundRequestId,
                  '${widget.isArabic ? 'النوع' : 'Kind'}: ${_coachMiniProgramStatusWord(coachRefundKindWireValue(_result!.refundRequest.selectedKind), widget.isArabic)}',
                  '${widget.isArabic ? 'المبلغ' : 'Amount'}: ${widget.moneyLabel(_result!.refundRequest.requestedMinorUnits, _result!.refundRequest.currency)}',
                  '${widget.isArabic ? 'التالي' : 'Next action'}: ${_coachMiniProgramStatusWord(_result!.nextAction, widget.isArabic)}',
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CheckoutDraftCard extends StatelessWidget {
  final bool isArabic;
  final TextEditingController contactEmailController;
  final String paymentMethod;
  final ValueChanged<String?> onPaymentMethodChanged;
  final List<TextEditingController> passengerIdControllers;
  final List<TextEditingController> passengerGivenNameControllers;
  final List<TextEditingController> passengerFamilyNameControllers;
  final List<TextEditingController> passengerNationalityControllers;
  final List<CoachPassengerRiderCategory> passengerCategories;
  final void Function(int index, CoachPassengerRiderCategory category)
      onPassengerCategoryChanged;
  final List<TextEditingController> preferredSeatControllers;
  final bool deliverWalletPass;
  final bool deliverPdf;
  final bool deliverEmail;
  final ValueChanged<bool> onDeliverWalletPassChanged;
  final ValueChanged<bool> onDeliverPdfChanged;
  final ValueChanged<bool> onDeliverEmailChanged;

  const _CheckoutDraftCard({
    required this.isArabic,
    required this.contactEmailController,
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    required this.passengerIdControllers,
    required this.passengerGivenNameControllers,
    required this.passengerFamilyNameControllers,
    required this.passengerNationalityControllers,
    required this.passengerCategories,
    required this.onPassengerCategoryChanged,
    required this.preferredSeatControllers,
    required this.deliverWalletPass,
    required this.deliverPdf,
    required this.deliverEmail,
    required this.onDeliverWalletPassChanged,
    required this.onDeliverPdfChanged,
    required this.onDeliverEmailChanged,
  });

  @override
  Widget build(BuildContext context) {
    final contactEmail = contactEmailController.text.trim();
    final deliveryLabels = <String>[
      if (deliverWalletPass) isArabic ? 'محفظة' : 'Wallet pass',
      if (deliverPdf) 'PDF',
      if (deliverEmail) isArabic ? 'بريد' : 'Email',
    ];
    final deliverySummary = deliveryLabels.join(' • ');
    final travelerCount = passengerIdControllers.length;
    var manifestReadyCount = 0;
    var seatPreferenceCount = 0;
    for (var index = 0; index < travelerCount; index++) {
      final hasPassengerId =
          passengerIdControllers[index].text.trim().isNotEmpty;
      final hasGivenName =
          passengerGivenNameControllers[index].text.trim().isNotEmpty;
      final hasFamilyName =
          passengerFamilyNameControllers[index].text.trim().isNotEmpty;
      if (hasPassengerId && hasGivenName && hasFamilyName) {
        manifestReadyCount++;
      }
      if (preferredSeatControllers[index].text.trim().isNotEmpty) {
        seatPreferenceCount++;
      }
    }
    final manifestSummary = isArabic
        ? '$manifestReadyCount من $travelerCount جاهز'
        : '$manifestReadyCount of $travelerCount ready';
    final seatSummary = seatPreferenceCount == 0
        ? (isArabic ? 'بدون تفضيل مقاعد' : 'No seat prefs')
        : (isArabic
            ? '$seatPreferenceCount تفضيلات مقاعد'
            : '$seatPreferenceCount seat prefs');
    final contactSummary = deliverEmail
        ? (contactEmail.isEmpty
            ? (isArabic ? 'البريد مطلوب' : 'Email required')
            : (isArabic ? 'البريد جاهز' : 'Email ready'))
        : (contactEmail.isEmpty
            ? (isArabic ? 'البريد اختياري' : 'Email optional')
            : contactEmail);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .5),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'لوحة إعداد الرحلة' : 'Travel setup board',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            isArabic
                ? 'راجع الجاهزية للمسافرين، المقاعد، والدفع قبل متابعة الحجز.'
                : 'Review traveler, seat, and payment readiness before moving further into booking.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CoachJourneyFactChip(
                icon: Icons.alternate_email_outlined,
                label: contactSummary,
                highlighted: deliverEmail && contactEmail.isEmpty,
              ),
              _CoachJourneyFactChip(
                icon: Icons.people_alt_outlined,
                label: manifestSummary,
                highlighted: manifestReadyCount < travelerCount,
              ),
              _CoachJourneyFactChip(
                icon: Icons.event_seat_outlined,
                label: seatSummary,
              ),
              _CoachJourneyFactChip(
                icon: Icons.confirmation_num_outlined,
                label: deliverySummary.isEmpty
                    ? (isArabic ? 'تسليم غير محدد' : 'No delivery set')
                    : deliverySummary,
                highlighted: deliverySummary.isEmpty,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CoachSetupSectionCard(
            title: isArabic ? 'بيانات التواصل والدفع' : 'Contact and payment',
            subtitle: isArabic
                ? 'حدد البريد وطريقة الدفع كما ستُستخدم في الحجز وتسليم التذاكر.'
                : 'Set the email and payment method exactly as they should be used for booking and delivery.',
            badges: [
              _coachMiniProgramPaymentMethodLabel(paymentMethod, isArabic),
              contactSummary,
            ],
            child: Column(
              children: [
                TextField(
                  controller: contactEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: isArabic
                        ? 'البريد الإلكتروني للتواصل'
                        : 'Contact email',
                    prefixIcon: const Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: paymentMethod,
                  decoration: InputDecoration(
                    labelText: isArabic ? 'طريقة الدفع' : 'Payment method',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                  items: <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: 'card',
                      child: Text(isArabic ? 'بطاقة' : 'Card'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'wallet_credit',
                      child: Text(isArabic ? 'رصيد المحفظة' : 'Wallet credit'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'split_tender',
                      child: Text(isArabic ? 'دفع مختلط' : 'Split tender'),
                    ),
                  ],
                  onChanged: onPaymentMethodChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _CoachSetupSectionCard(
            title: isArabic
                ? 'بيان المسافرين والمقاعد'
                : 'Passenger manifest and seats',
            subtitle: isArabic
                ? 'أدخل المسافرين كما يجب أن يظهروا على التذكرة مع تفضيلات المقاعد.'
                : 'Enter each traveler exactly as they should appear on the ticket, together with seat preferences.',
            badges: [
              manifestSummary,
              seatSummary,
            ],
            child: Column(
              children: [
                for (var index = 0;
                    index < passengerIdControllers.length;
                    index++) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isArabic
                              ? 'المسافر ${index + 1}'
                              : 'Traveler ${index + 1}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: passengerIdControllers[index],
                          decoration: InputDecoration(
                            labelText: isArabic
                                ? 'معرّف المسافر ${index + 1}'
                                : 'Passenger ID ${index + 1}',
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller:
                                    passengerGivenNameControllers[index],
                                decoration: InputDecoration(
                                  labelText: isArabic
                                      ? 'الاسم الأول ${index + 1}'
                                      : 'Given name ${index + 1}',
                                  prefixIcon: const Icon(Icons.badge_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller:
                                    passengerFamilyNameControllers[index],
                                decoration: InputDecoration(
                                  labelText: isArabic
                                      ? 'اسم العائلة ${index + 1}'
                                      : 'Family name ${index + 1}',
                                  prefixIcon: const Icon(Icons.badge_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<
                                  CoachPassengerRiderCategory>(
                                initialValue: passengerCategories[index],
                                decoration: InputDecoration(
                                  labelText: isArabic
                                      ? 'الفئة ${index + 1}'
                                      : 'Category ${index + 1}',
                                  prefixIcon:
                                      const Icon(Icons.category_outlined),
                                ),
                                items: CoachPassengerRiderCategory.values
                                    .map(
                                      (category) => DropdownMenuItem<
                                          CoachPassengerRiderCategory>(
                                        value: category,
                                        child: Text(
                                          switch (category) {
                                            CoachPassengerRiderCategory.adult =>
                                              isArabic ? 'بالغ' : 'Adult',
                                            CoachPassengerRiderCategory.child =>
                                              isArabic ? 'طفل' : 'Child',
                                            CoachPassengerRiderCategory
                                                  .student =>
                                              isArabic ? 'طالب' : 'Student',
                                            CoachPassengerRiderCategory
                                                  .senior =>
                                              isArabic ? 'كبير سن' : 'Senior',
                                          },
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) {
                                  if (value != null) {
                                    onPassengerCategoryChanged(index, value);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller:
                                    passengerNationalityControllers[index],
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: isArabic
                                      ? 'الجنسية ${index + 1}'
                                      : 'Nationality ${index + 1}',
                                  hintText: 'SY',
                                  prefixIcon: const Icon(Icons.flag_outlined),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: preferredSeatControllers[index],
                          decoration: InputDecoration(
                            labelText: isArabic
                                ? 'المقعد المفضل ${index + 1}'
                                : 'Preferred seat ${index + 1}',
                            prefixIcon: const Icon(Icons.event_seat_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (index < passengerIdControllers.length - 1)
                    const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _CoachSetupSectionCard(
            title: isArabic ? 'لوحة تسليم التذاكر' : 'Ticket delivery board',
            subtitle: isArabic
                ? 'اختر قنوات العرض والإرسال التي سترافق التذكرة بعد الإصدار.'
                : 'Choose the display and delivery channels that should accompany the ticket after issuance.',
            badges: [
              if (deliveryLabels.isEmpty)
                isArabic ? 'بدون قنوات' : 'No channels',
              ...deliveryLabels,
              if (deliverEmail && contactEmail.isEmpty)
                isArabic ? 'أضف بريداً' : 'Add email',
            ],
            child: Column(
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deliverWalletPass,
                  onChanged: (value) =>
                      onDeliverWalletPassChanged(value ?? false),
                  title: Text(isArabic ? 'بطاقة المحفظة' : 'Wallet pass'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deliverPdf,
                  onChanged: (value) => onDeliverPdfChanged(value ?? false),
                  title: const Text('PDF'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: deliverEmail,
                  onChanged: (value) => onDeliverEmailChanged(value ?? false),
                  title: Text(isArabic ? 'إرسال بالبريد' : 'Email delivery'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachSetupSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<String> badges;
  final Widget child;

  const _CoachSetupSectionCard({
    required this.title,
    required this.subtitle,
    this.badges = const <String>[],
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoachSectionHeader(
            title: title,
            subtitle: subtitle,
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final badge in badges) Chip(label: Text(badge)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _CoachMiniQuickActionButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _CoachMiniQuickActionButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 10);
    if (selected) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: WeChatPalette.green,
          padding: padding,
          minimumSize: const Size(0, 42),
          shape: shape,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: padding,
        minimumSize: const Size(0, 42),
        shape: shape,
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _PreviewTile({
    required this.title,
    required this.lines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (var index = 0; index < lines.length; index++) ...[
            Text(lines[index], style: Theme.of(context).textTheme.bodyMedium),
            if (index < lines.length - 1) ...[
              const SizedBox(height: 6),
              Divider(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: .5),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }
}
