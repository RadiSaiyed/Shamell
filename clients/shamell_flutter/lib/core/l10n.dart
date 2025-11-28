import 'package:flutter/material.dart';

class L10n {
  final Locale locale;

  const L10n(this.locale);

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
  ];

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n) ?? L10n(const Locale('en'));
  }

  bool get isArabic => locale.languageCode.toLowerCase().startsWith('ar');

  // High-level labels
  String get appTitle => isArabic ? 'شامل' : 'Shamell';

  // Login
  String get loginTitle => isArabic ? 'تسجيل الدخول' : 'Sign in';
  String get loginBaseUrl =>
      isArabic ? 'رابط خادم الـ BFF' : 'BFF Base URL';
  String get loginFullName =>
      isArabic ? 'الاسم الكامل' : 'Full name';
  String get loginPhone =>
      isArabic ? 'رقم الهاتف (+963…)' : 'Phone (+963…)';
  String get loginRequestCode =>
      isArabic ? 'طلب رمز' : 'Request code';
  String get loginCodeLabel =>
      isArabic ? 'رمز مكون من 6 أرقام' : 'Code (6 digits)';
  String get loginVerify =>
      isArabic ? 'تأكيد' : 'Verify';
  String get loginNoteDemo =>
      isArabic
          ? 'ملاحظة: يُعرض رمز الاختبار في مربع حوار (بيئة التطوير فقط).'
          : 'Note: Demo OTP is shown in a dialog (dev only).';
  String get loginTooManyAttempts =>
      isArabic
          ? 'محاولات كثيرة. يرجى الانتظار قليلاً.'
          : 'Too many attempts. Please wait a moment.';
  String get loginInvalidCode =>
      isArabic ? 'رمز غير صالح. حاول مرة أخرى.' : 'Invalid code. Please try again.';
  String get loginSignedIn =>
      isArabic ? 'تم تسجيل الدخول بنجاح.' : 'Signed in successfully.';
  String get loginFailed =>
      isArabic ? 'فشل تسجيل الدخول' : 'Login failed';

  // Home quick actions
  String get qaScanPay =>
      isArabic ? 'مسح و دفع' : 'Scan & pay';
  String get qaP2P =>
      isArabic ? 'تحويل شخصي' : 'P2P';
  String get qaTopup =>
      isArabic ? 'شحن الرصيد' : 'Topup';
  String get qaSonic =>
      isArabic ? 'فوري' : 'Sonic';

  // Ops / System status
  String get opsTitle =>
      isArabic ? 'العمليات والإدارة' : 'Ops & Admin';
  String get opsSystemStatus =>
      isArabic ? 'حالة النظام' : 'System status';

  String get systemStatusTitle =>
      isArabic ? 'حالة النظام' : 'System status';
  String get systemStatusStatusLabel =>
      isArabic ? 'الحالة' : 'Status';
  String get systemStatusHttpLabel =>
      'HTTP'; // remains short and common in AR as well

  // Generic titles
  String get settingsTitle =>
      isArabic ? 'الإعدادات' : 'Settings';
  String get chatTitle =>
      isArabic ? 'الدردشة' : 'Chat';
  String get sonicTitle =>
      isArabic ? 'دفعة Sonic' : 'Sonic Pay';
  String get vouchersTitle =>
      isArabic ? 'قسائم الشحن' : 'Vouchers';
  String get busTitle =>
      isArabic ? 'الحافلات' : 'Bus';
  String get staysOperatorTitle =>
      isArabic ? 'الإقامات والفنادق' : 'Stays & Hotel';

  // Home / modules
  String get homeActions =>
      isArabic ? 'الإجراءات' : 'Actions';
  String get homeTaxi =>
      isArabic ? 'تاكسي' : 'Taxi';
  String get homeTaxiRider =>
      isArabic ? 'راكب تاكسي' : 'Taxi';
  String get homeTaxiDriver =>
      isArabic ? 'سائق تاكسي' : 'Taxi Driver';
  String get homeTaxiOperator =>
      isArabic ? 'مشغل تاكسي' : 'Taxi Operator';
  String get homePayments =>
      isArabic ? 'المدفوعات' : 'Payment';
  String get homeWallet =>
      isArabic ? 'المحفظة' : 'Wallet';
  String get homeBills =>
      isArabic ? 'الفواتير' : 'Bills';
  String get homeRequests =>
      isArabic ? 'الطلبات' : 'Requests';
  String get homeVouchers =>
      isArabic ? 'قسائم' : 'Vouchers';
  String get homeFood =>
      isArabic ? 'الطعام' : 'Food';
  String get homeStays =>
      isArabic ? 'الفنادق والإقامات' : 'Hotels & Stays';
  String get homeBus =>
      isArabic ? 'الحافلات' : 'Bus';
  String get homeChat =>
      isArabic ? 'الدردشة' : 'Chat';
  String get homeDoctors =>
      isArabic ? 'الأطباء' : 'Doctors';
  String get homeFlights =>
      isArabic ? 'الرحلات' : 'Flights';
  String get homeJobs =>
      isArabic ? 'الوظائف' : 'Jobs';
  String get homeAgriculture =>
      isArabic ? 'الزراعة والثروة الحيوانية' : 'Agriculture & Livestock';
  String get homeLivestock =>
      isArabic ? 'الزراعة والثروة الحيوانية' : 'Agriculture & Livestock';
  String get homeCommerce =>
      isArabic ? 'السوق' : 'Marketplace';
  String get homeMerchantPos =>
      isArabic ? 'نقطة بيع التاجر' : 'Merchant POS';
  String get homeBuildingMaterials =>
      isArabic ? 'مواد البناء' : 'Building Materials';
  String get homeTopup =>
      isArabic ? 'شحن الرصيد' : 'Topup';

  // Settings / debug
  String get settingsBaseUrl =>
      isArabic ? 'رابط الخادم' : 'Base URL';
  String get settingsMyWallet =>
      isArabic ? 'محفظتي' : 'My Wallet';
  String get settingsUiRoute =>
      isArabic ? 'مسار الواجهة' : 'UI Route';
  String get settingsUiRouteA =>
      isArabic ? 'A — مركز وأقمار' : 'A — Hub & Satellites';
  String get settingsUiRouteB =>
      isArabic ? 'B — لوحة أوامر' : 'B — Command Palette';
  String get settingsUiRouteC =>
      isArabic ? 'C — أوراق سياق' : 'C — Context Sheets';
  String get settingsDebugSkeleton =>
      isArabic ? 'تصحيح: هياكل طويلة (1200 مللي ثانية)' : 'Debug: Long skeletons (1200 ms)';
  String get settingsSkipLogin =>
      isArabic ? 'تخطي تسجيل الدخول (تجريبي)' : 'Skip Login (Demo)';
  String get settingsSendMetrics =>
      isArabic ? 'إرسال المقاييس إلى الخادم' : 'Send metrics to backend';
  String get settingsSave =>
      isArabic ? 'حفظ' : 'Save';

  // Chat
  String get chatIdentity =>
      isArabic ? 'الهوية' : 'Identity';
  String get chatMyDeviceId =>
      isArabic ? 'معرّف جهازي' : 'My device id';
  String get chatDisplayName =>
      isArabic ? 'اسم العرض' : 'Display name';
  String get chatGenerate =>
      isArabic ? 'توليد' : 'Generate';
  String get chatRegister =>
      isArabic ? 'تسجيل' : 'Register';
  String get chatMyFingerprint =>
      isArabic ? 'بصمتي:' : 'My fingerprint:';
  String get chatMyPublicKey =>
      isArabic ? 'المفتاح العام' : 'My public key';
  String get chatPeer =>
      isArabic ? 'الطرف الآخر' : 'Peer';
  String get chatPeerId =>
      isArabic ? 'معرّف الطرف الآخر' : 'Peer id';
  String get chatResolve =>
      isArabic ? 'استعلام' : 'Resolve';
  String get chatPeerFp =>
      isArabic ? 'بصمة الطرف الآخر:' : 'Peer fp:';
  String get chatVerified =>
      isArabic ? 'مؤكد ✅' : 'Verified ✅';
  String get chatUnverified =>
      isArabic ? 'غير مؤكد ❌' : 'Unverified ❌';
  String get chatMarkVerified =>
      isArabic ? 'وضع علامة كمؤكد' : 'Mark verified';
  String get chatMessage =>
      isArabic ? 'الرسالة' : 'Message';
  String get chatSend =>
      isArabic ? 'إرسال' : 'Send';
  String get chatPoll =>
      isArabic ? 'استعلام' : 'Poll';
  String get chatAttachImage =>
      isArabic ? 'إرفاق صورة' : 'Attach image';
  String get chatOut =>
      isArabic ? 'خرج:' : 'Out:';
  String get chatInbox =>
      isArabic ? 'الوارد (مباشر عبر WS + استعلام)' : 'Inbox (live via WS + poll)';

  // Sonic / Vouchers / Cash
  String get sonicFromWallet =>
      isArabic ? 'من المحفظة' : 'From wallet';
  String get sonicToWalletOpt =>
      isArabic ? 'إلى المحفظة (اختياري)' : 'To wallet (optional)';
  String get labelAmount =>
      isArabic ? 'المبلغ (ليرة)' : 'Amount (SYP)';
  String get sonicIssueToken =>
      isArabic ? 'إصدار رمز' : 'Issue token';
  String get sonicRedeem =>
      isArabic ? 'استبدال' : 'Redeem';
  String get cashSecretPhraseOpt =>
      isArabic ? 'عبارة سرية (اختياري)' : 'Secret phrase (optional)';
  String get cashCreate =>
      isArabic ? 'إنشاء' : 'Create';
  String get cashStatus =>
      isArabic ? 'الحالة' : 'Status';
  String get cashCancel =>
      isArabic ? 'إلغاء' : 'Cancel';
  String get cashRedeem =>
      isArabic ? 'استبدال' : 'Redeem';
  String get labelCode =>
      isArabic ? 'الرمز' : 'Code';
  String get vouchersTitleText =>
      isArabic ? 'قسائم الشحن' : 'Vouchers';

  // Generic emergency / complaints
  String get emergencyTitle =>
      isArabic ? 'الطوارئ' : 'Emergency';
  String get emergencyPolice =>
      isArabic ? 'الشرطة' : 'Police';
  String get emergencyAmbulance =>
      isArabic ? 'الإسعاف' : 'Ambulance';
  String get emergencyFire =>
      isArabic ? 'الإطفاء' : 'Fire';
  String get complaintsTitle =>
      isArabic ? 'الشكاوى' : 'Complaints';
  String get complaintsEmailUs =>
      isArabic ? 'راسلنا عبر البريد' : 'Email us';

  // Main menu (bottom sheet)
  String get menuProfile =>
      isArabic ? 'الملف الشخصي' : 'Profile';
  String get menuTrips =>
      isArabic ? 'الرحلات' : 'Trips';
  String get menuRoles =>
      isArabic ? 'الأدوار (مستخدم / مشغل / مسؤول)' : 'Roles (User / Operator / Admin)';
  String get menuEmergency =>
      isArabic ? 'أرقام الطوارئ' : 'Emergency numbers';
  String get menuComplaints =>
      isArabic ? 'الشكاوى' : 'Complaints';
  String get menuCallUs =>
      isArabic ? 'اتصل بنا' : 'Call us';
  String get menuSwitchMode =>
      isArabic ? 'تبديل وضع التطبيق' : 'Switch app mode';
  String get menuLogout =>
      isArabic ? 'تسجيل الخروج' : 'Logout';
  String get menuOperatorConsole =>
      isArabic ? 'لوحة المشغل' : 'Operator console';
  String get menuAdminConsole =>
      isArabic ? 'لوحة المسؤول' : 'Admin console';
  String get menuSuperadminConsole =>
      isArabic ? 'لوحة السوبر أدمن' : 'Superadmin console';

  // Common labels
  String get labelWalletId =>
      isArabic ? 'معرف المحفظة' : 'Wallet ID';
  String get labelName =>
      isArabic ? 'الاسم' : 'Name';
  String get labelPhone =>
      isArabic ? 'الهاتف' : 'Phone';
  String get msgWalletCopied =>
      isArabic ? 'تم نسخ معرف المحفظة' : 'Wallet copied';
  String get profileTitle =>
      isArabic ? 'الملف الشخصي' : 'Profile';
  String get rolesOverviewTitle =>
      isArabic ? 'نظرة عامة على الأدوار' : 'Roles overview';

  // Generic small labels
  String get labelPage =>
      isArabic ? 'صفحة' : 'page';
  String get labelSize =>
      isArabic ? 'الحجم' : 'size';
  String get labelSearch =>
      isArabic ? 'بحث' : 'search';
  String get labelCity =>
      isArabic ? 'المدينة' : 'city';

  String get viewAll =>
      isArabic ? 'عرض الكل' : 'View all';
  String get notSet =>
      isArabic ? 'غير معيّن' : '(not set)';

  // Real‑estate / stays helpers
  String get rsBrowseByPropertyType =>
      isArabic ? 'تصفح حسب نوع العقار' : 'Browse by property type';
  String get rsPropertyType =>
      isArabic ? 'نوع العقار' : 'Property type';
  String get rsAllTypes =>
      isArabic ? 'كل الأنواع' : 'All types';
  String get rsAvailable =>
      isArabic ? 'متاح' : 'Available';
  String get rsUnavailable =>
      isArabic ? 'غير متاح' : 'Unavailable';
  String get rsPrices =>
      isArabic ? 'الأسعار' : 'Prices';
  String get rsSelect =>
      isArabic ? 'اختيار' : 'Select';
  String get rsSelectedListingPrefix =>
      isArabic ? 'تم اختيار العقار #' : 'Selected listing #';

  String get realEstateTitle =>
      isArabic ? 'العقارات' : 'RealEstate';
  String get rePropertyId =>
      isArabic ? 'معرف العقار' : 'property id';
  String get reBuyerWallet =>
      isArabic ? 'محفظة المشتري' : 'buyer wallet';
  String get reDeposit =>
      isArabic ? 'الدفعة المقدمة (SYP)' : 'deposit (SYP)';
  String get reSearch =>
      isArabic ? 'بحث' : 'Search';
  String get reReserveAndPay =>
      isArabic ? 'حجز و دفع' : 'Reserve & Pay';
  String get reSendInquiry =>
      isArabic ? 'إرسال استفسار' : 'Send inquiry';

  // Small stats labels
  String get taxiTodayTitle =>
      isArabic ? 'تاكسي · اليوم' : 'Taxi · Today';
  String get busTodayTitle =>
      isArabic ? 'الحافلات · اليوم' : 'Bus · Today';
  String get ridesLabel =>
      isArabic ? 'رحلات' : 'rides';
  String get completedLabel =>
      isArabic ? 'مكتملة' : 'completed';
  String get tripsLabel =>
      isArabic ? 'رحلات' : 'trips';
  String get bookingsLabel =>
      isArabic ? 'حجوزات' : 'bookings';

  // Bus booking / history
  String get busBookingTitle =>
      isArabic ? 'حجز الحافلة' : 'Bus booking';
  String get busSearchSectionTitle =>
      isArabic ? 'البحث عن رحلات الحافلات' : 'Search bus trips';
  String get busPaymentSectionTitle =>
      isArabic ? 'الدفع' : 'Payment';
  String get busAvailableTripsTitle =>
      isArabic ? 'الرحلات المتاحة' : 'Available trips';
  String get busNoTripsHint =>
      isArabic
          ? 'لا توجد رحلات بعد – ابحث باستخدام نقطة الانطلاق والوصول والتاريخ.'
          : 'No trips yet – search with origin, destination and date.';
  String get busDatePrefix =>
      isArabic ? 'التاريخ' : 'Date';
  String get busSearchButton =>
      isArabic ? 'بحث' : 'Search';
  String get busSelectOriginDestError =>
      isArabic ? 'يرجى اختيار نقطة الانطلاق والوصول' : 'Please select origin and destination';
  String get busSearchErrorBanner =>
      isArabic ? 'حدث خطأ أثناء البحث عن الرحلات' : 'Error while searching for trips';
  String busFoundTripsBanner(int count, String dateStr) =>
      isArabic
          ? 'تم العثور على $count رحلات للتاريخ $dateStr'
          : 'Found $count trips for $dateStr';
  String get busTicketsTitle =>
      isArabic ? 'التذاكر' : 'Tickets';
  String get busTicketsCopyLabel =>
      isArabic ? 'نسخ' : 'Copy';
  String get busTicketsCopiedSnack =>
      isArabic ? 'تم نسخ الحمولة إلى الحافظة' : 'Payload copied to clipboard';
  String get busPayerWalletLabel =>
      isArabic ? 'محفظة الدافع (مستحسن)' : 'Payer wallet (recommended)';
  String get busPayerWalletHintFilled =>
      isArabic
          ? 'ستدفع من المحفظة وتستلم التذاكر فوراً.'
          : 'You pay from your wallet and get instant tickets.';
  String get busPayerWalletHintEmpty =>
      isArabic
          ? 'أضف معرف محفظتك للدفع داخل التطبيق والحصول على التذاكر فوراً.'
          : 'Add your wallet ID to pay in-app and get instant tickets.';
  String get busSeatsLabel =>
      isArabic ? 'الركاب' : 'Passenger';
  String get busMyTripsTitle =>
      isArabic ? 'رحلات الحافلة الخاصة بي' : 'My bus trips';
  String get busMyTripsSubtitle =>
      isArabic
          ? 'شاهد الرحلات القادمة والسابقة لمحفظتك.'
          : 'See upcoming and past trips for your wallet.';
  String get busWalletIdLabel =>
      isArabic ? 'معرف المحفظة' : 'Wallet id';
  String get busLoadBookingsLabel =>
      isArabic ? 'تحميل حجوزاتي' : 'Load my bookings';
  String get busNoUpcomingTrips =>
      isArabic ? 'لا توجد رحلات قادمة بعد.' : 'No upcoming trips yet.';
  String get busNoPastTrips =>
      isArabic ? 'لا توجد رحلات سابقة بعد.' : 'No past trips yet.';
  String get busUpcomingTitle =>
      isArabic ? 'القادمة' : 'Upcoming';
  String get busPastTitle =>
      isArabic ? 'السابقة' : 'Past';
  String get busMyTicketsSectionTitle =>
      isArabic ? 'تذاكري' : 'My tickets';
  String get busLastBookingPrefix =>
      isArabic ? 'آخر حجز: ' : 'Last booking: ';
  String get busOpenTicketsLabel =>
      isArabic ? 'فتح التذاكر' : 'Open tickets';
  String get busMyTicketsHint =>
      isArabic
          ? 'بعد حجز رحلة، سيظهر آخر حجز هنا لتتمكن من فتح رموز QR الخاصة بالتذاكر.'
          : 'After you book a trip, your last booking will appear here so you can reopen your QR tickets.';
  String get busCreatedAtLabel =>
      isArabic ? 'تاريخ الإنشاء: ' : 'Created at: ';
  String busFareSummary(String perSeat, String currency, String total) =>
      isArabic
          ? 'الأجرة: $perSeat $currency لكل مقعد · $total $currency إجمالي'
          : 'Fare: $perSeat $currency per seat · $total $currency total';
  String get busSeatPrefix =>
      isArabic ? 'المقعد: ' : 'Seat: ';
  String get busStatusPrefix =>
      isArabic ? 'الحالة: ' : 'Status: ';
  String get busTicketsLoadingLabel =>
      isArabic ? 'جاري التحميل…' : 'Loading…';
  String get busTicketsReloadLabel =>
      isArabic ? 'إعادة تحميل التذاكر' : 'Reload tickets';
  String get busBookingTabSearch =>
      isArabic ? 'بحث' : 'Search';
  String get busBookingTabMyTrips =>
      isArabic ? 'رحلاتي' : 'My trips';

  // Mobility / journey
  String get mobilityHistoryTitle =>
      isArabic ? 'سجل الحركة' : 'Mobility history';
  String get mobilityTitle =>
      isArabic ? 'الحركة' : 'Mobility';
  String get filterLabel =>
      isArabic ? 'تصفية' : 'Filter';
  String get statusAll =>
      isArabic ? 'الكل' : 'all';
  String get statusCompleted =>
      isArabic ? 'مكتملة' : 'completed';
  String get statusCanceled =>
      isArabic ? 'ملغاة' : 'canceled';
  String get todayLabel =>
      isArabic ? 'اليوم' : 'Today';
  String get yesterdayLabel =>
      isArabic ? 'أمس' : 'Yesterday';
  String get noMobilityHistory =>
      isArabic ? 'لا توجد رحلات بعد' : 'No mobility history yet';
  String get driverLabel =>
      isArabic ? 'السائق' : 'Driver';

  // History / wallet
  String get historyTitle =>
      isArabic ? 'سجل المحفظة' : 'Wallet history';
  String get historyPostedTransactions =>
      isArabic ? 'الحركات المسجلة' : 'Posted transactions';
  String get historyLoadMore =>
      isArabic ? 'تحميل المزيد (الحد: ' : 'Load more (limit: ';
  String get historyUnexpectedFormat =>
      isArabic ? 'تنسيق غير متوقع لبيانات السجل' : 'Unexpected snapshot format';
  String get historyErrorPrefix =>
      isArabic ? 'خطأ' : 'Error';
  String get historyCsvErrorPrefix =>
      isArabic ? 'خطأ في CSV' : 'CSV error';
  String get historyDirLabel =>
      isArabic ? 'الاتجاه:' : 'Direction:';
  String get historyTypeLabel =>
      isArabic ? 'النوع:' : 'Type:';
  String get historyPeriodLabel =>
      isArabic ? 'الفترة:' : 'Period:';
  String get historyFromLabel =>
      isArabic ? 'من' : 'From';
  String get historyToLabel =>
      isArabic ? 'إلى' : 'To';
  String get historyExportSubject =>
      isArabic ? 'تصدير المدفوعات' : 'Payments Export';

  // Payment requests / receive
  String get payRequestTitle =>
      isArabic ? 'طلب دفعة' : 'Payment request';
  String get payNoEntries =>
      isArabic ? 'لا توجد عناصر' : 'No entries';
  String get payRequestAmountLabel =>
      isArabic ? 'المبلغ (SYP، اختياري)' : 'Amount (SYP, optional)';
  String get payRequestNoteLabel =>
      isArabic ? 'ملاحظة (اختياري)' : 'Note (optional)';
  String get payRequestPreviewPrefix =>
      isArabic ? 'طلب: ' : 'Requesting: ';
  String get payRequestQrLabel =>
      isArabic ? 'طلب (رمز QR)' : 'Request (QR)';
  String get payShareLinkLabel =>
      isArabic ? 'مشاركة الرابط' : 'Share link';
  String get copiedLabel =>
      isArabic ? 'تم النسخ' : 'Copied';
  String get walletLabel =>
      isArabic ? 'المحفظة' : 'Wallet';
  String get walletNotSetShort =>
      isArabic ? '(غير معيّن)' : '(not set)';
  String get balanceLabel =>
      isArabic ? 'الرصيد' : 'Balance';
  String get sonicSectionTitle =>
      isArabic ? 'دفعة قريبة (Sonic)' : 'Offline proximity payment (Sonic)';
  String get sonicAmountLabel =>
      isArabic ? 'المبلغ (SYP)' : 'Amount (SYP)';
  String get sonicIssueLabel =>
      isArabic ? 'إصدار رمز' : 'Issue token';
  String get sonicTokenLabel =>
      isArabic ? 'الرمز (اختياري)' : 'Token (optional)';
  String get sonicRedeemLabel =>
      isArabic ? 'استرداد' : 'Redeem';
  String get sonicQueuedOffline =>
      isArabic ? 'تمت الجدولة (بدون اتصال)' : 'Queued (offline)';

  // Payments helpers
  String get payFavoritesLabel =>
      isArabic ? 'المفضلة لدي' : 'My favorites';
  String get clearLabel =>
      isArabic ? 'مسح' : 'Clear';
  String get payRecipientLabel =>
      isArabic ? 'المستلم (محفظة / هاتف / @اسم)' : 'Recipient (Wallet/Phone/@alias)';
  String get payAmountLabel =>
      isArabic ? 'المبلغ (SYP)' : 'Amount (SYP)';
  String get payNoteLabel =>
      isArabic ? 'الملاحظات (اختياري)' : 'Reference (optional)';
  String get payCheckInputs =>
      isArabic ? 'يرجى التحقق من المدخلات' : 'Please check your inputs';
  String get payOfflineQueued =>
      isArabic ? 'بدون اتصال: تم التخزين في الانتظار' : 'Offline: queued';
  String get paySendFailed =>
      isArabic ? 'خطأ في التحويل، حاول مرة أخرى.' : 'Transfer failed, please try again.';
  String get payGuardrailAmount =>
      isArabic
          ? 'المبلغ يتجاوز الحد المسموح به لهذه العملية.'
          : 'Amount exceeds the maximum allowed for a single transfer.';
  String get payGuardrailVelocityWallet =>
      isArabic
          ? 'عدد كبير من التحويلات من هذه المحفظة خلال فترة قصيرة. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.'
          : 'Too many transfers from this wallet in a short period. Please wait a bit and try again.';
  String get payGuardrailVelocityDevice =>
      isArabic
          ? 'عدد كبير من التحويلات من هذا الجهاز خلال فترة قصيرة. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.'
          : 'Too many transfers from this device in a short period. Please wait a bit and try again.';
  String get payOfflineSavedPrefix =>
      isArabic ? 'تم الحفظ بدون اتصال' : 'Offline saved';
  String get payContactsLabel =>
      isArabic ? 'جهات الاتصال' : 'Contacts';
  String get sendLabel =>
      isArabic ? 'إرسال' : 'Send';
  String paySendAfter(int seconds) =>
      isArabic ? 'إرسال بعد ${seconds}s' : 'Send (${seconds}s)';
  String payWaitSeconds(int seconds) =>
      isArabic ? 'يرجى الانتظار ${seconds}ث' : 'Please wait ${seconds}s';

  // Taxi helpers
  String get taxiNoActiveRide =>
      isArabic ? 'لا توجد رحلة نشطة' : 'No active ride';
  String get taxiIncomingRide =>
      isArabic ? 'طلب رحلة جديد' : 'Incoming ride request';
  String get taxiDenyRequest =>
      isArabic ? 'رفض هذا الطلب؟' : 'Deny this request?';
  String get taxiTopupScanErrorPrefix =>
      isArabic ? 'خطأ في مسح رصيد الشحن' : 'Topup scan error';
  String get taxiTopupErrorPrefix =>
      isArabic ? 'خطأ في الشحن' : 'Topup error';

  // Freight / Courier & Transport
  String get freightTitle =>
      isArabic ? 'التوصيل والنقل' : 'Courier & Transport';
  String get freightQuoteLabel =>
      isArabic ? 'تسعير' : 'Quote';
  String get freightBookPayLabel =>
      isArabic ? 'حجز و دفع' : 'Book & Pay';
  String get freightGuardrailAmount =>
      isArabic
          ? 'قيمة الشحنة تتجاوز الحد المسموح به لهذه الخدمة.'
          : 'Shipment amount exceeds the maximum allowed for this service.';
  String get freightGuardrailDistance =>
      isArabic
          ? 'مسافة الشحنة بعيدة جداً بالنسبة لهذه الخدمة. حاول تقليل المسافة أو تقسيم الشحنة.'
          : 'Shipment distance is too far for this service. Try reducing the distance or splitting the shipment.';
  String get freightGuardrailWeight =>
      isArabic
          ? 'وزن الشحنة أعلى من الحد المسموح. حاول تقليل الوزن أو تقسيم الشحنة.'
          : 'Shipment weight is above the allowed limit. Try reducing the weight or splitting the shipment.';
  String get freightGuardrailVelocityPayer =>
      isArabic
          ? 'عدد كبير من شحنات الدفع من هذه المحفظة خلال فترة قصيرة. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.'
          : 'Too many paid shipments from this wallet in a short period. Please wait a bit and try again.';
  String get freightGuardrailVelocityDevice =>
      isArabic
          ? 'عدد كبير من شحنات الدفع من هذا الجهاز خلال فترة قصيرة. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.'
          : 'Too many paid shipments from this device in a short period. Please wait a bit and try again.';
  String get operatorDashboardTitle =>
      isArabic ? 'لوحة المشغل' : 'Operator Dashboard';
  String get adminDashboardTitle =>
      isArabic ? 'لوحة المسؤول' : 'Admin dashboard';
  String get superadminDashboardTitle =>
      isArabic ? 'لوحة السوبر أدمن' : 'Superadmin dashboard';

  // Carmarket / Carrental
  String get carmarketTitle =>
      isArabic ? 'تأجير وبيع السيارات' : 'Carrental & Carmarket';
  String get carrentalTitle =>
      isArabic ? 'تأجير وبيع السيارات' : 'Carrental & Carmarket';

  // Food orders
  String get foodOrdersTitle =>
      isArabic ? 'طلبات الطعام' : 'Food orders';
  String get foodOrderIdRequired =>
      isArabic ? 'معرّف الطلب مطلوب' : 'Order id required';
  String get foodStatusTitle =>
      isArabic ? 'الحالة' : 'Status';
  String get foodCreatedTitle =>
      isArabic ? 'تم الإنشاء' : 'Created';
  String get foodTotalTitle =>
      isArabic ? 'المجموع' : 'Total';
  String get foodRestaurantTitle =>
      isArabic ? 'المطعم' : 'Restaurant';
  String get foodItemsTitle =>
      isArabic ? 'العناصر' : 'Items';
  String get foodReorderPlaced =>
      isArabic ? 'تم إرسال طلب جديد' : 'Reorder placed';
  String foodErrorPrefix(int code) =>
      isArabic ? 'خطأ: $code' : 'Error: $code';
  String foodErrorGeneric(Object e) =>
      isArabic ? 'خطأ: $e' : 'Error: $e';
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  bool isSupported(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    return code == 'en' || code == 'ar';
  }

  @override
  Future<L10n> load(Locale locale) async {
    return L10n(locale);
  }

  @override
  bool shouldReload(_L10nDelegate old) => false;
}
