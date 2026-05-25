import 'package:flutter/material.dart';

import '../format.dart';
import '../wechat_ui.dart';
import 'ride_hailing_store.dart';

const List<String> taxiRideSupportedCurrencies = <String>[
  'SYP',
  'USD',
  'EUR',
  'TRY',
  'AED',
];

const List<String> taxiRidePaymentModes = <String>[
  'Wallet',
  'Cash',
  'Corporate',
  'Split',
];

const List<String> taxiRideFareModes = <String>[
  'Fixed',
  'Meter',
];

const List<String> taxiRideRoutePreferences = <String>[
  'Fastest',
  'Cheapest',
  'Safest',
  'Low traffic',
];

const List<String> taxiRideProfiles = <String>[
  'Standard',
  'Family',
  'Airport',
  'Hotel',
  'Event',
  'Child/Senior',
];

const List<String> taxiRideBusinessModes = <String>[
  'Personal',
  'Business',
  'Ride Pass',
];

const List<String> taxiOperatorZoneModes = <String>[
  'Balanced',
  'Airport',
  'Events',
  'Surge',
  'Restricted',
];

const List<String> taxiRideAccessibilityNeeds = <String>[
  'None',
  'Wheelchair',
  'Senior assist',
  'Large luggage',
  'Quiet ride',
];

const List<String> taxiRideCancellationRules = <String>[
  'Flexible',
  'Grace 3 min',
  'Strict airport',
];

class TaxiFeatureMetric {
  final IconData icon;
  final String label;
  final String value;
  final bool warning;

  const TaxiFeatureMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.warning = false,
  });
}

class TaxiFeatureAction {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  const TaxiFeatureAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
}

class _TaxiFeatureStep {
  final IconData icon;
  final String label;
  final String detail;
  final bool active;
  final bool warning;

  const _TaxiFeatureStep({
    required this.icon,
    required this.label,
    required this.detail,
    this.active = false,
    this.warning = false,
  });
}

String taxiRideStatusLabel(
  RideTripStatus? status, {
  required bool isArabic,
}) {
  switch (status) {
    case RideTripStatus.idle:
      return isArabic ? 'خامل' : 'Idle';
    case RideTripStatus.quoteShown:
      return isArabic ? 'تم عرض السعر' : 'Quote shown';
    case RideTripStatus.rideRequested:
      return isArabic ? 'تم طلب الرحلة' : 'Ride requested';
    case RideTripStatus.matching:
      return isArabic ? 'جار المطابقة' : 'Matching';
    case RideTripStatus.driverAssigned:
      return isArabic ? 'تم تعيين السائق' : 'Driver assigned';
    case RideTripStatus.driverArriving:
      return isArabic ? 'السائق في الطريق' : 'Driver arriving';
    case RideTripStatus.driverArrived:
      return isArabic ? 'السائق وصل' : 'Driver arrived';
    case RideTripStatus.tripStarted:
      return isArabic ? 'بدأت الرحلة' : 'Trip started';
    case RideTripStatus.tripInProgress:
      return isArabic ? 'الرحلة جارية' : 'Trip in progress';
    case RideTripStatus.tripCompleted:
      return isArabic ? 'اكتملت الرحلة' : 'Trip completed';
    case RideTripStatus.canceled:
      return isArabic ? 'ملغاة' : 'Canceled';
    case RideTripStatus.paymentFailed:
      return isArabic ? 'فشل الدفع' : 'Payment failed';
    case null:
      return isArabic ? 'جاهز' : 'Ready';
  }
}

int _taxiRideStatusRank(RideTripStatus? status) {
  switch (status) {
    case RideTripStatus.idle:
      return 0;
    case RideTripStatus.quoteShown:
      return 1;
    case RideTripStatus.rideRequested:
      return 2;
    case RideTripStatus.matching:
      return 3;
    case RideTripStatus.driverAssigned:
      return 4;
    case RideTripStatus.driverArriving:
      return 5;
    case RideTripStatus.driverArrived:
      return 6;
    case RideTripStatus.tripStarted:
      return 7;
    case RideTripStatus.tripInProgress:
      return 8;
    case RideTripStatus.tripCompleted:
      return 9;
    case RideTripStatus.paymentFailed:
      return 10;
    case RideTripStatus.canceled:
      return -1;
    case null:
      return 0;
  }
}

bool _taxiStatusAtLeast(RideTripStatus? status, RideTripStatus target) =>
    _taxiRideStatusRank(status) >= _taxiRideStatusRank(target);

String _formatAmountOrDash(int? amountMinorUnits, String currency) {
  if (amountMinorUnits == null) return '--';
  return '${fmtCents(amountMinorUnits)} $currency';
}

String _driverLabel(RideTrip? trip, {required bool isArabic}) {
  final name = (trip?.driverName ?? '').trim();
  final plate = (trip?.carPlate ?? '').trim();
  if (name.isEmpty || name.toLowerCase() == 'driver pending') {
    return isArabic ? 'إسناد تلقائي' : 'Auto assignment';
  }
  if (plate.isEmpty || plate == '--') return name;
  return '$name • $plate';
}

class TaxiPassengerJourneyPanel extends StatelessWidget {
  final RideTrip? activeTrip;
  final String pickupLabel;
  final String destinationLabel;
  final int? estimateMinorUnits;
  final int? estimateEtaMinutes;
  final bool hasRoutePreview;
  final bool hasDriverLocation;
  final VoidCallback? onScheduleRide;
  final VoidCallback? onOpenReceipt;
  final VoidCallback? onRateRide;

  const TaxiPassengerJourneyPanel({
    super.key,
    required this.activeTrip,
    required this.pickupLabel,
    required this.destinationLabel,
    required this.estimateMinorUnits,
    required this.estimateEtaMinutes,
    required this.hasRoutePreview,
    required this.hasDriverLocation,
    required this.onScheduleRide,
    required this.onOpenReceipt,
    required this.onRateRide,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    final trip = activeTrip;
    final eta = trip?.etaMinutes ?? estimateEtaMinutes;
    final fare = trip?.fareEstimateCents ?? estimateMinorUnits;
    final routeLabel = trip == null
        ? '${pickupLabel.isEmpty ? "--" : pickupLabel} -> ${destinationLabel.isEmpty ? "--" : destinationLabel}'
        : '${trip.pickup} -> ${trip.destination}';
    final status = trip?.status;
    return _TaxiFeatureCard(
      icon: Icons.route_outlined,
      title: isArabic ? 'مركز الرحلة' : 'Ride control center',
      subtitle: isArabic
          ? 'حالة مباشرة، إسناد السائق، نقطة الالتقاط، الإيصال والتقييم.'
          : 'Live trip status, driver assignment, pickup precision, receipt, and rating.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.timeline_outlined,
          label: isArabic ? 'الحالة' : 'Status',
          value: taxiRideStatusLabel(status, isArabic: isArabic),
          warning: status == RideTripStatus.paymentFailed ||
              status == RideTripStatus.canceled,
        ),
        TaxiFeatureMetric(
          icon: Icons.schedule_outlined,
          label: 'ETA',
          value: eta == null ? '--' : (isArabic ? '$eta د' : '$eta min'),
        ),
        TaxiFeatureMetric(
          icon: Icons.drive_eta_outlined,
          label: isArabic ? 'السائق' : 'Driver',
          value: _driverLabel(trip, isArabic: isArabic),
        ),
        TaxiFeatureMetric(
          icon: Icons.my_location_outlined,
          label: isArabic ? 'الالتقاط' : 'Pickup',
          value: hasRoutePreview
              ? (isArabic ? 'مثبت' : 'Pinned')
              : (isArabic ? 'بحث' : 'Search'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaxiInlineInfo(
            icon: Icons.alt_route_outlined,
            label: routeLabel,
          ),
          const SizedBox(height: 8),
          _TaxiInlineInfo(
            icon: Icons.payments_outlined,
            label: _formatAmountOrDash(fare, 'SYP'),
          ),
          const SizedBox(height: 12),
          _TaxiStepList(
            steps: <_TaxiFeatureStep>[
              _TaxiFeatureStep(
                icon: Icons.request_page_outlined,
                label: isArabic ? 'طلب وسعر' : 'Request and quote',
                detail: isArabic
                    ? 'السعر النهائي يظهر قبل التأكيد.'
                    : 'Final fare is visible before confirmation.',
                active: trip == null ||
                    _taxiStatusAtLeast(status, RideTripStatus.rideRequested),
              ),
              _TaxiFeatureStep(
                icon: Icons.manage_accounts_outlined,
                label: isArabic ? 'إسناد السائق' : 'Driver assignment',
                detail: isArabic
                    ? 'مطابقة تلقائية مع إمكانية تدخل المشغل.'
                    : 'Auto matching with operator override.',
                active:
                    _taxiStatusAtLeast(status, RideTripStatus.driverAssigned),
              ),
              _TaxiFeatureStep(
                icon: Icons.near_me_outlined,
                label: isArabic ? 'تتبع حي' : 'Live driver location',
                detail: hasDriverLocation
                    ? (isArabic
                        ? 'آخر موقع للسائق متاح.'
                        : 'Latest driver location is available.')
                    : (isArabic
                        ? 'ينتظر أول تحديث GPS.'
                        : 'Waiting for the first GPS update.'),
                active: hasDriverLocation,
              ),
              _TaxiFeatureStep(
                icon: Icons.receipt_long_outlined,
                label: isArabic ? 'إيصال وتقييم' : 'Receipt and rating',
                detail: isArabic
                    ? 'يظهر بعد اكتمال الرحلة.'
                    : 'Unlocked after ride completion.',
                active: status == RideTripStatus.tripCompleted,
              ),
            ],
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.event_available_outlined,
          label: isArabic ? 'جدولة' : 'Schedule',
          onPressed: onScheduleRide,
        ),
        TaxiFeatureAction(
          icon: Icons.receipt_long_outlined,
          label: isArabic ? 'إيصال' : 'Receipt',
          onPressed: onOpenReceipt,
        ),
        TaxiFeatureAction(
          icon: Icons.star_border_rounded,
          label: isArabic ? 'تقييم' : 'Rate',
          onPressed: onRateRide,
          primary: true,
        ),
      ],
    );
  }
}

class TaxiPassengerPaymentPanel extends StatelessWidget {
  final int? fareMinorUnits;
  final String selectedCurrency;
  final String selectedPaymentMode;
  final bool walletLinked;
  final ValueChanged<String>? onCurrencySelected;
  final ValueChanged<String>? onPaymentModeSelected;
  final VoidCallback? onOpenWallet;
  final VoidCallback? onOpenQrPay;
  final VoidCallback? onOpenPaymentRequests;

