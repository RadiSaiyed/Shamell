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
    final loc = Localizations.of<L10n>(context, L10n);
    if (loc != null) return loc;
    try {
      final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
      return L10n(locale);
    } catch (_) {
      return const L10n(Locale('en'));
    }
  }

  bool get isArabic => locale.languageCode.toLowerCase().startsWith('ar');

  // High-level labels
  String get appTitle => isArabic ? 'شامل' : 'Shamell';

  // Login
  String get loginTitle => isArabic ? 'تسجيل الدخول' : 'Sign in';
  String get loginBaseUrl => isArabic ? 'رابط خادم الـ BFF' : 'BFF Base URL';
  String get loginFullName => isArabic ? 'الاسم الكامل' : 'Full name';
  String get loginPhone => isArabic ? 'رقم الهاتف (+963…)' : 'Phone (+963…)';
  String get loginRequestCode => isArabic ? 'طلب رمز' : 'Request code';
  String get loginCodeLabel =>
      isArabic ? 'رمز مكون من 6 أرقام' : 'Code (6 digits)';
  String get loginVerify => isArabic ? 'تأكيد' : 'Verify';
  String get loginNoteDemo => isArabic
      ? 'ملاحظة: يُعرض رمز الاختبار في مربع حوار (بيئة التطوير فقط).'
      : 'Note: Demo OTP is shown in a dialog (dev only).';
  String get loginTooManyAttempts => isArabic
      ? 'محاولات كثيرة. يرجى الانتظار قليلاً.'
      : 'Too many attempts. Please wait a moment.';
  String get loginInvalidCode => isArabic
      ? 'رمز غير صالح. حاول مرة أخرى.'
      : 'Invalid code. Please try again.';
  String get loginSignedIn =>
      isArabic ? 'تم تسجيل الدخول بنجاح.' : 'Signed in successfully.';
  String get loginFailed => isArabic ? 'فشل تسجيل الدخول' : 'Login failed';
  String get loginQrHint => isArabic
      ? 'لاستخدام مرسال ويب، افتح رمز QR لتسجيل الدخول على الكمبيوتر وامسحه من داخل \"استكشاف > مسح\" في مرسال.'
      : 'To use Mirsaal Web, open a login QR on your computer and scan it from \"Discover > Scan\" in Mirsaal.';
  String get loginTerms => isArabic
      ? 'بمتابعة تسجيل الدخول، فأنت توافق على شروط الخدمة وسياسة الخصوصية.'
      : 'By signing in you agree to the Terms of Service and Privacy Policy.';

  // Home quick actions
  String get qaScanPay => isArabic ? 'مسح و دفع' : 'Scan & pay';
  String get qaP2P => isArabic ? 'تحويل شخصي' : 'P2P';
  String get qaTopup => isArabic ? 'شحن الرصيد' : 'Topup';
  String get qaSonic => isArabic ? 'فوري' : 'Sonic';

  // Ops / System status
  String get opsTitle => isArabic ? 'العمليات والإدارة' : 'Ops & Admin';
  String get opsSystemStatus => isArabic ? 'حالة النظام' : 'System status';

  String get systemStatusTitle => isArabic ? 'حالة النظام' : 'System status';
  String get systemStatusStatusLabel => isArabic ? 'الحالة' : 'Status';
  String get systemStatusHttpLabel =>
      'HTTP'; // remains short and common in AR as well

  // Generic titles
  String get settingsTitle => isArabic ? 'الإعدادات' : 'Settings';
  String get chatTitle => isArabic ? 'الدردشة' : 'Chat';
  String get sonicTitle => isArabic ? 'دفعة Sonic' : 'Sonic Pay';
  String get vouchersTitle => isArabic ? 'قسائم الشحن' : 'Vouchers';
  String get busTitle => isArabic ? 'الحافلات' : 'Bus';
  String get staysOperatorTitle =>
      isArabic ? 'الإقامات والفنادق' : 'Stays & Hotel';

  // Home / modules
  String get homeActions => isArabic ? 'الإجراءات' : 'Actions';
  String get homeTaxi => isArabic ? 'تاكسي' : 'Taxi';
  String get homeTaxiRider => isArabic ? 'راكب تاكسي' : 'Taxi';
  String get homeTaxiDriver => isArabic ? 'سائق تاكسي' : 'Taxi Driver';
  String get homeTaxiOperator => isArabic ? 'مشغل تاكسي' : 'Taxi Operator';
  String get taxiHistoryTitle => isArabic ? 'رحلات التاكسي' : 'Taxi Rides';
  String get homePayments => isArabic ? 'المدفوعات' : 'Payment';
  String get homeWallet => isArabic ? 'المحفظة' : 'Wallet';
  String get homeBills => isArabic ? 'الفواتير' : 'Bills';
  String get homeRequests => isArabic ? 'الطلبات' : 'Requests';
  String get homeVouchers => isArabic ? 'قسائم' : 'Vouchers';
  String get homeFood => isArabic ? 'الطعام' : 'Food';
  String get homeStays => isArabic ? 'الفنادق والإقامات' : 'Hotels & Stays';
  String get homeBus => isArabic ? 'الحافلات' : 'Bus';
  String get homeChat => isArabic ? 'مرسال' : 'Mirsaal';
  String get homeDoctors => isArabic ? 'الأطباء' : 'Doctors';
  String get homeFlights => isArabic ? 'الرحلات' : 'Flights';
  String get homeJobs => isArabic ? 'الوظائف' : 'Jobs';
  String get homeAgriculture =>
      isArabic ? 'سوق المنتجات الزراعية' : 'Agri Marketplace';
  String get homeLivestock =>
      isArabic ? 'سوق الثروة الحيوانية' : 'Livestock Marketplace';
  String get homeCommerce => isArabic ? 'السوق' : 'Marketplace';
  String get homeMerchantPos => isArabic ? 'نقطة بيع التاجر' : 'Merchant POS';
  String get homeBuildingMaterials =>
      isArabic ? 'مواد البناء' : 'Building Materials';
  String get homeTopup => isArabic ? 'شحن الرصيد' : 'Topup';

  // Settings / debug
  String get settingsBaseUrl => isArabic ? 'رابط الخادم' : 'Base URL';
  String get settingsMyWallet => isArabic ? 'محفظتي' : 'My Wallet';
  String get settingsDebugSkeleton => isArabic
      ? 'تصحيح: هياكل طويلة (1200 مللي ثانية)'
      : 'Debug: Long skeletons (1200 ms)';
  String get settingsSkipLogin =>
      isArabic ? 'تخطي تسجيل الدخول (تجريبي)' : 'Skip Login (Demo)';
  String get settingsSendMetrics =>
      isArabic ? 'إرسال المقاييس إلى الخادم' : 'Send metrics to backend';
  String get settingsSave => isArabic ? 'حفظ' : 'Save';

  // Chat
  String get chatIdentity => isArabic ? 'الهوية' : 'Identity';
  String get chatMyDeviceId => isArabic ? 'معرّف جهازي' : 'My device id';
  String get chatDisplayName => isArabic ? 'اسم العرض' : 'Display name';
  String get chatGenerate => isArabic ? 'توليد' : 'Generate';
  String get chatRegister => isArabic ? 'تسجيل' : 'Register';
  String get chatMyFingerprint => isArabic ? 'بصمتي:' : 'My fingerprint:';
  String get chatMyPublicKey => isArabic ? 'المفتاح العام' : 'My public key';
  String get chatPeer => isArabic ? 'الطرف الآخر' : 'Peer';
  String get chatPeerId => isArabic ? 'معرّف الطرف الآخر' : 'Peer id';
  String get chatResolve => isArabic ? 'استعلام' : 'Resolve';
  String get chatPeerFp => isArabic ? 'بصمة الطرف الآخر:' : 'Peer fp:';
  String get chatVerified => isArabic ? 'مؤكد ✅' : 'Verified ✅';
  String get chatUnverified => isArabic ? 'غير مؤكد ❌' : 'Unverified ❌';
  String get chatMarkVerified => isArabic ? 'وضع علامة كمؤكد' : 'Mark verified';
  String get chatMessage => isArabic ? 'الرسالة' : 'Message';
  String get chatSend => isArabic ? 'إرسال' : 'Send';
  String get chatPoll => isArabic ? 'استعلام' : 'Poll';
  String get chatAttachImage => isArabic ? 'إرفاق صورة' : 'Attach image';
  String get chatOut => isArabic ? 'خرج:' : 'Out:';
  String get chatInbox => isArabic
      ? 'الوارد (مباشر عبر WS + استعلام)'
      : 'Inbox (live via WS + poll)';

  // Mirsaal Identity / backup / dialogs
  String get mirsaalIdentityTitle => isArabic ? 'هويتك' : 'Your ID';
  String get mirsaalIdentityNotCreated =>
      isArabic ? 'لم يتم إنشاء الهوية بعد' : 'Not created yet';
  String get mirsaalIdentityHint =>
      isArabic ? 'أنشئ هويتك للبدء.' : 'Create your identity to start.';
  String get mirsaalDisplayNameOptional =>
      isArabic ? 'اسم العرض (اختياري)' : 'Display name (optional)';
  String get mirsaalGenerate => isArabic ? 'توليد' : 'Generate';
  String get mirsaalRegisterWithRelay =>
      isArabic ? 'التسجيل مع الخادم' : 'Register with relay';
  String get mirsaalShowQrButton => isArabic ? 'إظهار رمز QR' : 'Show QR';
  String get mirsaalCopyIdButton => isArabic ? 'نسخ المعرف' : 'Copy ID';
  String get mirsaalIdCopiedSnack => isArabic ? 'تم نسخ المعرف' : 'ID copied';
  String get mirsaalShareIdButton => isArabic ? 'مشاركة المعرف' : 'Share ID';
  String get mirsaalBackupPassphraseButton =>
      isArabic ? 'نسخة احتياطية (عبارة سرية)' : 'Backup (passphrase)';
  String get mirsaalRestoreBackupButton =>
      isArabic ? 'استعادة النسخة الاحتياطية' : 'Restore backup';
  String get mirsaalBackupDialogTitle =>
      isArabic ? 'لصق نص النسخة الاحتياطية' : 'Paste backup text';
  String get mirsaalBackupDialogLabel =>
      isArabic ? 'النسخة الاحتياطية' : 'Backup';
  String get mirsaalDialogCancel => isArabic ? 'إلغاء' : 'Cancel';
  String get mirsaalDialogOk => isArabic ? 'موافق' : 'OK';

  // Mirsaal settings
  String get mirsaalSettingsPrivacy => isArabic ? 'الخصوصية' : 'Privacy';
  String get mirsaalSettingsAppearance => isArabic ? 'المظهر' : 'Appearance';
  String get mirsaalSettingsNotifications =>
      isArabic ? 'الإشعارات' : 'Notifications';
  String get mirsaalSettingsChat => isArabic ? 'الدردشة' : 'Chat';
  String get mirsaalSettingsMedia => isArabic ? 'الوسائط' : 'Media';
  String get mirsaalSettingsStorage =>
      isArabic ? 'إدارة التخزين' : 'Storage management';
  String get mirsaalSettingsPasscode => isArabic ? 'قفل برمز' : 'Passcode lock';
  String get mirsaalSettingsCalls => isArabic ? 'المكالمات' : 'Calls';
  String get mirsaalSettingsRate => isArabic ? 'قيّم Mirsaal' : 'Rate Mirsaal';
  String get mirsaalSettingsInviteFriends =>
      isArabic ? 'دعوة الأصدقاء' : 'Invite friends';
  String get mirsaalSettingsSupport => isArabic ? 'الدعم' : 'Support';
  String get mirsaalSettingsPrivacyPolicy =>
      isArabic ? 'سياسة الخصوصية' : 'Privacy Policy';

  // Mini-apps / Mini-programs
  String get miniAppsTitle => isArabic ? 'البرامج المصغّرة' : 'Mini‑programs';
  String get miniAppsSearchHint =>
      isArabic ? 'بحث في البرامج المصغّرة' : 'Search mini‑programs';
  String get miniAppsRecentTitle =>
      isArabic ? 'اُستخدِمت مؤخراً' : 'Recently used';
  String get miniAppsAllTitle =>
      isArabic ? 'كل البرامج المصغّرة' : 'All mini‑programs';
  String get miniAppsBadgeOfficial => isArabic ? 'رسمي' : 'Official';
  String get miniAppsBadgePartner => isArabic ? 'شريك' : 'Partner';
  String get miniAppsBadgeBeta => isArabic ? 'تجريبي' : 'Beta';
  String get mirsaalSettingsTerms =>
      isArabic ? 'شروط الاستخدام' : 'Terms of Service';
  String get mirsaalSettingsLicense => isArabic ? 'الترخيص' : 'License';
  String get mirsaalSettingsAdvanced => isArabic ? 'متقدم' : 'Advanced';

  // Mirsaal bottom tabs
  String get mirsaalTabContacts => isArabic ? 'جهات الاتصال' : 'Contacts';
  String get mirsaalTabChats => isArabic ? 'الدردشات' : 'Chats';
  String get mirsaalTabProfile => isArabic ? 'الملف الشخصي' : 'Profile';
  String get mirsaalTabSettings => isArabic ? 'الإعدادات' : 'Settings';
  String get mirsaalTabChannel => isArabic ? 'استكشاف' : 'Discover';

  // Mirsaal chats / contacts
  String get mirsaalChatsMarkAllRead =>
      isArabic ? 'وضع الكل كمقروء' : 'Mark all as read';
  String get mirsaalChatsSelection =>
      isArabic ? 'تحديد المحادثات' : 'Selection';
  String get mirsaalChatsPinnedHeader => isArabic ? 'المثبتة' : 'Pinned';
  String get mirsaalChatsOthersHeader =>
      isArabic ? 'الدردشات الأخرى' : 'Other chats';
  String get mirsaalMessagePreviewsDisable =>
      isArabic ? 'إيقاف معاينة الرسائل' : 'Disable message previews';
  String get mirsaalMessagePreviewsEnable =>
      isArabic ? 'تفعيل معاينة الرسائل' : 'Enable message previews';
  String get mirsaalNoContactsHint => isArabic
      ? 'لا توجد جهات اتصال بعد. أضِف جهة عبر مسح رمز QR أو استعلام عن المعرف.'
      : 'No contacts yet. Add one via QR scan or by resolving an ID.';
  String get mirsaalNoMessagesYet =>
      isArabic ? 'لا توجد رسائل بعد.' : 'No messages yet.';
  String get mirsaalAddContactFirst => isArabic
      ? 'أضِف جهة اتصال لبدء المحادثة.'
      : 'Add a contact to start chatting.';
  String get mirsaalLastCallBannerPrefix =>
      isArabic ? 'آخر مكالمة' : 'Last call';
  String get mirsaalNewChatTooltip => isArabic ? 'محادثة جديدة' : 'New chat';
  String get mirsaalUnrecognizedQr =>
      isArabic ? 'رمز غير معروف.' : 'Unrecognized QR payload.';
  String get mirsaalFriendQrAlreadyFriends =>
      isArabic ? 'أنتم أصدقاء بالفعل.' : 'You are already friends.';
  String get mirsaalFriendQrPending => isArabic
      ? 'طلب الصداقة قيد الانتظار.'
      : 'Friend request already pending.';
  String get mirsaalFriendQrSent =>
      isArabic ? 'تم إرسال طلب الصداقة.' : 'Friend request sent.';
  String get mirsaalFriendQrSendFailed =>
      isArabic ? 'تعذر إرسال طلب الصداقة.' : 'Could not send friend request.';
  String get mirsaalFriendQrSendError => isArabic
      ? 'حدث خطأ أثناء إرسال طلب الصداقة.'
      : 'Error while sending friend request.';

  String get mirsaalSettingsNotificationsSubtitle => isArabic
      ? 'إدارة إشعارات الحسابات الرسمية داخل Mirsaal'
      : 'Manage official‑account notifications inside Mirsaal';

  // Mirsaal contacts tab sections
  String get mirsaalContactsNewFriends =>
      isArabic ? 'أصدقاء جدد' : 'New friends';
  String get mirsaalContactsNewFriendsSubtitle => isArabic
      ? 'إضافة صديق جديد عبر Shamell ID أو رمز QR'
      : 'Add a new friend via Shamell ID or QR';
  String get mirsaalContactsGroups => isArabic ? 'المجموعات' : 'Group chats';
  String get mirsaalContactsGroupsSubtitle => isArabic
      ? 'إنشاء مجموعات محادثة وإدارتها'
      : 'Create and manage group conversations';
  String get mirsaalContactsServiceAccounts =>
      isArabic ? 'حسابات الخدمات' : 'Service accounts';
  String get mirsaalContactsServiceAccountsSubtitle => isArabic
      ? 'Shamell Taxi, Food, Pay والمزيد'
      : 'Shamell Taxi, Food, Pay and more';
  String get mirsaalContactsPeopleP2P =>
      isArabic ? 'الأشخاص والمدفوعات' : 'People & P2P';
  String get mirsaalContactsPeopleP2PSubtitle => isArabic
      ? 'إرسال أموال بسرعة إلى جهات الاتصال'
      : 'Quickly send money to your contacts';
  String get mirsaalContactsShamellServicesTitle =>
      isArabic ? 'حسابات Shamell' : 'Shamell services';

  // Mirsaal Moments / favorites / channel tab
  String get mirsaalChannelSocial => isArabic ? 'اجتماعي' : 'Social';
  String get mirsaalChannelDiscover => isArabic ? 'اكتشاف' : 'Discover';
  String get mirsaalChannelMomentsTitle => isArabic ? 'اللحظات' : 'Moments';
  String get mirsaalChannelMomentsSubtitle =>
      isArabic ? 'شاهد وشارك لحظات أصدقائك' : 'View and share your Moments';
  String get mirsaalChannelFavoritesTitle => isArabic ? 'المفضلة' : 'Favorites';
  String get mirsaalChannelFavoritesSubtitle => isArabic
      ? 'وصول سريع إلى العناصر المحفوظة'
      : 'Quick access to saved items';
  String get mirsaalChannelOfficialAccountsTitle =>
      isArabic ? 'الحسابات الرسمية' : 'Official accounts';
  String get mirsaalChannelOfficialAccountsSubtitle => isArabic
      ? 'تابِع حسابات Shamell والخدمات الشريكة'
      : 'Follow Shamell and partner service accounts';
  String get mirsaalChannelSubscriptionAccountsTitle =>
      isArabic ? 'حسابات الاشتراك' : 'Subscription accounts';
  String get mirsaalChannelSubscriptionAccountsSubtitle => isArabic
      ? 'تابع المحتوى التفاعلي من الحسابات الرسمية'
      : 'Follow content updates from official accounts';
  String get mirsaalChannelScanTitle => isArabic ? 'مسح' : 'Scan';
  String get mirsaalChannelScanSubtitle => isArabic
      ? 'مسح رموز QR لتسجيل الدخول إلى مرسال ويب، المدفوعات والبرامج المصغّرة'
      : 'Scan QR for Mirsaal Web login, payments and mini‑apps';
  String get mirsaalMomentsAudienceHint => isArabic
      ? 'استخدم الوسوم مثل \"العائلة\" و\"العمل\" في شاشة الأصدقاء لتحديد من يرى لحظاتك (Only Family/Work بأسلوب WeChat).'
      : 'Use friend labels like \"Family\" and \"Work\" in the Friends screen to choose who sees this moment (Only Family/Work, WeChat‑style).';

  // Mirsaal subscriptions feed
  String get mirsaalSubscriptionsFeedTitle =>
      isArabic ? 'خلاصة الاشتراكات' : 'Subscriptions feed';
  String get mirsaalSubscriptionsFeedEmptySummary => isArabic
      ? 'تحديثات مجمّعة من حسابات الاشتراك الرسمية'
      : 'Aggregated updates from subscription official accounts';
  String mirsaalSubscriptionsFeedSummary(int subs, int unread) {
    if (isArabic) {
      final base = 'اشتراكات: $subs حساباً رسمياً من نوع الاشتراك';
      if (unread > 0) return '$base · $unread غير مقروءة';
      return base;
    } else {
      final base = 'Subscriptions: $subs official subscription accounts';
      if (unread > 0) return '$base · $unread unread';
      return base;
    }
  }

  String get mirsaalSubscriptionsFeedEmptyShort => isArabic
      ? 'عرض تحديثات الحسابات الرسمية من نوع الاشتراك'
      : 'Show updates from subscription official accounts';
  String mirsaalSubscriptionsAccountsSummary(int subs, int unread) {
    if (isArabic) {
      final base = 'حسابات اشتراك: $subs حساباً رسمياً من نوع الاشتراك';
      if (unread > 0) return '$base · $unread غير مقروءة';
      return base;
    } else {
      final base = 'Subscription accounts: $subs official subscriptions';
      if (unread > 0) return '$base · $unread unread';
      return base;
    }
  }

  String get mirsaalSubscriptionsTitle =>
      isArabic ? 'الاشتراكات' : 'Subscriptions';
  String get mirsaalSubscriptionsEmpty =>
      isArabic ? 'لا توجد تحديثات اشتراك بعد.' : 'No subscription updates yet.';
  String get mirsaalSubscriptionsFilterAll => isArabic ? 'الكل' : 'All';
  String get mirsaalSubscriptionsFilterUnread =>
      isArabic ? 'غير مقروءة' : 'Unread';
  String get mirsaalSubscriptionsMarkAllRead =>
      isArabic ? 'اعتبار كل التحديثات مقروءة' : 'Mark all updates as read';

  // Mirsaal friends / labels
  String get mirsaalFriendAliasTitle =>
      isArabic ? 'اسم مخصص للصديق' : 'Friend alias';
  String get mirsaalFriendAliasLabel =>
      isArabic ? 'الاسم في الدردشة (اختياري)' : 'Chat name (optional)';
  String get mirsaalFriendAliasHint =>
      isArabic ? 'مثلاً: أحمد (العمل)' : 'e.g. Ali (work)';
  String get mirsaalFriendTagsLabel =>
      isArabic ? 'الوسوم (اختياري)' : 'Tags (optional)';
  String get mirsaalFriendTagsHint =>
      isArabic ? 'مثلاً: العائلة، العمل' : 'e.g. Family, Work';
  String get mirsaalFriendTagsPrefix => isArabic ? 'الوسوم:' : 'Tags:';
  String get mirsaalFriendsCloseLabel =>
      isArabic ? 'صديق مقرّب' : 'Close friend';
  String get mirsaalFriendsAccept => isArabic ? 'قبول' : 'Accept';
  String get mirsaalFriendsAddNewTitle =>
      isArabic ? 'إضافة صديق جديد' : 'Add new friend';
  String get mirsaalFriendsSearchHint =>
      isArabic ? 'Shamell ID أو رقم الهاتف' : 'Shamell ID or phone number';
  String get mirsaalFriendsSending => isArabic ? '...جارٍ الإرسال' : 'Sending…';
  String get mirsaalFriendsSendRequest =>
      isArabic ? 'إرسال طلب صداقة' : 'Send friend request';
  String get mirsaalFriendsSuggestionsTitle =>
      isArabic ? 'اقتراحات من دفتر الهاتف' : 'Suggestions from phone contacts';
  String get mirsaalFriendsSuggestionsEmpty => isArabic
      ? 'اضغط للمزامنة مع دفتر الهاتف والحصول على اقتراحات أصدقاء على نمط WeChat.'
      : 'Tap to sync with your address book and get WeChat‑style friend suggestions.';
  String get mirsaalFriendsSyncContacts =>
      isArabic ? 'مزامنة دفتر الهاتف' : 'Sync phone contacts';
  String get mirsaalFriendsRequestsTitle =>
      isArabic ? 'طلبات الصداقة' : 'Friend requests';
  String get mirsaalFriendsSentTitle =>
      isArabic ? 'طلبات مرسلة' : 'Sent requests';
  String get mirsaalFriendsListTitle => isArabic ? 'الأصدقاء' : 'Friends';
  String get mirsaalFriendsEmpty =>
      isArabic ? 'لا توجد صداقات بعد.' : 'No friends yet.';
  String get mirsaalFriendsPeopleNearbyTitle =>
      isArabic ? 'الأشخاص القريبون' : 'People nearby';
  String get mirsaalFriendsPeopleNearbySubtitle => isArabic
      ? 'اكتشف مستخدمي وخدمات Shamell القريبة وأضفهم كأصدقاء، بأسلوب WeChat People Nearby.'
      : 'Discover nearby Shamell users and services to add as friends, similar to WeChat People Nearby.';
  String get mirsaalScanQr => isArabic ? 'مسح QR' : 'Scan QR';
  String get mirsaalSyncInbox => isArabic ? 'مزامنة الوارد' : 'Sync inbox';
  String get mirsaalHideLockedChats =>
      isArabic ? 'إخفاء الدردشات المقفلة' : 'Hide locked chats';
  String get mirsaalShowLockedChats => isArabic
      ? 'إظهار الدردشات المقفلة (يتطلب فتحاً)'
      : 'Show locked chats (requires auth)';
  String get mirsaalPeerIdLabel => isArabic ? 'معرّف الطرف' : 'Peer ID';
  String get mirsaalResolve => isArabic ? 'استعلام' : 'Resolve';
  String get mirsaalVerifiedLabel => isArabic ? 'موثوق' : 'Verified';
  String get mirsaalMarkVerifiedLabel =>
      isArabic ? 'وضع علامة كموثوق' : 'Mark verified';
  String get mirsaalDisableDisappear =>
      isArabic ? 'إيقاف الاختفاء' : 'Disable disappear';
  String get mirsaalEnableDisappear =>
      isArabic ? 'تفعيل الاختفاء' : 'Enable disappear';
  String get mirsaalDisappearAfter =>
      isArabic ? 'الاختفاء بعد' : 'Disappear after';
  String get mirsaalUnhideChat => isArabic ? 'إظهار المحادثة' : 'Unhide chat';
  String get mirsaalHideChat => isArabic ? 'إخفاء المحادثة' : 'Hide chat';
  String get mirsaalUnblock => isArabic ? 'إلغاء الحظر' : 'Unblock';
  String get mirsaalBlock => isArabic ? 'حظر' : 'Block';
  String get mirsaalTrustedFingerprint =>
      isArabic ? 'بصمة موثوقة' : 'Trusted fingerprint';
  String get mirsaalUnverifiedContact =>
      isArabic ? 'جهة اتصال غير موثوقة' : 'Unverified contact';
  String get mirsaalPeerFingerprintLabel =>
      isArabic ? 'بصمة الطرف:' : 'Peer FP:';
  String get mirsaalYourFingerprintLabel => isArabic ? 'بصمتك:' : 'Your FP:';
  String get mirsaalSafetyLabel => isArabic ? 'السلامة:' : 'Safety:';
  String get mirsaalResetSessionLabel =>
      isArabic ? 'إعادة تعيين الجلسة' : 'Reset session';
  String get mirsaalMessagesTitle => isArabic ? 'الرسائل' : 'Messages';
  String get mirsaalAttachImage => isArabic ? 'إرفاق صورة' : 'Attach image';
  String get mirsaalTypeMessage => isArabic ? 'اكتب رسالة' : 'Type a message';
  String get mirsaalImageAttached =>
      isArabic ? 'تم إرفاق صورة' : 'Image attached';
  String get mirsaalRemoveAttachment =>
      isArabic ? 'إزالة المرفق' : 'Remove attachment';
  String get mirsaalSessionChangedTitle =>
      isArabic ? 'تم تغيير الجلسة' : 'Session changed';
  String get mirsaalSessionChangedBody => isArabic
      ? 'تم تغيير مفتاح المرسل. تحقق من رقم الأمان مع جهة الاتصال. أعد تعيين الجلسة إذا لم تكن متأكدًا.'
      : 'Sender key changed. Verify the safety number with your contact. Reset the session if unsure.';
  String get mirsaalLater => isArabic ? 'لاحقًا' : 'Later';
  String get mirsaalUnlockHiddenReason =>
      isArabic ? 'فتح الدردشات المخفية' : 'Unlock hidden chats';
  String get mirsaalScanContactQrTitle =>
      isArabic ? 'مسح رمز QR لجهة الاتصال' : 'Scan contact QR';

  // Mirsaal errors / backup / notifications
  String get mirsaalAttachFailed =>
      isArabic ? 'فشل إرفاق الملف' : 'Attach failed';
  String get mirsaalShareFailed =>
      isArabic ? 'فشل مشاركة الملف' : 'Share failed';
  String get mirsaalBackupCreated => isArabic
      ? 'تم إنشاء النسخة الاحتياطية ونسخها. احتفظ بها بأمان.'
      : 'Backup created and copied. Keep it safe.';
  String get mirsaalBackupFailed =>
      isArabic ? 'فشل إنشاء النسخة الاحتياطية' : 'Backup failed';
  String get mirsaalBackupInvalidFormat =>
      isArabic ? 'تنسيق النسخة الاحتياطية غير صالح' : 'Invalid backup format';
  String get mirsaalBackupMissingFields =>
      isArabic ? 'النسخة الاحتياطية تفتقد حقولاً' : 'Backup missing fields';
  String get mirsaalBackupCorrupt =>
      isArabic ? 'النسخة الاحتياطية تالفة' : 'Backup corrupt';
  String get mirsaalRestoreFailed =>
      isArabic ? 'فشل الاستعادة' : 'Restore failed';
  String get mirsaalBackupPassphraseTitleSet =>
      isArabic ? 'تعيين عبارة مرور النسخة الاحتياطية' : 'Set backup passphrase';
  String get mirsaalBackupPassphraseTitleEnter => isArabic
      ? 'إدخال عبارة مرور النسخة الاحتياطية'
      : 'Enter backup passphrase';
  String get mirsaalBackupPassphraseLabel =>
      isArabic ? 'عبارة المرور' : 'Passphrase';
  String get mirsaalBackupPassphraseConfirm =>
      isArabic ? 'تأكيد عبارة المرور' : 'Confirm';
  String get mirsaalNewMessageTitle => isArabic ? 'رسالة جديدة' : 'New message';
  String get mirsaalNewMessageBody =>
      isArabic ? 'افتح المحادثة لعرض الرسالة.' : 'Open chat to view.';
  String get mirsaalRatchetKeyMismatch => isArabic
      ? 'تم اكتشاف عدم تطابق في المفتاح. أعد تعيين الجلسة.'
      : 'Key mismatch detected. Reset session.';
  String get mirsaalRatchetWindowWarning => isArabic
      ? 'الرسالة خارج النافذة. فكّر في إعادة تعيين الجلسة.'
      : 'Message outside window; consider resetting session.';
  String get mirsaalRatchetAheadWarning => isArabic
      ? 'الرسالة بعيدة جدًا للأمام؛ لم يتم تخزين المفاتيح.'
      : 'Message too far ahead; keys not stored.';
  String get mirsaalPreviewImage => isArabic ? '[صورة]' : '[Image]';
  String get mirsaalPreviewUnknown => isArabic ? '<رسالة>' : '<message>';
  String get mirsaalPreviewVoice =>
      isArabic ? '[رسالة صوتية]' : '[Voice message]';
  String get mirsaalStartVoice =>
      isArabic ? 'تسجيل رسالة صوتية' : 'Record voice message';
  String get mirsaalStopVoice => isArabic ? 'إيقاف التسجيل' : 'Stop recording';
  String get mirsaalRecordingVoice =>
      isArabic ? 'جاري تسجيل رسالة صوتية...' : 'Recording voice note…';
  String get mirsaalVoiceHoldToTalk =>
      isArabic ? 'اضغط مع الاستمرار للتسجيل' : 'Hold to talk';
  String get mirsaalVoiceSlideUpToCancel => isArabic
      ? 'اسحب للأعلى للإلغاء، اسحب لليمين للقفل'
      : 'Slide up to cancel, slide right to lock';
  String get mirsaalVoiceReleaseToCancel =>
      isArabic ? 'حرر للإلغاء' : 'Release to cancel';
  String get mirsaalVoiceCanceledSnack =>
      isArabic ? 'تم إلغاء الرسالة الصوتية' : 'Voice message canceled';
  String get mirsaalVoiceTooShort =>
      isArabic ? 'الرسالة الصوتية قصيرة جداً' : 'Voice message too short';
  String get mirsaalVoiceLocked =>
      isArabic ? 'التسجيل مقفل' : 'Recording locked';
  String mirsaalVoiceMessageLabel(String seconds) => isArabic
      ? (seconds.isNotEmpty ? 'رسالة صوتية (${seconds} ثوان)' : 'رسالة صوتية')
      : (seconds.isNotEmpty ? 'Voice message (${seconds}s)' : 'Voice message');
  String get mirsaalVoicePlaybackSoon => isArabic
      ? 'تشغيل الرسائل الصوتية غير متاح على هذا الجهاز.'
      : 'Voice message playback is unavailable on this device.';
  String get mirsaalVoiceSpeakerMode =>
      isArabic ? 'تشغيل عبر مكبر الصوت' : 'Play via speaker';
  String get mirsaalVoiceEarpieceMode =>
      isArabic ? 'تشغيل عبر سماعة الأذن' : 'Play via earpiece';
  String get mirsaalStickers => isArabic ? 'الملصقات' : 'Stickers';
  String get mirsaalStickersRecent =>
      isArabic ? 'المستخدمة مؤخراً' : 'Recently used';
  String get mirsaalStickersYourPacks => isArabic ? 'حزمك' : 'Your packs';
  String get mirsaalStickersSearchHint =>
      isArabic ? 'ابحث عن ملصق' : 'Search stickers';
  String get mirsaalStickersFilterAll => isArabic ? 'كل الحزم' : 'All packs';
  String get mirsaalStickersFilterInstalled =>
      isArabic ? 'المثبتة فقط' : 'Installed only';
  String get mirsaalStickersCategoryLabel =>
      isArabic ? 'فئات مقترحة' : 'Suggested categories';
  String get mirsaalMessageActionsTitle =>
      isArabic ? 'خيارات الرسالة' : 'Message options';
  String get mirsaalCopyMessage => isArabic ? 'نسخ' : 'Copy';
  String get mirsaalForwardMessage => isArabic ? 'إعادة التوجيه' : 'Forward';
  String get mirsaalTranslateMessage => isArabic ? 'ترجمة' : 'Translate';
  String get mirsaalReplyMessage => isArabic ? 'الرد' : 'Reply';
  String get mirsaalDeleteForMe => isArabic ? 'حذف' : 'Delete';
  String get mirsaalRecallMessage => isArabic ? 'استرجاع' : 'Recall';
  String get mirsaalMessageRecalledByMe =>
      isArabic ? 'لقد استرجعت هذه الرسالة.' : 'You recalled this message.';
  String get mirsaalMessageRecalledByOther =>
      isArabic ? 'تم استرجاع هذه الرسالة.' : 'This message was recalled.';
  String get mirsaalPinMessage =>
      isArabic ? 'تثبيت الرسالة في الأعلى' : 'Pin message to top';
  String get mirsaalUnpinMessage =>
      isArabic ? 'إلغاء تثبيت الرسالة' : 'Unpin message';
  String get mirsaalAddToFavorites =>
      isArabic ? 'إضافة إلى المفضلة' : 'Add to favorites';
  String get mirsaalMessageCopiedSnack =>
      isArabic ? 'تم نسخ الرسالة' : 'Message copied';
  String get mirsaalMessageFavoritedSnack =>
      isArabic ? 'تمت إضافة الرسالة إلى المفضلة' : 'Message added to favorites';
  String get mirsaalPreviewLocation => isArabic ? 'موقع' : 'Location';
  String get mirsaalSendLocation => isArabic ? 'إرسال الموقع' : 'Send location';
  String get mirsaalLocationOpenInMap =>
      isArabic ? 'فتح على الخريطة' : 'Open in map';
  String get mirsaalLocationFavorite =>
      isArabic ? 'إضافة إلى المواقع المفضلة' : 'Add to favorite locations';
  String get mirsaalLocationFavoritedSnack =>
      isArabic ? 'تم حفظ الموقع في المفضلة' : 'Location saved to favorites';
  String get mirsaalCallKindVideo => isArabic ? 'فيديو' : 'Video';
  String get mirsaalCallKindVoice => isArabic ? 'صوت' : 'Voice';
  String get mirsaalCallDirectionOutgoing => isArabic ? 'صادر' : 'Outgoing';
  String get mirsaalCallDirectionIncoming => isArabic ? 'وارد' : 'Incoming';
  String get mirsaalCallStatusMissed =>
      isArabic ? 'مكالمة فائتة' : 'Missed call';
  String get mirsaalCallStatusMissedShort =>
      isArabic ? 'لم يتم الرد' : 'Missed';
  String get mirsaalCallStatusShort => isArabic ? 'مكالمة قصيرة' : 'Short call';
  String get mirsaalCallRedial => isArabic ? 'إعادة الاتصال' : 'Redial';
  String get mirsaalDevicesThisDevice =>
      isArabic ? 'هذا الجهاز' : 'This device';
  String get mirsaalDevicesLogoutOthers =>
      isArabic ? 'تسجيل الخروج من الأجهزة الأخرى' : 'Log out of other devices';
  String get mirsaalDevicesLogoutOthersConfirm => isArabic
      ? 'سيتم إزالة جميع الأجهزة الأخرى المرتبطة بهذا الحساب. المتابعة؟'
      : 'All other devices linked to this account will be removed. Continue?';
  String get mirsaalDeviceLoginTitle => isArabic
      ? 'تأكيد تسجيل الدخول على جهاز جديد'
      : 'Confirm login on new device';
  String get mirsaalDeviceLoginBody => isArabic
      ? 'السماح لهذا الجهاز بتسجيل الدخول إلى مرسال باستخدام حسابك؟'
      : 'Allow this device to sign in to Mirsaal with your account?';
  String get mirsaalDeviceLoginApprovedSnack => isArabic
      ? 'تمت الموافقة على تسجيل الدخول على الجهاز الجديد.'
      : 'Login approved on the new device.';
  String get mirsaalDeviceLoginErrorExpired => isArabic
      ? 'رمز تسجيل الدخول غير صالح أو منتهي الصلاحية.'
      : 'Login code is invalid or has expired.';
  String get mirsaalPinChat => isArabic ? 'تثبيت الدردشة' : 'Pin chat';
  String get mirsaalUnpinChat =>
      isArabic ? 'إلغاء تثبيت الدردشة' : 'Unpin chat';
  String get mirsaalMuteChat =>
      isArabic ? 'كتم إشعارات هذه الدردشة' : 'Mute this chat';
  String get mirsaalUnmuteChat =>
      isArabic ? 'إلغاء كتم هذه الدردشة' : 'Unmute this chat';
  String get mirsaalMarkUnread =>
      isArabic ? 'وضع علامة كغير مقروءة' : 'Mark as unread';
  String get mirsaalMarkRead => isArabic ? 'وضع علامة كمقروءة' : 'Mark as read';
  String get mirsaalSendMoney => isArabic ? 'إرسال أموال' : 'Send money';
  String get mirsaalClearChatHistory =>
      isArabic ? 'مسح سجل الدردشة' : 'Clear chat history';
  String get mirsaalDeleteChat => isArabic ? 'حذف الدردشة' : 'Delete chat';
  String get mirsaalInternetCall => isArabic ? 'مكالمة فيديو' : 'Video call';
  String get mirsaalPhoneCall => isArabic ? 'مكالمة هاتفية' : 'Phone call';
  String get mirsaalCallHistory => isArabic ? 'سجل المكالمات' : 'Call history';
  String get mirsaalNoCallsWithContact => isArabic
      ? 'لا يوجد سجل مكالمات مع هذا الحساب بعد.'
      : 'No call history with this contact yet.';
  String get mirsaalPinnedMessagesTitle =>
      isArabic ? 'رسائل مثبتة' : 'Pinned messages';
  String get mirsaalSearchFilterAll => isArabic ? 'الكل' : 'All';
  String get mirsaalSearchFilterMedia => isArabic ? 'الوسائط' : 'Media';
  String get mirsaalSearchFilterLinks => isArabic ? 'الروابط' : 'Links';
  String get mirsaalSearchFilterFiles => isArabic ? 'الملفات' : 'Files';
  String get mirsaalSearchFilterRedPackets =>
      isArabic ? 'الحزم الحمراء' : 'Red packets';
  String get mirsaalSearchFilterVoice =>
      isArabic ? 'الرسائل الصوتية' : 'Voice notes';
  String get mirsaalSearchFilterCalls => isArabic ? 'المكالمات' : 'Calls';
  String get mirsaalMediaOverviewTitle => isArabic
      ? 'الوسائط والروابط في هذه الدردشة'
      : 'Media and links in this chat';
  String get mirsaalMediaOverviewEmpty => isArabic
      ? 'لا توجد صور أو روابط في هذه الدردشة بعد.'
      : 'No media or links in this chat yet.';
  String get mirsaalGlobalMediaTitle => isArabic
      ? 'الوسائط والملفات في كل الدردشات'
      : 'Media & files across chats';
  String get mirsaalGlobalMediaEmpty => isArabic
      ? 'لن تظهر هنا الوسائط والملفات حتى تستخدم مرسال مع أصدقائك.'
      : 'Media and files will appear here once you use Mirsaal with your friends.';
  String get mirsaalGlobalMediaSearchHint =>
      isArabic ? 'بحث في الوسائط والملفات' : 'Search in media and files';

  // Mirsaal reactions
  String get mirsaalReactionsTitle =>
      isArabic ? 'تفاعل مع الرسالة' : 'React to message';

  // Mirsaal contact info / favorites
  String get mirsaalContactInfoTitle =>
      isArabic ? 'معلومات جهة الاتصال' : 'Contact info';
  String get mirsaalContactRemarkLabel =>
      isArabic ? 'ملاحظة (اسم مخصص)' : 'Remark (alias)';
  String get mirsaalContactChatIdPrefix =>
      isArabic ? 'معرّف الدردشة:' : 'Chat ID:';
  String get mirsaalFavoritesTitle => isArabic ? 'المفضلة' : 'Favorites';
  String get mirsaalFavoritesNewTitle =>
      isArabic ? 'عنصر مفضل جديد' : 'New favorite';
  String get mirsaalFavoritesHint => isArabic
      ? 'احفظ أي شيء تريد الرجوع إليه لاحقاً'
      : 'Save anything you want to revisit later';
  String get mirsaalFavoritesAdd => isArabic ? 'إضافة' : 'Add';
  String get mirsaalFavoritesEmpty =>
      isArabic ? 'لا توجد عناصر مفضلة بعد.' : 'No favorites yet.';
  String get mirsaalFavoritesTagsPrefix => isArabic ? 'الوسوم:' : 'Tags:';
  String get mirsaalFavoritesOpenChatTooltip =>
      isArabic ? 'فتح الدردشة' : 'Open chat';
  String get mirsaalFavoritesRemoveTooltip => isArabic ? 'حذف' : 'Remove';
  String get mirsaalChatThemeTitle => isArabic ? 'سمة الدردشة' : 'Chat theme';
  String get mirsaalChatThemeDefault => isArabic ? 'افتراضية' : 'Default';
  String get mirsaalChatThemeDark => isArabic ? 'داكنة' : 'Dark';
  String get mirsaalChatThemeGreen => isArabic ? 'أخضر' : 'Green';
  String get mirsaalFavoritesFilterAll => isArabic ? 'كل العناصر' : 'All items';
  String get mirsaalFavoritesFilterMessages =>
      isArabic ? 'رسائل الدردشة' : 'Starred messages';

  // Mirsaal profile
  String get mirsaalProfileShowQr => isArabic ? 'إظهار رمز QR' : 'Show QR';
  String get mirsaalProfileShareId =>
      isArabic ? 'مشاركة معرف Mirsaal' : 'Share Mirsaal ID';
  String get mirsaalProfileSafe => isArabic ? 'خزنة Mirsaal' : 'Mirsaal safe';
  String get mirsaalProfileExportId => isArabic ? 'تصدير المعرف' : 'Export ID';
  String get mirsaalProfileRevocationPass =>
      isArabic ? 'كلمة مرور إلغاء المعرف' : 'ID revocation passphrase';
  String get mirsaalProfileLinkedPhone =>
      isArabic ? 'رقم هاتف مرتبط' : 'Linked phone number';
  String get mirsaalProfileLinkedEmail =>
      isArabic ? 'بريد إلكتروني مرتبط' : 'Linked email';
  String get mirsaalProfilePublicKey =>
      isArabic ? 'المفتاح العام' : 'Public key';
  String get mirsaalProfileDeleteId =>
      isArabic ? 'حذف المعرف والبيانات' : 'Delete ID and data';

  // Sonic / Vouchers / Cash
  String get sonicFromWallet => isArabic ? 'من المحفظة' : 'From wallet';
  String get sonicToWalletOpt =>
      isArabic ? 'إلى المحفظة (اختياري)' : 'To wallet (optional)';
  String get labelAmount => isArabic ? 'المبلغ (ليرة)' : 'Amount (SYP)';
  String get sonicIssueToken => isArabic ? 'إصدار رمز' : 'Issue token';
  String get sonicRedeem => isArabic ? 'استبدال' : 'Redeem';
  String get cashSecretPhraseOpt =>
      isArabic ? 'عبارة سرية (اختياري)' : 'Secret phrase (optional)';
  String get cashCreate => isArabic ? 'إنشاء' : 'Create';
  String get cashStatus => isArabic ? 'الحالة' : 'Status';
  String get cashCancel => isArabic ? 'إلغاء' : 'Cancel';
  String get cashRedeem => isArabic ? 'استبدال' : 'Redeem';
  String get labelCode => isArabic ? 'الرمز' : 'Code';
  String get vouchersTitleText => isArabic ? 'قسائم الشحن' : 'Vouchers';

  // Generic emergency / complaints
  String get emergencyTitle => isArabic ? 'الطوارئ' : 'Emergency';
  String get emergencyPolice => isArabic ? 'الشرطة' : 'Police';
  String get emergencyAmbulance => isArabic ? 'الإسعاف' : 'Ambulance';
  String get emergencyFire => isArabic ? 'الإطفاء' : 'Fire';
  String get complaintsTitle => isArabic ? 'الشكاوى' : 'Complaints';
  String get complaintsEmailUs => isArabic ? 'راسلنا عبر البريد' : 'Email us';

  // Main menu (bottom sheet)
  String get menuProfile => isArabic ? 'الملف الشخصي' : 'Profile';
  String get menuTrips => isArabic ? 'الرحلات' : 'Trips';
  String get menuRoles => isArabic
      ? 'الأدوار (مستخدم / مشغل / مسؤول)'
      : 'Roles (User / Operator / Admin)';
  String get menuEmergency => isArabic ? 'أرقام الطوارئ' : 'Emergency numbers';
  String get menuComplaints => isArabic ? 'الشكاوى' : 'Complaints';
  String get menuCallUs => isArabic ? 'اتصل بنا' : 'Call us';
  String get menuSwitchMode =>
      isArabic ? 'تبديل وضع التطبيق' : 'Switch app mode';
  String get menuLogout => isArabic ? 'تبديل الحساب' : 'Switch account';
  String get menuLogoutSubtitle => isArabic
      ? 'تسجيل الخروج من هذا الجهاز وتسجيل الدخول برقم آخر.'
      : 'Log out from this device and sign in with a different number.';
  String get menuOperatorConsole =>
      isArabic ? 'لوحة المشغل' : 'Operator console';
  String get menuAdminConsole => isArabic ? 'لوحة المسؤول' : 'Admin console';
  String get menuSuperadminConsole =>
      isArabic ? 'لوحة السوبر أدمن' : 'Superadmin console';

  // Common labels
  String get labelWalletId => isArabic ? 'معرف المحفظة' : 'Wallet ID';
  String get labelName => isArabic ? 'الاسم' : 'Name';
  String get labelPhone => isArabic ? 'الهاتف' : 'Phone';
  String get msgWalletCopied =>
      isArabic ? 'تم نسخ معرف المحفظة' : 'Wallet copied';
  String get profileTitle => isArabic ? 'الملف الشخصي' : 'Profile';
  String get rolesOverviewTitle =>
      isArabic ? 'نظرة عامة على الأدوار' : 'Roles overview';

  // Me tab – Shamell Pay entry
  String get mePayEntryTitle => isArabic ? 'Shamell Pay' : 'Shamell Pay';
  String get mePayEntrySubtitleSetup => isArabic
      ? 'إعداد Shamell Pay للمحفظة والفواتير'
      : 'Set up Shamell Pay for wallet and bills';
  String get mePayEntrySubtitleManage => isArabic
      ? 'إدارة المحفظة، الفواتير والحزم الحمراء'
      : 'Manage wallet, bills and red packets';

  // Generic small labels
  String get labelPage => isArabic ? 'صفحة' : 'page';
  String get labelSize => isArabic ? 'الحجم' : 'size';
  String get labelSearch => isArabic ? 'بحث' : 'search';
  String get labelCity => isArabic ? 'المدينة' : 'city';

  String get viewAll => isArabic ? 'عرض الكل' : 'View all';
  String get notSet => isArabic ? 'غير معيّن' : '(not set)';
  String get unknownLabel => isArabic ? 'غير معروف' : 'Unknown';

  // Real‑estate / stays helpers
  String get rsBrowseByPropertyType =>
      isArabic ? 'تصفح حسب نوع العقار' : 'Browse by property type';
  String get rsPropertyType => isArabic ? 'نوع العقار' : 'Property type';
  String get rsAllTypes => isArabic ? 'كل الأنواع' : 'All types';
  String get rsAvailable => isArabic ? 'متاح' : 'Available';
  String get rsUnavailable => isArabic ? 'غير متاح' : 'Unavailable';
  String get rsPrices => isArabic ? 'الأسعار' : 'Prices';
  String get rsSelect => isArabic ? 'اختيار' : 'Select';
  String get rsSelectedListingPrefix =>
      isArabic ? 'تم اختيار العقار #' : 'Selected listing #';

  String get realEstateTitle => isArabic ? 'العقارات' : 'RealEstate';
  String get rePropertyId => isArabic ? 'معرف العقار' : 'property id';
  String get reBuyerWallet => isArabic ? 'محفظة المشتري' : 'buyer wallet';
  String get reDeposit => isArabic ? 'الدفعة المقدمة (SYP)' : 'deposit (SYP)';
  String get reSearch => isArabic ? 'بحث' : 'Search';
  String get reReserveAndPay => isArabic ? 'حجز و دفع' : 'Reserve & Pay';
  String get reSendInquiry => isArabic ? 'إرسال استفسار' : 'Send inquiry';

  // Small stats labels
  String get taxiTodayTitle => isArabic ? 'تاكسي · اليوم' : 'Taxi · Today';
  String get busTodayTitle => isArabic ? 'الحافلات · اليوم' : 'Bus · Today';
  String get ridesLabel => isArabic ? 'رحلات' : 'rides';
  String get completedLabel => isArabic ? 'مكتملة' : 'completed';
  String get tripsLabel => isArabic ? 'رحلات' : 'trips';
  String get bookingsLabel => isArabic ? 'حجوزات' : 'bookings';

  // Bus booking / history
  String get busBookingTitle => isArabic ? 'حجز الحافلة' : 'Bus booking';
  String get busSearchSectionTitle =>
      isArabic ? 'البحث عن رحلات الحافلات' : 'Search bus trips';
  String get busPaymentSectionTitle => isArabic ? 'الدفع' : 'Payment';
  String get busAvailableTripsTitle =>
      isArabic ? 'الرحلات المتاحة' : 'Available trips';
  String get busNoTripsHint => isArabic
      ? 'لا توجد رحلات بعد – ابحث باستخدام نقطة الانطلاق والوصول والتاريخ.'
      : 'No trips yet – search with origin, destination and date.';
  String get busDatePrefix => isArabic ? 'التاريخ' : 'Date';
  String get busSearchButton => isArabic ? 'بحث' : 'Search';
  String get busSearchingLabel => isArabic ? 'جاري البحث…' : 'Searching…';
  String get busSwapLabel => isArabic ? 'تبديل' : 'Swap';
  String get busBookPayLabel => isArabic ? 'حجز و دفع' : 'Book & Pay';
  String get busBookingBusyLabel => isArabic ? 'جاري الحجز…' : 'Booking…';
  String busBookingCreatedBanner(String id) =>
      isArabic ? 'تم إنشاء الحجز (المعرف: $id)' : 'Booking created (ID: $id)';
  String get busDetailsLabel => isArabic ? 'تفاصيل' : 'Details';
  String get busTripDetailsTitle => isArabic ? 'تفاصيل الرحلة' : 'Trip details';
  String get busSelectSeatsLabel =>
      isArabic ? 'اختيار المقاعد' : 'Select seats';
  String get busCancelLabel => isArabic ? 'إلغاء' : 'Cancel';
  String get busChangeLabel => isArabic ? 'تغيير' : 'Change';
  String get busCloseLabel => isArabic ? 'إغلاق' : 'Close';
  String get busSelectOriginDestError => isArabic
      ? 'يرجى اختيار نقطة الانطلاق والوصول'
      : 'Please select origin and destination';
  String get busSearchErrorBanner => isArabic
      ? 'حدث خطأ أثناء البحث عن الرحلات'
      : 'Error while searching for trips';
  String busFoundTripsBanner(int count, String dateStr) => isArabic
      ? 'تم العثور على $count رحلات للتاريخ $dateStr'
      : 'Found $count trips for $dateStr';
  String get busTicketsTitle => isArabic ? 'التذاكر' : 'Tickets';
  String get busTicketsCopyLabel => isArabic ? 'نسخ' : 'Copy';
  String get busTicketsCopiedSnack =>
      isArabic ? 'تم نسخ الحمولة إلى الحافظة' : 'Payload copied to clipboard';
  String get busPayerWalletLabel =>
      isArabic ? 'محفظة الدافع (مستحسن)' : 'Payer wallet (recommended)';
  String get busPayerWalletHintFilled => isArabic
      ? 'ستدفع من المحفظة وتستلم التذاكر فوراً.'
      : 'You pay from your wallet and get instant tickets.';
  String get busPayerWalletHintEmpty => isArabic
      ? 'افتح المحفظة لتفعيل الدفع داخل التطبيق والحصول على التذاكر فوراً.'
      : 'Open Wallet to enable in-app payments and get instant tickets.';
  String get busSeatsLabel => isArabic ? 'الركاب' : 'Passenger';
  String get busMyTripsTitle =>
      isArabic ? 'رحلات الحافلة الخاصة بي' : 'My bus trips';
  String get busMyTripsSubtitle => isArabic
      ? 'شاهد الرحلات القادمة والسابقة لمحفظتك.'
      : 'See upcoming and past trips for your wallet.';
  String get busWalletIdLabel => isArabic ? 'معرف المحفظة' : 'Wallet id';
  String get busLoadBookingsLabel =>
      isArabic ? 'تحميل حجوزاتي' : 'Load my bookings';
  String get busNoUpcomingTrips =>
      isArabic ? 'لا توجد رحلات قادمة بعد.' : 'No upcoming trips yet.';
  String get busNoPastTrips =>
      isArabic ? 'لا توجد رحلات سابقة بعد.' : 'No past trips yet.';
  String get busUpcomingTitle => isArabic ? 'القادمة' : 'Upcoming';
  String get busPastTitle => isArabic ? 'السابقة' : 'Past';
  String get busMyTicketsSectionTitle => isArabic ? 'تذاكري' : 'My tickets';
  String get busLastBookingPrefix => isArabic ? 'آخر حجز: ' : 'Last booking: ';
  String get busOpenTicketsLabel => isArabic ? 'فتح التذاكر' : 'Open tickets';
  String get busMyTicketsHint => isArabic
      ? 'بعد حجز رحلة، سيظهر آخر حجز هنا لتتمكن من فتح رموز QR الخاصة بالتذاكر.'
      : 'After you book a trip, your last booking will appear here so you can reopen your QR tickets.';
  String get busCreatedAtLabel => isArabic ? 'تاريخ الإنشاء: ' : 'Created at: ';
  String busFareSummary(String perSeat, String currency, String total) =>
      isArabic
          ? 'الأجرة: $perSeat $currency لكل مقعد · $total $currency إجمالي'
          : 'Fare: $perSeat $currency per seat · $total $currency total';
  String get busSeatPrefix => isArabic ? 'المقعد: ' : 'Seat: ';
  String get busStatusPrefix => isArabic ? 'الحالة: ' : 'Status: ';
  String get busTicketsLoadingLabel => isArabic ? 'جاري التحميل…' : 'Loading…';
  String get busTicketsReloadLabel =>
      isArabic ? 'إعادة تحميل التذاكر' : 'Reload tickets';
  String get busBookingTabSearch => isArabic ? 'بحث' : 'Search';
  String get busBookingTabMyTrips => isArabic ? 'رحلاتي' : 'My trips';

  // Mobility / journey
  String get journeyTitle => isArabic ? 'رحلتي' : 'My journey';
  String get mobilityHistoryTitle =>
      isArabic ? 'سجل الحركة' : 'Mobility history';
  String get mobilityTitle => isArabic ? 'التنقل والسفر' : 'Mobility & Travel';
  String get filterLabel => isArabic ? 'تصفية' : 'Filter';
  String get statusAll => isArabic ? 'الكل' : 'all';
  String get statusCompleted => isArabic ? 'مكتملة' : 'completed';
  String get statusCanceled => isArabic ? 'ملغاة' : 'canceled';
  String get todayLabel => isArabic ? 'اليوم' : 'Today';
  String get yesterdayLabel => isArabic ? 'أمس' : 'Yesterday';
  String get noMobilityHistory =>
      isArabic ? 'لا توجد رحلات بعد' : 'No mobility history yet';
  String get driverLabel => isArabic ? 'السائق' : 'Driver';

  // History / wallet
  String get historyTitle => isArabic ? 'سجل المحفظة' : 'Wallet history';
  String get historyPostedTransactions =>
      isArabic ? 'الحركات المسجلة' : 'Posted transactions';
  String get historyLoadMore =>
      isArabic ? 'تحميل المزيد (الحد: ' : 'Load more (limit: ';
  String get historyUnexpectedFormat =>
      isArabic ? 'تنسيق غير متوقع لبيانات السجل' : 'Unexpected snapshot format';
  String get historyErrorPrefix => isArabic ? 'خطأ' : 'Error';
  String get historyCsvErrorPrefix => isArabic ? 'خطأ في CSV' : 'CSV error';
  String get historyDirLabel => isArabic ? 'الاتجاه:' : 'Direction:';
  String get historyTypeLabel => isArabic ? 'النوع:' : 'Type:';
  String get historyPeriodLabel => isArabic ? 'الفترة:' : 'Period:';
  String get historyFromLabel => isArabic ? 'من' : 'From';
  String get historyToLabel => isArabic ? 'إلى' : 'To';
  String get historyExportSubject =>
      isArabic ? 'تصدير المدفوعات' : 'Payments Export';

  // Payment requests / receive
  String get payRequestTitle => isArabic ? 'طلب دفعة' : 'Payment request';
  String get payNoEntries => isArabic ? 'لا توجد عناصر' : 'No entries';
  String get payRequestAmountLabel =>
      isArabic ? 'المبلغ (SYP، اختياري)' : 'Amount (SYP, optional)';
  String get payRequestNoteLabel =>
      isArabic ? 'ملاحظة (اختياري)' : 'Note (optional)';
  String get payRequestPreviewPrefix => isArabic ? 'طلب: ' : 'Requesting: ';
  String get payRequestQrLabel => isArabic ? 'طلب (رمز QR)' : 'Request (QR)';
  String get payShareLinkLabel => isArabic ? 'مشاركة الرابط' : 'Share link';
  String get copiedLabel => isArabic ? 'تم النسخ' : 'Copied';
  String get walletLabel => isArabic ? 'المحفظة' : 'Wallet';
  String get walletNotSetShort => isArabic ? '(غير معيّن)' : '(not set)';
  String get balanceLabel => isArabic ? 'الرصيد' : 'Balance';
  String get sonicSectionTitle =>
      isArabic ? 'دفعة قريبة (Sonic)' : 'Offline proximity payment (Sonic)';
  String get sonicAmountLabel => isArabic ? 'المبلغ (SYP)' : 'Amount (SYP)';
  String get sonicIssueLabel => isArabic ? 'إصدار رمز' : 'Issue token';
  String get sonicTokenLabel =>
      isArabic ? 'الرمز (اختياري)' : 'Token (optional)';
  String get sonicRedeemLabel => isArabic ? 'استرداد' : 'Redeem';
  String get sonicQueuedOffline =>
      isArabic ? 'تمت الجدولة (بدون اتصال)' : 'Queued (offline)';

  // Payments helpers
  String get payFavoritesLabel => isArabic ? 'المفضلة لدي' : 'My favorites';
  String get clearLabel => isArabic ? 'مسح' : 'Clear';
  String get payRecipientLabel => isArabic
      ? 'المستلم (محفظة / هاتف / @اسم)'
      : 'Recipient (Wallet/Phone/@alias)';
  String get payAmountLabel => isArabic ? 'المبلغ (SYP)' : 'Amount (SYP)';
  String get payNoteLabel =>
      isArabic ? 'الملاحظات (اختياري)' : 'Reference (optional)';
  String get payCheckInputs =>
      isArabic ? 'يرجى التحقق من المدخلات' : 'Please check your inputs';
  String get payOfflineQueued =>
      isArabic ? 'بدون اتصال: تم التخزين في الانتظار' : 'Offline: queued';
  String get paySendFailed => isArabic
      ? 'خطأ في التحويل، حاول مرة أخرى.'
      : 'Transfer failed, please try again.';
  String get payGuardrailAmount => isArabic
      ? 'المبلغ يتجاوز الحد المسموح به لهذه العملية.'
      : 'Amount exceeds the maximum allowed for a single transfer.';
  String get payGuardrailVelocityWallet => isArabic
      ? 'عدد كبير من التحويلات من هذه المحفظة خلال فترة قصيرة. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.'
      : 'Too many transfers from this wallet in a short period. Please wait a bit and try again.';
  String get payGuardrailVelocityDevice => isArabic
      ? 'عدد كبير من التحويلات من هذا الجهاز خلال فترة قصيرة. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.'
      : 'Too many transfers from this device in a short period. Please wait a bit and try again.';
  String get payOfflineSavedPrefix =>
      isArabic ? 'تم الحفظ بدون اتصال' : 'Offline saved';
  String get payContactsLabel => isArabic ? 'جهات الاتصال' : 'Contacts';
  String get sendLabel => isArabic ? 'إرسال' : 'Send';
  String paySendAfter(int seconds) =>
      isArabic ? 'إرسال بعد ${seconds}s' : 'Send (${seconds}s)';
  String payWaitSeconds(int seconds) =>
      isArabic ? 'يرجى الانتظار ${seconds}ث' : 'Please wait ${seconds}s';
  String get payReqStatusPending => isArabic ? 'قيد الانتظار' : 'Pending';
  String get payReqStatusAccepted => isArabic ? 'مكتمل' : 'Completed';
  String get payReqStatusCancelled => isArabic ? 'ملغاة' : 'Cancelled';
  String get payReqStatusExpired => isArabic ? 'منتهية الصلاحية' : 'Expired';

  // Taxi helpers
  String get taxiNoActiveRide =>
      isArabic ? 'لا توجد رحلة نشطة' : 'No active ride';
  String get taxiIncomingRide =>
      isArabic ? 'طلب رحلة جديد' : 'Incoming ride request';
  String get taxiDenyRequest =>
      isArabic ? 'رفض هذا الطلب؟' : 'Deny this request?';
  String get taxiTopupScanErrorPrefix =>
      isArabic ? 'خطأ في مسح رصيد الشحن' : 'Topup scan error';
  String get taxiTopupErrorPrefix => isArabic ? 'خطأ في الشحن' : 'Topup error';

  // Freight / Courier & Transport
  String get freightTitle => isArabic ? 'التوصيل' : 'Courier';
  String get freightQuoteLabel => isArabic ? 'تسعير' : 'Quote';
  String get freightBookPayLabel => isArabic ? 'حجز و دفع' : 'Book & Pay';
  String get freightGuardrailAmount => isArabic
      ? 'قيمة الشحنة تتجاوز الحد المسموح به لهذه الخدمة.'
      : 'Shipment amount exceeds the maximum allowed for this service.';
  String get freightGuardrailDistance => isArabic
      ? 'مسافة الشحنة بعيدة جداً بالنسبة لهذه الخدمة. حاول تقليل المسافة أو تقسيم الشحنة.'
      : 'Shipment distance is too far for this service. Try reducing the distance or splitting the shipment.';
  String get freightGuardrailWeight => isArabic
      ? 'وزن الشحنة أعلى من الحد المسموح. حاول تقليل الوزن أو تقسيم الشحنة.'
      : 'Shipment weight is above the allowed limit. Try reducing the weight or splitting the shipment.';
  String get freightGuardrailVelocityPayer => isArabic
      ? 'عدد كبير من شحنات الدفع من هذه المحفظة خلال فترة قصيرة. يرجى الانتظار قليلاً قبل المحاولة مرة أخرى.'
      : 'Too many paid shipments from this wallet in a short period. Please wait a bit and try again.';
  String get freightGuardrailVelocityDevice => isArabic
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
  String get equipmentTitle => isArabic ? 'تأجير المعدات' : 'Equipment rental';

  // Food orders
  String get foodOrdersTitle => isArabic ? 'طلبات الطعام' : 'Food orders';
  String get foodOrdersAutoRefresh =>
      isArabic ? 'تحديث تلقائي (10ث)' : 'Auto‑refresh (10s)';
  String get foodOrdersPendingOfflineTitle =>
      isArabic ? 'معلّق (بدون اتصال)' : 'Pending (offline)';
  String foodOrdersSignedInLabel(String phone) {
    final p = phone.trim();
    if (isArabic) {
      return 'تم تسجيل الدخول: ${p.isEmpty ? '(بدون رقم)' : p}';
    }
    return 'Signed in: ${p.isEmpty ? '(no phone)' : p}';
  }

  String get foodOrdersLoadList => isArabic ? 'تحميل القائمة' : 'Load list';
  String get foodOrdersExportCsv => isArabic ? 'تصدير CSV' : 'Export CSV';
  String get foodOrdersPeriodTitle => isArabic ? 'الفترة' : 'Period';
  String get foodOrdersFrom => isArabic ? 'من' : 'From';
  String get foodOrdersTo => isArabic ? 'إلى' : 'To';
  String get foodOrdersListTitle => isArabic ? 'الطلبات' : 'Orders';
  String get foodOrderIdLabel => isArabic ? 'معرّف الطلب' : 'Order ID';
  String get foodOrdersCheckStatus =>
      isArabic ? 'تحقق من الحالة' : 'Check status';
  String get foodOrdersRecentTitle =>
      isArabic ? 'الطلبات الأخيرة' : 'Recent orders';
  String foodOrdersOrderTitle(String id) => isArabic ? 'طلب $id' : 'Order $id';
  String get foodFilterAll => isArabic ? 'الكل' : 'All';
  String get foodStatusPending => isArabic ? 'قيد الانتظار' : 'Pending';
  String get foodStatusConfirmed => isArabic ? 'مؤكد' : 'Confirmed';
  String get foodStatusDelivered => isArabic ? 'تم التسليم' : 'Delivered';
  String get foodStatusCanceled => isArabic ? 'ملغى' : 'Canceled';
  String get foodPeriodAll => isArabic ? 'كل الوقت' : 'All time';
  String get foodPeriod7d => isArabic ? 'آخر 7 أيام' : 'Last 7 days';
  String get foodPeriod30d => isArabic ? 'آخر 30 يوماً' : 'Last 30 days';
  String get foodPeriodCustom => isArabic ? 'مخصص' : 'Custom';
  String get foodOrderIdRequired =>
      isArabic ? 'معرّف الطلب مطلوب' : 'Order id required';
  String get foodStatusTitle => isArabic ? 'الحالة' : 'Status';
  String get foodCreatedTitle => isArabic ? 'تم الإنشاء' : 'Created';
  String get foodTotalTitle => isArabic ? 'المجموع' : 'Total';
  String get foodRestaurantTitle => isArabic ? 'المطعم' : 'Restaurant';
  String get foodItemsTitle => isArabic ? 'العناصر' : 'Items';
  String get foodReorderPlaced =>
      isArabic ? 'تم إرسال طلب جديد' : 'Reorder placed';
  String foodErrorPrefix(int code) => isArabic ? 'خطأ: $code' : 'Error: $code';
  String foodErrorGeneric(Object e) => isArabic ? 'خطأ: $e' : 'Error: $e';
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
