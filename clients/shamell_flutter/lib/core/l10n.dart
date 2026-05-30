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
  String get loginBiometricSignIn =>
      isArabic ? 'تسجيل الدخول بالبصمة' : 'Sign in with biometrics';
  String get loginAuthenticating =>
      isArabic ? 'جارٍ التحقق…' : 'Authenticating…';
  String get loginBiometricWebUnavailable => isArabic
      ? 'تسجيل الدخول بالبصمة غير متاح على الويب.'
      : 'Biometric sign-in is not available on web.';
  String get loginBiometricRequired => isArabic
      ? 'تسجيل الدخول يتطلب المصادقة البيومترية على هذا الجهاز.'
      : 'Biometric authentication is required on this device.';
  String get loginBiometricFailed => isArabic
      ? 'فشلت المصادقة البيومترية.'
      : 'Biometric authentication failed.';
  String get loginAuthCancelled =>
      isArabic ? 'تم إلغاء التحقق.' : 'Authentication cancelled.';
  String get loginDeviceNotEnrolled => isArabic
      ? 'لا يوجد حساب على هذا الجهاز بعد. أنشئ معرّف Shamell جديد، أو اربط هذا الجهاز عبر رمز QR لتسجيل الدخول من جهاز آخر.'
      : 'No account on this device yet. Create a new Shamell ID, or link this device via Device-Login QR from another device.';
  String get loginQrHint => isArabic
      ? 'لاستخدام شامل ويب، افتح رمز QR لتسجيل الدخول على الكمبيوتر وامسحه من داخل \"استكشاف > مسح\" في شامل.'
      : 'To use Shamell Web, open a login QR on your computer and scan it from \"Discover > Scan\" in Shamell.';
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

  // Home / modules
  String get homeActions => isArabic ? 'الإجراءات' : 'Actions';
  String get homePayments => isArabic ? 'المدفوعات' : 'Payment';
  String get homeWallet => isArabic ? 'المحفظة' : 'Wallet';
  String get homeBills => isArabic ? 'الفواتير' : 'Bills';
  String get homeRequests => isArabic ? 'الطلبات' : 'Requests';
  String get homeVouchers => isArabic ? 'قسائم' : 'Vouchers';
  String get homeBus => isArabic ? 'الحافلات' : 'Bus';
  String get homeChat => isArabic ? 'شامل' : 'Shamell';
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

  // Shamell Identity / backup / dialogs
  String get shamellIdentityTitle => isArabic ? 'معرّف الدردشة' : 'Chat ID';
  String get shamellIdentityNotCreated =>
      isArabic ? 'لم يتم إنشاء الهوية بعد' : 'Not created yet';
  String get shamellIdentityHint => isArabic
      ? 'أنشئ هوية الدردشة للبدء.'
      : 'Create your chat identity to start.';
  String get shamellDisplayNameOptional =>
      isArabic ? 'اسم العرض (اختياري)' : 'Display name (optional)';
  String get shamellGenerate => isArabic ? 'توليد' : 'Generate';
  String get shamellRegisterWithRelay =>
      isArabic ? 'التسجيل مع الخادم' : 'Register with relay';
  String get shamellShowQrButton => isArabic ? 'إظهار رمز QR' : 'Show QR';
  String get shamellCopyIdButton => isArabic ? 'نسخ المعرف' : 'Copy ID';
  String get shamellIdCopiedSnack => isArabic ? 'تم نسخ المعرف' : 'ID copied';
  String get shamellShareIdButton => isArabic ? 'مشاركة المعرف' : 'Share ID';
  String get shamellBackupPassphraseButton =>
      isArabic ? 'نسخة احتياطية (عبارة سرية)' : 'Backup (passphrase)';
  String get shamellRestoreBackupButton =>
      isArabic ? 'استعادة النسخة الاحتياطية' : 'Restore backup';
  String get shamellBackupDialogTitle =>
      isArabic ? 'لصق نص النسخة الاحتياطية' : 'Paste backup text';
  String get shamellBackupDialogLabel =>
      isArabic ? 'النسخة الاحتياطية' : 'Backup';
  String get shamellDialogCancel => isArabic ? 'إلغاء' : 'Cancel';
  String get shamellDialogOk => isArabic ? 'موافق' : 'OK';

  // Shamell settings
  String get shamellSettingsPrivacy => isArabic ? 'الخصوصية' : 'Privacy';
  String get shamellSettingsAppearance => isArabic ? 'المظهر' : 'Appearance';
  String get shamellSettingsNotifications =>
      isArabic ? 'الإشعارات' : 'Notifications';
  String get shamellSettingsChat => isArabic ? 'الدردشة' : 'Chat';
  String get shamellSettingsMedia => isArabic ? 'الوسائط' : 'Media';
  String get shamellSettingsStorage =>
      isArabic ? 'إدارة التخزين' : 'Storage management';
  String get shamellSettingsPasscode => isArabic ? 'قفل برمز' : 'Passcode lock';
  String get shamellSettingsCalls => isArabic ? 'المكالمات' : 'Calls';
  String get shamellSettingsRate => isArabic ? 'قيّم Shamell' : 'Rate Shamell';
  String get shamellSettingsInviteFriends =>
      isArabic ? 'دعوة الأصدقاء' : 'Invite friends';
  String get shamellSettingsSupport => isArabic ? 'الدعم' : 'Support';
  String get shamellSettingsPrivacyPolicy =>
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
  String get shamellSettingsTerms =>
      isArabic ? 'شروط الاستخدام' : 'Terms of Service';
  String get shamellSettingsLicense => isArabic ? 'الترخيص' : 'License';
  String get shamellSettingsAdvanced => isArabic ? 'متقدم' : 'Advanced';

  // Shamell bottom tabs
  String get shamellTabContacts => isArabic ? 'جهات الاتصال' : 'Contacts';
  String get shamellTabChats => isArabic ? 'الدردشات' : 'Chats';
  String get shamellTabProfile => isArabic ? 'الملف الشخصي' : 'Profile';
  String get shamellTabSettings => isArabic ? 'الإعدادات' : 'Settings';
  String get shamellTabChannel => isArabic ? 'استكشاف' : 'Discover';

  // Shamell chats / contacts
  String get shamellChatsMarkAllRead =>
      isArabic ? 'وضع الكل كمقروء' : 'Mark all as read';
  String get shamellChatsSelection =>
      isArabic ? 'تحديد المحادثات' : 'Selection';
  String get shamellChatsPinnedHeader => isArabic ? 'المثبتة' : 'Pinned';
  String get shamellChatsOthersHeader =>
      isArabic ? 'الدردشات الأخرى' : 'Other chats';
  String get shamellMessagePreviewsDisable =>
      isArabic ? 'إيقاف معاينة الرسائل' : 'Disable message previews';
  String get shamellMessagePreviewsEnable =>
      isArabic ? 'تفعيل معاينة الرسائل' : 'Enable message previews';
  String get shamellNoContactsHint => isArabic
      ? 'لا توجد جهات اتصال بعد. أضِف جهة عبر مسح رمز QR أو استعلام عن المعرف.'
      : 'No contacts yet. Add one via QR scan or by resolving an ID.';
  String get shamellNoMessagesYet =>
      isArabic ? 'لا توجد رسائل بعد.' : 'No messages yet.';
  String get shamellAddContactFirst => isArabic
      ? 'أضِف جهة اتصال لبدء المحادثة.'
      : 'Add a contact to start chatting.';
  String get shamellLastCallBannerPrefix =>
      isArabic ? 'آخر مكالمة' : 'Last call';
  String get shamellNewChatTooltip => isArabic ? 'محادثة جديدة' : 'New chat';
  String get shamellUnrecognizedQr =>
      isArabic ? 'رمز غير معروف.' : 'Unrecognized QR payload.';
  String get shamellFriendQrAlreadyFriends =>
      isArabic ? 'أنتم أصدقاء بالفعل.' : 'You are already friends.';
  String get shamellFriendQrPending => isArabic
      ? 'طلب الصداقة قيد الانتظار.'
      : 'Friend request already pending.';
  String get shamellFriendQrSent =>
      isArabic ? 'تم إرسال طلب الصداقة.' : 'Friend request sent.';
  String get shamellFriendQrSendFailed =>
      isArabic ? 'تعذر إرسال طلب الصداقة.' : 'Could not send friend request.';
  String get shamellFriendQrSendError => isArabic
      ? 'حدث خطأ أثناء إرسال طلب الصداقة.'
      : 'Error while sending friend request.';

  String get shamellSettingsNotificationsSubtitle => isArabic
      ? 'إدارة إشعارات الحسابات الرسمية داخل Shamell'
      : 'Manage official‑account notifications inside Shamell';

  // Shamell contacts tab sections
  String get shamellContactsNewFriends =>
      isArabic ? 'أصدقاء جدد' : 'New friends';
  String get shamellContactsNewFriendsSubtitle => isArabic
      ? 'إضافة صديق جديد عبر Shamell ID أو رمز QR'
      : 'Add a new friend via Shamell ID or QR';
  String get shamellContactsGroups => isArabic ? 'المجموعات' : 'Group chats';
  String get shamellContactsGroupsSubtitle => isArabic
      ? 'إنشاء مجموعات محادثة وإدارتها'
      : 'Create and manage group conversations';
  String get shamellContactsServiceAccounts =>
      isArabic ? 'حسابات الخدمات' : 'Service accounts';
  String get shamellContactsServiceAccountsSubtitle =>
      isArabic ? 'Shamell Bus, Pay والمزيد' : 'Shamell Bus, Pay and more';
  String get shamellContactsPeopleP2P =>
      isArabic ? 'الأشخاص والمدفوعات' : 'People & P2P';
  String get shamellContactsPeopleP2PSubtitle => isArabic
      ? 'إرسال أموال بسرعة إلى جهات الاتصال'
      : 'Quickly send money to your contacts';
  String get shamellContactsShamellServicesTitle =>
      isArabic ? 'حسابات Shamell' : 'Shamell services';

  // Shamell Moments / favorites / channel tab
  String get shamellChannelSocial => isArabic ? 'اجتماعي' : 'Social';
  String get shamellChannelDiscover => isArabic ? 'اكتشاف' : 'Discover';
  String get shamellChannelMomentsTitle => isArabic ? 'اللحظات' : 'Moments';
  String get shamellChannelMomentsSubtitle =>
      isArabic ? 'شاهد وشارك لحظات أصدقائك' : 'View and share your Moments';
  String get shamellChannelFavoritesTitle => isArabic ? 'المفضلة' : 'Favorites';
  String get shamellChannelFavoritesSubtitle => isArabic
      ? 'وصول سريع إلى العناصر المحفوظة'
      : 'Quick access to saved items';
  String get shamellChannelOfficialAccountsTitle =>
      isArabic ? 'الحسابات الرسمية' : 'Official accounts';
  String get shamellChannelOfficialAccountsSubtitle => isArabic
      ? 'تابِع حسابات Shamell والخدمات الشريكة'
      : 'Follow Shamell and partner service accounts';
  String get shamellChannelSubscriptionAccountsTitle =>
      isArabic ? 'حسابات الاشتراك' : 'Subscription accounts';
  String get shamellChannelSubscriptionAccountsSubtitle => isArabic
      ? 'تابع المحتوى التفاعلي من الحسابات الرسمية'
      : 'Follow content updates from official accounts';
  String get shamellChannelScanTitle => isArabic ? 'مسح' : 'Scan';
  String get shamellChannelScanSubtitle => isArabic
      ? 'مسح رموز QR لتسجيل الدخول إلى شامل ويب، المدفوعات والبرامج المصغّرة'
      : 'Scan QR for Shamell Web login, payments and mini‑apps';
  String get shamellMomentsAudienceHint => isArabic
      ? 'استخدم الوسوم مثل \"العائلة\" و\"العمل\" في شاشة الأصدقاء لتحديد من يرى لحظاتك (Only Family/Work بأسلوب Shamell).'
      : 'Use friend labels like \"Family\" and \"Work\" in the Friends screen to choose who sees this moment (Only Family/Work, Shamell‑style).';

  // Shamell subscriptions feed
  String get shamellSubscriptionsFeedTitle =>
      isArabic ? 'خلاصة الاشتراكات' : 'Subscriptions feed';
  String get shamellSubscriptionsFeedEmptySummary => isArabic
      ? 'تحديثات مجمّعة من حسابات الاشتراك الرسمية'
      : 'Aggregated updates from subscription official accounts';
  String shamellSubscriptionsFeedSummary(int subs, int unread) {
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

  String get shamellSubscriptionsFeedEmptyShort => isArabic
      ? 'عرض تحديثات الحسابات الرسمية من نوع الاشتراك'
      : 'Show updates from subscription official accounts';
  String shamellSubscriptionsAccountsSummary(int subs, int unread) {
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

  String get shamellSubscriptionsTitle =>
      isArabic ? 'الاشتراكات' : 'Subscriptions';
  String get shamellSubscriptionsEmpty =>
      isArabic ? 'لا توجد تحديثات اشتراك بعد.' : 'No subscription updates yet.';
  String get shamellSubscriptionsFilterAll => isArabic ? 'الكل' : 'All';
  String get shamellSubscriptionsFilterUnread =>
      isArabic ? 'غير مقروءة' : 'Unread';
  String get shamellSubscriptionsMarkAllRead =>
      isArabic ? 'اعتبار كل التحديثات مقروءة' : 'Mark all updates as read';

  // Shamell friends / labels
  String get shamellFriendAliasTitle =>
      isArabic ? 'اسم مخصص للصديق' : 'Friend alias';
  String get shamellFriendAliasLabel =>
      isArabic ? 'الاسم في الدردشة (اختياري)' : 'Chat name (optional)';
  String get shamellFriendAliasHint =>
      isArabic ? 'مثلاً: أحمد (العمل)' : 'e.g. Ali (work)';
  String get shamellFriendTagsLabel =>
      isArabic ? 'الوسوم (اختياري)' : 'Tags (optional)';
  String get shamellFriendTagsHint =>
      isArabic ? 'مثلاً: العائلة، العمل' : 'e.g. Family, Work';
  String get shamellFriendTagsPrefix => isArabic ? 'الوسوم:' : 'Tags:';
  String get shamellFriendsCloseLabel =>
      isArabic ? 'صديق مقرّب' : 'Close friend';
  String get shamellFriendsAccept => isArabic ? 'قبول' : 'Accept';
  String get shamellFriendsAddNewTitle =>
      isArabic ? 'إضافة صديق جديد' : 'Add new friend';
  String get shamellFriendsSearchHint =>
      isArabic ? 'Shamell ID' : 'Shamell ID';
  String get shamellFriendsSending => isArabic ? '...جارٍ الإرسال' : 'Sending…';
  String get shamellFriendsSendRequest =>
      isArabic ? 'إرسال طلب صداقة' : 'Send friend request';
  String get shamellFriendsSuggestionsTitle =>
      isArabic ? 'اقتراحات' : 'Suggestions';
  String get shamellFriendsSuggestionsEmpty => isArabic
      ? 'استخدم Shamell ID أو رمز QR لإضافة صديق.'
      : 'Use Shamell ID or QR to add a friend.';
  String get shamellFriendsSyncContacts =>
      isArabic ? 'إضافة عبر QR' : 'Add via QR';
  String get shamellFriendsRequestsTitle =>
      isArabic ? 'طلبات الصداقة' : 'Friend requests';
  String get shamellFriendsSentTitle =>
      isArabic ? 'طلبات مرسلة' : 'Sent requests';
  String get shamellFriendsListTitle => isArabic ? 'الأصدقاء' : 'Friends';
  String get shamellFriendsEmpty =>
      isArabic ? 'لا توجد صداقات بعد.' : 'No friends yet.';
  String get shamellScanQr => isArabic ? 'مسح QR' : 'Scan QR';
  String get shamellSyncInbox => isArabic ? 'مزامنة الوارد' : 'Sync inbox';
  String get shamellHideLockedChats =>
      isArabic ? 'إخفاء الدردشات المقفلة' : 'Hide locked chats';
  String get shamellShowLockedChats => isArabic
      ? 'إظهار الدردشات المقفلة (يتطلب فتحاً)'
      : 'Show locked chats (requires auth)';
  String get shamellPeerIdLabel => isArabic ? 'معرّف الطرف' : 'Peer ID';
  String get shamellResolve => isArabic ? 'استعلام' : 'Resolve';
  String get shamellVerifiedLabel => isArabic ? 'موثوق' : 'Verified';
  String get shamellMarkVerifiedLabel =>
      isArabic ? 'وضع علامة كموثوق' : 'Mark verified';
  String get shamellDisableDisappear =>
      isArabic ? 'إيقاف الاختفاء' : 'Disable disappear';
  String get shamellEnableDisappear =>
      isArabic ? 'تفعيل الاختفاء' : 'Enable disappear';
  String get shamellDisappearAfter =>
      isArabic ? 'الاختفاء بعد' : 'Disappear after';
  String get shamellUnhideChat => isArabic ? 'إظهار المحادثة' : 'Unhide chat';
  String get shamellHideChat => isArabic ? 'إخفاء المحادثة' : 'Hide chat';
  String get shamellUnblock => isArabic ? 'إلغاء الحظر' : 'Unblock';
  String get shamellBlock => isArabic ? 'حظر' : 'Block';
  String get shamellTrustedFingerprint =>
      isArabic ? 'بصمة موثوقة' : 'Trusted fingerprint';
  String get shamellUnverifiedContact =>
      isArabic ? 'جهة اتصال غير موثوقة' : 'Unverified contact';
  String get shamellPeerFingerprintLabel =>
      isArabic ? 'بصمة الطرف:' : 'Peer FP:';
  String get shamellYourFingerprintLabel => isArabic ? 'بصمتك:' : 'Your FP:';
  String get shamellSafetyLabel => isArabic ? 'السلامة:' : 'Safety:';
  String get shamellResetSessionLabel =>
      isArabic ? 'إعادة تعيين الجلسة' : 'Reset session';
  String get shamellMessagesTitle => isArabic ? 'الرسائل' : 'Messages';
  String get shamellAttachImage => isArabic ? 'إرفاق صورة' : 'Attach image';
  String get shamellTypeMessage => isArabic ? 'اكتب رسالة' : 'Type a message';
  String get shamellImageAttached =>
      isArabic ? 'تم إرفاق صورة' : 'Image attached';
  String get shamellRemoveAttachment =>
      isArabic ? 'إزالة المرفق' : 'Remove attachment';
  String get shamellSessionChangedTitle =>
      isArabic ? 'تم تغيير الجلسة' : 'Session changed';
  String get shamellSessionChangedBody => isArabic
      ? 'تم تغيير مفتاح المرسل. تحقق من رقم الأمان مع جهة الاتصال. أعد تعيين الجلسة إذا لم تكن متأكدًا.'
      : 'Sender key changed. Verify the safety number with your contact. Reset the session if unsure.';
  String get shamellLater => isArabic ? 'لاحقًا' : 'Later';
  String get shamellUnlockHiddenReason =>
      isArabic ? 'فتح الدردشات المخفية' : 'Unlock hidden chats';
  String get shamellScanContactQrTitle =>
      isArabic ? 'مسح رمز QR لجهة الاتصال' : 'Scan contact QR';

  // Shamell errors / backup / notifications
  String get shamellAttachFailed =>
      isArabic ? 'فشل إرفاق الملف' : 'Attach failed';
  String get shamellShareFailed =>
      isArabic ? 'فشل مشاركة الملف' : 'Share failed';
  String get shamellBackupCreated => isArabic
      ? 'تم إنشاء النسخة الاحتياطية ونسخها. احتفظ بها بأمان.'
      : 'Backup created and copied. Keep it safe.';
  String get shamellBackupFailed =>
      isArabic ? 'فشل إنشاء النسخة الاحتياطية' : 'Backup failed';
  String get shamellBackupInvalidFormat =>
      isArabic ? 'تنسيق النسخة الاحتياطية غير صالح' : 'Invalid backup format';
  String get shamellBackupMissingFields =>
      isArabic ? 'النسخة الاحتياطية تفتقد حقولاً' : 'Backup missing fields';
  String get shamellBackupCorrupt =>
      isArabic ? 'النسخة الاحتياطية تالفة' : 'Backup corrupt';
  String get shamellRestoreFailed =>
      isArabic ? 'فشل الاستعادة' : 'Restore failed';
  String get shamellBackupPassphraseTitleSet =>
      isArabic ? 'تعيين عبارة مرور النسخة الاحتياطية' : 'Set backup passphrase';
  String get shamellBackupPassphraseTitleEnter => isArabic
      ? 'إدخال عبارة مرور النسخة الاحتياطية'
      : 'Enter backup passphrase';
  String get shamellBackupPassphraseLabel =>
      isArabic ? 'عبارة المرور' : 'Passphrase';
  String get shamellBackupPassphraseConfirm =>
      isArabic ? 'تأكيد عبارة المرور' : 'Confirm';
  String get shamellNewMessageTitle => isArabic ? 'رسالة جديدة' : 'New message';
  String get shamellNewMessageBody =>
      isArabic ? 'افتح المحادثة لعرض الرسالة.' : 'Open chat to view.';
  String get shamellRatchetKeyMismatch => isArabic
      ? 'تم اكتشاف عدم تطابق في المفتاح. أعد تعيين الجلسة.'
      : 'Key mismatch detected. Reset session.';
  String get shamellRatchetWindowWarning => isArabic
      ? 'الرسالة خارج النافذة. فكّر في إعادة تعيين الجلسة.'
      : 'Message outside window; consider resetting session.';
  String get shamellRatchetAheadWarning => isArabic
      ? 'الرسالة بعيدة جدًا للأمام؛ لم يتم تخزين المفاتيح.'
      : 'Message too far ahead; keys not stored.';
  String get shamellPreviewImage => isArabic ? '[صورة]' : '[Image]';
  String get shamellPreviewUnknown => isArabic ? '<رسالة>' : '<message>';
  String get shamellPreviewVoice =>
      isArabic ? '[رسالة صوتية]' : '[Voice message]';
  String get shamellStartVoice =>
      isArabic ? 'تسجيل رسالة صوتية' : 'Record voice message';
  String get shamellStopVoice => isArabic ? 'إيقاف التسجيل' : 'Stop recording';
  String get shamellRecordingVoice =>
      isArabic ? 'جاري تسجيل رسالة صوتية...' : 'Recording voice note…';
  String get shamellVoiceHoldToTalk =>
      isArabic ? 'اضغط مع الاستمرار للتسجيل' : 'Hold to talk';
  String get shamellVoiceSlideUpToCancel => isArabic
      ? 'اسحب للأعلى للإلغاء، اسحب لليمين للقفل'
      : 'Slide up to cancel, slide right to lock';
  String get shamellVoiceReleaseToCancel =>
      isArabic ? 'حرر للإلغاء' : 'Release to cancel';
  String get shamellVoiceCanceledSnack =>
      isArabic ? 'تم إلغاء الرسالة الصوتية' : 'Voice message canceled';
  String get shamellVoiceTooShort =>
      isArabic ? 'الرسالة الصوتية قصيرة جداً' : 'Voice message too short';
  String get shamellVoiceLocked =>
      isArabic ? 'التسجيل مقفل' : 'Recording locked';
  String shamellVoiceMessageLabel(String seconds) => isArabic
      ? (seconds.isNotEmpty ? 'رسالة صوتية (${seconds} ثوان)' : 'رسالة صوتية')
      : (seconds.isNotEmpty ? 'Voice message (${seconds}s)' : 'Voice message');
  String get shamellVoicePlaybackSoon => isArabic
      ? 'تشغيل الرسائل الصوتية غير متاح على هذا الجهاز.'
      : 'Voice message playback is unavailable on this device.';
  String get shamellVoiceSpeakerMode =>
      isArabic ? 'تشغيل عبر مكبر الصوت' : 'Play via speaker';
  String get shamellVoiceEarpieceMode =>
      isArabic ? 'تشغيل عبر سماعة الأذن' : 'Play via earpiece';
  String get shamellMessageActionsTitle =>
      isArabic ? 'خيارات الرسالة' : 'Message options';
  String get shamellCopyMessage => isArabic ? 'نسخ' : 'Copy';
  String get shamellForwardMessage => isArabic ? 'إعادة التوجيه' : 'Forward';
  String get shamellTranslateMessage => isArabic ? 'ترجمة' : 'Translate';
  String get shamellReplyMessage => isArabic ? 'الرد' : 'Reply';
  String get shamellDeleteForMe => isArabic ? 'حذف' : 'Delete';
  String get shamellRecallMessage => isArabic ? 'استرجاع' : 'Recall';
  String get shamellMessageRecalledByMe =>
      isArabic ? 'لقد استرجعت هذه الرسالة.' : 'You recalled this message.';
  String get shamellMessageRecalledByOther =>
      isArabic ? 'تم استرجاع هذه الرسالة.' : 'This message was recalled.';
  String get shamellPinMessage =>
      isArabic ? 'تثبيت الرسالة في الأعلى' : 'Pin message to top';
  String get shamellUnpinMessage =>
      isArabic ? 'إلغاء تثبيت الرسالة' : 'Unpin message';
  String get shamellAddToFavorites =>
      isArabic ? 'إضافة إلى المفضلة' : 'Add to favorites';
  String get shamellMessageCopiedSnack =>
      isArabic ? 'تم نسخ الرسالة' : 'Message copied';
  String get shamellMessageFavoritedSnack =>
      isArabic ? 'تمت إضافة الرسالة إلى المفضلة' : 'Message added to favorites';
  String get shamellPreviewLocation => isArabic ? 'موقع' : 'Location';
  String get shamellSendLocation => isArabic ? 'إرسال الموقع' : 'Send location';
  String get shamellLocationOpenInMap =>
      isArabic ? 'فتح على الخريطة' : 'Open in map';
  String get shamellLocationFavorite =>
      isArabic ? 'إضافة إلى المواقع المفضلة' : 'Add to favorite locations';
  String get shamellLocationFavoritedSnack =>
      isArabic ? 'تم حفظ الموقع في المفضلة' : 'Location saved to favorites';
  String get shamellCallKindVideo => isArabic ? 'فيديو' : 'Video';
  String get shamellCallKindVoice => isArabic ? 'صوت' : 'Voice';
  String get shamellCallDirectionOutgoing => isArabic ? 'صادر' : 'Outgoing';
  String get shamellCallDirectionIncoming => isArabic ? 'وارد' : 'Incoming';
  String get shamellCallStatusMissed =>
      isArabic ? 'مكالمة فائتة' : 'Missed call';
  String get shamellCallStatusMissedShort =>
      isArabic ? 'لم يتم الرد' : 'Missed';
  String get shamellCallStatusShort => isArabic ? 'مكالمة قصيرة' : 'Short call';
  String get shamellCallRedial => isArabic ? 'إعادة الاتصال' : 'Redial';
  String get shamellDevicesThisDevice =>
      isArabic ? 'هذا الجهاز' : 'This device';
  String get shamellDevicesLogoutOthers =>
      isArabic ? 'تسجيل الخروج من الأجهزة الأخرى' : 'Log out of other devices';
  String get shamellDevicesLogoutOthersConfirm => isArabic
      ? 'سيتم إزالة جميع الأجهزة الأخرى المرتبطة بهذا الحساب. المتابعة؟'
      : 'All other devices linked to this account will be removed. Continue?';
  String get shamellDeviceLoginTitle => isArabic
      ? 'تأكيد تسجيل الدخول على جهاز جديد'
      : 'Confirm login on new device';
  String get shamellDeviceLoginBody => isArabic
      ? 'السماح لهذا الجهاز بتسجيل الدخول إلى شامل باستخدام حسابك؟'
      : 'Allow this device to sign in to Shamell with your account?';
  String get shamellDeviceLoginApprovedSnack => isArabic
      ? 'تمت الموافقة على تسجيل الدخول على الجهاز الجديد.'
      : 'Login approved on the new device.';
  String get shamellDeviceLoginErrorExpired => isArabic
      ? 'رمز تسجيل الدخول غير صالح أو منتهي الصلاحية.'
      : 'Login code is invalid or has expired.';
  String get shamellPinChat => isArabic ? 'تثبيت الدردشة' : 'Pin chat';
  String get shamellUnpinChat =>
      isArabic ? 'إلغاء تثبيت الدردشة' : 'Unpin chat';
  String get shamellMuteChat =>
      isArabic ? 'كتم إشعارات هذه الدردشة' : 'Mute this chat';
  String get shamellUnmuteChat =>
      isArabic ? 'إلغاء كتم هذه الدردشة' : 'Unmute this chat';
  String get shamellMarkUnread =>
      isArabic ? 'وضع علامة كغير مقروءة' : 'Mark as unread';
  String get shamellMarkRead => isArabic ? 'وضع علامة كمقروءة' : 'Mark as read';
  String get shamellSendMoney => isArabic ? 'إرسال أموال' : 'Send money';
  String get shamellClearChatHistory =>
      isArabic ? 'مسح سجل الدردشة' : 'Clear chat history';
  String get shamellDeleteChat => isArabic ? 'حذف الدردشة' : 'Delete chat';
  String get shamellInternetCall => isArabic ? 'مكالمة فيديو' : 'Video call';
  String get shamellPhoneCall => isArabic ? 'مكالمة هاتفية' : 'Phone call';
  String get shamellCallHistory => isArabic ? 'سجل المكالمات' : 'Call history';
  String get shamellNoCallsWithContact => isArabic
      ? 'لا يوجد سجل مكالمات مع هذا الحساب بعد.'
      : 'No call history with this contact yet.';
  String get shamellPinnedMessagesTitle =>
      isArabic ? 'رسائل مثبتة' : 'Pinned messages';
  String get shamellSearchFilterAll => isArabic ? 'الكل' : 'All';
  String get shamellSearchFilterMedia => isArabic ? 'الوسائط' : 'Media';
  String get shamellSearchFilterLinks => isArabic ? 'الروابط' : 'Links';
  String get shamellSearchFilterFiles => isArabic ? 'الملفات' : 'Files';
  String get shamellSearchFilterVoice =>
      isArabic ? 'الرسائل الصوتية' : 'Voice notes';
  String get shamellSearchFilterCalls => isArabic ? 'المكالمات' : 'Calls';
  String get shamellMediaOverviewTitle => isArabic
      ? 'الوسائط والروابط في هذه الدردشة'
      : 'Media and links in this chat';
  String get shamellMediaOverviewEmpty => isArabic
      ? 'لا توجد صور أو روابط في هذه الدردشة بعد.'
      : 'No media or links in this chat yet.';
  String get shamellGlobalMediaTitle => isArabic
      ? 'الوسائط والملفات في كل الدردشات'
      : 'Media & files across chats';
  String get shamellGlobalMediaEmpty => isArabic
      ? 'لن تظهر هنا الوسائط والملفات حتى تستخدم شامل مع أصدقائك.'
      : 'Media and files will appear here once you use Shamell with your friends.';
  String get shamellGlobalMediaSearchHint =>
      isArabic ? 'بحث في الوسائط والملفات' : 'Search in media and files';

  // Shamell reactions
  String get shamellReactionsTitle =>
      isArabic ? 'تفاعل مع الرسالة' : 'React to message';

  // Shamell contact info / favorites
  String get shamellContactInfoTitle =>
      isArabic ? 'معلومات جهة الاتصال' : 'Contact info';
  String get shamellContactRemarkLabel =>
      isArabic ? 'ملاحظة (اسم مخصص)' : 'Remark (alias)';
  String get shamellContactChatIdPrefix =>
      isArabic ? 'معرّف الدردشة:' : 'Chat ID:';
  String get shamellFavoritesTitle => isArabic ? 'المفضلة' : 'Favorites';
  String get shamellFavoritesNewTitle =>
      isArabic ? 'عنصر مفضل جديد' : 'New favorite';
  String get shamellFavoritesHint => isArabic
      ? 'احفظ أي شيء تريد الرجوع إليه لاحقاً'
      : 'Save anything you want to revisit later';
  String get shamellFavoritesAdd => isArabic ? 'إضافة' : 'Add';
  String get shamellFavoritesEmpty =>
      isArabic ? 'لا توجد عناصر مفضلة بعد.' : 'No favorites yet.';
  String get shamellFavoritesTagsPrefix => isArabic ? 'الوسوم:' : 'Tags:';
  String get shamellFavoritesOpenChatTooltip =>
      isArabic ? 'فتح الدردشة' : 'Open chat';
  String get shamellFavoritesRemoveTooltip => isArabic ? 'حذف' : 'Remove';
  String get shamellChatThemeTitle => isArabic ? 'سمة الدردشة' : 'Chat theme';
  String get shamellChatThemeDefault => isArabic ? 'افتراضية' : 'Default';
  String get shamellChatThemeDark => isArabic ? 'داكنة' : 'Dark';
  String get shamellChatThemeGreen => isArabic ? 'أخضر' : 'Green';
  String get shamellFavoritesFilterAll => isArabic ? 'كل العناصر' : 'All items';
  String get shamellFavoritesFilterMessages =>
      isArabic ? 'رسائل الدردشة' : 'Starred messages';

  // Shamell profile
  String get shamellProfileShowQr => isArabic ? 'إظهار رمز QR' : 'Show QR';
  String get shamellProfileShareId =>
      isArabic ? 'مشاركة معرف Shamell' : 'Share Shamell ID';
  String get shamellProfileSafe => isArabic ? 'خزنة Shamell' : 'Shamell safe';
  String get shamellProfileExportId => isArabic ? 'تصدير المعرف' : 'Export ID';
  String get shamellProfileRevocationPass =>
      isArabic ? 'كلمة مرور إلغاء المعرف' : 'ID revocation passphrase';
  String get shamellProfileLinkedPhone =>
      isArabic ? 'رقم هاتف مرتبط' : 'Linked phone number';
  String get shamellProfileLinkedEmail =>
      isArabic ? 'بريد إلكتروني مرتبط' : 'Linked email';
  String get shamellProfilePublicKey =>
      isArabic ? 'المفتاح العام' : 'Public key';
  String get shamellProfileDeleteId =>
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
      ? 'تسجيل الخروج من هذا الجهاز. يمكنك الرجوع بالبصمة، أو ربط حساب آخر عبر رمز QR.'
      : 'Log out from this device. You can come back with biometrics, or link a different account via QR.';
  String get menuLogoutForgetDevice => isArabic
      ? 'تسجيل الخروج ونسيان هذا الجهاز'
      : 'Logout & forget this device';
  String get menuLogoutForgetDeviceSubtitle => isArabic
      ? 'سيتم حذف تسجيل الدخول عبر القياسات الحيوية ومعرف الجهاز وكلمة المرور المحلية.'
      : 'Removes biometric sign-in, device ID, and local password.';
  String get menuLogoutForgetDeviceConfirmTitle =>
      isArabic ? 'تأكيد' : 'Confirm';
  String get menuLogoutForgetDeviceConfirmBody => isArabic
      ? 'سيؤدي ذلك إلى إزالة هذا الجهاز من الحساب ومسح كل بياناته المحلية. ستحتاج إلى ربطه من جديد.'
      : 'This will remove this device from your account and wipe all local data. You will need to re-enroll this device.';
  String get menuLogoutForgetDeviceConfirmAction =>
      isArabic ? 'نسيان الجهاز' : 'Forget device';
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
      ? 'إدارة المحفظة والفواتير'
      : 'Manage wallet and bills';

  // Generic small labels
  String get labelPage => isArabic ? 'صفحة' : 'page';
  String get labelSize => isArabic ? 'الحجم' : 'size';
  String get labelSearch => isArabic ? 'بحث' : 'search';
  String get labelCity => isArabic ? 'المدينة' : 'city';

  String get viewAll => isArabic ? 'عرض الكل' : 'View all';
  String get notSet => isArabic ? 'غير معيّن' : '(not set)';
  String get unknownLabel => isArabic ? 'غير معروف' : 'Unknown';

  // Small stats labels
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

  String get operatorDashboardTitle =>
      isArabic ? 'لوحة المشغل' : 'Operator Dashboard';
  String get adminDashboardTitle =>
      isArabic ? 'لوحة المسؤول' : 'Admin dashboard';
  String get superadminDashboardTitle =>
      isArabic ? 'لوحة السوبر أدمن' : 'Superadmin dashboard';
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