  const TaxiPassengerPaymentPanel({
    super.key,
    required this.fareMinorUnits,
    required this.selectedCurrency,
    required this.selectedPaymentMode,
    required this.walletLinked,
    required this.onCurrencySelected,
    required this.onPaymentModeSelected,
    required this.onOpenWallet,
    required this.onOpenQrPay,
    required this.onOpenPaymentRequests,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    final currency = selectedCurrency.trim().isEmpty
        ? 'SYP'
        : selectedCurrency.trim().toUpperCase();
    return _TaxiFeatureCard(
      icon: Icons.account_balance_wallet_outlined,
      title: isArabic ? 'الدفع متعدد العملات' : 'Multi-currency taxi payments',
      subtitle: isArabic
          ? 'دفع الرحلة، طلب الدفع، QR، نقد/محفظة/شركة وتقسيم المبلغ.'
          : 'Ride payment, payment requests, QR, cash, wallet, corporate, and split settlement.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.wallet_outlined,
          label: isArabic ? 'المحفظة' : 'Wallet',
          value: walletLinked
              ? (isArabic ? 'مرتبطة' : 'Linked')
              : (isArabic ? 'غير مرتبطة' : 'Missing'),
          warning: !walletLinked,
        ),
        TaxiFeatureMetric(
          icon: Icons.payments_outlined,
          label: isArabic ? 'السعر' : 'Fare',
          value: _formatAmountOrDash(fareMinorUnits, 'SYP'),
        ),
        TaxiFeatureMetric(
          icon: Icons.currency_exchange_outlined,
          label: isArabic ? 'العملة' : 'Currency',
          value: currency,
        ),
        TaxiFeatureMetric(
          icon: Icons.point_of_sale_outlined,
          label: isArabic ? 'طريقة الدفع' : 'Mode',
          value: selectedPaymentMode,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaxiChoiceRow(
            label: isArabic ? 'عملة الدفع' : 'Payment currency',
            values: taxiRideSupportedCurrencies,
            selectedValue: currency,
            onSelected: onCurrencySelected,
          ),
          const SizedBox(height: 10),
          _TaxiChoiceRow(
            label: isArabic ? 'طريقة التسوية' : 'Settlement mode',
            values: taxiRidePaymentModes,
            selectedValue: selectedPaymentMode,
            onSelected: onPaymentModeSelected,
          ),
          const SizedBox(height: 10),
          Text(
            currency == 'SYP'
                ? (isArabic
                    ? 'سيتم الخصم مباشرة بعملة SYP.'
                    : 'The fare settles directly in SYP.')
                : (isArabic
                    ? 'سيطلب SyrChat Pay عرض صرف قبل تأكيد الدفع بهذه العملة.'
                    : 'SyrChat Pay requests an FX quote before confirming this currency.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.account_balance_wallet_outlined,
          label: isArabic ? 'المحفظة' : 'Wallet',
          onPressed: onOpenWallet,
        ),
        TaxiFeatureAction(
          icon: Icons.qr_code_scanner_outlined,
          label: isArabic ? 'QR' : 'QR pay/top up',
          onPressed: onOpenQrPay,
        ),
        TaxiFeatureAction(
          icon: Icons.request_quote_outlined,
          label: isArabic ? 'طلب دفع' : 'Payment request',
          onPressed: onOpenPaymentRequests,
          primary: true,
        ),
      ],
    );
  }
}

class TaxiPassengerSafetyCommsPanel extends StatelessWidget {
  final bool hasActiveTrip;
  final int openSupportTickets;
  final VoidCallback? onOpenChat;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onAudioMessage;
  final VoidCallback? onSafetySos;

  const TaxiPassengerSafetyCommsPanel({
    super.key,
    required this.hasActiveTrip,
    required this.openSupportTickets,
    required this.onOpenChat,
    required this.onVoiceCall,
    required this.onVideoCall,
    required this.onAudioMessage,
    required this.onSafetySos,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    return _TaxiFeatureCard(
      icon: Icons.health_and_safety_outlined,
      title: isArabic ? 'السلامة والتواصل' : 'Safety and ride communication',
      subtitle: isArabic
          ? 'محادثة، مكالمات صوت/فيديو، رسائل صوتية ونداء SOS للرحلة.'
          : 'Chat, voice calls, video calls, audio notes, and ride SOS.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.chat_bubble_outline,
          label: isArabic ? 'الدردشة' : 'Chat',
          value: hasActiveTrip
              ? (isArabic ? 'رحلة' : 'Trip')
              : (isArabic ? 'جاهز' : 'Ready'),
        ),
        TaxiFeatureMetric(
          icon: Icons.mic_none_outlined,
          label: isArabic ? 'صوت' : 'Audio notes',
          value: isArabic ? 'مدعوم' : 'Enabled',
        ),
        TaxiFeatureMetric(
          icon: Icons.support_agent_outlined,
          label: isArabic ? 'الدعم' : 'Support',
          value: '$openSupportTickets',
          warning: openSupportTickets > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.sos_outlined,
          label: 'SOS',
          value: hasActiveTrip
              ? (isArabic ? 'نشط' : 'Active')
              : (isArabic ? 'جاهز' : 'Ready'),
        ),
      ],
      body: _TaxiStepList(
        steps: <_TaxiFeatureStep>[
          _TaxiFeatureStep(
            icon: Icons.chat_outlined,
            label: isArabic ? 'محادثة السائق' : 'Driver chat',
            detail: isArabic
                ? 'يفتح من الرحلة الحالية أو من تذكرة دعم مرتبطة.'
                : 'Opens from the current ride or a linked support ticket.',
            active: hasActiveTrip,
          ),
          _TaxiFeatureStep(
            icon: Icons.call_outlined,
            label: isArabic ? 'مكالمة صوتية' : 'Voice call',
            detail: isArabic
                ? 'للتنسيق السريع عند الالتقاط.'
                : 'Fast coordination around pickup.',
            active: hasActiveTrip,
          ),
          _TaxiFeatureStep(
            icon: Icons.videocam_outlined,
            label: isArabic ? 'مكالمة فيديو' : 'Video call',
            detail: isArabic
                ? 'للمواقف التي تحتاج تحقق بصري.'
                : 'For cases that need visual confirmation.',
            active: hasActiveTrip,
          ),
          _TaxiFeatureStep(
            icon: Icons.emergency_share_outlined,
            label: 'SOS',
            detail: isArabic
                ? 'يربط الرحلة بالدعم وسجل السلامة.'
                : 'Links the ride to support and the safety log.',
            active: true,
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.chat_outlined,
          label: isArabic ? 'دردشة' : 'Chat',
          onPressed: onOpenChat,
        ),
        TaxiFeatureAction(
          icon: Icons.call_outlined,
          label: isArabic ? 'صوت' : 'Voice',
          onPressed: onVoiceCall,
        ),
        TaxiFeatureAction(
          icon: Icons.videocam_outlined,
          label: isArabic ? 'فيديو' : 'Video',
          onPressed: onVideoCall,
        ),
        TaxiFeatureAction(
          icon: Icons.mic_none_outlined,
          label: isArabic ? 'رسالة صوتية' : 'Audio note',
          onPressed: onAudioMessage,
        ),
        TaxiFeatureAction(
          icon: Icons.sos_outlined,
          label: 'SOS',
          onPressed: onSafetySos,
          primary: true,
        ),
      ],
    );
  }
}

class TaxiDriverCommandPanel extends StatelessWidget {
  final RideTrip? activeTrip;
  final bool online;
  final bool readyForDispatch;
  final int queueCount;
  final int completedTodayCount;
  final int? payoutMinorUnits;
  final int? reserveMinorUnits;
  final int? cashCollectedMinorUnits;
  final bool walletLinked;
  final VoidCallback? onOpenWallet;
  final VoidCallback? onRequestPayout;

  const TaxiDriverCommandPanel({
    super.key,
    required this.activeTrip,
    required this.online,
    required this.readyForDispatch,
    required this.queueCount,
    required this.completedTodayCount,
    required this.payoutMinorUnits,
    required this.reserveMinorUnits,
    required this.cashCollectedMinorUnits,
    required this.walletLinked,
    required this.onOpenWallet,
    required this.onRequestPayout,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    return _TaxiFeatureCard(
      icon: Icons.local_taxi_outlined,
      title: isArabic ? 'مركز السائق' : 'Driver command center',
      subtitle: isArabic
          ? 'إسناد الرحلات، الجاهزية، محفظة السائق، السحب والتحصيل النقدي.'
          : 'Trip assignment, readiness, driver wallet, payouts, and cash collection.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.power_settings_new_outlined,
          label: isArabic ? 'الحالة' : 'Status',
          value: online
              ? (isArabic ? 'متصل' : 'Online')
              : (isArabic ? 'غير متصل' : 'Offline'),
          warning: !online,
        ),
        TaxiFeatureMetric(
          icon: Icons.assignment_outlined,
          label: isArabic ? 'الطابور' : 'Queue',
          value: '$queueCount',
        ),
        TaxiFeatureMetric(
          icon: Icons.account_balance_wallet_outlined,
          label: isArabic ? 'السحب' : 'Payout',
          value: _formatAmountOrDash(payoutMinorUnits, 'SYP'),
          warning: !walletLinked,
        ),
        TaxiFeatureMetric(
          icon: Icons.savings_outlined,
          label: isArabic ? 'الاحتياطي' : 'Reserve',
          value: _formatAmountOrDash(reserveMinorUnits, 'SYP'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaxiStepList(
            steps: <_TaxiFeatureStep>[
              _TaxiFeatureStep(
                icon: Icons.badge_outlined,
                label: isArabic ? 'الملف والوثائق' : 'Profile and documents',
                detail: readyForDispatch
                    ? (isArabic
                        ? 'جاهز لقبول الرحلات.'
                        : 'Ready to accept rides.')
                    : (isArabic
                        ? 'أكمل المتطلبات قبل القبول.'
                        : 'Complete requirements before accepting.'),
                active: readyForDispatch,
                warning: !readyForDispatch,
              ),
              _TaxiFeatureStep(
                icon: Icons.route_outlined,
                label: isArabic ? 'رحلة نشطة' : 'Active ride',
                detail: activeTrip == null
                    ? (isArabic ? 'لا توجد رحلة حالية.' : 'No current ride.')
                    : '${activeTrip!.pickup} -> ${activeTrip!.destination}',
                active: activeTrip != null,
              ),
              _TaxiFeatureStep(
                icon: Icons.point_of_sale_outlined,
                label: isArabic ? 'النقد والمحفظة' : 'Cash and wallet',
                detail:
                    '${_formatAmountOrDash(cashCollectedMinorUnits, 'SYP')} ${isArabic ? "تحصيل نقدي" : "cash collected"}',
                active: walletLinked,
                warning: !walletLinked,
              ),
              _TaxiFeatureStep(
                icon: Icons.verified_outlined,
                label: isArabic ? 'إغلاق الرحلة' : 'Trip closeout',
                detail: isArabic
                    ? '$completedTodayCount رحلات مكتملة اليوم.'
                    : '$completedTodayCount rides completed today.',
                active: completedTodayCount > 0,
              ),
            ],
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.account_balance_wallet_outlined,
          label: isArabic ? 'المحفظة' : 'Wallet',
          onPressed: onOpenWallet,
        ),
        TaxiFeatureAction(
          icon: Icons.payments_outlined,
          label: isArabic ? 'طلب سحب' : 'Request payout',
          onPressed: onRequestPayout,
          primary: true,
        ),
      ],
    );
  }
}

class TaxiDriverSafetyCommsPanel extends StatelessWidget {
  final bool hasActiveTrip;
  final bool trackingFresh;
  final int paymentFailureCount;
  final VoidCallback? onOpenChat;
  final VoidCallback? onVoiceCall;
  final VoidCallback? onVideoCall;
  final VoidCallback? onAudioMessage;
  final VoidCallback? onSafetySos;

  const TaxiDriverSafetyCommsPanel({
    super.key,
    required this.hasActiveTrip,
    required this.trackingFresh,
    required this.paymentFailureCount,
    required this.onOpenChat,
    required this.onVoiceCall,
    required this.onVideoCall,
    required this.onAudioMessage,
    required this.onSafetySos,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    return _TaxiFeatureCard(
      icon: Icons.admin_panel_settings_outlined,
      title: isArabic ? 'سلامة وتواصل السائق' : 'Driver safety and comms',
      subtitle: isArabic
          ? 'دردشة الراكب، مكالمات، رسائل صوتية، SOS ومراقبة GPS.'
          : 'Rider chat, calls, audio notes, SOS, and GPS freshness.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.gps_fixed_outlined,
          label: 'GPS',
          value: trackingFresh
              ? (isArabic ? 'حديث' : 'Fresh')
              : (isArabic ? 'ينتظر' : 'Waiting'),
          warning: !trackingFresh && hasActiveTrip,
        ),
        TaxiFeatureMetric(
          icon: Icons.chat_outlined,
          label: isArabic ? 'الدردشة' : 'Chat',
          value: hasActiveTrip
              ? (isArabic ? 'رحلة' : 'Trip')
              : (isArabic ? 'جاهز' : 'Ready'),
        ),
        TaxiFeatureMetric(
          icon: Icons.payments_outlined,
          label: isArabic ? 'دفع عالق' : 'Pay fail',
          value: '$paymentFailureCount',
          warning: paymentFailureCount > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.sos_outlined,
          label: 'SOS',
          value: isArabic ? 'متاح' : 'Ready',
        ),
      ],
      body: _TaxiStepList(
        steps: <_TaxiFeatureStep>[
          _TaxiFeatureStep(
            icon: Icons.my_location_outlined,
            label: isArabic ? 'دقة الالتقاط' : 'Pickup precision',
            detail: isArabic
                ? 'الخريطة ونقطة الالتقاط مرتبطة بالرحلة.'
                : 'Map and pickup point stay attached to the ride.',
            active: hasActiveTrip,
          ),
          _TaxiFeatureStep(
            icon: Icons.record_voice_over_outlined,
            label: isArabic ? 'رسائل صوتية' : 'Audio messages',
            detail: isArabic
                ? 'تستخدم نفس بنية رسائل سرتشات الصوتية.'
                : 'Uses the same SyrChat voice-note pattern.',
            active: true,
          ),
          _TaxiFeatureStep(
            icon: Icons.report_problem_outlined,
            label: isArabic ? 'شكاوى وتقييم' : 'Complaints and rating',
            detail: isArabic
                ? 'تسجل بعد الرحلة أو عبر الدعم.'
                : 'Captured after the ride or through support.',
            active: true,
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.chat_outlined,
          label: isArabic ? 'دردشة' : 'Chat',
          onPressed: onOpenChat,
        ),
        TaxiFeatureAction(
          icon: Icons.call_outlined,
          label: isArabic ? 'صوت' : 'Voice',
          onPressed: onVoiceCall,
        ),
        TaxiFeatureAction(
          icon: Icons.videocam_outlined,
          label: isArabic ? 'فيديو' : 'Video',
          onPressed: onVideoCall,
        ),
        TaxiFeatureAction(
          icon: Icons.mic_none_outlined,
          label: isArabic ? 'صوتية' : 'Audio note',
          onPressed: onAudioMessage,
        ),
        TaxiFeatureAction(
          icon: Icons.sos_outlined,
          label: 'SOS',
          onPressed: onSafetySos,
          primary: true,
        ),
      ],
    );
  }
}

class TaxiOperatorControlPanel extends StatelessWidget {
  final int openDispatches;
  final int activeTrips;
  final int onlineDrivers;
  final int idleDrivers;
  final int staleDrivers;
  final int noGpsDrivers;
  final int criticalCases;
  final int urgentSupportTickets;
  final int pendingDocuments;
  final int pendingPayouts;
  final int paymentFailures;

  const TaxiOperatorControlPanel({
    super.key,
    required this.openDispatches,
    required this.activeTrips,
    required this.onlineDrivers,
    required this.idleDrivers,
    required this.staleDrivers,
    required this.noGpsDrivers,
    required this.criticalCases,
    required this.urgentSupportTickets,
    required this.pendingDocuments,
    required this.pendingPayouts,
    required this.paymentFailures,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    return _TaxiFeatureCard(
      icon: Icons.dashboard_customize_outlined,
      title: isArabic ? 'مركز تاكسي مباشر' : 'Taxi live control suite',
      subtitle: isArabic
          ? 'إسناد، GPS، سلامة، دعم، مدفوعات وسائقون من شاشة واحدة.'
          : 'Dispatch, GPS, safety, support, payments, and driver supply in one screen.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.local_shipping_outlined,
          label: isArabic ? 'طلبات' : 'Dispatch',
          value: '$openDispatches',
          warning: openDispatches > idleDrivers && openDispatches > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.route_outlined,
          label: isArabic ? 'رحلات' : 'Active',
          value: '$activeTrips',
        ),
        TaxiFeatureMetric(
          icon: Icons.drive_eta_outlined,
          label: isArabic ? 'سائقون' : 'Drivers',
          value: '$onlineDrivers',
          warning: onlineDrivers == 0 && openDispatches > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.health_and_safety_outlined,
          label: isArabic ? 'سلامة' : 'Safety',
          value: '${criticalCases + urgentSupportTickets}',
          warning: criticalCases + urgentSupportTickets > 0,
        ),
      ],
      body: _TaxiStepList(
        steps: <_TaxiFeatureStep>[
          _TaxiFeatureStep(
            icon: Icons.assignment_ind_outlined,
            label: isArabic ? 'إسناد السائقين' : 'Driver assignment',
            detail: isArabic
                ? '$idleDrivers سائقين متاحين الآن.'
                : '$idleDrivers drivers are idle right now.',
            active: idleDrivers > 0,
            warning: openDispatches > idleDrivers && openDispatches > 0,
          ),
          _TaxiFeatureStep(
            icon: Icons.gps_off_outlined,
            label: isArabic ? 'رؤية GPS' : 'GPS visibility',
            detail: isArabic
                ? '$staleDrivers نبضات قديمة، $noGpsDrivers بدون GPS.'
                : '$staleDrivers stale, $noGpsDrivers without GPS.',
            active: staleDrivers == 0 && noGpsDrivers == 0,
            warning: staleDrivers > 0 || noGpsDrivers > 0,
          ),
          _TaxiFeatureStep(
            icon: Icons.price_change_outlined,
            label: isArabic ? 'تسعير ديناميكي' : 'Dynamic pricing',
            detail: isArabic
                ? 'يتابع الطلب، السعة، الازدحام وفشل الدفع.'
                : 'Tracks demand, capacity, traffic, and payment failures.',
            active: true,
            warning: paymentFailures > 0,
          ),
          _TaxiFeatureStep(
            icon: Icons.badge_outlined,
            label: isArabic ? 'تفعيل السائقين' : 'Driver onboarding',
            detail: isArabic
                ? '$pendingDocuments وثائق تنتظر المراجعة.'
                : '$pendingDocuments documents waiting review.',
            active: pendingDocuments == 0,
            warning: pendingDocuments > 0,
          ),
        ],
      ),
    );
  }
}

class TaxiOperatorRiskPaymentPanel extends StatelessWidget {
  final int paymentFailures;
  final int pendingPayouts;
  final int criticalCases;
  final int openSupportTickets;
  final int capacityGap;
  final int longRunningTrips;

  const TaxiOperatorRiskPaymentPanel({
    super.key,
    required this.paymentFailures,
    required this.pendingPayouts,
    required this.criticalCases,
    required this.openSupportTickets,
    required this.capacityGap,
    required this.longRunningTrips,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    final fraudRisk = paymentFailures + criticalCases + longRunningTrips;
    return _TaxiFeatureCard(
      icon: Icons.policy_outlined,
      title: isArabic ? 'المخاطر والمدفوعات' : 'Risk and payment guardrails',
      subtitle: isArabic
          ? 'مراقبة الاحتيال، فشل الدفع، السحب، الشكاوى وطلبات السلامة.'
          : 'Fraud signals, payment failures, payouts, complaints, and safety escalations.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.warning_amber_outlined,
          label: isArabic ? 'مخاطر' : 'Risk',
          value: '$fraudRisk',
          warning: fraudRisk > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.payments_outlined,
          label: isArabic ? 'فشل دفع' : 'Pay fail',
          value: '$paymentFailures',
          warning: paymentFailures > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.account_balance_wallet_outlined,
          label: isArabic ? 'سحوبات' : 'Payouts',
          value: '$pendingPayouts',
          warning: pendingPayouts > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.support_agent_outlined,
          label: isArabic ? 'دعم' : 'Support',
          value: '$openSupportTickets',
          warning: openSupportTickets > 0,
        ),
      ],
      body: _TaxiStepList(
        steps: <_TaxiFeatureStep>[
          _TaxiFeatureStep(
            icon: Icons.currency_exchange_outlined,
            label: isArabic ? 'عملات متعددة' : 'Multi-currency rides',
            detail: isArabic
                ? 'الدفع والطلبات تمر عبر SyrChat Pay مع فلتر العملة.'
                : 'Payments and requests route through SyrChat Pay currency filters.',
            active: true,
          ),
          _TaxiFeatureStep(
            icon: Icons.speed_outlined,
            label: isArabic ? 'سعة وتسعير' : 'Capacity and surge',
            detail: isArabic
                ? '$capacityGap فجوة سعة تحتاج قرار تسعير أو إسناد.'
                : '$capacityGap capacity gap items need pricing or assignment.',
            active: capacityGap == 0,
            warning: capacityGap > 0,
          ),
          _TaxiFeatureStep(
            icon: Icons.receipt_long_outlined,
            label: isArabic ? 'إيصال وإغلاق' : 'Receipt closeout',
            detail: isArabic
                ? 'كل رحلة تغلق بإيصال، تقييم ومسار دعم.'
                : 'Every ride closes with receipt, rating, and support path.',
            active: true,
          ),
          _TaxiFeatureStep(
            icon: Icons.shield_outlined,
            label: isArabic ? 'مكافحة الاحتيال' : 'Fraud detection',
            detail: isArabic
                ? 'يربط الرحلات الطويلة، فشل الدفع والقضايا الحرجة.'
                : 'Combines long rides, payment failures, and critical cases.',
            active: fraudRisk == 0,
            warning: fraudRisk > 0,
          ),
        ],
      ),
    );
  }
}

class TaxiPassengerAdvancedBookingPanel extends StatelessWidget {
  final int? liveMeterMinorUnits;
  final int extraStopCount;
  final String selectedFareMode;
  final String selectedRoutePreference;
  final String selectedRideProfile;
  final String selectedBusinessMode;
  final bool poolingEnabled;
  final bool familyModeEnabled;
  final bool favoriteDriverEnabled;
  final ValueChanged<String>? onFareModeSelected;
  final ValueChanged<String>? onRoutePreferenceSelected;
  final ValueChanged<String>? onRideProfileSelected;
  final ValueChanged<String>? onBusinessModeSelected;
  final ValueChanged<bool>? onPoolingChanged;
  final ValueChanged<bool>? onFamilyModeChanged;
  final ValueChanged<bool>? onFavoriteDriverChanged;
  final VoidCallback? onAddStop;

  const TaxiPassengerAdvancedBookingPanel({
    super.key,
    required this.liveMeterMinorUnits,
    required this.extraStopCount,
    required this.selectedFareMode,
    required this.selectedRoutePreference,
    required this.selectedRideProfile,
    required this.selectedBusinessMode,
    required this.poolingEnabled,
    required this.familyModeEnabled,
    required this.favoriteDriverEnabled,
    required this.onFareModeSelected,
    required this.onRoutePreferenceSelected,
    required this.onRideProfileSelected,
    required this.onBusinessModeSelected,
    required this.onPoolingChanged,
    required this.onFamilyModeChanged,
    required this.onFavoriteDriverChanged,
    required this.onAddStop,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    return _TaxiFeatureCard(
      icon: Icons.tune_outlined,
      title: isArabic ? 'خيارات الحجز المتقدمة' : 'Advanced taxi booking',
      subtitle: isArabic
          ? 'عداد حي، سعر ثابت، مسارات، توقفات، مشاركة، عائلة، أعمال وRide Pass.'
          : 'Live meter, fixed fare, routes, stops, pooling, family mode, business, and Ride Pass.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.speed_outlined,
          label: isArabic ? 'العداد' : 'Live meter',
          value: _formatAmountOrDash(liveMeterMinorUnits, 'SYP'),
        ),
        TaxiFeatureMetric(
          icon: Icons.alt_route_outlined,
          label: isArabic ? 'المسار' : 'Route',
          value: selectedRoutePreference,
        ),
        TaxiFeatureMetric(
          icon: Icons.add_road_outlined,
          label: isArabic ? 'توقفات' : 'Stops',
          value: '$extraStopCount',
        ),
        TaxiFeatureMetric(
          icon: Icons.business_center_outlined,
          label: isArabic ? 'الحساب' : 'Account',
          value: selectedBusinessMode,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaxiChoiceRow(
            label: isArabic ? 'نمط السعر' : 'Fare mode',
            values: taxiRideFareModes,
            selectedValue: selectedFareMode,
            onSelected: onFareModeSelected,
          ),
          const SizedBox(height: 10),
          _TaxiChoiceRow(
            label: isArabic ? 'اختيار المسار' : 'Route preference',
            values: taxiRideRoutePreferences,
            selectedValue: selectedRoutePreference,
            onSelected: onRoutePreferenceSelected,
          ),
          const SizedBox(height: 10),
          _TaxiChoiceRow(
            label: isArabic ? 'نوع الرحلة' : 'Ride profile',
            values: taxiRideProfiles,
            selectedValue: selectedRideProfile,
            onSelected: onRideProfileSelected,
          ),
          const SizedBox(height: 10),
          _TaxiChoiceRow(
            label: isArabic ? 'شخصي أو أعمال' : 'Personal or business',
            values: taxiRideBusinessModes,
            selectedValue: selectedBusinessMode,
            onSelected: onBusinessModeSelected,
          ),
          const SizedBox(height: 8),
          _TaxiSwitchLine(
            icon: Icons.group_add_outlined,
            title: isArabic ? 'Ride Pool' : 'Ride pool',
            subtitle: isArabic
                ? 'مطابقة رحلة مشتركة بسعر أقل.'
                : 'Match a shared ride for a lower fare.',
            value: poolingEnabled,
            onChanged: onPoolingChanged,
          ),
          _TaxiSwitchLine(
            icon: Icons.family_restroom_outlined,
            title: isArabic ? 'وضع العائلة' : 'Family mode',
            subtitle: isArabic
                ? 'مشاركة المسار وثقة إضافية للعائلة.'
                : 'Shared route and extra family trust checks.',
            value: familyModeEnabled,
            onChanged: onFamilyModeChanged,
          ),
          _TaxiSwitchLine(
            icon: Icons.favorite_border_rounded,
            title: isArabic ? 'السائقون المفضلون' : 'Favorite drivers',
            subtitle: isArabic
                ? 'يفضل السائقين المحفوظين ويتجنب المحظورين.'
                : 'Prefers saved drivers and avoids blocked ones.',
            value: favoriteDriverEnabled,
            onChanged: onFavoriteDriverChanged,
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.add_location_alt_outlined,
          label: isArabic ? 'إضافة توقف' : 'Add stop',
          onPressed: onAddStop,
          primary: true,
        ),
      ],
    );
  }
}

class TaxiPassengerPostRideServicesPanel extends StatelessWidget {
  final int? fareMinorUnits;
  final int selectedTipPercent;
  final bool hasRidePass;
  final VoidCallback? onSendTip;
  final VoidCallback? onLostAndFound;
  final VoidCallback? onOpenDispute;
  final ValueChanged<int>? onTipPercentSelected;

  const TaxiPassengerPostRideServicesPanel({
    super.key,
    required this.fareMinorUnits,
    required this.selectedTipPercent,
    required this.hasRidePass,
    required this.onSendTip,
    required this.onLostAndFound,
    required this.onOpenDispute,
    required this.onTipPercentSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    final tipAmount = fareMinorUnits == null
        ? null
        : (fareMinorUnits! * selectedTipPercent) ~/ 100;
    return _TaxiFeatureCard(
      icon: Icons.receipt_long_outlined,
      title: isArabic ? 'خدمات بعد الرحلة' : 'Post-ride services',
      subtitle: isArabic
          ? 'بقشيش، مفقودات، اعتراض على السعر أو المسار، وRide Pass.'
          : 'Tips, lost and found, fare or route disputes, and Ride Pass.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.volunteer_activism_outlined,
          label: isArabic ? 'بقشيش' : 'Tip',
          value: _formatAmountOrDash(tipAmount, 'SYP'),
        ),
        TaxiFeatureMetric(
          icon: Icons.workspace_premium_outlined,
          label: 'Ride Pass',
          value: hasRidePass
              ? (isArabic ? 'مفعل' : 'Active')
              : (isArabic ? 'غير مفعل' : 'Off'),
        ),
        TaxiFeatureMetric(
          icon: Icons.inventory_2_outlined,
          label: isArabic ? 'مفقودات' : 'Lost item',
          value: isArabic ? 'جاهز' : 'Ready',
        ),
        TaxiFeatureMetric(
          icon: Icons.gavel_outlined,
          label: isArabic ? 'اعتراض' : 'Dispute',
          value: isArabic ? 'جاهز' : 'Ready',
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaxiChoiceRow(
            label: isArabic ? 'نسبة البقشيش' : 'Tip percentage',
            values: const <String>['0%', '10%', '15%', '20%'],
            selectedValue: '$selectedTipPercent%',
            onSelected: onTipPercentSelected == null
                ? null
                : (value) {
                    final percent =
                        int.tryParse(value.replaceAll('%', '').trim()) ?? 0;
                    onTipPercentSelected!(percent);
                  },
          ),
          const SizedBox(height: 10),
          _TaxiStepList(
            steps: <_TaxiFeatureStep>[
              _TaxiFeatureStep(
                icon: Icons.volunteer_activism_outlined,
                label: isArabic ? 'بقشيش للسائق' : 'Driver tip',
                detail: isArabic
                    ? 'يدفع عبر المحفظة أو يضاف للإيصال.'
                    : 'Paid through wallet or attached to the receipt.',
                active: selectedTipPercent > 0,
              ),
              _TaxiFeatureStep(
                icon: Icons.search_outlined,
                label: isArabic ? 'Lost & Found' : 'Lost and found',
                detail: isArabic
                    ? 'يربط البلاغ بالرحلة والسائق.'
                    : 'Links the report to the ride and driver.',
                active: true,
              ),
              _TaxiFeatureStep(
                icon: Icons.rule_folder_outlined,
                label: isArabic ? 'مركز الاعتراض' : 'Dispute center',
                detail: isArabic
                    ? 'للسعر، الطريق، الدفع أو سلوك السائق.'
                    : 'For fare, route, payment, or driver behavior.',
                active: true,
              ),
            ],
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.volunteer_activism_outlined,
          label: isArabic ? 'إرسال بقشيش' : 'Send tip',
          onPressed: onSendTip,
        ),
        TaxiFeatureAction(
          icon: Icons.inventory_2_outlined,
          label: isArabic ? 'مفقودات' : 'Lost item',
          onPressed: onLostAndFound,
        ),
        TaxiFeatureAction(
          icon: Icons.gavel_outlined,
          label: isArabic ? 'اعتراض' : 'Dispute',
          onPressed: onOpenDispute,
          primary: true,
        ),
      ],
    );
  }
}

class TaxiDriverGrowthPanel extends StatelessWidget {
  final int completedTodayCount;
  final int queueCount;
  final int? bonusMinorUnits;
  final int offlineQueueCount;
  final bool heatmapFresh;
  final VoidCallback? onOpenHeatmap;
  final VoidCallback? onOpenQuests;
  final VoidCallback? onSyncOffline;

  const TaxiDriverGrowthPanel({
    super.key,
    required this.completedTodayCount,
    required this.queueCount,
    required this.bonusMinorUnits,
    required this.offlineQueueCount,
    required this.heatmapFresh,
    required this.onOpenHeatmap,
    required this.onOpenQuests,
    required this.onSyncOffline,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    final questTarget = completedTodayCount >= 8 ? 12 : 8;
    return _TaxiFeatureCard(
      icon: Icons.local_fire_department_outlined,
      title: isArabic ? 'نمو السائق والطلب' : 'Driver growth and demand',
      subtitle: isArabic
          ? 'Heatmap، مناطق ساخنة، مكافآت، Quests وسينك أوفلاين.'
          : 'Heatmap, hot zones, bonuses, quests, and offline sync.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.map_outlined,
          label: 'Heatmap',
          value: heatmapFresh
              ? (isArabic ? 'حديث' : 'Fresh')
              : (isArabic ? 'ينتظر' : 'Waiting'),
          warning: !heatmapFresh,
        ),
        TaxiFeatureMetric(
          icon: Icons.emoji_events_outlined,
          label: isArabic ? 'المكافأة' : 'Bonus',
          value: _formatAmountOrDash(bonusMinorUnits, 'SYP'),
        ),
        TaxiFeatureMetric(
          icon: Icons.flag_outlined,
          label: 'Quest',
          value: '$completedTodayCount/$questTarget',
        ),
        TaxiFeatureMetric(
          icon: Icons.sync_problem_outlined,
          label: isArabic ? 'أوفلاين' : 'Offline',
          value: '$offlineQueueCount',
          warning: offlineQueueCount > 0,
        ),
      ],
      body: _TaxiStepList(
        steps: <_TaxiFeatureStep>[
          _TaxiFeatureStep(
            icon: Icons.where_to_vote_outlined,
            label: isArabic ? 'Hotspots' : 'Hotspots',
            detail: isArabic
                ? 'يرشد السائق إلى مناطق الطلب المتوقع.'
                : 'Guides the driver toward expected demand zones.',
            active: heatmapFresh,
          ),
          _TaxiFeatureStep(
            icon: Icons.bolt_outlined,
            label: isArabic ? 'مكافآت وقت الذروة' : 'Peak bonuses',
            detail: isArabic
                ? 'تحسب من الطلب المفتوح والرحلات المكتملة.'
                : 'Calculated from open demand and completed rides.',
            active: (bonusMinorUnits ?? 0) > 0,
          ),
          _TaxiFeatureStep(
            icon: Icons.offline_bolt_outlined,
            label: isArabic ? 'أوفلاين فallback' : 'Offline fallback',
            detail: isArabic
                ? 'يحفظ أوامر الرحلة مؤقتا عند ضعف الشبكة.'
                : 'Queues trip commands during weak connectivity.',
            active: true,
            warning: offlineQueueCount > 0,
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.map_outlined,
          label: 'Heatmap',
          onPressed: onOpenHeatmap,
        ),
        TaxiFeatureAction(
          icon: Icons.emoji_events_outlined,
          label: isArabic ? 'Quests' : 'Quests',
          onPressed: onOpenQuests,
        ),
        TaxiFeatureAction(
          icon: Icons.sync_outlined,
          label: isArabic ? 'Sync' : 'Sync offline',
          onPressed: onSyncOffline,
          primary: true,
        ),
      ],
    );
  }
}

class TaxiOperatorZoneControlPanel extends StatelessWidget {
  final String selectedZoneMode;
  final int activeZones;
  final int surgeZones;
  final int airportQueue;
  final int eventQueue;
  final int businessAccounts;
  final int childSeniorRides;
  final int disputeCount;
  final int lostFoundCount;
  final ValueChanged<String>? onZoneModeSelected;

  const TaxiOperatorZoneControlPanel({
    super.key,
    required this.selectedZoneMode,
    required this.activeZones,
    required this.surgeZones,
    required this.airportQueue,
    required this.eventQueue,
    required this.businessAccounts,
    required this.childSeniorRides,
    required this.disputeCount,
    required this.lostFoundCount,
    required this.onZoneModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    return _TaxiFeatureCard(
      icon: Icons.public_outlined,
      title: isArabic
          ? 'زونات التاكسي والتشغيل الخاص'
          : 'Taxi zones and special operations',
      subtitle: isArabic
          ? 'مطار، فنادق، فعاليات، مناطق Surge، أعمال، أطفال/كبار ومفقودات.'
          : 'Airport, hotels, events, surge zones, business rides, child/senior rides, and lost items.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.map_outlined,
          label: isArabic ? 'زونات' : 'Zones',
          value: '$activeZones',
        ),
        TaxiFeatureMetric(
          icon: Icons.price_change_outlined,
          label: 'Surge',
          value: '$surgeZones',
          warning: surgeZones > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.flight_takeoff_outlined,
          label: isArabic ? 'مطار' : 'Airport',
          value: '$airportQueue',
          warning: airportQueue > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.gavel_outlined,
          label: isArabic ? 'اعتراضات' : 'Disputes',
          value: '$disputeCount',
          warning: disputeCount > 0,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaxiChoiceRow(
            label: isArabic ? 'وضع الزونات' : 'Zone mode',
            values: taxiOperatorZoneModes,
            selectedValue: selectedZoneMode,
            onSelected: onZoneModeSelected,
          ),
          const SizedBox(height: 12),
          _TaxiStepList(
            steps: <_TaxiFeatureStep>[
              _TaxiFeatureStep(
                icon: Icons.event_available_outlined,
                label: isArabic
                    ? 'Airport / Hotel / Event'
                    : 'Airport, hotel, and event mode',
                detail: isArabic
                    ? '$airportQueue مطار، $eventQueue فعاليات تحتاج إسناد.'
                    : '$airportQueue airport and $eventQueue event rides need dispatch attention.',
                active: airportQueue == 0 && eventQueue == 0,
                warning: airportQueue + eventQueue > 0,
              ),
              _TaxiFeatureStep(
                icon: Icons.business_center_outlined,
                label: isArabic ? 'Business taxi' : 'Business taxi',
                detail: isArabic
                    ? '$businessAccounts حسابات أعمال نشطة بتكلفة/مركز تكلفة.'
                    : '$businessAccounts active business accounts with budgets and cost centers.',
                active: businessAccounts > 0,
              ),
              _TaxiFeatureStep(
                icon: Icons.elderly_outlined,
                label: isArabic ? 'أطفال وكبار السن' : 'Child and senior rides',
                detail: isArabic
                    ? '$childSeniorRides رحلات تحتاج متابعة ثقة.'
                    : '$childSeniorRides rides need trust monitoring.',
                active: childSeniorRides == 0,
                warning: childSeniorRides > 0,
              ),
              _TaxiFeatureStep(
                icon: Icons.inventory_2_outlined,
                label: isArabic ? 'Lost & Found' : 'Lost and found',
                detail: isArabic
                    ? '$lostFoundCount بلاغات مفقودات مفتوحة.'
                    : '$lostFoundCount open lost-item reports.',
                active: lostFoundCount == 0,
                warning: lostFoundCount > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TaxiPassengerTrustOptionsPanel extends StatelessWidget {
  final String ridePin;
  final bool routeDeviationAlertsEnabled;
  final int waitingGraceMinutes;
  final String selectedCancellationRule;
  final String selectedAccessibilityNeed;
  final bool petTaxiEnabled;
  final bool packageRideEnabled;
  final bool recurringRideEnabled;
  final bool pickupInstructionsReady;
  final int fareSplitContactCount;
  final int? promoCreditMinorUnits;
  final bool surgeExplanationVisible;
  final VoidCallback? onGenerateRidePin;
  final ValueChanged<bool>? onRouteDeviationAlertsChanged;
  final VoidCallback? onWaitingFeeInfo;
  final ValueChanged<String>? onCancellationRuleSelected;
  final ValueChanged<String>? onAccessibilityNeedSelected;
  final ValueChanged<bool>? onPetTaxiChanged;
  final ValueChanged<bool>? onPackageRideChanged;
  final ValueChanged<bool>? onRecurringRideChanged;
  final VoidCallback? onPickupInstructions;
  final VoidCallback? onFareSplit;
  final VoidCallback? onPromoCode;
  final VoidCallback? onSurgeExplanation;

  const TaxiPassengerTrustOptionsPanel({
    super.key,
    required this.ridePin,
    required this.routeDeviationAlertsEnabled,
    required this.waitingGraceMinutes,
    required this.selectedCancellationRule,
    required this.selectedAccessibilityNeed,
    required this.petTaxiEnabled,
    required this.packageRideEnabled,
    required this.recurringRideEnabled,
    required this.pickupInstructionsReady,
    required this.fareSplitContactCount,
    required this.promoCreditMinorUnits,
    required this.surgeExplanationVisible,
    required this.onGenerateRidePin,
    required this.onRouteDeviationAlertsChanged,
    required this.onWaitingFeeInfo,
    required this.onCancellationRuleSelected,
    required this.onAccessibilityNeedSelected,
    required this.onPetTaxiChanged,
    required this.onPackageRideChanged,
    required this.onRecurringRideChanged,
    required this.onPickupInstructions,
    required this.onFareSplit,
    required this.onPromoCode,
    required this.onSurgeExplanation,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    return _TaxiFeatureCard(
      icon: Icons.verified_user_outlined,
      title: isArabic ? 'الثقة وخيارات الرحلة' : 'Trust and ride options',
      subtitle: isArabic
          ? 'PIN، انحراف المسار، الانتظار، الإلغاء، الحيوانات، الشحن، التكرار، التقسيم والعروض.'
          : 'Pickup PIN, route deviation, waiting rules, cancellations, pets, courier, recurring rides, split fare, and promos.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.password_outlined,
          label: isArabic ? 'PIN' : 'Pickup PIN',
          value: ridePin.trim().isEmpty ? '--' : ridePin,
        ),
        TaxiFeatureMetric(
          icon: Icons.timer_outlined,
          label: isArabic ? 'انتظار' : 'Waiting',
          value:
              isArabic ? '$waitingGraceMinutes د' : '$waitingGraceMinutes min',
        ),
        TaxiFeatureMetric(
          icon: Icons.group_add_outlined,
          label: isArabic ? 'تقسيم' : 'Split',
          value: '$fareSplitContactCount',
        ),
        TaxiFeatureMetric(
          icon: Icons.sell_outlined,
          label: isArabic ? 'رصيد' : 'Promo',
          value: _formatAmountOrDash(promoCreditMinorUnits, 'SYP'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TaxiChoiceRow(
            label: isArabic ? 'سياسة الإلغاء' : 'Cancellation rule',
            values: taxiRideCancellationRules,
            selectedValue: selectedCancellationRule,
            onSelected: onCancellationRuleSelected,
          ),
          const SizedBox(height: 10),
          _TaxiChoiceRow(
            label: isArabic ? 'احتياج خاص' : 'Accessibility need',
            values: taxiRideAccessibilityNeeds,
            selectedValue: selectedAccessibilityNeed,
            onSelected: onAccessibilityNeedSelected,
          ),
          const SizedBox(height: 8),
          _TaxiSwitchLine(
            icon: Icons.alt_route_outlined,
            title: isArabic ? 'تنبيه انحراف المسار' : 'Route-deviation alerts',
            subtitle: isArabic
                ? 'ينبه عند الابتعاد عن المسار المخطط.'
                : 'Warns when the ride moves far from the planned route.',
            value: routeDeviationAlertsEnabled,
            onChanged: onRouteDeviationAlertsChanged,
          ),
          _TaxiSwitchLine(
            icon: Icons.pets_outlined,
            title: isArabic ? 'Pet Taxi' : 'Pet taxi',
            subtitle: isArabic
                ? 'يطلب سائقا يقبل الحيوانات الأليفة.'
                : 'Requests a driver who accepts pets.',
            value: petTaxiEnabled,
            onChanged: onPetTaxiChanged,
          ),
          _TaxiSwitchLine(
            icon: Icons.inventory_2_outlined,
            title: isArabic ? 'إرسال طرد' : 'Package / courier ride',
            subtitle: isArabic
                ? 'رحلة توصيل صغيرة بدون راكب.'
                : 'Small package delivery without a passenger.',
            value: packageRideEnabled,
            onChanged: onPackageRideChanged,
          ),
          _TaxiSwitchLine(
            icon: Icons.event_available_outlined,
            title: isArabic ? 'رحلة متكررة' : 'Recurring ride',
            subtitle: isArabic
                ? 'حفظ مشوار متكرر للعمل، المدرسة أو المطار.'
                : 'Save a recurring commute, school, or airport ride.',
            value: recurringRideEnabled,
            onChanged: onRecurringRideChanged,
          ),
          const SizedBox(height: 8),
          _TaxiStepList(
            steps: <_TaxiFeatureStep>[
              _TaxiFeatureStep(
                icon: Icons.notes_outlined,
                label: isArabic ? 'تعليمات الالتقاط' : 'Pickup instructions',
                detail: pickupInstructionsReady
                    ? (isArabic
                        ? 'تم تجهيز تعليمات الالتقاط للسائق.'
                        : 'Pickup note is ready for the driver.')
                    : (isArabic
                        ? 'أضف وصفا أو علامة مميزة عند نقطة الالتقاط.'
                        : 'Add a note or landmark at the pickup point.'),
                active: pickupInstructionsReady,
              ),
              _TaxiFeatureStep(
                icon: Icons.price_check_outlined,
                label: isArabic ? 'شرح Surge' : 'Surge explanation',
                detail: surgeExplanationVisible
                    ? (isArabic
                        ? 'سبب السعر المرتفع ظاهر قبل التأكيد.'
                        : 'The reason for the higher fare is visible before confirmation.')
                    : (isArabic
                        ? 'يعرض الطلب، المرور والمنطقة عند الحاجة.'
                        : 'Shows demand, traffic, and zone factors when needed.'),
                active: surgeExplanationVisible,
              ),
            ],
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.password_outlined,
          label: isArabic ? 'إنشاء PIN' : 'Pickup PIN',
          onPressed: onGenerateRidePin,
        ),
        TaxiFeatureAction(
          icon: Icons.timer_outlined,
          label: isArabic ? 'الانتظار' : 'Waiting fee',
          onPressed: onWaitingFeeInfo,
        ),
        TaxiFeatureAction(
          icon: Icons.notes_outlined,
          label: isArabic ? 'تعليمات' : 'Pickup note',
          onPressed: onPickupInstructions,
        ),
        TaxiFeatureAction(
          icon: Icons.call_split_outlined,
          label: isArabic ? 'تقسيم السعر' : 'Split fare',
          onPressed: onFareSplit,
        ),
        TaxiFeatureAction(
          icon: Icons.sell_outlined,
          label: isArabic ? 'Promo' : 'Promo code',
          onPressed: onPromoCode,
        ),
        TaxiFeatureAction(
          icon: Icons.info_outline,
          label: isArabic ? 'Surge' : 'Surge info',
          onPressed: onSurgeExplanation,
          primary: true,
        ),
      ],
    );
  }
}

class TaxiDriverOperationsPanel extends StatelessWidget {
  final bool hasActiveTrip;
  final bool pickupCodeRequired;
  final bool navigationReady;
  final bool waitingTimerActive;
  final bool vehicleChecklistReady;
  final bool packageModeEnabled;
  final bool pickupInstructionsReady;
  final int rematchCandidateCount;
  final VoidCallback? onVerifyPickupCode;
  final VoidCallback? onOpenNavigation;
  final VoidCallback? onStartWaitingTimer;
  final VoidCallback? onCompleteVehicleChecklist;
  final VoidCallback? onConfirmPackageHandoff;
  final VoidCallback? onRequestRematch;

  const TaxiDriverOperationsPanel({
    super.key,
    required this.hasActiveTrip,
    required this.pickupCodeRequired,
    required this.navigationReady,
    required this.waitingTimerActive,
    required this.vehicleChecklistReady,
    required this.packageModeEnabled,
    required this.pickupInstructionsReady,
    required this.rematchCandidateCount,
    required this.onVerifyPickupCode,
    required this.onOpenNavigation,
    required this.onStartWaitingTimer,
    required this.onCompleteVehicleChecklist,
    required this.onConfirmPackageHandoff,
    required this.onRequestRematch,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    return _TaxiFeatureCard(
      icon: Icons.navigation_outlined,
      title: isArabic ? 'تشغيل الرحلة للسائق' : 'Driver trip operations',
      subtitle: isArabic
          ? 'PIN الالتقاط، الملاحة، الانتظار، فحص المركبة، الطرود وإعادة المطابقة.'
          : 'Pickup PIN, navigation launch, waiting timer, vehicle checklist, package handoff, and rematch.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.password_outlined,
          label: isArabic ? 'PIN' : 'PIN',
          value: pickupCodeRequired
              ? (isArabic ? 'مطلوب' : 'Required')
              : (isArabic ? 'جاهز' : 'Ready'),
          warning: pickupCodeRequired && hasActiveTrip,
        ),
        TaxiFeatureMetric(
          icon: Icons.navigation_outlined,
          label: isArabic ? 'ملاحة' : 'Navigation',
          value: navigationReady
              ? (isArabic ? 'جاهز' : 'Ready')
              : (isArabic ? 'ينتظر' : 'Waiting'),
        ),
        TaxiFeatureMetric(
          icon: Icons.fact_check_outlined,
          label: isArabic ? 'فحص' : 'Checklist',
          value: vehicleChecklistReady
              ? (isArabic ? 'تم' : 'Done')
              : (isArabic ? 'مطلوب' : 'Needed'),
          warning: !vehicleChecklistReady,
        ),
        TaxiFeatureMetric(
          icon: Icons.manage_search_outlined,
          label: isArabic ? 'Rematch' : 'Rematch',
          value: '$rematchCandidateCount',
          warning: rematchCandidateCount > 0,
        ),
      ],
      body: _TaxiStepList(
        steps: <_TaxiFeatureStep>[
          _TaxiFeatureStep(
            icon: Icons.notes_outlined,
            label: isArabic ? 'تعليمات الالتقاط' : 'Pickup instructions',
            detail: pickupInstructionsReady
                ? (isArabic
                    ? 'تعليمات الراكب جاهزة قبل الوصول.'
                    : 'Rider pickup instructions are ready before arrival.')
                : (isArabic
                    ? 'تظهر التعليمات عند إضافتها من الراكب.'
                    : 'Instructions appear when the rider adds them.'),
            active: pickupInstructionsReady,
          ),
          _TaxiFeatureStep(
            icon: Icons.timer_outlined,
            label: isArabic ? 'عداد الانتظار' : 'Waiting timer',
            detail: waitingTimerActive
                ? (isArabic
                    ? 'يحسب الانتظار بعد فترة السماح.'
                    : 'Counts waiting after the grace period.')
                : (isArabic
                    ? 'ابدأه عند الوصول إلى نقطة الالتقاط.'
                    : 'Start it when arriving at pickup.'),
            active: waitingTimerActive,
          ),
          _TaxiFeatureStep(
            icon: Icons.inventory_2_outlined,
            label: isArabic ? 'تسليم الطرد' : 'Package handoff',
            detail: packageModeEnabled
                ? (isArabic
                    ? 'يتطلب تأكيد استلام وتسليم.'
                    : 'Requires pickup and delivery confirmation.')
                : (isArabic
                    ? 'غير مفعل لهذه الرحلة.'
                    : 'Not enabled for this trip.'),
            active: packageModeEnabled,
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.password_outlined,
          label: isArabic ? 'تحقق PIN' : 'Verify PIN',
          onPressed: onVerifyPickupCode,
        ),
        TaxiFeatureAction(
          icon: Icons.navigation_outlined,
          label: isArabic ? 'ملاحة' : 'Navigate',
          onPressed: onOpenNavigation,
          primary: true,
        ),
        TaxiFeatureAction(
          icon: Icons.timer_outlined,
          label: isArabic ? 'انتظار' : 'Waiting',
          onPressed: onStartWaitingTimer,
        ),
        TaxiFeatureAction(
          icon: Icons.fact_check_outlined,
          label: isArabic ? 'فحص المركبة' : 'Checklist',
          onPressed: onCompleteVehicleChecklist,
        ),
        TaxiFeatureAction(
          icon: Icons.inventory_2_outlined,
          label: isArabic ? 'طرد' : 'Package',
          onPressed: onConfirmPackageHandoff,
        ),
        TaxiFeatureAction(
          icon: Icons.manage_search_outlined,
          label: isArabic ? 'Rematch' : 'Rematch',
          onPressed: onRequestRematch,
        ),
      ],
    );
  }
}

class TaxiOperatorAssurancePanel extends StatelessWidget {
  final int routeDeviationAlerts;
  final int noShowReviews;
  final int autoRematchCandidates;
  final int expiringDocuments;
  final int incidentEvidenceBundles;
  final int rideReplayCount;
  final int accessibilityRideCount;
  final int packageRideCount;
  final int promoCreditRequests;
  final VoidCallback? onOpenRideReplay;
  final VoidCallback? onPrepareEvidenceBundle;
  final VoidCallback? onRunAutoRematch;
  final VoidCallback? onOpenDocumentExpiry;

  const TaxiOperatorAssurancePanel({
    super.key,
    required this.routeDeviationAlerts,
    required this.noShowReviews,
    required this.autoRematchCandidates,
    required this.expiringDocuments,
    required this.incidentEvidenceBundles,
    required this.rideReplayCount,
    required this.accessibilityRideCount,
    required this.packageRideCount,
    required this.promoCreditRequests,
    required this.onOpenRideReplay,
    required this.onPrepareEvidenceBundle,
    required this.onRunAutoRematch,
    required this.onOpenDocumentExpiry,
  });

  @override
  Widget build(BuildContext context) {
    final isArabic = Directionality.maybeOf(context) == TextDirection.rtl;
    return _TaxiFeatureCard(
      icon: Icons.admin_panel_settings_outlined,
      title:
          isArabic ? 'ضمان الجودة والتشغيل' : 'Taxi assurance and operations',
      subtitle: isArabic
          ? 'انحراف المسار، No-show، انتهاء الوثائق، الأدلة، Replay، Rematch، Accessibility، الطرود وPromo.'
          : 'Route deviation, no-show, document expiry, evidence bundles, ride replay, rematch, accessibility, packages, and promos.',
      metrics: <TaxiFeatureMetric>[
        TaxiFeatureMetric(
          icon: Icons.alt_route_outlined,
          label: isArabic ? 'انحراف' : 'Deviation',
          value: '$routeDeviationAlerts',
          warning: routeDeviationAlerts > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.event_busy_outlined,
          label: 'No-show',
          value: '$noShowReviews',
          warning: noShowReviews > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.badge_outlined,
          label: isArabic ? 'وثائق' : 'Docs',
          value: '$expiringDocuments',
          warning: expiringDocuments > 0,
        ),
        TaxiFeatureMetric(
          icon: Icons.manage_search_outlined,
          label: 'Rematch',
          value: '$autoRematchCandidates',
          warning: autoRematchCandidates > 0,
        ),
      ],
      body: _TaxiStepList(
        steps: <_TaxiFeatureStep>[
          _TaxiFeatureStep(
            icon: Icons.folder_copy_outlined,
            label: isArabic ? 'حزمة أدلة الحادث' : 'Incident evidence bundle',
            detail: isArabic
                ? '$incidentEvidenceBundles حزم تجمع المسار، الدردشة، الدفع والتايملاين.'
                : '$incidentEvidenceBundles bundles combine route, chat, payment, and timeline.',
            active: incidentEvidenceBundles > 0,
          ),
          _TaxiFeatureStep(
            icon: Icons.history_outlined,
            label: isArabic ? 'Ride replay' : 'Operator ride replay',
            detail: isArabic
                ? '$rideReplayCount رحلات جاهزة للمراجعة كتسلسل زمني.'
                : '$rideReplayCount rides are ready for timeline review.',
            active: rideReplayCount > 0,
          ),
          _TaxiFeatureStep(
            icon: Icons.accessibility_new_outlined,
            label: isArabic
                ? 'Accessibility / Package'
                : 'Accessibility and package rides',
            detail: isArabic
                ? '$accessibilityRideCount احتياجات خاصة، $packageRideCount طرود.'
                : '$accessibilityRideCount accessibility rides, $packageRideCount package rides.',
            active: accessibilityRideCount + packageRideCount > 0,
          ),
          _TaxiFeatureStep(
            icon: Icons.sell_outlined,
            label: isArabic ? 'Promo credits' : 'Promo credits',
            detail: isArabic
                ? '$promoCreditRequests طلبات رصيد أو تعويض.'
                : '$promoCreditRequests credit or compensation requests.',
            active: promoCreditRequests > 0,
          ),
        ],
      ),
      actions: <TaxiFeatureAction>[
        TaxiFeatureAction(
          icon: Icons.history_outlined,
          label: isArabic ? 'Replay' : 'Replay',
          onPressed: onOpenRideReplay,
        ),
        TaxiFeatureAction(
          icon: Icons.folder_copy_outlined,
          label: isArabic ? 'أدلة' : 'Evidence',
          onPressed: onPrepareEvidenceBundle,
          primary: true,
        ),
        TaxiFeatureAction(
          icon: Icons.manage_search_outlined,
          label: isArabic ? 'Rematch' : 'Auto-rematch',
          onPressed: onRunAutoRematch,
        ),
        TaxiFeatureAction(
          icon: Icons.badge_outlined,
          label: isArabic ? 'وثائق' : 'Doc expiry',
          onPressed: onOpenDocumentExpiry,
        ),
      ],
    );
  }
}

class _TaxiFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<TaxiFeatureMetric> metrics;
  final Widget body;
  final List<TaxiFeatureAction> actions;

  const _TaxiFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.metrics,
    required this.body,
    this.actions = const <TaxiFeatureAction>[],
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .38 : .82),
          width: .7,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? .14 : .04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: isDark ? .42 : .22,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: .72,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (metrics.isNotEmpty) ...[
              const SizedBox(height: 12),
              _TaxiMetricWrap(metrics: metrics),
            ],
            const SizedBox(height: 12),
            body,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              _TaxiActionWrap(actions: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaxiMetricWrap extends StatelessWidget {
  final List<TaxiFeatureMetric> metrics;

  const _TaxiMetricWrap({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: metrics
          .map(
            (metric) => Container(
              constraints: const BoxConstraints(minWidth: 128),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: metric.warning
                    ? theme.colorScheme.errorContainer.withValues(alpha: .58)
                    : (theme.brightness == Brightness.dark
                        ? theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: .28)
                        : WeChatPalette.searchFill),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: metric.warning
                      ? theme.colorScheme.error.withValues(alpha: .26)
                      : theme.dividerColor.withValues(alpha: .70),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    metric.icon,
                    size: 18,
                    color: metric.warning
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          metric.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: .70,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          metric.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _TaxiStepList extends StatelessWidget {
  final List<_TaxiFeatureStep> steps;

  const _TaxiStepList({required this.steps});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: steps
          .map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: step.warning
                          ? theme.colorScheme.errorContainer
                          : step.active
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                    ),
                    child: Icon(
                      step.icon,
                      size: 18,
                      color: step.warning
                          ? theme.colorScheme.error
                          : step.active
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: .58,
                                ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.detail,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: .72,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _TaxiChoiceRow extends StatelessWidget {
  final String label;
  final List<String> values;
  final String selectedValue;
  final ValueChanged<String>? onSelected;

  const _TaxiChoiceRow({
    required this.label,
    required this.values,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values
              .map(
                (value) => ChoiceChip(
                  label: Text(value),
                  selected: selectedValue == value,
                  onSelected: onSelected == null
                      ? null
                      : (selected) {
                          if (selected) onSelected!(value);
                        },
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _TaxiSwitchLine extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _TaxiSwitchLine({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .72),
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _TaxiActionWrap extends StatelessWidget {
  final List<TaxiFeatureAction> actions;

  const _TaxiActionWrap({required this.actions});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: actions
          .map(
            (action) => action.primary
                ? FilledButton.icon(
                    onPressed: action.onPressed,
                    icon: Icon(action.icon),
                    label: Text(action.label),
                  )
                : OutlinedButton.icon(
                    onPressed: action.onPressed,
                    icon: Icon(action.icon),
                    label: Text(action.label),
                  ),
          )
          .toList(growable: false),
    );
  }
}

class _TaxiInlineInfo extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TaxiInlineInfo({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
