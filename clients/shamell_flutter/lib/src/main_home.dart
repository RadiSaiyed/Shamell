part of '../main.dart';

const String _shamellAppLinkHost = shamellAppLinkHost;
const String _shamellAppLinkPathPrefix = shamellAppLinkPathPrefix;
const Set<String> _shamellInboundHosts = <String>{
  'device_login',
  'invite',
  'friend',
  'chat',
  'miniapp',
  'mini_program',
  'moduleapp',
  'moduleapps',
  'green_paket',
  'green_packet',
  'redpacket',
  'red_packet',
  'hongbao',
  'ride',
  'taxi',
  'coach',
  'bus',
  'official',
  'moments',
  'shake',
};
const Set<String> _shamellCustomSchemeInboundHosts =
    shamellCustomSchemeInboundHosts;
const int _shamellInboundUriMaxChars = 2048;
const int _shamellScanPayloadMaxChars = 4096;

enum _ShamellInboundUriSource { appLink, scanResult }

bool _shamellIsSupportedInboundHost(String host) =>
    _shamellInboundHosts.contains(host.trim().toLowerCase());

String _canonicalShamellInboundHost(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized == 'miniapp' ||
      normalized == 'moduleapp' ||
      normalized == 'moduleapps') {
    return 'mini_program';
  }
  return normalized;
}

bool _shamellInboundUriExceedsMaxChars(Uri uri) =>
    uri.toString().length > _shamellInboundUriMaxChars;

Map<String, String> _shamellMergedInboundParams(
  Uri uri, {
  bool includeQueryParameters = true,
}) {
  return shamellMergedInboundParams(
    uri,
    includeQueryParameters: includeQueryParameters,
  );
}

@visibleForTesting
Set<String> shamellSupportedInboundHosts() =>
    Set<String>.unmodifiable(_shamellInboundHosts);

@visibleForTesting
Set<String> shamellSupportedCustomSchemeInboundHosts() =>
    Set<String>.unmodifiable(_shamellCustomSchemeInboundHosts);

@visibleForTesting
String shamellInboundAppLinkHost() => _shamellAppLinkHost;

@visibleForTesting
String shamellInboundAppLinkPathPrefix() => _shamellAppLinkPathPrefix;

@visibleForTesting
Uri normalizeInboundShamellUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'shamell') {
    final mergedParams = _shamellMergedInboundParams(uri);
    final normalizedHost = _canonicalShamellInboundHost(uri.host);
    if (uri.hasPort) {
      return Uri(
        scheme: 'shamell',
        userInfo: uri.userInfo,
        host: normalizedHost,
        port: uri.port,
        pathSegments: uri.pathSegments,
        queryParameters: mergedParams.isEmpty ? null : mergedParams,
      );
    }
    return Uri(
      scheme: 'shamell',
      userInfo: uri.userInfo,
      host: normalizedHost,
      pathSegments: uri.pathSegments,
      queryParameters: mergedParams.isEmpty ? null : mergedParams,
    );
  }
  if (scheme != 'https') return uri;
  if (uri.host.toLowerCase() != _shamellAppLinkHost) return uri;
  if (uri.userInfo.isNotEmpty || uri.hasPort) return uri;

  final segs = uri.pathSegments
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  if (segs.isEmpty ||
      '/${segs.first.toLowerCase()}' != _shamellAppLinkPathPrefix) {
    return uri;
  }

  final deepLinkSegs = segs.skip(1).toList(growable: false);
  final host = _canonicalShamellInboundHost(
    deepLinkSegs.isEmpty ? 'app' : deepLinkSegs.first,
  );
  if (!_shamellIsSupportedInboundHost(host)) return uri;
  final mergedParams = _shamellMergedInboundParams(
    uri,
    includeQueryParameters: !shamellHostedAppLinkRequiresFragment(host),
  );
  if (shamellHostedAppLinkRequiresFragment(host) && mergedParams.isEmpty) {
    // Hosted bearer-style app links must keep capabilities in the fragment so
    // browsers and edge logs do not observe query token material.
    return uri;
  }
  final pathSegs =
      deepLinkSegs.length > 1 ? deepLinkSegs.sublist(1) : const <String>[];
  return Uri(
    scheme: 'shamell',
    host: host,
    pathSegments: pathSegs,
    queryParameters: mergedParams.isEmpty ? null : mergedParams,
  );
}

@visibleForTesting
bool shamellIsSafeCustomSchemeInboundUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'shamell') return false;
  if (uri.host.trim().isEmpty) return false;
  if (uri.userInfo.isNotEmpty || uri.hasPort) return false;
  return true;
}

@visibleForTesting
bool shamellShouldHandleInboundUri(Uri uri) {
  if (_shamellInboundUriExceedsMaxChars(uri)) {
    return false;
  }
  final normalized = normalizeInboundShamellUri(uri);
  if (!shamellIsSafeCustomSchemeInboundUri(normalized)) {
    return false;
  }
  return _shamellIsSupportedInboundHost(normalized.host);
}

@visibleForTesting
bool shamellAllowsCustomSchemeInboundHost(
  String host, {
  bool isReleaseMode = kReleaseMode,
}) {
  final normalizedHost = host.trim().toLowerCase();
  if (!_shamellIsSupportedInboundHost(normalizedHost)) {
    return false;
  }
  if (!isReleaseMode) {
    return true;
  }
  return _shamellCustomSchemeInboundHosts.contains(normalizedHost);
}

OfficialNotificationMode _officialNotificationModeFromRaw(String? raw) {
  switch (raw?.trim().toLowerCase()) {
    case 'summary':
      return OfficialNotificationMode.summary;
    case 'muted':
      return OfficialNotificationMode.muted;
    default:
      return OfficialNotificationMode.full;
  }
}

bool _officialAccountMatchesNotificationGroup(
  Map<String, dynamic> account,
  AnalyticsOfficialGroup group,
) {
  final kindStr = (account['kind'] ?? 'service').toString().toLowerCase();
  final isService = kindStr == 'service';
  if (group == AnalyticsOfficialGroup.service) {
    return isService;
  }
  return !isService;
}

class _FriendsServerRosterResponse {
  const _FriendsServerRosterResponse({
    required this.friends,
    required this.statusCode,
    required this.rawBody,
  });

  final List<Map<String, dynamic>> friends;
  final int statusCode;
  final String rawBody;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

@visibleForTesting
OfficialNotificationMode officialNotificationGroupModeForAccounts({
  required List<Map<String, dynamic>> accounts,
  required Map<String, String> serverModes,
  required AnalyticsOfficialGroup group,
}) {
  OfficialNotificationMode? resolved;
  for (final account in accounts) {
    if (account['followed'] != true) continue;
    if (!_officialAccountMatchesNotificationGroup(account, group)) continue;
    final accountId = (account['id'] ?? '').toString().trim();
    if (accountId.isEmpty) continue;
    final mode = _officialNotificationModeFromRaw(serverModes[accountId]);
    if (resolved == null) {
      resolved = mode;
      continue;
    }
    if (resolved != mode) {
      // The sheet has a single selection per group, so mixed server state falls
      // back to the conservative default instead of presenting a fake value.
      return OfficialNotificationMode.full;
    }
  }
  return resolved ?? OfficialNotificationMode.full;
}

String _newOfficialMutationIdempotencyKey(String prefix) {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rnd = Random.secure();
  final nonceA = rnd.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
  final nonceB = rnd.nextInt(0x7fffffff).toRadixString(16).padLeft(8, '0');
  return '$prefix-$ts-$nonceA$nonceB';
}

class _OfficialNotificationSheetState {
  final List<Map<String, dynamic>> accounts;
  final OfficialNotificationMode serviceMode;
  final OfficialNotificationMode nonServiceMode;

  const _OfficialNotificationSheetState({
    required this.accounts,
    required this.serviceMode,
    required this.nonServiceMode,
  });
}

class HomePage extends StatefulWidget {
  final AppMode lockedMode;
  final int initialTabIndex;
  final bool runStartupTasks;
  final ShamellCapabilities? initialCapabilities;
  final String? baseUrlOverride;
  final String? initialChatPeerId;
  final String? initialChatAutoSendText;
  final http.Client? client;
  final Future<bool> Function()? deviceLoginApprovalAuthPrompt;
  final VoidCallback? onCriticalDeviceLoginSessionFailure;

  const HomePage({
    super.key,
    this.lockedMode = AppMode.auto,
    this.initialTabIndex = 0,
    this.runStartupTasks = true,
    this.initialCapabilities,
    this.baseUrlOverride,
    this.initialChatPeerId,
    this.initialChatAutoSendText,
    this.client,
    this.deviceLoginApprovalAuthPrompt,
    this.onCriticalDeviceLoginSessionFailure,
  }) : assert(initialTabIndex >= 0 && initialTabIndex <= 4);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _CurrencyWalletState {
  final String currency;
  final String walletId;
  final int? balanceCents;

  const _CurrencyWalletState({
    required this.currency,
    required this.walletId,
    this.balanceCents,
  });
}

class _MiniProgramShelfPrefs {
  final List<String> pinnedIds;
  final List<String> recentIds;

  const _MiniProgramShelfPrefs({
    required this.pinnedIds,
    required this.recentIds,
  });

  bool get isEmpty => pinnedIds.isEmpty && recentIds.isEmpty;
}

class _HomePageState extends State<HomePage> with SafeSetStateMixin<HomePage> {
  static const Duration _startupDataRequestTimeout = Duration(seconds: 10);
  static const Duration _sessionMgmtRequestTimeout = Duration(seconds: 10);
  static const int _officialAccountsPageSize = 200;

  String _baseUrl = const String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://api.shamell.online',
  );
  // SyrChat-like bottom navigation tabs:
  // 0 = Chats, 1 = Contacts, 2 = Wallet/Payments, 3 = Discover/Services, 4 = Me.
  int _tabIndex = 0;
  bool _hasInvalidExplicitBaseOverride = false;
  bool _shamellStrictUi = true;
  bool _pluginShowScan = true;
  ShamellCapabilities _caps = ShamellCapabilities.conservativeDefaults;
  String _walletId = '';
  int? _walletBalanceCents;
  String _walletCurrency = 'SYP';
  bool _walletHidden = false;
  bool _walletLoading = false;
  bool _walletSummaryLoaded = false;
  bool _walletProvisionInFlight = false;
  final Map<String, _CurrencyWalletState> _currencyWallets =
      <String, _CurrencyWalletState>{};
  final PageController _currencyWalletsPageController = PageController(
    viewportFraction: .88,
  );
  int _currencyWalletsPageIndex = 0;
  final deviceId = _randId();
  Timer? _flushTimer;
  bool _showOps = false;
  bool _showSuperadmin = false;
  List<String> _roles = const [];
  AccountPrivilegeSnapshot _privilegeSnapshot = AccountPrivilegeSnapshot.empty;
  AppMode _appMode = currentAppMode;
  final ChatLocalStore _chatStore = ChatLocalStore();
  int _totalUnreadChats = 0;
  CallSignalingClient? _callClient;
  StreamSubscription<Map<String, dynamic>>? _callSub;
  bool _callSignalingInitInFlight = false;
  String? _callSignalingBaseUrl;
  String? _callSignalingDeviceId;
  Timer? _callSignalingReconnectTimer;
  int _callSignalingReconnectAttempt = 0;
  int _callSignalingInitRequestCount = 0;
  bool _suppressCallSignalingInitForTesting = false;
  bool _hasDefaultOfficialAccount = false;
  bool _hasUnreadServiceNotifications = false;
  int _friendsCount = 0;
  int _closeFriendsCount = 0;
  int _friendRequestsPending = 0;
  bool _contactsRosterLoading = false;
  String? _contactsRosterError;
  List<Map<String, dynamic>> _contactsRoster = const <Map<String, dynamic>>[];
  final Map<String, String> _pendingOfficialFollowIdempotencyKeys =
      <String, String>{};
  final Map<String, String> _pendingOfficialNotificationModeIdempotencyKeys =
      <String, String>{};
  Future<_FriendsServerRosterResponse>? _friendsServerRosterInFlight;
  Map<String, String> _contactsAliases = const <String, String>{};
  Map<String, String> _contactsTags = const <String, String>{};
  final ScrollController _contactsScrollCtrl = ScrollController();
  final GlobalKey _contactsViewportKey = GlobalKey();
  final Map<String, GlobalKey> _contactsLetterKeys = <String, GlobalKey>{};
  Timer? _contactsIndexHintTimer;
  String? _contactsIndexHint;
  bool _contactsIndexDragging = false;
  String? _contactsStickyHeader;
  double _contactsStickyHeaderOffset = 0.0;
  String _profileName = '';
  String _profilePhone = '';
  String _profileShamellId = '';
  List<String> _miniProgramShelfPinnedIds = const <String>[];
  List<String> _miniProgramShelfRecentIds = const <String>[];
  bool _sessionBootstrapInFlight = false;
  DateTime? _sessionBootstrapLastAttemptAt;
  DateTime? _sessionBootstrapLastSuccessAt;
  bool _deviceBindingReauthTriggered = false;
  bool _deviceLoginApprovalInFlight = false;
  bool _inviteRedeemInFlight = false;
  bool _resolveByShamellIdInFlight = false;
  bool _initialChatPeerNavigationTriggered = false;
  String? _seededInitialChatPeerId;
  String? _seededInitialChatAutoSendText;
  int _seededInitialChatLaunchNonce = 0;

  bool _beginDeviceLoginApproval() {
    if (_deviceLoginApprovalInFlight) {
      return false;
    }
    _deviceLoginApprovalInFlight = true;
    return true;
  }

  void _endDeviceLoginApproval() {
    _deviceLoginApprovalInFlight = false;
  }

  bool _beginInviteRedeem() {
    if (_inviteRedeemInFlight) {
      return false;
    }
    _inviteRedeemInFlight = true;
    return true;
  }

  void _endInviteRedeem() {
    _inviteRedeemInFlight = false;
  }

  void _applyCapabilityDisabledHomeState(ShamellCapabilities caps) {
    if (!caps.officialAccounts) {
      _hasDefaultOfficialAccount = false;
    }
    if (!caps.serviceNotifications) {
      _hasUnreadServiceNotifications = false;
    }
    if (!caps.friends) {
      _friendsCount = 0;
      _closeFriendsCount = 0;
      _friendRequestsPending = 0;
      _contactsRosterLoading = false;
      _contactsRosterError = null;
      _contactsRoster = const <Map<String, dynamic>>[];
      _contactsAliases = const <String, String>{};
      _contactsTags = const <String, String>{};
      _contactsIndexHint = null;
      _contactsIndexDragging = false;
      _contactsStickyHeader = null;
      _contactsStickyHeaderOffset = 0.0;
    }
  }

  bool _computeHomeShowOps(AccountPrivilegeSnapshot snapshot, AppMode appMode) {
    switch (appMode) {
      case AppMode.user:
        return false;
      case AppMode.auto:
      case AppMode.operator:
      case AppMode.admin:
        return shamellAllowsOpsConsoleSnapshot(snapshot);
    }
  }

  bool get _allowsOpsWorkbench =>
      shamellAllowsOpsConsoleSnapshot(_privilegeSnapshot);

  bool get _allowsAdminWorkbench =>
      shamellAllowsAdminConsoleSnapshot(_privilegeSnapshot);

  void _applyPrivilegeSnapshotHomeState(
    AccountPrivilegeSnapshot snapshot,
    AppMode appMode, {
    bool hideWorkbench = false,
  }) {
    final effectiveHideWorkbench = hideWorkbench || kEnduserOnly;
    final baseShowOps = _computeHomeShowOps(snapshot, appMode);
    final showSuper = effectiveHideWorkbench ? false : snapshot.isSuperadmin;
    final showOps = effectiveHideWorkbench ? false : (baseShowOps || showSuper);
    _privilegeSnapshot = snapshot;
    _roles = snapshot.roles;
    _showOps = showOps;
    _showSuperadmin = showSuper;
  }

  void _clearWalletSummaryHomeState() {
    _walletBalanceCents = null;
    _walletCurrency = 'SYP';
    _walletLoading = false;
    _walletSummaryLoaded = false;
  }

  void _clearWalletSnapshotHomeState() {
    _walletId = '';
    _currencyWallets.clear();
    _clearWalletSummaryHomeState();
  }

  bool _applyWalletSummaryHomeState(dynamic rawWallet) {
    if (rawWallet is! Map) return false;
    if (!rawWallet.containsKey('balance_cents')) return false;
    final rawBalance = rawWallet['balance_cents'];
    final cents = switch (rawBalance) {
      int value => value,
      num value => value.toInt(),
      _ => int.tryParse((rawBalance ?? '').toString()),
    };
    if (cents == null) return false;
    final currency = (rawWallet['currency'] ?? 'SYP').toString().trim();
    final normalizedCurrency = shamellNormalizeWalletCurrency(currency);
    _walletBalanceCents = cents;
    _walletCurrency = normalizedCurrency;
    _walletLoading = false;
    _walletSummaryLoaded = true;
    final walletId = (rawWallet['wallet_id'] ?? rawWallet['id'] ?? _walletId)
        .toString()
        .trim();
    if (walletId.isNotEmpty) {
      _currencyWallets[normalizedCurrency] = _CurrencyWalletState(
        currency: normalizedCurrency,
        walletId: walletId,
        balanceCents: cents,
      );
    }
    return true;
  }

  void _applyCurrencyWalletsHomeState(dynamic rawWallets) {
    if (rawWallets is! List) return;
    for (final rawWallet in rawWallets) {
      if (rawWallet is! Map) continue;
      final walletId =
          (rawWallet['wallet_id'] ?? rawWallet['id'] ?? '').toString().trim();
      if (walletId.isEmpty) continue;
      final currency = shamellNormalizeWalletCurrency(
        (rawWallet['currency'] ?? '').toString(),
      );
      final rawBalance = rawWallet['balance_cents'];
      final balanceCents = switch (rawBalance) {
        int value => value,
        num value => value.toInt(),
        _ => int.tryParse((rawBalance ?? '').toString()),
      };
      _currencyWallets[currency] = _CurrencyWalletState(
        currency: currency,
        walletId: walletId,
        balanceCents: balanceCents,
      );
    }
  }

  List<_CurrencyWalletState> _orderedCurrencyWalletsHomeState() {
    final byCurrency = <String, _CurrencyWalletState>{..._currencyWallets};
    if (_walletId.trim().isNotEmpty) {
      byCurrency[_walletCurrency] = _CurrencyWalletState(
        currency: _walletCurrency,
        walletId: _walletId,
        balanceCents: _walletBalanceCents,
      );
    }
    final supportedOrder = shamellSupportedWalletCurrencies
        .map((currency) => currency.code)
        .toList(growable: false);
    return <_CurrencyWalletState>[
      for (final currency in supportedOrder)
        if (byCurrency[currency] != null) byCurrency[currency]!,
      for (final entry in byCurrency.entries)
        if (!supportedOrder.contains(entry.key)) entry.value,
    ];
  }

  bool _isPrimaryCurrencyWalletHomeState(_CurrencyWalletState wallet) {
    final walletId = wallet.walletId.trim();
    return walletId.isNotEmpty && walletId == _walletId.trim();
  }

  Color _currencyWalletAccent(String currency) {
    switch (currency.trim().toUpperCase()) {
      case 'USD':
        return const Color(0xFF10B981);
      case 'EUR':
        return const Color(0xFF2563EB);
      case 'SAR':
        return const Color(0xFF059669);
      case 'AED':
        return const Color(0xFF0EA5E9);
      case 'QAR':
        return const Color(0xFFBE123C);
      case 'KWD':
        return const Color(0xFF7C3AED);
      case 'SYP':
      default:
        return Tokens.colorPayments;
    }
  }

  String _currencyWalletBalanceLabel(
    _CurrencyWalletState wallet, {
    required L10n l,
  }) {
    if (_walletHidden) return '••••••';
    final balance = wallet.balanceCents;
    if (balance == null) {
      return l.isArabic ? 'الرصيد غير متاح' : 'Balance unavailable';
    }
    return '${fmtCents(balance)} ${wallet.currency}';
  }

  void _openCurrencyWallet(_CurrencyWalletState wallet) {
    final walletId = wallet.walletId.trim();
    if (walletId.isEmpty) return;
    unawaited(_recordModuleUse('payments'));
    unawaited(
      _ensureServiceOfficialFollow(
        officialId: 'shamell_pay',
        chatPeerId: 'shamell_pay',
      ),
    );
    _navPush(
      PaymentsPage(
        _baseUrl,
        walletId,
        deviceId,
        initialCurrency: wallet.currency,
        client: widget.client,
      ),
    );
  }

  Widget _buildCurrencyWalletsSection({
    required L10n l,
    required ThemeData theme,
    required bool compact,
  }) {
    final wallets = _orderedCurrencyWalletsHomeState();
    if (wallets.length <= 1) return const SizedBox.shrink();
    final isDark = theme.brightness == Brightness.dark;
    final effectivePageIndex = _currencyWalletsPageIndex.clamp(
      0,
      wallets.length - 1,
    );

    Widget walletCard(_CurrencyWalletState wallet) {
      final accent = _currencyWalletAccent(wallet.currency);
      final primary = _isPrimaryCurrencyWalletHomeState(wallet);
      final title = shamellWalletCurrencyLabel(
        wallet.currency,
        isArabic: l.isArabic,
      );
      final textColor = theme.colorScheme.onSurface;
      final mutedColor = textColor.withValues(alpha: .62);
      final cardBg = isDark
          ? theme.colorScheme.surface.withValues(alpha: .88)
          : theme.colorScheme.surface;
      final borderColor =
          theme.dividerColor.withValues(alpha: isDark ? .42 : .72);

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openCurrencyWallet(wallet),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: EdgeInsetsDirectional.only(
              end: compact ? 10 : 12,
            ),
            padding: EdgeInsets.fromLTRB(14, compact ? 12 : 14, 14, 12),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: .7),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: compact ? 38 : 40,
                      height: compact ? 38 : 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        color: accent.withValues(alpha: isDark ? .18 : .10),
                        border: Border.all(
                          color: accent.withValues(alpha: isDark ? .30 : .20),
                          width: .7,
                        ),
                      ),
                      child: Text(
                        wallet.currency,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              if (primary) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: Tokens.colorPayments.withValues(
                                      alpha: isDark ? .18 : .12,
                                    ),
                                  ),
                                  child: Text(
                                    l.isArabic ? 'أساسية' : 'Primary',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Tokens.colorPayments,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            wallet.walletId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: mutedColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      l.isArabic ? Icons.chevron_left : Icons.chevron_right,
                      size: 20,
                      color: textColor.withValues(alpha: .42),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  _currencyWalletBalanceLabel(wallet, l: l),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontSize: compact ? 21 : 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 3,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.isArabic ? 'SyrChat Pay' : 'SyrChat Pay',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: mutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 16,
                      color: mutedColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
          child: Row(
            children: [
              Text(
                l.isArabic ? 'محافظ العملات' : 'Currency wallets',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .68),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${wallets.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .45),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: compact ? 136 : 148,
          child: PageView.builder(
            controller: _currencyWalletsPageController,
            itemCount: wallets.length,
            padEnds: false,
            allowImplicitScrolling: true,
            onPageChanged: (index) {
              setState(() => _currencyWalletsPageIndex = index);
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsetsDirectional.only(
                  start: index == 0 ? 16 : 0,
                  end: index == wallets.length - 1 ? 16 : 0,
                ),
                child: walletCard(wallets[index]),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < wallets.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == effectivePageIndex ? 16 : 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: i == effectivePageIndex
                        ? Tokens.colorPayments
                        : theme.colorScheme.onSurface.withValues(
                            alpha: isDark ? .22 : .18,
                          ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _walletNotReadyUiMessage() {
    final l = L10n.of(context);
    return l.isArabic
        ? 'المحفظة غير جاهزة بعد. حاول مجددًا بعد قليل.'
        : 'Wallet is not ready yet. Please try again shortly.';
  }

  String _chatOperationErrorForUi(Object error, {required bool isArabic}) {
    if (error is ChatHttpException) {
      return sanitizeHttpError(
        statusCode: error.statusCode,
        rawBody: error.body,
        isArabic: isArabic,
      );
    }
    return sanitizeExceptionForUi(error: error, isArabic: isArabic);
  }

  Future<bool> _ensureWalletReady({bool interactive = false}) async {
    if (!_caps.payments) return false;
    if (_walletId.trim().isNotEmpty) return true;
    if (_walletProvisionInFlight) return false;
    _walletProvisionInFlight = true;
    final l = L10n.of(context);
    try {
      await _ensureSessionForOnlineOps(baseUrl: _baseUrl, force: true);
      if (_deviceBindingReauthTriggered) return false;
      final sp = await SharedPreferences.getInstance();
      await _refreshHomeSnapshotFromServer(sp, _appMode);
      if (_walletId.trim().isNotEmpty) {
        await _loadWalletSummary();
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _refreshHomeSnapshotFromServer(sp, _appMode);
      if (_walletId.trim().isNotEmpty) {
        await _loadWalletSummary();
        return true;
      }
      if (interactive && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_walletNotReadyUiMessage())));
      }
      return false;
    } catch (e) {
      final forcedReauth = await _handleCriticalAccountSessionError(e);
      if (forcedReauth || _deviceBindingReauthTriggered || !interactive) {
        return false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_chatOperationErrorForUi(e, isArabic: l.isArabic)),
          ),
        );
      }
      return false;
    } finally {
      _walletProvisionInFlight = false;
    }
  }

  Future<String?> _requireWalletIdForPaymentsAction({
    bool interactive = true,
  }) async {
    var walletId = _walletId.trim();
    if (walletId.isEmpty) {
      try {
        walletId =
            (await loadStoredWalletId(baseUrlOverride: _baseUrl) ?? '').trim();
      } catch (_) {}
      if (walletId.isNotEmpty && mounted) {
        setState(() {
          _walletId = walletId;
        });
      }
    }
    if (walletId.isNotEmpty) {
      return walletId;
    }
    final ready = await _ensureWalletReady(interactive: interactive);
    if (!ready) return null;
    walletId = _walletId.trim();
    if (walletId.isNotEmpty) {
      return walletId;
    }
    if (interactive && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_walletNotReadyUiMessage())));
    }
    return null;
  }

  Future<void> _applyFailClosedHomeSnapshotState(
    SharedPreferences sp,
    AppMode appMode,
  ) async {
    await saveAccountPrivilegeSnapshot(
      roles: const <String>[],
      isSuperadmin: false,
      sp: sp,
      baseUrlOverride: _baseUrl,
    );
    await saveStoredWalletId('', sp: sp, baseUrlOverride: _baseUrl);
    await saveStoredShamellUserId('', sp: sp, baseUrlOverride: _baseUrl);
    if (!mounted) return;
    setState(() {
      _caps = ShamellCapabilities.conservativeDefaults;
      _applyCapabilityDisabledHomeState(_caps);
      _applyPrivilegeSnapshotHomeState(AccountPrivilegeSnapshot.empty, appMode);
      _clearWalletSnapshotHomeState();
      _profileShamellId = '';
    });
  }

  static String _randId() {
    const chars = 'abcdef0123456789';
    final r = Random();
    return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
  }

  void _requestCallSignalingInit() {
    _callSignalingInitRequestCount += 1;
    if (_suppressCallSignalingInitForTesting) return;
    unawaited(_initCallSignaling());
  }

  Future<void> _forceReauthDueToDeviceBindingDrift() async {
    if (_deviceBindingReauthTriggered) return;
    _deviceBindingReauthTriggered = true;
    // Soft logout: keep the user's chat identity, contacts, message
    // history, friend annotations, and per-thread notify prefs so the
    // next login resumes the same account state. "Forget Device" still
    // wipes everything; that path lives in `_logoutForgetDevice`.
    unawaited(
      wipeLocalAccountData(
        preserveDevicePrefs: true,
        preserveContactsAndChats: true,
      ).catchError((_) {}),
    );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        ),
      );
    });
  }

  Future<bool> _handleCriticalAccountSessionError(Object error) async {
    if (shamellIsCriticalAccountSessionError(error)) {
      await _forceReauthDueToDeviceBindingDrift();
      return true;
    }
    return false;
  }

  Uri? _homeApiUri({
    required List<String> pathSegments,
    Map<String, String>? queryParameters,
  }) {
    if (_hasInvalidExplicitBaseOverride) {
      return null;
    }
    return secureApiChildUri(
      baseUrl: _baseUrl,
      pathSegments: pathSegments,
      queryParameters: queryParameters,
    );
  }

  String _invalidServerUrlMessage() {
    final isArabic = L10n.of(context).isArabic;
    return isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
  }

  String _localStateBaseUrlOverride() {
    if (_hasInvalidExplicitBaseOverride) {
      return (widget.baseUrlOverride ?? '').trim();
    }
    return _baseUrl;
  }

  Future<void> _registerDeviceBestEffort() async {
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final uri = _homeApiUri(
        pathSegments: const <String>['auth', 'devices', 'register'],
      );
      if (uri == null) return;
      final headers = await _hdr(json: true);
      // Stable per-install device id: supports server-side session revocation
      // and keeps device lists consistent across restarts/logouts.
      final did = await getOrCreateStableDeviceId(baseUrlOverride: _baseUrl);
      final body = jsonEncode(<String, dynamic>{
        'device_id': did,
        'device_type': kIsWeb ? 'web' : 'mobile',
        'platform': Theme.of(context).platform.name,
      });
      final resp = await httpClient
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      if (shamellIsCriticalAccountSessionHttpFailure(
        statusCode: resp.statusCode,
        rawBody: resp.body,
      )) {
        await _forceReauthDueToDeviceBindingDrift();
        return;
      }
    } catch (_) {
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _ensureChatAccountReadyBestEffort() async {
    try {
      await ChatService(_baseUrl).ensureAccountChatReady();
    } catch (_) {
      // Bootstrap is best-effort: a per-call `_ensureChatIdentityAndRegistration`
      // retries later for the user-driven flow that actually needs it.
    }
  }

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex;
    final rawExplicitBaseOverride = (widget.baseUrlOverride ?? '').trim();
    final overriddenBase = normalizeSecureApiBaseUrl(rawExplicitBaseOverride);
    _hasInvalidExplicitBaseOverride = rawExplicitBaseOverride.isNotEmpty &&
        (overriddenBase == null || overriddenBase.isEmpty);
    if (overriddenBase != null && overriddenBase.isNotEmpty) {
      _baseUrl = overriddenBase;
    }
    shamellSetActiveBootstrapBaseUrl(_baseUrl);
    if (widget.initialCapabilities != null) {
      _caps = widget.initialCapabilities!;
    }
    final explicitInitialChatPeerId = (widget.initialChatPeerId ?? '').trim();
    final explicitInitialChatAutoSendText =
        (widget.initialChatAutoSendText ?? '').trim();
    if (explicitInitialChatPeerId.isNotEmpty) {
      _initialChatPeerNavigationTriggered = true;
      _seededInitialChatPeerId = explicitInitialChatPeerId;
      _seededInitialChatAutoSendText = explicitInitialChatAutoSendText.isEmpty
          ? null
          : explicitInitialChatAutoSendText;
      _seededInitialChatLaunchNonce = 1;
      _tabIndex = 0;
    }
    if (widget.runStartupTasks && !_hasInvalidExplicitBaseOverride) {
      _loadPrefs();
      // offline sync timer disabled
      _setupLinks();
      unawaited(_consumePendingNotificationPayload());
      _flushTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
        await OfflineQueue.flush(baseUrlOverride: _baseUrl);
      });
      _registerDeviceBestEffort();
      unawaited(_ensureChatAccountReadyBestEffort());
      _loadUnreadBadge();
      _requestCallSignalingInit();
      _loadDefaultOfficialAccountFlag();
      unawaited(_refreshFriendsSurface());
      _loadServiceNotificationsBadge();
    }
    if (!_initialChatPeerNavigationTriggered) {
      unawaited(_maybeOpenInitialChatPeer());
    }
    _contactsScrollCtrl.addListener(_updateContactsStickyHeader);
  }

  Future<void> _maybeOpenInitialChatPeer() async {
    if (_initialChatPeerNavigationTriggered) {
      return;
    }
    var peerId = (widget.initialChatPeerId ?? '').trim();
    var autoSendText = (widget.initialChatAutoSendText ?? '').trim();
    if (peerId.isEmpty) {
      final seed = await shamellConsumeDebugChatSeed();
      peerId = (seed?['peer_id'] ?? '').trim();
      autoSendText = (seed?['autosend_text'] ?? '').trim();
    }
    if (peerId.isEmpty || !mounted) {
      return;
    }
    _initialChatPeerNavigationTriggered = true;
    setState(() {
      _tabIndex = 0;
      _seededInitialChatPeerId = peerId;
      _seededInitialChatAutoSendText =
          autoSendText.isEmpty ? null : autoSendText;
      _seededInitialChatLaunchNonce += 1;
    });
  }

  Future<void> _consumePendingNotificationPayload() async {
    try {
      var tapTarget = await takePendingNotificationTapTarget(
        baseUrlOverride: _baseUrl,
      );
      if (tapTarget == null) {
        final storedBaseUrl = await _loadStoredBaseUrl();
        if (storedBaseUrl != _baseUrl) {
          tapTarget = await takePendingNotificationTapTarget(
            baseUrlOverride: storedBaseUrl,
          );
        }
      }
      if (tapTarget == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_handleNotificationTapTarget(tapTarget!));
      });
    } catch (_) {}
  }

  Future<void> _loadFriendsSummary() async {
    if (!_caps.friends) return;
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      int friends = 0;
      int closeFriends = 0;
      int pendingRequests = 0;
      // Friends
      try {
        final uri = _homeApiUri(pathSegments: const <String>['me', 'friends']);
        if (uri == null) {
          if (!mounted) return;
          setState(() {
            _friendsCount = 0;
            _closeFriendsCount = 0;
            _friendRequestsPending = 0;
          });
          return;
        }
        final response = await _fetchFriendsServerRoster(
          uri: uri,
          httpClient: httpClient,
        );
        if (response.isSuccess) {
          friends = response.friends.length;
        } else if (shamellIsCriticalAccountSessionHttpFailure(
          statusCode: response.statusCode,
          rawBody: response.rawBody,
        )) {
          await _forceReauthDueToDeviceBindingDrift();
          return;
        }
      } catch (e) {
        if (await _handleCriticalAccountSessionError(e)) return;
      }
      // Close friends
      try {
        closeFriends = (await loadCloseFriendIds(
          baseUrlOverride: _baseUrl,
        ))
            .length;
      } catch (_) {}
      // Pending friend requests (incoming only)
      try {
        final uri = _homeApiUri(
          pathSegments: const <String>['me', 'friend_requests'],
        );
        if (uri == null) {
          if (!mounted) return;
          setState(() {
            _friendsCount = 0;
            _closeFriendsCount = 0;
            _friendRequestsPending = 0;
          });
          return;
        }
        final r = await httpClient
            .get(uri, headers: await _hdr())
            .timeout(_startupDataRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          List<dynamic>? arr;
          if (decoded is Map && decoded['incoming'] is List) {
            arr = decoded['incoming'] as List;
          } else if (decoded is List) {
            arr = decoded;
          }
          if (arr != null) {
            pendingRequests = arr.length;
          }
        } else if (shamellIsCriticalAccountSessionHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          await _forceReauthDueToDeviceBindingDrift();
          return;
        }
      } catch (e) {
        if (await _handleCriticalAccountSessionError(e)) return;
      }
      if (!mounted) return;
      setState(() {
        _friendsCount = friends;
        _closeFriendsCount = closeFriends;
        _friendRequestsPending = pendingRequests;
      });
    } catch (_) {
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _loadContactsRosterMeta() async {
    if (!_caps.friends) return;
    try {
      final annotations = await loadFriendAnnotations(
        baseUrlOverride: _baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _contactsAliases = annotations.aliases;
        _contactsTags = annotations.tags;
      });
    } catch (_) {}
  }

  Future<_FriendsServerRosterResponse> _fetchFriendsServerRoster({
    required Uri uri,
    required http.Client httpClient,
  }) async {
    final inFlight = _friendsServerRosterInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _fetchFriendsServerRosterImpl(
      uri: uri,
      httpClient: httpClient,
    );
    _friendsServerRosterInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_friendsServerRosterInFlight, future)) {
        _friendsServerRosterInFlight = null;
      }
    }
  }

  Future<_FriendsServerRosterResponse> _fetchFriendsServerRosterImpl({
    required Uri uri,
    required http.Client httpClient,
  }) async {
    final response = await httpClient
        .get(uri, headers: await _hdr())
        .timeout(_startupDataRequestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _FriendsServerRosterResponse(
        friends: const <Map<String, dynamic>>[],
        statusCode: response.statusCode,
        rawBody: response.body,
      );
    }
    final decoded = jsonDecode(response.body);
    List<dynamic>? arr;
    if (decoded is Map && decoded['friends'] is List) {
      arr = decoded['friends'] as List;
    } else if (decoded is List) {
      arr = decoded;
    }
    final friends = (arr ?? const <dynamic>[])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
    return _FriendsServerRosterResponse(
      friends: friends,
      statusCode: response.statusCode,
      rawBody: response.body,
    );
  }

  Future<void> _refreshFriendsSurface({bool forceRoster = false}) async {
    if (!_caps.friends) return;
    final shouldRefreshRoster = forceRoster || _contactsRoster.isEmpty;
    if (shouldRefreshRoster && mounted) {
      setState(() {
        _contactsRosterLoading = true;
        _contactsRosterError = null;
      });
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      await _loadContactsRosterMeta();

      int friends = 0;
      int closeFriends = 0;
      int pendingRequests = 0;
      var nextRoster = _contactsRoster;
      String? nextRosterError = _contactsRosterError;

      final friendsUri = _homeApiUri(
        pathSegments: const <String>['me', 'friends'],
      );
      if (friendsUri == null) {
        if (!mounted) return;
        setState(() {
          _friendsCount = 0;
          _closeFriendsCount = 0;
          _friendRequestsPending = 0;
          if (shouldRefreshRoster) {
            _contactsRoster = const <Map<String, dynamic>>[];
            _contactsRosterError = _invalidServerUrlMessage();
          }
        });
        return;
      }

      final friendsResponse = await _fetchFriendsServerRoster(
        uri: friendsUri,
        httpClient: httpClient,
      );
      if (friendsResponse.isSuccess) {
        friends = friendsResponse.friends.length;
        if (shouldRefreshRoster) {
          nextRoster = await _mergeContactsRosterWithLocal(
            friendsResponse.friends,
          );
          nextRosterError = null;
        }
      } else if (shamellIsCriticalAccountSessionHttpFailure(
        statusCode: friendsResponse.statusCode,
        rawBody: friendsResponse.rawBody,
      )) {
        await _forceReauthDueToDeviceBindingDrift();
        return;
      } else if (shouldRefreshRoster) {
        final localOnly = await _localContactsRoster();
        nextRoster = localOnly;
        nextRosterError =
            localOnly.isEmpty ? 'HTTP ${friendsResponse.statusCode}' : null;
      }

      try {
        closeFriends = (await loadCloseFriendIds(
          baseUrlOverride: _baseUrl,
        ))
            .length;
      } catch (_) {}

      try {
        final requestsUri = _homeApiUri(
          pathSegments: const <String>['me', 'friend_requests'],
        );
        if (requestsUri == null) {
          if (!mounted) return;
          setState(() {
            _friendsCount = 0;
            _closeFriendsCount = 0;
            _friendRequestsPending = 0;
          });
          return;
        }
        final response = await httpClient
            .get(requestsUri, headers: await _hdr())
            .timeout(_startupDataRequestTimeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          List<dynamic>? arr;
          if (decoded is Map && decoded['incoming'] is List) {
            arr = decoded['incoming'] as List;
          } else if (decoded is List) {
            arr = decoded;
          }
          if (arr != null) {
            pendingRequests = arr.length;
          }
        } else if (shamellIsCriticalAccountSessionHttpFailure(
          statusCode: response.statusCode,
          rawBody: response.body,
        )) {
          await _forceReauthDueToDeviceBindingDrift();
          return;
        }
      } catch (e) {
        if (await _handleCriticalAccountSessionError(e)) return;
      }

      if (!mounted) return;
      setState(() {
        _friendsCount = friends;
        _closeFriendsCount = closeFriends;
        _friendRequestsPending = pendingRequests;
        if (shouldRefreshRoster) {
          _contactsRoster = nextRoster;
          _contactsRosterError = nextRosterError;
        }
      });
    } catch (_) {
    } finally {
      if (closeClient) {
        httpClient.close();
      }
      if (shouldRefreshRoster && mounted) {
        setState(() {
          _contactsRosterLoading = false;
        });
      }
    }
  }

  Future<void> _loadContactsRoster({bool force = false}) async {
    if (!_caps.friends) return;
    if (_contactsRosterLoading) return;
    if (!force && _contactsRoster.isNotEmpty) return;
    setState(() {
      _contactsRosterLoading = true;
      _contactsRosterError = null;
    });
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final uri = _homeApiUri(pathSegments: const <String>['me', 'friends']);
      if (uri == null) {
        if (!mounted) return;
        setState(() {
          _contactsRoster = const <Map<String, dynamic>>[];
          _contactsRosterError = _invalidServerUrlMessage();
        });
        return;
      }
      final response = await _fetchFriendsServerRoster(
        uri: uri,
        httpClient: httpClient,
      );
      if (response.isSuccess) {
        final list = response.friends;
        final merged = await _mergeContactsRosterWithLocal(list);
        if (!mounted) return;
        setState(() {
          _contactsRoster = merged;
          _contactsRosterError = null;
        });
      } else {
        if (shamellIsCriticalAccountSessionHttpFailure(
          statusCode: response.statusCode,
          rawBody: response.rawBody,
        )) {
          await _forceReauthDueToDeviceBindingDrift();
          return;
        }
        final localOnly = await _localContactsRoster();
        if (!mounted) return;
        setState(() {
          _contactsRoster = localOnly;
          _contactsRosterError =
              localOnly.isEmpty ? 'HTTP ${response.statusCode}' : null;
        });
      }
    } catch (e) {
      if (shamellIsCriticalAccountSessionError(e)) {
        await _forceReauthDueToDeviceBindingDrift();
        return;
      }
      final localOnly = await _localContactsRoster();
      final safeDetail = sanitizeExceptionForUi(
        error: e,
        isArabic: L10n.of(context).isArabic,
      );
      if (!mounted) return;
      setState(() {
        _contactsRoster = localOnly;
        _contactsRosterError = localOnly.isEmpty ? safeDetail : null;
      });
    } finally {
      if (closeClient) {
        httpClient.close();
      }
      if (mounted) {
        setState(() {
          _contactsRosterLoading = false;
        });
      }
    }
  }

  String _contactsRosterKey(Map<String, dynamic> entry) {
    final deviceId = (entry['device_id'] ?? '').toString().trim();
    if (deviceId.isNotEmpty) return deviceId;
    final id = (entry['id'] ?? '').toString().trim();
    if (id.isNotEmpty) return id;
    final phone = (entry['phone'] ?? '').toString().trim();
    if (phone.isNotEmpty) return phone;
    return '';
  }

  Future<List<Map<String, dynamic>>> _localContactsRoster() async {
    try {
      final local = await _chatStore.loadContacts(baseUrlOverride: _baseUrl);
      return local
          .where((c) => c.id.trim().isNotEmpty)
          .map(
            (c) => <String, dynamic>{
              'id': c.id,
              'name': (c.name ?? '').trim(),
              'device_id': c.id,
              'close': c.starred,
            },
          )
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _mergeContactsRosterWithLocal(
    List<Map<String, dynamic>> serverRoster,
  ) async {
    final mergedByKey = <String, Map<String, dynamic>>{};

    for (final raw in serverRoster) {
      final item = Map<String, dynamic>.from(raw);
      final key = _contactsRosterKey(item);
      if (key.isEmpty) continue;
      mergedByKey[key] = item;
    }

    final localRoster = await _localContactsRoster();
    for (final local in localRoster) {
      final key = _contactsRosterKey(local);
      if (key.isEmpty) continue;
      final existing = mergedByKey[key];
      if (existing == null) {
        mergedByKey[key] = Map<String, dynamic>.from(local);
        continue;
      }

      // Keep server fields authoritative, but fill obvious local gaps.
      final localName = (local['name'] ?? '').toString().trim();
      if ((existing['name'] ?? '').toString().trim().isEmpty &&
          localName.isNotEmpty) {
        existing['name'] = localName;
      }
      final localDeviceId = (local['device_id'] ?? '').toString().trim();
      if ((existing['device_id'] ?? '').toString().trim().isEmpty &&
          localDeviceId.isNotEmpty) {
        existing['device_id'] = localDeviceId;
      }
      final localClose = (local['close'] == true);
      if (localClose && existing['close'] != true) {
        existing['close'] = true;
      }
    }

    return mergedByKey.values.toList();
  }

  Future<void> _refreshContactsRosterFromLocalCache() async {
    final merged = await _mergeContactsRosterWithLocal(_contactsRoster);
    if (!mounted) return;
    setState(() {
      _contactsRoster = merged;
      if (merged.isNotEmpty) {
        _contactsRosterError = null;
      }
    });
  }

  Future<void> _loadDefaultOfficialAccountFlag() async {
    if (!_caps.officialAccounts) {
      if (!mounted) return;
      setState(() {
        _hasDefaultOfficialAccount = false;
      });
      return;
    }
    try {
      final sp = await SharedPreferences.getInstance();
      final official = await loadLegacyDefaultOfficialAccountContext(
        sp: sp,
        baseUrlOverride: _baseUrl,
      );
      var hasDefaultOfficialAccount = official.accountId.isNotEmpty;
      if (!hasDefaultOfficialAccount) {
        final serverOfficial =
            await _loadDefaultOfficialAccountContextFromServer(sp);
        hasDefaultOfficialAccount =
            (serverOfficial?.accountId ?? '').trim().isNotEmpty;
      }
      if (!mounted) return;
      setState(() {
        _hasDefaultOfficialAccount = hasDefaultOfficialAccount;
      });
    } catch (_) {}
  }

  Future<LegacyDefaultOfficialAccountContext?>
      _loadDefaultOfficialAccountContextFromServer(
    SharedPreferences sp,
  ) async {
    final uri = _homeApiUri(
      pathSegments: const <String>['me', 'official_account_requests'],
    );
    if (uri == null) return null;
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final response = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_startupDataRequestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rawRequests = decoded is Map && decoded['requests'] is List
            ? decoded['requests'] as List
            : decoded is List
                ? decoded
                : const <dynamic>[];
        for (final raw in rawRequests) {
          if (raw is! Map) continue;
          final status = (raw['status'] ?? raw['review_status'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          if (status.isNotEmpty && status != 'approved') continue;
          final accountId =
              (raw['account_id'] ?? raw['id'] ?? '').toString().trim();
          if (accountId.isEmpty) continue;
          final accountName =
              (raw['name'] ?? raw['account_name'] ?? '').toString().trim();
          final resolvedName = accountName.isEmpty ? accountId : accountName;
          await saveLegacyDefaultOfficialAccountContext(
            accountId: accountId,
            accountName: resolvedName,
            sp: sp,
            baseUrlOverride: _baseUrl,
          );
          return LegacyDefaultOfficialAccountContext(
            accountId: accountId,
            accountName: resolvedName,
          );
        }
      } else if (shamellIsCriticalAccountSessionHttpFailure(
        statusCode: response.statusCode,
        rawBody: response.body,
      )) {
        await _forceReauthDueToDeviceBindingDrift();
      }
    } catch (e) {
      await _handleCriticalAccountSessionError(e);
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
    return null;
  }

  Future<void> _initCallSignaling() async {
    if (_callSignalingInitInFlight) return;
    if (_deviceBindingReauthTriggered) return;
    _callSignalingInitInFlight = true;
    try {
      final base = _baseUrl.trim();
      if (base.isEmpty || !isSecureApiBaseUrl(base)) {
        _scheduleCallSignalingReconnect();
        return;
      }
      // Keep incoming-call signaling resilient on iOS: if a device identity
      // was not initialized yet, bootstrap account+chat first.
      try {
        final svc = ChatService(base, httpClient: widget.client);
        try {
          await svc.ensureAccountChatReady();
        } finally {
          svc.close();
        }
      } catch (e) {
        final forcedReauth = await _handleCriticalAccountSessionError(e);
        if (forcedReauth || _deviceBindingReauthTriggered) return;
      }
      final devId = await CallSignalingClient.loadDeviceId(
        baseUrlOverride: base,
      );
      if (!mounted) return;
      if (devId == null || devId.isEmpty) {
        _scheduleCallSignalingReconnect();
        return;
      }
      final alreadyConnected = _callClient != null &&
          _callSignalingBaseUrl == base &&
          _callSignalingDeviceId == devId;
      if (alreadyConnected) {
        _callSignalingReconnectAttempt = 0;
        return;
      }
      await _callSub?.cancel();
      _callSub = null;
      _callClient?.close();
      _callClient = null;

      final client = CallSignalingClient(base);
      final stream = client.connect(deviceId: devId);
      _callClient = client;
      _callSub = stream.listen(
        (msg) {
          unawaited(_handleCallSignalingStreamEvent(msg));
        },
        onError: (_) {
          _scheduleCallSignalingReconnect();
        },
        onDone: () {
          _scheduleCallSignalingReconnect();
        },
      );
      _callSignalingBaseUrl = base;
      _callSignalingDeviceId = devId;
      _callSignalingReconnectAttempt = 0;
    } catch (_) {
      _scheduleCallSignalingReconnect();
    } finally {
      _callSignalingInitInFlight = false;
    }
  }

  void _scheduleCallSignalingReconnect() {
    if (!mounted) return;
    final attempt = _callSignalingReconnectAttempt.clamp(0, 5);
    final delayMs = 600 * (1 << attempt);
    _callSignalingReconnectAttempt = (_callSignalingReconnectAttempt + 1).clamp(
      0,
      8,
    );
    _callSignalingReconnectTimer?.cancel();
    _callSignalingReconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _requestCallSignalingInit();
    });
  }

  Future<void> _handleCallSignalingStreamEvent(Map<String, dynamic> msg) async {
    if (_deviceBindingReauthTriggered || !mounted) return;
    if (shamellCallSignalingEventRequiresReauth(msg)) {
      final forcedReauth = await _handleCriticalAccountSessionError(
        (msg['detail'] ?? msg['reason'] ?? '').toString(),
      );
      if (forcedReauth || _deviceBindingReauthTriggered || !mounted) return;
    }
    final type = (msg['type'] ?? '').toString().trim().toLowerCase();
    if (type == 'closed' || type == 'error') {
      _scheduleCallSignalingReconnect();
      return;
    }
    _handleCallSignal(msg);
  }

  void _handleCallSignal(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = (msg['type'] ?? '').toString();
    if (type != 'invite') return;
    final callId = (msg['call_id'] ?? '').toString();
    final from = (msg['from'] ?? '').toString();
    if (callId.isEmpty || from.isEmpty) return;
    final modeRaw = (msg['mode'] ?? '').toString().trim().toLowerCase();
    final mode = (modeRaw == 'audio' || modeRaw == 'video') ? modeRaw : 'video';
    // The caller's WS invite carries an optional `from_name` (matching the
    // FCM `from_name` plumbing). Trim + cap at 80 grapheme clusters so the
    // in-app ring banner shows the human name immediately instead of
    // flashing the raw deviceId while the local resolver runs.
    final rawFromName = (msg['from_name'] ?? '').toString().trim();
    final fromName = rawFromName.isEmpty
        ? null
        : rawFromName.characters.take(80).toString();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IncomingCallPage(
          baseUrl: _baseUrl,
          callId: callId,
          fromDeviceId: from,
          mode: mode,
          initialCallerName: fromName,
        ),
      ),
    );
  }

  Future<void> _ensureServiceOfficialFollow({
    required String officialId,
    required String chatPeerId,
  }) async {
    if (officialId.isEmpty || chatPeerId.isEmpty) return;
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final alreadyFollowed = await _chatStore.hasOfficialAutofollowed(
        officialId,
        baseUrlOverride: _baseUrl,
      );
      var justFollowed = false;
      if (!alreadyFollowed) {
        final uri = _homeApiUri(
          pathSegments: <String>['official_accounts', officialId, 'follow'],
        );
        if (uri == null) {
          return;
        }
        final reqHeaders = await _hdr(json: true);
        final idempotencyScope = '$officialId|follow';
        final idempotencyKey =
            _pendingOfficialFollowIdempotencyKeys.putIfAbsent(
          idempotencyScope,
          () => _newOfficialMutationIdempotencyKey('official-follow'),
        );
        reqHeaders['Idempotency-Key'] = idempotencyKey;
        final r = await httpClient
            .post(uri, headers: reqHeaders)
            .timeout(_startupDataRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          _pendingOfficialFollowIdempotencyKeys.remove(idempotencyScope);
          await _chatStore.markOfficialAutofollowed(
            officialId,
            baseUrlOverride: _baseUrl,
          );
          justFollowed = true;
        } else if (shamellIsCriticalAccountSessionHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          await _forceReauthDueToDeviceBindingDrift();
          return;
        } else {
          // Do not mark as done; try again on next use.
          return;
        }
      }
      // Optionally ensure a chat contact exists for this service account.
      final alreadyLinked = await _chatStore.hasOfficialAutochat(
        chatPeerId,
        baseUrlOverride: _baseUrl,
      );
      if (alreadyLinked) return;
      final me = await _chatStore.loadIdentity(baseUrlOverride: _baseUrl);
      if (me == null) return;
      final svc = ChatService(_baseUrl, httpClient: widget.client);
      try {
        ChatContact peer;
        try {
          peer = await svc.resolveDevice(chatPeerId);
        } catch (_) {
          return;
        }
        final contacts = await _chatStore.loadContacts(
          baseUrlOverride: _baseUrl,
        );
        final exists = contacts.any((c) => c.id == peer.id);
        if (!exists) {
          final updated = <ChatContact>[...contacts, peer];
          await _chatStore.saveContacts(updated, baseUrlOverride: _baseUrl);
        }
        await _chatStore.markOfficialAutochat(
          chatPeerId,
          baseUrlOverride: _baseUrl,
        );
        if (justFollowed && mounted) {
          final l = L10n.of(context);
          final msg = l.isArabic
              ? 'تمت متابعة الحساب الرسمي للخدمة تلقائياً.'
              : 'You now follow the service official account.';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(msg)));
        }
      } finally {
        svc.close();
      }
    } catch (e) {
      await _handleCriticalAccountSessionError(e);
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _applyOfficialNotificationGroupMode({
    required List<Map<String, dynamic>> accounts,
    required AnalyticsOfficialGroup group,
    required OfficialNotificationMode mode,
  }) async {
    if (accounts.isEmpty) return;
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final contacts = await _chatStore.loadContacts(baseUrlOverride: _baseUrl);
      final byId = {for (final c in contacts) c.id: c};
      final updatedContacts = List<ChatContact>.from(contacts);
      var changedContacts = false;
      final modeStr = switch (mode) {
        OfficialNotificationMode.full => 'full',
        OfficialNotificationMode.summary => 'summary',
        OfficialNotificationMode.muted => 'muted',
      };
      for (final m in accounts) {
        if (m['followed'] != true) continue;
        if (!_officialAccountMatchesNotificationGroup(m, group)) continue;
        final peerId = (m['chat_peer_id'] ?? '').toString().trim();
        if (peerId.isNotEmpty) {
          await _chatStore.setOfficialNotifMode(
            peerId,
            mode,
            baseUrlOverride: _baseUrl,
          );
          final existing = byId[peerId];
          if (existing != null) {
            final shouldMute = mode == OfficialNotificationMode.muted;
            if (existing.muted != shouldMute) {
              final idx = updatedContacts.indexWhere((c) => c.id == peerId);
              if (idx != -1) {
                updatedContacts[idx] = existing.copyWith(muted: shouldMute);
                changedContacts = true;
              }
            }
          }
        }
        final accId = (m['id'] ?? '').toString();
        if (accId.isNotEmpty) {
          final uri = _homeApiUri(
            pathSegments: <String>[
              'official_accounts',
              accId,
              'notification_mode',
            ],
          );
          if (uri == null) {
            return;
          }
          final body = jsonEncode({'mode': modeStr});
          final reqHeaders = await _hdr(json: true);
          final idempotencyScope = '$accId|$modeStr';
          final idempotencyKey =
              _pendingOfficialNotificationModeIdempotencyKeys.putIfAbsent(
            idempotencyScope,
            () => _newOfficialMutationIdempotencyKey('official-notif-mode'),
          );
          reqHeaders['Idempotency-Key'] = idempotencyKey;
          final r = await httpClient
              .post(uri, headers: reqHeaders, body: body)
              .timeout(_startupDataRequestTimeout);
          if (r.statusCode >= 200 && r.statusCode < 300) {
            _pendingOfficialNotificationModeIdempotencyKeys.remove(
              idempotencyScope,
            );
          }
          if (shamellIsCriticalAccountSessionHttpFailure(
            statusCode: r.statusCode,
            rawBody: r.body,
          )) {
            await _forceReauthDueToDeviceBindingDrift();
            return;
          }
        }
      }
      if (changedContacts) {
        await _chatStore.saveContacts(
          updatedContacts,
          baseUrlOverride: _baseUrl,
        );
      }
    } catch (e) {
      await _handleCriticalAccountSessionError(e);
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<_OfficialNotificationSheetState?>
      _loadOfficialNotificationSheetState() async {
    final accounts = <Map<String, dynamic>>[];
    final seenAccountIds = <String>{};
    final serverModes = <String, String>{};
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      String? beforeName;
      String? beforeId;
      bool? beforeFeatured;
      String? lastCursorKey;
      while (true) {
        final queryParameters = <String, String>{
          'followed_only': 'true',
          'limit': '$_officialAccountsPageSize',
        };
        if (beforeName != null && beforeId != null && beforeFeatured != null) {
          queryParameters['before_featured'] = '$beforeFeatured';
          queryParameters['before_name'] = beforeName;
          queryParameters['before_id'] = beforeId;
        }
        final uri = _homeApiUri(
          pathSegments: const <String>['official_accounts'],
          queryParameters: queryParameters,
        );
        if (uri == null) {
          return null;
        }
        final r = await httpClient
            .get(uri, headers: await _hdr())
            .timeout(_startupDataRequestTimeout);
        if (r.statusCode >= 200 && r.statusCode < 300) {
          final decoded = jsonDecode(r.body);
          List<dynamic> raw = const [];
          if (decoded is Map && decoded['accounts'] is List) {
            raw = decoded['accounts'] as List;
          } else if (decoded is List) {
            raw = decoded;
          }
          Map<String, dynamic>? lastAccount;
          for (final e in raw) {
            if (e is! Map) continue;
            final account = e.cast<String, dynamic>();
            lastAccount = account;
            final accountId = (account['id'] ?? '').toString().trim();
            if (accountId.isNotEmpty && !seenAccountIds.add(accountId)) {
              continue;
            }
            accounts.add(account);
          }
          if (raw.length < _officialAccountsPageSize || lastAccount == null) {
            break;
          }
          final nextBeforeName = (lastAccount['name'] ?? '').toString();
          final nextBeforeId = (lastAccount['id'] ?? '').toString().trim();
          if (nextBeforeName.isEmpty || nextBeforeId.isEmpty) {
            break;
          }
          final nextBeforeFeatured =
              (lastAccount['featured'] as bool?) ?? false;
          final nextCursorKey =
              '$nextBeforeFeatured|$nextBeforeName|$nextBeforeId';
          if (nextCursorKey == lastCursorKey) {
            break;
          }
          lastCursorKey = nextCursorKey;
          beforeFeatured = nextBeforeFeatured;
          beforeName = nextBeforeName;
          beforeId = nextBeforeId;
        } else if (shamellIsCriticalAccountSessionHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          await _forceReauthDueToDeviceBindingDrift();
          return null;
        } else {
          break;
        }
      }

      final notificationsUri = _homeApiUri(
        pathSegments: const <String>['official_accounts', 'notifications'],
      );
      if (notificationsUri == null) {
        return null;
      }
      final modesResponse = await httpClient
          .get(notificationsUri, headers: await _hdr())
          .timeout(_startupDataRequestTimeout);
      if (modesResponse.statusCode >= 200 && modesResponse.statusCode < 300) {
        final decoded = jsonDecode(modesResponse.body);
        if (decoded is Map && decoded['modes'] is Map) {
          for (final entry in (decoded['modes'] as Map).entries) {
            final accountId = entry.key.toString().trim();
            final mode = entry.value?.toString().trim().toLowerCase() ?? '';
            if (accountId.isEmpty || mode.isEmpty) continue;
            serverModes[accountId] = mode;
          }
        }
      } else if (shamellIsCriticalAccountSessionHttpFailure(
        statusCode: modesResponse.statusCode,
        rawBody: modesResponse.body,
      )) {
        await _forceReauthDueToDeviceBindingDrift();
        return null;
      }
    } catch (e) {
      if (await _handleCriticalAccountSessionError(e)) return null;
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }

    return _OfficialNotificationSheetState(
      accounts: accounts,
      serviceMode: officialNotificationGroupModeForAccounts(
        accounts: accounts,
        serverModes: serverModes,
        group: AnalyticsOfficialGroup.service,
      ),
      nonServiceMode: officialNotificationGroupModeForAccounts(
        accounts: accounts,
        serverModes: serverModes,
        group: AnalyticsOfficialGroup.nonservice,
      ),
    );
  }

  Future<void> _openOfficialNotifications() async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    Perf.action('official_open_notifications_sheet');
    final preload = await _loadOfficialNotificationSheetState();
    if (preload == null) return;
    if (!mounted) return;
    final accounts = preload.accounts;

    AnalyticsNotifMode toAnalyticsNotifMode(OfficialNotificationMode mode) {
      return switch (mode) {
        OfficialNotificationMode.full => AnalyticsNotifMode.full,
        OfficialNotificationMode.summary => AnalyticsNotifMode.summary,
        OfficialNotificationMode.muted => AnalyticsNotifMode.muted,
      };
    }

    OfficialNotificationMode serviceMode = preload.serviceMode;
    OfficialNotificationMode nonServiceMode = preload.nonServiceMode;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Material(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            child: StatefulBuilder(
              builder: (ctx, setModalState) {
                return SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.notifications_none_outlined),
                        title: Text(
                          l.isArabic
                              ? 'إشعارات الحسابات الرسمية'
                              : 'Official account notifications',
                        ),
                        subtitle: Text(
                          l.isArabic
                              ? 'تغيير وضع الإشعارات لكل الحسابات الرسمية'
                              : 'Change notification mode for all official accounts',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: .70,
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: Text(
                          l.isArabic ? 'حسابات الخدمات' : 'Service accounts',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      RadioGroup<OfficialNotificationMode>(
                        groupValue: serviceMode,
                        onChanged: (mode) async {
                          if (mode == null) return;
                          setModalState(() => serviceMode = mode);
                          await _applyOfficialNotificationGroupMode(
                            accounts: accounts,
                            group: AnalyticsOfficialGroup.service,
                            mode: mode,
                          );
                          for (final event in notificationModeEvents(
                            group: AnalyticsOfficialGroup.service,
                            mode: toAnalyticsNotifMode(mode),
                          )) {
                            Perf.action(event);
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.full,
                              title: Text(
                                l.isArabic
                                    ? 'إظهار معاينة الرسائل'
                                    : 'Show message preview',
                              ),
                            ),
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.summary,
                              title: Text(
                                l.isArabic
                                    ? 'إخفاء محتوى الرسائل'
                                    : 'Hide message content',
                              ),
                            ),
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.muted,
                              title: Text(
                                l.isArabic
                                    ? 'كتم الإشعارات'
                                    : 'Mute notifications',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        title: Text(
                          l.isArabic
                              ? 'باقي الحسابات الرسمية'
                              : 'Other official accounts',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      RadioGroup<OfficialNotificationMode>(
                        groupValue: nonServiceMode,
                        onChanged: (mode) async {
                          if (mode == null) return;
                          setModalState(() => nonServiceMode = mode);
                          await _applyOfficialNotificationGroupMode(
                            accounts: accounts,
                            group: AnalyticsOfficialGroup.nonservice,
                            mode: mode,
                          );
                          for (final event in notificationModeEvents(
                            group: AnalyticsOfficialGroup.nonservice,
                            mode: toAnalyticsNotifMode(mode),
                          )) {
                            Perf.action(event);
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.full,
                              title: Text(
                                l.isArabic
                                    ? 'إظهار معاينة الرسائل'
                                    : 'Show message preview',
                              ),
                            ),
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.summary,
                              title: Text(
                                l.isArabic
                                    ? 'إخفاء محتوى الرسائل'
                                    : 'Hide message content',
                              ),
                            ),
                            RadioListTile<OfficialNotificationMode>(
                              value: OfficialNotificationMode.muted,
                              title: Text(
                                l.isArabic
                                    ? 'كتم الإشعارات'
                                    : 'Mute notifications',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final switchDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 260);
    String _homeTitle() {
      switch (_tabIndex) {
        case 0:
          return l.shamellTabChats;
        case 1:
          return l.shamellTabContacts;
        case 2:
          return l.homeWallet;
        case 3:
          return l.shamellTabChannel;
        case 4:
          return l.isArabic ? 'أنا' : 'Me';
        default:
          return l.appTitle;
      }
    }

    return Scaffold(
      extendBody: true,
      // Chats tab is a full-page chat shell (it has its own AppBar with
      // SyrChat-style actions), so avoid rendering a second AppBar here.
      appBar: _tabIndex == 0
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              toolbarHeight: 48,
              titleSpacing: 16,
              actionsIconTheme: const IconThemeData(size: 22),
              flexibleSpace: const _ShamellGlassAppBarBackdrop(),
              title: Text(
                _homeTitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0,
                    ),
              ),
              actions: [
                if (_tabIndex == 1)
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.white24,
                    ),
                    child: PopupMenuButton<String>(
                      tooltip: l.isArabic ? 'إضافة' : 'Add',
                      icon: const Icon(Icons.add),
                      position: PopupMenuPosition.under,
                      offset: const Offset(0, 6),
                      color: const Color(0xFF1F1F1F),
                      elevation: 6,
                      shadowColor: Colors.black.withValues(alpha: .22),
                      surfaceTintColor: Colors.transparent,
                      menuPadding: const EdgeInsets.symmetric(vertical: 5),
                      constraints: const BoxConstraints(
                        minWidth: 212,
                        maxWidth: 236,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'scan':
                            unawaited(_openShamellScanAndHandle());
                            return;
                          case 'shamell_id':
                            unawaited(_openShamellIdContactResolveDialog());
                            return;
                        }
                      },
                      itemBuilder: (ctx) {
                        Widget item(IconData icon, String label) {
                          return SizedBox(
                            width: 204,
                            child: Row(
                              children: [
                                Icon(
                                  icon,
                                  size: 20,
                                  color: Colors.white.withValues(alpha: .92),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return [
                          PopupMenuItem<String>(
                            value: 'shamell_id',
                            height: 46,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            child: item(
                              Icons.person_search_outlined,
                              l.isArabic ? 'معرّف SyrChat' : 'SyrChat ID',
                            ),
                          ),
                          const PopupMenuDivider(height: .7),
                          PopupMenuItem<String>(
                            value: 'scan',
                            height: 46,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            child: item(
                              Icons.qr_code_scanner_outlined,
                              l.isArabic ? 'مسح' : 'Scan',
                            ),
                          ),
                        ];
                      },
                    ),
                  ),
              ],
            ),
      body: AppBG(
        // SafeArea is already handled by the AppBar (and by the embedded
        // chat shell on the Chats tab). Wrapping here would double-apply
        // padding on notched devices.
        child: AnimatedSwitcher(
          duration: switchDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            if (reduceMotion) {
              return FadeTransition(opacity: animation, child: child);
            }
            final slide = Tween<Offset>(
              begin: const Offset(.02, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(position: slide, child: child),
            );
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_tabIndex),
            child: _buildTabBody(),
          ),
        ),
      ),
      bottomNavigationBar: _ShamellHomeBottomBar(
        currentIndex: _tabIndex,
        items: [
          _ShamellHomeBottomBarItem(
            icon: _ShamellBottomNavBadgeIcon(
              icon: Icons.chat_bubble_outline,
              showBadge: _totalUnreadChats > 0,
            ),
            activeIcon: _ShamellBottomNavBadgeIcon(
              icon: Icons.chat_bubble,
              showBadge: _totalUnreadChats > 0,
            ),
            label: l.shamellTabChats,
          ),
          _ShamellHomeBottomBarItem(
            icon: const Icon(Icons.people_outline),
            activeIcon: const Icon(Icons.people),
            label: l.shamellTabContacts,
          ),
          _ShamellHomeBottomBarItem(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            activeIcon: const Icon(Icons.account_balance_wallet),
            label: l.homeWallet,
          ),
          _ShamellHomeBottomBarItem(
            icon: _ShamellBottomNavBadgeIcon(
              icon: Icons.travel_explore_outlined,
              showBadge: _hasUnreadServiceNotifications,
            ),
            activeIcon: _ShamellBottomNavBadgeIcon(
              icon: Icons.travel_explore,
              showBadge: _hasUnreadServiceNotifications,
            ),
            label: l.shamellTabChannel,
          ),
          _ShamellHomeBottomBarItem(
            icon: const Icon(Icons.person_outline),
            activeIcon: const Icon(Icons.person),
            label: l.isArabic ? 'أنا' : 'Me',
          ),
        ],
        onTap: (index) {
          setState(() {
            _tabIndex = index;
          });
          if (index == 2 && _caps.payments && _walletId.trim().isEmpty) {
            unawaited(_ensureWalletReady(interactive: false));
          }
        },
      ),
    );
  }

  /// Top-level body switch for SyrChat-like tab layout.
  Widget _buildTabBody() {
    switch (_tabIndex) {
      case 0:
        return _buildChatsTab();
      case 1:
        return _buildContactsTab();
      case 2:
        return _buildPaymentsTab();
      case 3:
        return _buildServicesTab();
      case 4:
        return _buildMeTab();
      default:
        return _buildChatsTab();
    }
  }

  Widget _buildMoodBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? accent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = accent ?? theme.colorScheme.primary;
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurface,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: .78),
      height: 1.25,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .34 : .70),
          width: .7,
        ),
      ),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: baseColor.withValues(alpha: isDark ? .18 : .10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(icon, size: 20, color: baseColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: subtitleStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabStagger({required int order, required Widget child}) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;
    final start = (order * 0.12).clamp(0.0, 0.65).toDouble();
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('tab-${_tabIndex}-$order'),
      duration: const Duration(milliseconds: 520),
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      tween: Tween<double>(begin: 0, end: 1),
      child: child,
      builder: (context, value, child) {
        final opacity = value.clamp(0.0, 1.0);
        final y = (1 - opacity) * 16;
        return Opacity(
          opacity: opacity,
          child: Transform.translate(offset: Offset(0, y), child: child),
        );
      },
    );
  }

  double _liquidBottomChromePadding(BuildContext context) {
    return MediaQuery.sizeOf(context).width < 430 ? 66 : 70;
  }

  /// Tab 0 – Chats: entry point for end-user and service chats.
  Widget _buildChatsTab() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final body = ShamellChatPage(
      key: ValueKey<String>(
        'home-chat:${_seededInitialChatLaunchNonce}:${_seededInitialChatPeerId ?? ''}',
      ),
      baseUrl: _baseUrl,
      initialPeerId: _seededInitialChatPeerId,
      debugAutoSendText: _seededInitialChatAutoSendText,
      showBottomNav: false,
      runStartupTasks: widget.runStartupTasks,
    );
    final bottomChromePadding = _liquidBottomChromePadding(context);

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomChromePadding),
            child: body,
          ),
        ),
        IgnorePointer(
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: 86,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.scaffoldBackgroundColor.withValues(
                      alpha: isDark ? .42 : .30,
                    ),
                    theme.scaffoldBackgroundColor.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tab 1 – Contacts: people, P2P and service assistants.
  Widget _buildContactsTab() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerBg = theme.colorScheme.surface.withValues(
      alpha: isDark ? .78 : .90,
    );
    final rosterBg = theme.colorScheme.surface.withValues(
      alpha: isDark ? .84 : .94,
    );
    final rosterBorder = theme.dividerColor.withValues(
      alpha: isDark ? .40 : .72,
    );
    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .52),
        );

    Widget friendReqBadge() => Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.redAccent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _friendRequestsPending > 99 ? '99+' : '$_friendRequestsPending',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

    Widget contactsHubCard() {
      return ShamellSearchBar(
        hintText: l.isArabic
            ? 'البحث في جهات الاتصال ومعرّفات SyrChat'
            : 'Search contacts and SyrChat IDs',
        readOnly: true,
        onTap: _openGlobalSearch,
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      );
    }

    Widget contactsListSection({
      required List<Widget> children,
      EdgeInsets margin = const EdgeInsets.only(top: 8),
      double dividerIndent = 72,
    }) {
      if (children.isEmpty) return const SizedBox.shrink();
      final sectionBorder = BorderSide(color: rosterBorder, width: .7);
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          color: rosterBg,
          border: Border(top: sectionBorder, bottom: sectionBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: .5,
                  indent: dividerIndent,
                  color: theme.dividerColor.withValues(alpha: isDark ? .54 : 1),
                ),
              children[i],
            ],
          ],
        ),
      );
    }

    void showIndexHint(String letter, {bool persist = false}) {
      _contactsIndexHintTimer?.cancel();
      if (_contactsIndexHint != letter) {
        setState(() {
          _contactsIndexHint = letter;
        });
      }
      if (persist) return;
      _contactsIndexHintTimer = Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() {
          _contactsIndexHint = null;
        });
      });
    }

    String chatIdForFriend(Map<String, dynamic> f) {
      final deviceId = (f['device_id'] ?? '').toString().trim();
      if (deviceId.isNotEmpty) return deviceId;
      // Chat peer ids must be device-scoped (Chat-ID), not user handles (SyrChat-ID).
      final id = (f['id'] ?? '').toString().trim();
      if (id.isNotEmpty) return id;
      final phone = (f['phone'] ?? '').toString().trim();
      if (phone.isNotEmpty) return phone;
      return '';
    }

    String displayForFriend(Map<String, dynamic> f) {
      final chatId = chatIdForFriend(f);
      final alias = (_contactsAliases[chatId] ?? '').trim();
      final name = (f['name'] ?? f['id'] ?? '').toString().trim();
      final id = (f['id'] ?? '').toString().trim();
      if (alias.isNotEmpty) return alias;
      if (name.isNotEmpty) return name;
      return id.isNotEmpty ? id : chatId;
    }

    String letterForDisplay(String display) {
      final raw = display.trim();
      if (raw.isEmpty) return '#';
      final first = raw[0].toUpperCase();
      final code = first.codeUnitAt(0);
      if (code < 65 || code > 90) return '#';
      return first;
    }

    final topKey = GlobalKey();
    final closeKey = GlobalKey();
    _contactsLetterKeys.clear();
    _contactsLetterKeys['↑'] = topKey;

    Widget contactRow(Map<String, dynamic> f) {
      final chatId = chatIdForFriend(f);
      final alias = (_contactsAliases[chatId] ?? '').trim();
      final tags = (_contactsTags[chatId] ?? '').trim();
      final display = displayForFriend(f);
      final original = (f['name'] ?? f['id'] ?? '').toString().trim();
      final isClose = ((f['close'] as bool?) ?? false) == true;
      final isDark = theme.brightness == Brightness.dark;
      final bg = theme.colorScheme.surface.withValues(
        alpha: isDark ? .74 : .94,
      );
      return Material(
        color: bg,
        child: InkWell(
          onTap: () {
            if (chatId.isEmpty) return;
            _navPush(
              ShamellContactInfoPage(
                baseUrl: _baseUrl,
                friend: f,
                peerId: chatId,
                displayName: original.isNotEmpty ? original : display,
                alias: alias,
                tags: tags,
                isCloseFriend: isClose,
                pushPage: _navPush,
              ),
              onReturn: () {
                unawaited(_refreshFriendsSurface(forceRoster: true));
              },
            );
          },
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: 40,
                      height: 40,
                      color: theme.colorScheme.primary.withValues(alpha: .20),
                      alignment: Alignment.center,
                      child: Text(
                        display.isNotEmpty
                            ? display.substring(0, 1).toUpperCase()
                            : '?',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      display,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget contactLetterHeader(String letter, GlobalKey key) {
      return Container(
        key: key,
        color: headerBg,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Text(
          letter,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: .72),
          ),
        ),
      );
    }

    Widget contactSectionHeader(String label, {Key? headerKey}) {
      return Container(
        key: headerKey,
        color: headerBg,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: .72),
          ),
        ),
      );
    }

    Widget roster() {
      if (_contactsRosterLoading && _contactsRoster.isEmpty) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (_contactsRoster.isEmpty) {
        final message = _contactsRosterError != null
            ? (l.isArabic
                ? 'اسحب للأسفل لتحديث جهات الاتصال.'
                : 'Pull down to refresh contacts.')
            : (l.isArabic ? 'لا توجد جهات اتصال بعد.' : 'No contacts yet.');
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              color: theme.colorScheme.onSurface.withValues(alpha: .48),
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }

      final all = List<Map<String, dynamic>>.from(_contactsRoster);
      all.sort(
        (a, b) => displayForFriend(
          a,
        ).toLowerCase().compareTo(displayForFriend(b).toLowerCase()),
      );
      final close =
          all.where((f) => ((f['close'] as bool?) ?? false) == true).toList();
      final normal =
          all.where((f) => ((f['close'] as bool?) ?? false) != true).toList();

      final widgets = <Widget>[];
      const dividerIndent = 72.0;

      void addContactRow(Map<String, dynamic> f, {bool addDivider = true}) {
        widgets.add(contactRow(f));
        if (addDivider) {
          widgets.add(
            Divider(
              height: 1,
              thickness: 0.5,
              indent: dividerIndent,
              color: theme.dividerColor,
            ),
          );
        }
      }

      if (close.isNotEmpty) {
        _contactsLetterKeys['☆'] = closeKey;
        widgets.add(
          contactSectionHeader(l.shamellFriendsCloseLabel, headerKey: closeKey),
        );
        for (var i = 0; i < close.length; i++) {
          addContactRow(close[i], addDivider: i != close.length - 1);
        }
      }

      if (normal.isNotEmpty) {
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 8));
        }
        String currentLetter = '';
        for (var i = 0; i < normal.length; i++) {
          final f = normal[i];
          final letter = letterForDisplay(displayForFriend(f));
          if (letter != currentLetter) {
            currentLetter = letter;
            final key = GlobalKey();
            _contactsLetterKeys[letter] = key;
            widgets.add(contactLetterHeader(letter, key));
          }
          addContactRow(f, addDivider: i != normal.length - 1);
        }
      }

      return Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: rosterBg,
          border: Border(
            top: BorderSide(color: rosterBorder, width: .7),
            bottom: BorderSide(color: rosterBorder, width: .7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widgets,
        ),
      );
    }

    final content = RefreshIndicator(
      onRefresh: () async {
        await _refreshFriendsSurface(forceRoster: true);
      },
      child: ListView(
        key: _contactsViewportKey,
        controller: _contactsScrollCtrl,
        padding: EdgeInsets.only(
          top: 8,
          bottom: _liquidBottomChromePadding(context) + 16,
        ),
        children: [
          Container(key: topKey),
          _tabStagger(
            order: 0,
            child: contactsHubCard(),
          ),
          _tabStagger(
            order: 1,
            child: contactsListSection(
              margin: const EdgeInsets.only(top: 8),
              children: [
                if (_caps.friends)
                  ListTile(
                    dense: true,
                    leading: const ShamellLeadingIcon(
                      icon: Icons.person_add_outlined,
                      background: Color(0xFFF59E0B),
                    ),
                    title: Text(l.isArabic ? 'أصدقاء جدد' : 'New friends'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_friendRequestsPending > 0) ...[
                          friendReqBadge(),
                          const SizedBox(width: 8),
                        ],
                        chevron(),
                      ],
                    ),
                    onTap: () {
                      _navPush(
                        FriendsPage(_baseUrl, mode: FriendsPageMode.newFriends),
                        onReturn: () {
                          unawaited(_refreshFriendsSurface(forceRoster: true));
                        },
                      );
                    },
                  ),
                ListTile(
                  dense: true,
                  leading: const ShamellLeadingIcon(
                    icon: Icons.group_outlined,
                    background: ShamellPalette.green,
                  ),
                  title: Text(l.isArabic ? 'الدردشات الجماعية' : 'Group chats'),
                  trailing: chevron(),
                  onTap: () => _navPush(GroupChatsPage(baseUrl: _baseUrl)),
                ),
                if (_caps.friends)
                  ListTile(
                    dense: true,
                    leading: const ShamellLeadingIcon(
                      icon: Icons.sell_outlined,
                      background: Color(0xFF3B82F6),
                    ),
                    title: Text(l.isArabic ? 'الوسوم' : 'Tags'),
                    trailing: chevron(),
                    onTap: () => _navPush(FriendTagsPage(baseUrl: _baseUrl)),
                  ),
                // Official Accounts + Nearby tiles were removed from
                // Contacts — both now live exclusively under Discover so
                // each surface has a single canonical entry point.
              ],
            ),
          ),
          if (_caps.friends)
            _tabStagger(order: 3, child: roster())
          else
            _tabStagger(
              order: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                child: Text(
                  l.isArabic
                      ? 'جهات الاتصال غير متاحة حالياً.'
                      : 'Contacts are not available right now.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .76),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final letters = <String>[
      '↑',
      '☆',
      ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ#'.split(''),
    ];
    final showIndex = _contactsRoster.isNotEmpty;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateContactsStickyHeader();
    });

    return Stack(
      children: [
        content,
        if (_contactsStickyHeader != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Transform.translate(
                offset: Offset(0, _contactsStickyHeaderOffset),
                child: Container(
                  height: 28,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: headerBg,
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(
                          alpha: isDark ? .18 : .45,
                        ),
                        width: 0.6,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _contactsStickyHeader == '☆'
                        ? l.shamellFriendsCloseLabel
                        : _contactsStickyHeader!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface.withValues(alpha: .72),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (showIndex)
          Positioned(
            right: l.isArabic ? null : 2,
            left: l.isArabic ? 2 : null,
            top: 88,
            bottom: 80,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final height = constraints.maxHeight;
                const indexPaddingV = 8.0;
                final effectiveHeight = max(1.0, height - indexPaddingV * 2);
                final cellHeight = effectiveHeight / letters.length;

                void jumpTo(String letter, {required bool persistHint}) {
                  final isSame = _contactsIndexHint == letter;
                  showIndexHint(letter, persist: persistHint);
                  if (isSame) return;
                  if (letter == '↑') {
                    if (!_contactsScrollCtrl.hasClients) return;
                    _contactsScrollCtrl.animateTo(
                      0,
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOutCubic,
                    );
                    return;
                  }
                  final key = _contactsLetterKeys[letter];
                  if (key == null) return;
                  final target = key.currentContext;
                  if (target == null) return;
                  Scrollable.ensureVisible(
                    target,
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                  );
                }

                void handle(Offset localPos, {required bool persistHint}) {
                  final dy = (localPos.dy - indexPaddingV).clamp(
                    0.0,
                    effectiveHeight,
                  );
                  final idx = (dy / cellHeight)
                      .floor()
                      .clamp(0, letters.length - 1)
                      .toInt();
                  jumpTo(letters[idx], persistHint: persistHint);
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) {
                    if (_contactsIndexDragging) {
                      setState(() {
                        _contactsIndexDragging = false;
                      });
                    }
                    handle(d.localPosition, persistHint: false);
                  },
                  onVerticalDragStart: (d) {
                    if (!_contactsIndexDragging) {
                      setState(() {
                        _contactsIndexDragging = true;
                      });
                    }
                    handle(d.localPosition, persistHint: true);
                  },
                  onVerticalDragUpdate: (d) =>
                      handle(d.localPosition, persistHint: true),
                  onVerticalDragEnd: (_) {
                    if (_contactsIndexDragging) {
                      setState(() {
                        _contactsIndexDragging = false;
                      });
                    }
                    final hint = _contactsIndexHint;
                    if (hint != null) showIndexHint(hint);
                  },
                  onVerticalDragCancel: () {
                    if (_contactsIndexDragging) {
                      setState(() {
                        _contactsIndexDragging = false;
                      });
                    }
                    final hint = _contactsIndexHint;
                    if (hint != null) showIndexHint(hint);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _contactsIndexDragging
                          ? theme.colorScheme.onSurface.withValues(
                              alpha: isDark ? .14 : .06,
                            )
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: letters.map((letter) {
                        final selected = _contactsIndexHint == letter;
                        const size = 16.0;
                        return SizedBox(
                          width: size,
                          height: size,
                          child: DecoratedBox(
                            decoration: selected
                                ? const BoxDecoration(
                                    color: ShamellPalette.green,
                                    shape: BoxShape.circle,
                                  )
                                : const BoxDecoration(),
                            child: Center(
                              child: Text(
                                letter,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10.5,
                                  color: selected
                                      ? Colors.white
                                      : theme.colorScheme.onSurface.withValues(
                                          alpha: .72,
                                        ),
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
        if (_contactsIndexHint != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .62),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      _contactsIndexHint!,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _updateContactsStickyHeader() {
    if (!mounted) return;
    if (_tabIndex != 1) return;
    final viewportCtx = _contactsViewportKey.currentContext;
    if (viewportCtx == null) return;
    final viewportObj = viewportCtx.findRenderObject();
    if (viewportObj is! RenderBox) return;

    const headerH = 28.0;
    final entries = <MapEntry<String, double>>[];

    for (final e in _contactsLetterKeys.entries) {
      if (e.key == '↑') continue;
      final ctx = e.value.currentContext;
      if (ctx == null) continue;
      final obj = ctx.findRenderObject();
      if (obj is! RenderBox) continue;
      final pos = obj.localToGlobal(Offset.zero, ancestor: viewportObj);
      entries.add(MapEntry(e.key, pos.dy));
    }
    if (entries.isEmpty) {
      if (_contactsStickyHeader != null || _contactsStickyHeaderOffset != 0.0) {
        setState(() {
          _contactsStickyHeader = null;
          _contactsStickyHeaderOffset = 0.0;
        });
      }
      return;
    }
    entries.sort((a, b) => a.value.compareTo(b.value));

    MapEntry<String, double>? current;
    for (final e in entries) {
      if (e.value <= 0) {
        current = e;
      } else {
        break;
      }
    }

    final nextHeader = current == null
        ? null
        : (() {
            final idx = entries.indexOf(current!);
            if (idx < 0 || idx >= entries.length - 1) return null;
            return entries[idx + 1];
          })();

    final nextKey = current?.key;
    final nextOffset = (current == null || nextHeader == null)
        ? 0.0
        : min(0.0, nextHeader.value - headerH);

    if (nextKey == _contactsStickyHeader &&
        (nextOffset - _contactsStickyHeaderOffset).abs() < 0.5) {
      return;
    }

    setState(() {
      _contactsStickyHeader = nextKey;
      _contactsStickyHeaderOffset = nextOffset;
    });
  }

  void _openShamellSettings() {
    _navPush(
      ShamellSettingsPage(
        baseUrl: _baseUrl,
        walletId: _walletId,
        deviceId: deviceId,
        profileShamellId: _profileShamellId,
        showDev: _showOps || _showSuperadmin,
        hasDefaultOfficialAccount:
            _caps.officialAccounts && _hasDefaultOfficialAccount,
        onLogout: _logout,
        onLogoutForgetDevice: _logoutForgetDevice,
        pushPage: (page) => _navPush(page),
      ),
    );
  }

  void _openGlobalSearch() {
    unawaited(_recordModuleUse('search'));
    _navPush(
      GlobalSearchPage(
        baseUrl: _baseUrl,
        walletId: _walletId,
        deviceId: deviceId,
        onOpenMod: _openMod,
      ),
    );
  }

  void _openMiniProgramsHub({bool openPinnedManage = false}) {
    unawaited(_recordModuleUse('mini_programs'));
    _navPush(
      MiniProgramsDiscoverPage(
        baseUrl: _baseUrl,
        walletId: _walletId,
        deviceId: deviceId,
        onOpenMod: _openMod,
        openPinnedManageOnStart: openPinnedManage,
      ),
    );
  }

  List<MiniAppDescriptor> _sortedMiniProgramDescriptors() {
    final descriptors = MiniAppRegistry.descriptors
        .where((d) => d.enabled)
        .toList(growable: false);
    final sorted = descriptors.toList(growable: true)
      ..sort((a, b) {
        final usage = b.usageScore.compareTo(a.usageScore);
        if (usage != 0) return usage;
        return b.rating.compareTo(a.rating);
      });
    return sorted;
  }

  List<String> _cleanMiniProgramIds(Iterable<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final id = item.trim();
      if (id.isEmpty) continue;
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  Future<_MiniProgramShelfPrefs> _loadMiniProgramShelfPrefs(
    SharedPreferences sp,
  ) async {
    final ordered = loadMiniProgramPinnedOrderSync(sp);
    final recents = loadMiniProgramRecentIdsSync(sp);
    return _MiniProgramShelfPrefs(pinnedIds: ordered, recentIds: recents);
  }

  Future<void> _persistMiniProgramShelfPrefs(
    SharedPreferences sp,
    _MiniProgramShelfPrefs prefs,
  ) async {
    await saveMiniProgramShelfPrefs(
      sp,
      pinnedIds: prefs.pinnedIds,
      pinnedOrder: prefs.pinnedIds,
      recentIds: prefs.recentIds,
    );
  }

  _MiniProgramShelfPrefs _parseMiniProgramShelfSnapshot(dynamic raw) {
    if (raw is! Map) {
      return const _MiniProgramShelfPrefs(
        pinnedIds: <String>[],
        recentIds: <String>[],
      );
    }

    List<String> idsFromList(dynamic value) {
      if (value is! List) return const <String>[];
      return _cleanMiniProgramIds(value.map((item) => (item ?? '').toString()));
    }

    final explicitPinned = idsFromList(raw['pinned_ids']);
    final explicitRecent = idsFromList(raw['recent_ids']);
    final derivedPinned = <String>[];
    final derivedRecent = <String>[];
    final items = raw['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final id = (item['app_id'] ?? item['id'] ?? '').toString().trim();
        if (id.isEmpty) continue;
        if (item['pinned'] == true) {
          derivedPinned.add(id);
        }
        final lastOpened = (item['last_opened_at'] ?? '').toString().trim();
        final openCount = item['open_count'];
        if (lastOpened.isNotEmpty || (openCount is num && openCount > 0)) {
          derivedRecent.add(id);
        }
      }
    }

    return _MiniProgramShelfPrefs(
      pinnedIds: explicitPinned.isNotEmpty
          ? explicitPinned
          : _cleanMiniProgramIds(derivedPinned),
      recentIds: explicitRecent.isNotEmpty
          ? explicitRecent
          : _cleanMiniProgramIds(derivedRecent),
    );
  }

  Future<void> _applyMiniProgramShelfHomeState(
    dynamic raw,
    SharedPreferences sp, {
    required bool persist,
  }) async {
    final parsed = _parseMiniProgramShelfSnapshot(raw);
    if (parsed.isEmpty) return;
    final local = await _loadMiniProgramShelfPrefs(sp);
    final next = _MiniProgramShelfPrefs(
      pinnedIds:
          parsed.pinnedIds.isNotEmpty ? parsed.pinnedIds : local.pinnedIds,
      recentIds:
          parsed.recentIds.isNotEmpty ? parsed.recentIds : local.recentIds,
    );
    if (persist) {
      await _persistMiniProgramShelfPrefs(sp, next);
    }
    if (!mounted) return;
    setState(() {
      _miniProgramShelfPinnedIds = next.pinnedIds;
      _miniProgramShelfRecentIds = next.recentIds;
    });
  }

  Color _miniProgramAccent(String id) {
    switch (id) {
      case 'payments':
        return const Color(0xFF07C160);
      case 'green_paket':
        return const Color(0xFF16A34A);
      case 'cards':
        return const Color(0xFF0F766E);
      case 'moments':
        return const Color(0xFF2563EB);
      case 'favorites':
        return const Color(0xFFF59E0B);
      case 'official_accounts':
        return const Color(0xFF0EA5E9);
      case 'channels':
        return const Color(0xFFEF4444);
      case 'people_nearby':
        return const Color(0xFF14B8A6);
      case 'stickers':
        return const Color(0xFFF97316);
      case 'bus':
        return Tokens.colorBus;
      default:
        return const Color(0xFF64748B);
    }
  }

  void _openMiniProgramDescriptor(MiniAppDescriptor descriptor) {
    final id = (descriptor.runtimeAppId ?? descriptor.id).trim();
    if (id.isEmpty) return;
    _openMod(id);
  }

  Future<void> _showMiniProgramsQuickPanel() async {
    final l = L10n.of(context);
    final all = _sortedMiniProgramDescriptors();
    final byId = <String, MiniAppDescriptor>{
      for (final descriptor in all) descriptor.id: descriptor,
      for (final descriptor in all)
        if ((descriptor.runtimeAppId ?? '').trim().isNotEmpty)
          descriptor.runtimeAppId!.trim(): descriptor,
    };

    List<String> pinnedIds = const <String>[];
    List<String> recentIds = const <String>[];
    try {
      final sp = await SharedPreferences.getInstance();
      final ordered = loadMiniProgramPinnedOrderSync(sp);
      final recentMiniPrograms = loadMiniProgramRecentIdsSync(sp);
      pinnedIds = _cleanMiniProgramIds(<String>[
        ..._miniProgramShelfPinnedIds,
        ...ordered,
      ]);
      recentIds = _cleanMiniProgramIds(<String>[
        ..._miniProgramShelfRecentIds,
        ...recentMiniPrograms,
      ]);
    } catch (_) {}

    final pinnedApps = pinnedIds
        .map((id) => byId[id])
        .whereType<MiniAppDescriptor>()
        .toList(growable: false);
    final recentApps = recentIds
        .map((id) => byId[id])
        .whereType<MiniAppDescriptor>()
        .toList(growable: false);
    final usedIds = <String>{
      for (final descriptor in pinnedApps) descriptor.id,
      for (final descriptor in recentApps) descriptor.id,
    };
    final recommendedApps = all
        .where((descriptor) => !usedIds.contains(descriptor.id))
        .take(6)
        .toList(growable: false);
    final fallbackRecent = all.take(5).toList(growable: false);
    unawaited(_recordModuleUse('mini_programs'));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final theme = Theme.of(ctx);
            final isDark = theme.brightness == Brightness.dark;
            final normalizedQuery = query.trim().toLowerCase();
            final filtered = all.where((descriptor) {
              if (normalizedQuery.isEmpty) return true;
              final titleEn = descriptor.titleEn.toLowerCase();
              final titleAr = descriptor.titleAr.toLowerCase();
              final categoryEn = descriptor.categoryEn.toLowerCase();
              final id = descriptor.id.toLowerCase();
              return titleEn.contains(normalizedQuery) ||
                  titleAr.contains(normalizedQuery) ||
                  categoryEn.contains(normalizedQuery) ||
                  id.contains(normalizedQuery);
            }).toList(growable: false);
            final recent = recentApps.isNotEmpty ? recentApps : fallbackRecent;
            final recommended =
                recommendedApps.isNotEmpty ? recommendedApps : all.take(6);

            Widget miniProgramIcon(MiniAppDescriptor descriptor,
                {double size = 42}) {
              final accent = _miniProgramAccent(descriptor.id);
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? .20 : .12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(descriptor.icon, color: accent, size: size * .48),
              );
            }

            Widget recentTile(MiniAppDescriptor descriptor) {
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openMiniProgramDescriptor(descriptor);
                },
                child: SizedBox(
                  width: 84,
                  child: Column(
                    children: [
                      miniProgramIcon(descriptor, size: 48),
                      const SizedBox(height: 7),
                      Text(
                        descriptor.title(isArabic: l.isArabic),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget directoryTile(MiniAppDescriptor descriptor) {
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                leading: miniProgramIcon(descriptor),
                title: Text(
                  descriptor.title(isArabic: l.isArabic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  descriptor.category(isArabic: l.isArabic),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 15, color: Colors.amber.shade700),
                    const SizedBox(width: 3),
                    Text(
                      descriptor.rating.toStringAsFixed(1),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      l.isArabic ? Icons.chevron_left : Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurface.withValues(alpha: .46),
                    ),
                  ],
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _openMiniProgramDescriptor(descriptor);
                },
              );
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: .78,
              minChildSize: .48,
              maxChildSize: .92,
              builder: (ctx2, scrollController) {
                return SafeArea(
                  top: false,
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      l.isArabic
                                          ? 'البرامج المصغّرة'
                                          : 'Mini Programs',
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: l.isArabic ? 'إدارة' : 'Manage',
                                    onPressed: () {
                                      Navigator.of(ctx).pop();
                                      _openMiniProgramsHub(
                                        openPinnedManage: true,
                                      );
                                    },
                                    icon: const Icon(
                                      Icons.tune_outlined,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                textInputAction: TextInputAction.search,
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: l.isArabic ? 'بحث' : 'Search',
                                  prefixIcon:
                                      const Icon(Icons.search, size: 20),
                                  filled: true,
                                  fillColor: isDark
                                      ? theme
                                          .colorScheme.surfaceContainerHighest
                                          .withValues(alpha: .34)
                                      : const Color(0xFFF3F4F6),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onChanged: (value) {
                                  setLocal(() => query = value);
                                },
                              ),
                              const SizedBox(height: 16),
                              if (pinnedApps.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        l.isArabic
                                            ? 'مثبتة'
                                            : 'Pinned mini programs',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () {
                                        Navigator.of(ctx).pop();
                                        _openMiniProgramsHub(
                                          openPinnedManage: true,
                                        );
                                      },
                                      child: Text(
                                        l.isArabic ? 'تعديل' : 'Edit',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 86,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemBuilder: (_, i) =>
                                        recentTile(pinnedApps[i]),
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemCount: pinnedApps.length,
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                              Text(
                                l.isArabic ? 'الأكثر استخداماً' : 'Recent',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 86,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemBuilder: (_, i) => recentTile(recent[i]),
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 10),
                                  itemCount: recent.length,
                                ),
                              ),
                              if (recommended.isNotEmpty) ...[
                                const SizedBox(height: 14),
                                Text(
                                  l.isArabic ? 'اقتراحات' : 'Recommended',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  height: 86,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemBuilder: (_, i) =>
                                        recentTile(recommended.elementAt(i)),
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemCount: recommended.length,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                      SliverList.separated(
                        itemBuilder: (_, i) => directoryTile(filtered[i]),
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          indent: 74,
                          color: theme.dividerColor,
                        ),
                        itemCount: filtered.length,
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: 18,
                            right: 18,
                            top: 12,
                            bottom: MediaQuery.of(ctx).padding.bottom + 18,
                          ),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _openMiniProgramsHub();
                            },
                            icon: const Icon(Icons.apps_outlined, size: 18),
                            label: Text(
                              l.isArabic
                                  ? 'عرض كل البرامج'
                                  : 'View all mini programs',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMiniProgramsQuickShelf() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final all = _sortedMiniProgramDescriptors();
    final byId = <String, MiniAppDescriptor>{
      for (final descriptor in all) descriptor.id: descriptor,
      for (final descriptor in all)
        if ((descriptor.runtimeAppId ?? '').trim().isNotEmpty)
          descriptor.runtimeAppId!.trim(): descriptor,
    };
    final selectedIds = _cleanMiniProgramIds(<String>[
      ..._miniProgramShelfPinnedIds,
      ..._miniProgramShelfRecentIds,
    ]);
    final apps = <MiniAppDescriptor>[];
    final usedIds = <String>{};
    for (final id in selectedIds) {
      final descriptor = byId[id];
      if (descriptor == null) continue;
      if (!usedIds.add(descriptor.id)) continue;
      apps.add(descriptor);
      if (apps.length >= 4) break;
    }
    for (final descriptor in all) {
      if (apps.length >= 4) break;
      if (!usedIds.add(descriptor.id)) continue;
      apps.add(descriptor);
    }
    if (apps.isEmpty) return const SizedBox.shrink();

    Widget shelfItem(MiniAppDescriptor descriptor) {
      final accent = _miniProgramAccent(descriptor.id);
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => _openMiniProgramDescriptor(descriptor),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? .20 : .12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(descriptor.icon, size: 21, color: accent),
                ),
                const SizedBox(height: 6),
                Text(
                  descriptor.title(isArabic: l.isArabic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    height: 1.08,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: .84),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .50 : .85),
          width: .7,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const ShamellLeadingIcon(
                icon: Icons.widgets_outlined,
                background: Color(0xFF07C160),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.isArabic ? 'البرامج المصغّرة' : 'Mini Programs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l.isArabic
                          ? 'مدفوعات وخدمات ومجتمع في لوحة واحدة'
                          : 'Pay, services and social tools in one panel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .64),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l.isArabic ? 'فتح' : 'Open',
                onPressed: () => unawaited(_showMiniProgramsQuickPanel()),
                icon: const Icon(Icons.grid_view_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(children: [for (final app in apps) shelfItem(app)]),
        ],
      ),
    );
  }

  void _openOfficialAccounts() {
    unawaited(_recordModuleUse('official_accounts'));
    _navPush(
      OfficialAccountsPage(
        baseUrl: _baseUrl,
        onOpenChat: (peerId) {
          if (peerId.trim().isEmpty) return;
          _navPush(ShamellChatPage(baseUrl: _baseUrl, initialPeerId: peerId));
        },
      ),
    );
  }

  void _openServiceNotificationsPage() {
    if (!_caps.serviceNotifications) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'إشعارات الخدمات غير مفعّلة على هذا الخادم.'
                : 'Service notifications are disabled on this server.',
          ),
        ),
      );
      return;
    }
    unawaited(_recordModuleUse('service_notifications'));
    _navPush(
      OfficialTemplateMessagesPage(baseUrl: _baseUrl),
      onReturn: () => unawaited(_loadServiceNotificationsBadge()),
    );
  }

  void _openChannels() {
    unawaited(_recordModuleUse('channels'));
    _navPush(ChannelsPage(baseUrl: _baseUrl, initialHotOnly: true));
  }

  void _openPeopleNearby() {
    unawaited(_recordModuleUse('people_nearby'));
    _navPush(NearbyPage(baseUrl: _baseUrl));
  }

  // `_openShake` removed — duplicates Nearby's surface area; deep-link
  // entries for "shake" / "shake_phone" are translated to People-Nearby
  // by `_openMod` so existing scan codes still land somewhere useful.
  //
  // `_openStickerStore` removed — Sticker Store retired alongside its
  // pack runtime; legacy "stickers" / "sticker_store" mod ids no-op.

  void _openCardsOffers() {
    unawaited(_recordModuleUse('cards'));
    _navPush(CardsOffersPage(baseUrl: _baseUrl));
  }

  void _openGreenPaket({String? initialGreenPaketId}) {
    unawaited(_openGreenPaketAsync(initialGreenPaketId: initialGreenPaketId));
  }

  Future<void> _openGreenPaketAsync({String? initialGreenPaketId}) async {
    final walletId = await _requireWalletIdForPaymentsAction(
      interactive: true,
    );
    if (walletId == null || walletId.trim().isEmpty) return;
    unawaited(_recordModuleUse('green_paket'));
    _navPush(
      GreenPaketPage(
        baseUrl: _baseUrl,
        walletId: walletId,
        deviceId: deviceId,
        initialGreenPaketId: initialGreenPaketId,
        client: widget.client,
      ),
    );
  }

  Future<void> _showInviteQr() async {
    final l = L10n.of(context);
    var showing = false;
    if (mounted) {
      showing = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    try {
      final svc = ChatService(_baseUrl, httpClient: widget.client);
      try {
        await _ensureSessionForOnlineOps(baseUrl: _baseUrl);
        if (_deviceBindingReauthTriggered || !mounted) {
          if (showing && mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          showing = false;
          return;
        }
        final tok = await svc.createContactInviteTokenEnsured(maxUses: 1);
        final payload = buildShamellInviteAppLink(tok).toString();
        if (!mounted) return;
        if (showing) Navigator.of(context, rootNavigator: true).pop();
        showing = false;
        _navPush(
          ShamellMyQrCodePage(
            payload: payload,
            profileName: _profileName,
            // Best practice: invite QR is a bearer-capability; do not display
            // stable identifiers (phone/SyrChat-ID) on this screen.
            profileShamellId: '',
          ),
        );
      } finally {
        svc.close();
      }
    } catch (e) {
      if (shamellIsCriticalAccountSessionError(e)) {
        if (showing && mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        showing = false;
        await _forceReauthDueToDeviceBindingDrift();
        return;
      }
      if (!mounted) return;
      if (showing) Navigator.of(context, rootNavigator: true).pop();
      showing = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_chatOperationErrorForUi(e, isArabic: l.isArabic)),
        ),
      );
    } finally {
      if (mounted && showing) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  /// Tab 2 – Wallet: focused money & payments hub.
  Widget _buildPaymentsTab() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 430;
    final hasWallet = _walletId.isNotEmpty;
    final paymentsEnabled = _caps.payments;
    final isDark = theme.brightness == Brightness.dark;
    final walletSectionBorder = BorderSide(
      color: theme.dividerColor.withValues(alpha: isDark ? .40 : .72),
      width: .7,
    );
    final subtitle = !paymentsEnabled
        ? (l.isArabic
            ? 'المدفوعات غير متاحة على هذا الخادم.'
            : 'Payments are not available on this server.')
        : hasWallet
            ? (l.isArabic
                ? 'إدارة المحفظة، التحويلات، والطلبات في مكان واحد.'
                : 'Manage wallet, transfers, and requests in one place.')
            : (l.isArabic
                ? 'ستظهر المحفظة تلقائياً عند مزامنة حسابك.'
                : 'Wallet appears automatically when your account syncs.');

    Widget walletListSection({
      required List<Widget> children,
      EdgeInsets margin = const EdgeInsets.only(top: 8),
      double dividerIndent = 70,
    }) {
      if (children.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surface.withValues(alpha: isDark ? .84 : .94),
          border: Border(top: walletSectionBorder, bottom: walletSectionBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: .5,
                  indent: dividerIndent,
                  color: theme.dividerColor.withValues(alpha: isDark ? .54 : 1),
                ),
              children[i],
            ],
          ],
        ),
      );
    }

    Widget walletStatusSection() {
      final statusLabel = !paymentsEnabled
          ? (l.isArabic ? 'غير متاح' : 'Unavailable')
          : hasWallet
              ? (l.isArabic ? 'جاهزة' : 'Ready')
              : (l.isArabic ? 'مزامنة' : 'Syncing');
      final statusColor = paymentsEnabled && hasWallet
          ? Tokens.colorPayments
          : theme.colorScheme.onSurface.withValues(alpha: .48);
      return walletListSection(
        margin: const EdgeInsets.only(top: 6),
        dividerIndent: 70,
        children: [
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            minLeadingWidth: 48,
            minVerticalPadding: 6,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: const ShamellLeadingIcon(
              icon: Icons.account_balance_wallet_outlined,
              background: Tokens.colorPayments,
              size: 34,
              iconSize: 19,
            ),
            title: Text(
              'SyrChat Pay',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12.5,
                color: theme.colorScheme.onSurface.withValues(alpha: .60),
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: isDark ? .20 : .12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                statusLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            onTap: hasWallet
                ? _quickP2P
                : () => unawaited(_ensureWalletReady(interactive: true)),
          ),
        ],
      );
    }

    Widget walletHubAction({
      required IconData icon,
      required Color accent,
      required String title,
      required String subtitle,
      required VoidCallback onTap,
    }) {
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        minLeadingWidth: 50,
        minVerticalPadding: compact ? 5 : 6,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        onTap: onTap,
        leading: ShamellLeadingIcon(
          icon: icon,
          background: accent,
          size: compact ? 32 : 34,
          iconSize: compact ? 18 : 19,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            height: 1.20,
            color: theme.colorScheme.onSurface.withValues(alpha: .62),
          ),
        ),
        trailing: Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 20,
          color: theme.colorScheme.onSurface.withValues(alpha: .42),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.only(top: 8, bottom: compact ? 150 : 128),
      children: [
        _tabStagger(
          order: 0,
          child: walletStatusSection(),
        ),
        if (paymentsEnabled && hasWallet)
          _tabStagger(
            order: 1,
            child: _buildCurrencyWalletsSection(
              l: l,
              theme: theme,
              compact: compact,
            ),
          ),
        if (!paymentsEnabled)
          _tabStagger(
            order: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Text(
                l.isArabic
                    ? 'المدفوعات معطّلة حالياً على هذا الخادم.'
                    : 'Payments are currently disabled on this server.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: .76),
                ),
              ),
            ),
          )
        else ...[
          _tabStagger(
            order: 2,
            child: walletListSection(
              margin: const EdgeInsets.only(top: 8),
              dividerIndent: 64,
              children: [
                walletHubAction(
                  icon: Icons.account_balance_wallet_outlined,
                  accent: Tokens.colorPayments,
                  title:
                      l.isArabic ? 'نظرة عامة على المحفظة' : 'Wallet overview',
                  subtitle: l.isArabic
                      ? 'الأرصدة، السجل، والنشاط الأخير في مكان واحد.'
                      : 'Balances, history, and recent activity in one place.',
                  // Used to call `_quickP2P` which lands on the Send tab —
                  // a label/action mismatch operators flagged. The
                  // overview opener defaults to PaymentsPage tab index 0
                  // (PaymentOverviewTab) which is the actual balance +
                  // recent-activity surface.
                  onTap: hasWallet
                      ? _quickWalletOverview
                      : () => unawaited(_ensureWalletReady(interactive: true)),
                ),
                walletHubAction(
                  icon: Icons.qr_code_scanner,
                  accent: const Color(0xFF3B82F6),
                  title: l.qaScanPay,
                  subtitle: l.isArabic
                      ? 'ادفع أو استقبل بسرعة عبر تدفقات QR.'
                      : 'Pay or receive instantly with QR flows.',
                  onTap: hasWallet
                      ? _quickScanPay
                      : () => unawaited(_ensureWalletReady(interactive: true)),
                ),
                walletHubAction(
                  icon: Icons.swap_horiz,
                  accent: const Color(0xFF10B981),
                  title: l.qaP2P,
                  subtitle: l.isArabic
                      ? 'أرسل المال مباشرة إلى محفظة أخرى.'
                      : 'Send money directly to another wallet.',
                  onTap: hasWallet
                      ? _quickP2P
                      : () => unawaited(_ensureWalletReady(interactive: true)),
                ),
                walletHubAction(
                  icon: Icons.add_card_outlined,
                  accent: const Color(0xFFF59E0B),
                  title: l.qaTopup,
                  subtitle: l.isArabic
                      ? 'أضف رصيداً عبر مسار الشحن المدعوم حالياً.'
                      : 'Add funds through the current top-up path.',
                  onTap: hasWallet
                      ? _quickTopup
                      : () => unawaited(_ensureWalletReady(interactive: true)),
                ),
                if (_caps.paymentsBills)
                  walletHubAction(
                    icon: Icons.receipt_long_outlined,
                    accent: const Color(0xFF6366F1),
                    title: l.isArabic ? 'الفواتير' : 'Bills',
                    subtitle: l.isArabic
                        ? 'راجع الفواتير وسوّها من محفظتك.'
                        : 'Review and settle bills from your wallet.',
                    onTap: hasWallet
                        ? () => _navPush(
                              BillsPage(_baseUrl, _walletId, deviceId),
                            )
                        : () =>
                            unawaited(_ensureWalletReady(interactive: true)),
                  ),
                walletHubAction(
                  icon: Icons.history,
                  accent: const Color(0xFF64748B),
                  title: l.historyTitle,
                  subtitle: l.isArabic
                      ? 'راجع التحويلات، الشحنات، والرسوم بالتفصيل.'
                      : 'Review transfers, top-ups, and fees in detail.',
                  onTap: hasWallet
                      ? () => _navPush(
                            HistoryPage(baseUrl: _baseUrl, walletId: _walletId),
                          )
                      : () => unawaited(_ensureWalletReady(interactive: true)),
                ),
                if (_caps.paymentsSonic)
                  walletHubAction(
                    icon: Icons.bolt,
                    accent: const Color(0xFFF97316),
                    title: 'Sonic',
                    subtitle: l.isArabic
                        ? 'استخدم مسار Sonic السريع للدفع.'
                        : 'Use the fast Sonic payment rail.',
                    onTap: hasWallet
                        ? () => _navPush(SonicPayPage(_baseUrl))
                        : () =>
                            unawaited(_ensureWalletReady(interactive: true)),
                  ),
              ],
            ),
          ),
          if (!hasWallet)
            _tabStagger(
              order: 3,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  l.isArabic
                      ? 'المحفظة غير متاحة بعد. ستظهر تلقائياً عند تحديث بيانات الحساب.'
                      : 'Wallet is not available yet. It will appear automatically after account data refreshes.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: .76),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// Tab 3 – Services: main super app hub (existing HomeRoute* layouts).
  Widget _buildServicesTab() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasWallet = _walletId.isNotEmpty;
    if (_shamellStrictUi) {
      final sectionBorder = BorderSide(
        color: theme.dividerColor.withValues(alpha: isDark ? .40 : .72),
        width: .7,
      );
      Icon chevron() => Icon(
            l.isArabic ? Icons.chevron_left : Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: .52),
          );

      Widget discoverListSection({
        required List<Widget> children,
        EdgeInsets margin = const EdgeInsets.only(top: 8),
        double dividerIndent = 72,
      }) {
        if (children.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: margin,
          decoration: BoxDecoration(
            color:
                theme.colorScheme.surface.withValues(alpha: isDark ? .84 : .94),
            border: Border(top: sectionBorder, bottom: sectionBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: .5,
                    indent: dividerIndent,
                    color:
                        theme.dividerColor.withValues(alpha: isDark ? .54 : 1),
                  ),
                children[i],
              ],
            ],
          ),
        );
      }

      Widget discoverTile({
        required IconData icon,
        required Color accent,
        required String title,
        required VoidCallback onTap,
        String? subtitle,
        bool showSubtitle = false,
        bool showUnreadDot = false,
        Widget? trailingPreview,
      }) {
        final leading = ShamellLeadingIcon(
          icon: icon,
          background: accent,
          size: 32,
          iconSize: 18,
          borderRadius: BorderRadius.circular(7),
        );
        final subtitleText = (subtitle ?? '').trim();
        final hasSubtitle = showSubtitle && subtitleText.isNotEmpty;
        final chevronWidget = chevron();
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          minLeadingWidth: 50,
          minVerticalPadding: hasSubtitle ? 5 : 4,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 0,
          ),
          leading: showUnreadDot
              ? Stack(
                  clipBehavior: Clip.none,
                  children: [
                    leading,
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFA5151),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ],
                )
              : leading,
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: hasSubtitle
              ? Text(
                  subtitleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    height: 1.20,
                    color: theme.colorScheme.onSurface.withValues(alpha: .62),
                  ),
                )
              : null,
          trailing: trailingPreview == null
              ? chevronWidget
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    trailingPreview,
                    const SizedBox(width: 6),
                    chevronWidget,
                  ],
                ),
          onTap: onTap,
        );
      }

      Widget discoverSearch() {
        return ShamellSearchBar(
          hintText: l.isArabic
              ? 'البحث في الدردشات والخدمات واللحظات'
              : 'Search chats, services and moments',
          readOnly: true,
          onTap: _openGlobalSearch,
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        );
      }

      Widget momentsPreview() {
        Widget chip(IconData icon, Color color, {bool showDot = false}) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: color.withValues(alpha: .28),
                    width: .7,
                  ),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              if (showDot)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFA5151),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip(Icons.card_giftcard_outlined, const Color(0xFF16A34A)),
            const SizedBox(width: 4),
            chip(Icons.widgets_outlined, const Color(0xFF7C3AED)),
            const SizedBox(width: 4),
            chip(
              Icons.notifications_none_outlined,
              const Color(0xFFEF4444),
              showDot: _hasUnreadServiceNotifications,
            ),
          ],
        );
      }

      Widget miniProgramsPreview() {
        final apps =
            _sortedMiniProgramDescriptors().take(3).toList(growable: false);
        if (apps.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < apps.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _miniProgramAccent(apps[i].id).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color:
                        _miniProgramAccent(apps[i].id).withValues(alpha: .28),
                    width: .7,
                  ),
                ),
                child: Icon(
                  apps[i].icon,
                  size: 15,
                  color: _miniProgramAccent(apps[i].id),
                ),
              ),
            ],
          ],
        );
      }

      // Moments + Official Accounts + Nearby share a single "Discover"
      // card so the social/discovery surfaces sit together at the top
      // of the tab instead of being split across three cards.
      final discoverSocialTiles = <Widget>[
        if (_caps.moments)
          discoverTile(
            icon: Icons.camera_alt_outlined,
            accent: const Color(0xFF07C160),
            title: l.isArabic ? 'اللحظات' : 'Moments',
            subtitle: l.isArabic
                ? 'منشورات الأصدقاء والبرامج المصغّرة والحزمة الخضراء'
                : 'Friends, Mini Program shares and Green Paket updates',
            trailingPreview: momentsPreview(),
            onTap: () => _openMod('moments'),
          ),
        discoverTile(
          icon: Icons.verified_outlined,
          accent: const Color(0xFF2563EB),
          title: l.isArabic ? 'الحسابات الرسمية' : 'Official Accounts',
          subtitle: l.isArabic
              ? 'تابع الخدمات والتجار والتحديثات الرسمية'
              : 'Follow services, merchants and official updates',
          onTap: _openOfficialAccounts,
        ),
        discoverTile(
          icon: Icons.near_me_outlined,
          accent: const Color(0xFF14B8A6),
          title: l.nearbyTitle,
          subtitle: l.isArabic
              ? 'مطاعم، صيدليات، محطات وقود وأكثر بالقرب منك'
              : 'Restaurants, pharmacies, fuel stations and more nearby',
          onTap: _openPeopleNearby,
        ),
      ];

      // Channels tile hidden until the backend `/channels/*` endpoints
      // ship a working hot-clip feed — today they return 404, which
      // surfaces in-app as an alarming "404: not found" toast and
      // makes the whole Discover tab feel broken. Re-enable here once
      // the BFF route is live and the page loads cleanly.
      // "Shake" was retired — Nearby covers the same surface (and
      // already includes the same OSM categories), so two entry
      // points for one feature was confusing. "Sticker Store" was
      // retired alongside the legacy sticker pack runtime.
      final discoverScanTiles = <Widget>[
        if (_pluginShowScan)
          discoverTile(
            icon: Icons.qr_code_scanner,
            accent: const Color(0xFF3B82F6),
            title: l.shamellChannelScanTitle,
            subtitle: l.isArabic
                ? 'امسح QR للدفع أو تسجيل الدخول أو فتح خدمة'
                : 'Scan QR to pay, sign in or open a service',
            onTap: () => unawaited(_openShamellScanAndHandle()),
          ),
      ];

      final miniProgramCount =
          MiniAppRegistry.descriptors.where((d) => d.enabled).length;
      // Count enabled Gaming-category mini-programs so the Discover
      // tile can show "N games inside SyrChat" instead of a static
      // string. The Gaming directory currently lists Jump-Jump as
      // the first member; future games (e.g. memory, snake) drop in
      // by adding a sibling `_MiniAppRegistration` with
      // `categoryEn: 'Gaming'`.
      final gamingCount = MiniAppRegistry.descriptors
          .where((d) => d.enabled && d.categoryEn == 'Gaming')
          .length;
      final discoverPlatformTiles = <Widget>[
        discoverTile(
          icon: Icons.widgets_outlined,
          accent: const Color(0xFF7C3AED),
          title: l.isArabic ? 'البرامج المصغّرة' : 'Mini Programs',
          subtitle: l.isArabic
              ? '$miniProgramCount خدمة داخل سرتشات'
              : '$miniProgramCount services inside SyrChat',
          trailingPreview: miniProgramsPreview(),
          onTap: () => unawaited(_showMiniProgramsQuickPanel()),
        ),
        // New "Gaming" category — opens the Mini Programs directory
        // pre-filtered to gaming-category mini-apps. The Jump-Jump
        // WeChat-style 跳一跳 entry is the first member.
        if (gamingCount > 0)
          discoverTile(
            icon: Icons.sports_esports_outlined,
            accent: const Color(0xFFFF6B6B),
            title: l.isArabic ? 'الألعاب' : 'Gaming',
            subtitle: l.isArabic
                ? 'ألعاب صغيرة بأسلوب WeChat — استمتع بسرعة'
                : 'WeChat-style mini-games — quick casual fun',
            onTap: _openGamingMiniPrograms,
          ),
        // Official Accounts moved up to the Moments/Nearby card so
        // the social/discovery surfaces sit together.
        if (_caps.serviceNotifications)
          discoverTile(
            icon: Icons.notifications_none_outlined,
            accent: const Color(0xFF07C160),
            title: l.isArabic ? 'إشعارات الخدمات' : 'Service notifications',
            subtitle: l.isArabic
                ? 'رسائل القوالب والتنبيهات من الحسابات الرسمية'
                : 'Template messages and account updates',
            showUnreadDot: _hasUnreadServiceNotifications,
            onTap: _openServiceNotificationsPage,
          ),
      ];

      final discoverPaymentsTiles = <Widget>[
        discoverTile(
          icon: Icons.card_giftcard_outlined,
          accent: const Color(0xFF07C160),
          title: l.isArabic ? 'الحزمة الخضراء' : 'Green Paket',
          subtitle: l.isArabic
              ? 'هدايا دفع اجتماعية داخل الدردشات واللحظات'
              : 'Social payment gifts for chats and Moments',
          onTap: () => _openGreenPaket(),
        ),
        discoverTile(
          icon: Icons.local_offer_outlined,
          accent: const Color(0xFF0F766E),
          title: l.isArabic ? 'البطاقات والعروض' : 'Cards & Offers',
          subtitle: l.isArabic
              ? 'قسائم وبطاقات عضوية من الحسابات الرسمية'
              : 'Coupons and member cards from official accounts',
          onTap: () => _openMod('cards'),
        ),
        discoverTile(
          icon: Icons.bookmark_added_outlined,
          accent: const Color(0xFFF59E0B),
          title: l.shamellChannelFavoritesTitle,
          subtitle: l.isArabic
              ? 'الرسائل والخدمات والعناصر المحفوظة'
              : 'Saved messages, services and useful items',
          onTap: () => _openMod('favorites'),
        ),
      ];

      // Taxi + Coach Bus removed from Discover as standalone cards —
      // both now live exclusively under Mini Programs (see
      // `MiniAppRegistry`: `bus` + `ride` entries) so mobility lives
      // with the rest of the mini-program surface and Discover stays
      // focused on social/payments/platform shelves.

      final discoverSections = <List<Widget>>[
        discoverSocialTiles,
        discoverScanTiles,
        discoverPlatformTiles,
        discoverPaymentsTiles,
      ].where((section) => section.isNotEmpty).toList(growable: false);

      return ListView(
        padding: EdgeInsets.only(
          top: 8,
          bottom: _liquidBottomChromePadding(context) + 16,
        ),
        children: [
          _tabStagger(
            order: 0,
            child: discoverSearch(),
          ),
          _tabStagger(
            order: 1,
            child: _buildMiniProgramsQuickShelf(),
          ),
          if (!kEnduserOnly && _showSuperadmin)
            _tabStagger(
              order: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Builder(
                  builder: (context) {
                    final hasOps = _allowsOpsWorkbench;
                    final hasAdmin = _allowsAdminWorkbench;
                    final isSuper = _showSuperadmin;
                    final allowSwitch = isSuper;
                    return Row(
                      children: [
                        _RoleChip(
                          mode: AppMode.user,
                          current: _appMode,
                          onTap: () => _changeAppMode(AppMode.user),
                          enabled: allowSwitch || _appMode == AppMode.user,
                        ),
                        const SizedBox(width: 8),
                        _RoleChip(
                          mode: AppMode.operator,
                          current: _appMode,
                          onTap: () => _changeAppMode(AppMode.operator),
                          enabled: allowSwitch && hasOps,
                        ),
                        const SizedBox(width: 8),
                        _RoleChip(
                          mode: AppMode.admin,
                          current: _appMode,
                          onTap: () => _changeAppMode(AppMode.admin),
                          enabled: allowSwitch && hasAdmin,
                        ),
                        const SizedBox(width: 8),
                        _SuperadminChip(
                          selected: isSuper && _appMode == AppMode.admin,
                          enabled: allowSwitch && isSuper,
                          onTap: () {
                            if (!isSuper || !allowSwitch) return;
                            _changeAppMode(AppMode.admin);
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          for (var i = 0; i < discoverSections.length; i++)
            _tabStagger(
              order: 3 + i,
              child: discoverListSection(
                margin: EdgeInsets.only(top: i == 0 ? 8 : 10),
                children: discoverSections[i],
              ),
            ),
        ],
      );
    }
    return Column(
      children: [
        if (!kEnduserOnly && _showSuperadmin)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Builder(
              builder: (context) {
                final hasOps = _allowsOpsWorkbench;
                final hasAdmin = _allowsAdminWorkbench;
                final isSuper = _showSuperadmin;
                final allowSwitch = isSuper;
                return Row(
                  children: [
                    _RoleChip(
                      mode: AppMode.user,
                      current: _appMode,
                      onTap: () => _changeAppMode(AppMode.user),
                      enabled: allowSwitch || _appMode == AppMode.user,
                    ),
                    const SizedBox(width: 8),
                    _RoleChip(
                      mode: AppMode.operator,
                      current: _appMode,
                      onTap: () => _changeAppMode(AppMode.operator),
                      enabled: allowSwitch && hasOps,
                    ),
                    const SizedBox(width: 8),
                    _RoleChip(
                      mode: AppMode.admin,
                      current: _appMode,
                      onTap: () => _changeAppMode(AppMode.admin),
                      enabled: allowSwitch && hasAdmin,
                    ),
                    const SizedBox(width: 8),
                    _SuperadminChip(
                      selected: isSuper && _appMode == AppMode.admin,
                      enabled: allowSwitch && isSuper,
                      onTap: () {
                        if (!isSuper || !allowSwitch) return;
                        _changeAppMode(AppMode.admin);
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        // SyrChat-like primary Discover list: updates, scan, and official
        // account surfaces.
        ShamellSection(
          margin: const EdgeInsets.only(top: 8),
          children: [
            if (_pluginShowScan)
              ListTile(
                dense: true,
                leading: const ShamellLeadingIcon(
                  icon: Icons.qr_code_scanner,
                  background: Color(0xFF3B82F6),
                ),
                title: Text(l.shamellChannelScanTitle),
                subtitle: Text(l.shamellChannelScanSubtitle),
                trailing: Icon(
                  l.isArabic ? Icons.chevron_left : Icons.chevron_right,
                ),
                onTap: () {
                  unawaited(_openShamellScanAndHandle());
                },
              ),
          ],
        ),
        if (_walletId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _appMode == AppMode.operator
                              ? (L10n.of(context).isArabic
                                  ? 'محفظة المشغل'
                                  : 'Operator wallet')
                              : L10n.of(context).homeWallet,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _walletHidden
                              ? '••••••'
                              : (_walletBalanceCents == null
                                  ? (_walletLoading
                                      ? (L10n.of(context).isArabic
                                          ? 'جارٍ التحميل…'
                                          : 'Loading…')
                                      : (L10n.of(context).isArabic
                                          ? 'الرصيد غير متاح'
                                          : 'Balance unavailable'))
                                  : '${fmtCents(_walletBalanceCents!)} $_walletCurrency'),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _walletHidden ? 'Show balance' : 'Hide balance',
                    icon: Icon(
                      _walletHidden
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () {
                      setState(() => _walletHidden = !_walletHidden);
                    },
                  ),
                ],
              ),
            ),
          ),
        if (_walletId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: PayActionButton(
                    icon: Icons.qr_code_scanner,
                    label: l.qaScanPay,
                    onTap: _quickScanPay,
                    tint: Tokens.colorPayments,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PayActionButton(
                    icon: Icons.swap_horiz,
                    label: l.qaP2P,
                    onTap: _quickP2P,
                    tint: Tokens.colorPayments,
                  ),
                ),
              ],
            ),
          ),
        if (_walletId.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: PayActionButton(
                    icon: Icons.account_balance_wallet_outlined,
                    label: l.qaTopup,
                    onTap: _quickTopup,
                    tint: Tokens.colorPayments,
                  ),
                ),
                if (_caps.paymentsSonic) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: PayActionButton(
                      icon: Icons.bolt,
                      label: 'Sonic',
                      onTap: () => _navPush(SonicPayPage(_baseUrl)),
                      tint: Tokens.colorPayments,
                    ),
                  ),
                ],
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.shamellTabChannel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              // SyrChat-like “Discover” strip: lightweight promos to key modules.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildDiscoverPromoChip(
                      icon: Icons.search_outlined,
                      label: l.isArabic ? 'البحث' : 'Search',
                      onTap: _openGlobalSearch,
                    ),
                    if (_caps.moments)
                      _buildDiscoverPromoChip(
                        icon: Icons.camera_alt_outlined,
                        label: l.isArabic ? 'اللحظات' : 'Moments',
                        onTap: () => _openMod('moments'),
                      ),
                    _buildDiscoverPromoChip(
                      icon: Icons.widgets_outlined,
                      label: l.isArabic ? 'البرامج' : 'Mini Programs',
                      onTap: _openMiniProgramsHub,
                    ),
                    _buildDiscoverPromoChip(
                      icon: Icons.verified_outlined,
                      label: l.isArabic ? 'الرسمية' : 'Official',
                      onTap: _openOfficialAccounts,
                    ),
                    // Channels promo chip removed (see `discoverTile`
                    // comment above) until the backend endpoints stop
                    // 404-ing.
                    _buildDiscoverPromoChip(
                      icon: Icons.card_giftcard_outlined,
                      label: l.isArabic ? 'حزمة خضراء' : 'Green Paket',
                      onTap: () => _openGreenPaket(),
                    ),
                    _buildDiscoverPromoChip(
                      icon: Icons.near_me_outlined,
                      label: l.isArabic ? 'بالقرب' : 'Nearby',
                      onTap: _openPeopleNearby,
                    ),
                    // "Shake" + "Sticker Store" retired (Nearby covers
                    // the same OSM-driven surface). Taxi + Coach bus
                    // live exclusively under Mini Programs now (see
                    // `MiniAppRegistry`: `ride` + `bus`); both still
                    // reachable via deep-link mods + the directory.
                    if (_walletId.isNotEmpty && _caps.payments)
                      _buildDiscoverPromoChip(
                        icon: Icons
                            .qr_code_scanner, // mirrors Wallet “Scan & pay”
                        label: l.isArabic ? 'امسح للدفع' : 'Scan & pay',
                        onTap: _quickScanPay,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildHomeRoute()),
      ],
    );
  }

  /// Tab 4 – Me: profile, journey, settings and ops/admin tools.
  Widget _buildMeTab() {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;
    String avatarInitial() {
      final n = _profileName.trim();
      if (n.isNotEmpty) {
        return n.characters.first.toUpperCase();
      }
      final p = _profilePhone.trim();
      if (p.isNotEmpty) {
        return p.characters.last;
      }
      return '?';
    }

    final displayName =
        _profileName.trim().isNotEmpty ? _profileName.trim() : l.menuProfile;
    final shamellId = _profileShamellId.trim();
    final hasWallet = _walletId.trim().isNotEmpty;
    final shamellLabel = l.isArabic ? 'معرّف SyrChat' : 'SyrChat ID';
    final profileSubtitle = shamellId.isNotEmpty
        ? (l.isArabic
            ? '$shamellLabel: $shamellId'
            : '$shamellLabel: $shamellId')
        : (l.isArabic
            ? 'ملفك وإعداداتك في مكان مطمئن'
            : 'Your profile and settings in one calm place');

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .52),
        );

    final meSectionBorder = BorderSide(
      color: theme.dividerColor.withValues(alpha: isDark ? .40 : .72),
      width: .7,
    );

    Widget meListSection({
      required List<Widget> children,
      EdgeInsets margin = const EdgeInsets.only(top: 10),
      double dividerIndent = 72,
    }) {
      if (children.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surface.withValues(alpha: isDark ? .84 : .94),
          border: Border(top: meSectionBorder, bottom: meSectionBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: .5,
                  indent: dividerIndent,
                  color: theme.dividerColor.withValues(alpha: isDark ? .54 : 1),
                ),
              children[i],
            ],
          ],
        ),
      );
    }

    Widget meProfileHero() {
      final initial = avatarInitial();
      final hasInitial = initial != '?';
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surface.withValues(alpha: isDark ? .84 : .94),
          border: Border(
            top: meSectionBorder,
            bottom: meSectionBorder,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _navPush(ProfilePage(_baseUrl)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: ShamellPalette.green.withValues(
                        alpha: isDark ? .18 : .10,
                      ),
                    ),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: hasInitial
                            ? Text(
                                initial,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.onSurface,
                                ),
                              )
                            : Icon(
                                Icons.person_outline,
                                size: 28,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: .68,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        shamellId.isNotEmpty
                            ? '$shamellLabel: $shamellId'
                            : (_profilePhone.trim().isNotEmpty
                                ? _profilePhone.trim()
                                : profileSubtitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: .68,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l.isArabic ? 'رمز SyrChat' : 'My QR code',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(_showInviteQr()),
                  icon: Icon(
                    Icons.qr_code_2_outlined,
                    color: theme.colorScheme.onSurface.withValues(alpha: .70),
                  ),
                ),
                chevron(),
              ],
            ),
          ),
        ),
      );
    }

    if (_shamellStrictUi) {
      return Container(
        color: bgColor,
        child: ListTileTheme.merge(
          dense: true,
          visualDensity: VisualDensity.compact,
          minLeadingWidth: 50,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
          child: ListView(
            padding: EdgeInsets.only(
              top: 8,
              bottom: _liquidBottomChromePadding(context) + 24,
            ),
            children: [
              _tabStagger(
                order: 0,
                child: meProfileHero(),
              ),
              // "Me" tab cleanup: tiles that duplicated Discover/Wallet
              // were removed to keep this surface focused on identity /
              // device-local actions. The retired tiles (and where they
              // now live exclusively):
              //   • SyrChat Pay         → Wallet tab
              //   • Green Paket         → Discover tab
              //   • Favorites           → Discover tab
              //   • Mini Programs       → Discover tab
              //   • Official Accounts   → Discover tab
              //   • Nearby              → Discover tab
              _tabStagger(
                order: 1,
                child: meListSection(
                  margin: const EdgeInsets.only(top: 10),
                  children: [
                    ListTile(
                      dense: true,
                      leading: const ShamellLeadingIcon(
                        icon: Icons.qr_code_2_outlined,
                        background: Color(0xFF111827),
                      ),
                      title: Text(l.isArabic ? 'رمزي' : 'My QR'),
                      trailing: chevron(),
                      onTap: () => unawaited(_showInviteQr()),
                    ),
                    ListTile(
                      dense: true,
                      leading: const ShamellLeadingIcon(
                        icon: Icons.devices_other_outlined,
                        background: Color(0xFF2563EB),
                      ),
                      title: Text(l.isArabic ? 'الأجهزة' : 'Devices'),
                      trailing: chevron(),
                      onTap: () => _navPush(DevicesPage(baseUrl: _baseUrl)),
                    ),
                    if (_caps.moments)
                      ListTile(
                        dense: true,
                        leading: const ShamellLeadingIcon(
                          icon: Icons.camera_alt_outlined,
                          background: Color(0xFF07C160),
                        ),
                        title: Text(l.isArabic ? 'اللحظات' : 'Moments'),
                        trailing: chevron(),
                        onTap: () => _openMod('moments'),
                      ),
                  ],
                ),
              ),
              if (!kEnduserOnly && _showOps)
                _tabStagger(
                  order: 3,
                  child: meListSection(
                    margin: const EdgeInsets.only(top: 10),
                    children: [
                      ListTile(
                        dense: true,
                        leading: const ShamellLeadingIcon(
                          icon: Icons.layers_outlined,
                          background: Color(0xFF475569),
                        ),
                        title: Text(l.menuSwitchMode),
                        trailing: chevron(),
                        onTap: _showModeSheet,
                      ),
                      if (!kEnduserOnly && _allowsAdminWorkbench)
                        ListTile(
                          dense: true,
                          leading: const ShamellLeadingIcon(
                            icon: Icons.admin_panel_settings_outlined,
                            background: Color(0xFF0F766E),
                          ),
                          title: Text(l.menuAdminConsole),
                          trailing: chevron(),
                          onTap: () => _navPush(AdminDashboardPage(_baseUrl)),
                        ),
                      if (!kEnduserOnly && _showSuperadmin)
                        ListTile(
                          dense: true,
                          leading: const ShamellLeadingIcon(
                            icon: Icons.security_outlined,
                            background: Color(0xFF7F1D1D),
                          ),
                          title: Text(l.menuSuperadminConsole),
                          trailing: chevron(),
                          onTap: () => _navPush(
                            SuperadminDashboardPage(
                              _baseUrl,
                              walletId: _walletId,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              _tabStagger(
                order: 4,
                child: meListSection(
                  margin: const EdgeInsets.only(top: 10),
                  children: [
                    ListTile(
                      dense: true,
                      leading: const ShamellLeadingIcon(
                        icon: Icons.settings_outlined,
                        background: Color(0xFF64748B),
                      ),
                      title: Text(l.settingsTitle),
                      trailing: chevron(),
                      onTap: _openShamellSettings,
                    ),
                    ListTile(
                      dense: true,
                      leading: const ShamellLeadingIcon(
                        icon: Icons.help_outline,
                        background: Color(0xFF0EA5E9),
                      ),
                      title: Text(l.isArabic ? 'دليل سريع' : 'Quick guide'),
                      trailing: chevron(),
                      onTap: _openOnboarding,
                    ),
                    ListTile(
                      dense: true,
                      leading: const ShamellLeadingIcon(
                        icon: Icons.shield_outlined,
                        background: Color(0xFF16A34A),
                      ),
                      title: Text(l.menuEmergency),
                      trailing: chevron(),
                      onTap: _showEmergency,
                    ),
                    ListTile(
                      dense: true,
                      leading: const ShamellLeadingIcon(
                        icon: Icons.report_problem_outlined,
                        background: Color(0xFFF97316),
                      ),
                      title: Text(l.menuComplaints),
                      trailing: chevron(),
                      onTap: _showComplaints,
                    ),
                    ListTile(
                      dense: true,
                      leading: ShamellLeadingIcon(
                        icon: Icons.logout,
                        background:
                            theme.colorScheme.error.withValues(alpha: .90),
                      ),
                      title: Text(
                        l.menuLogout,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error.withValues(alpha: .92),
                        ),
                      ),
                      trailing: chevron(),
                      onTap: _logout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: bgColor,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  child: Text(
                    avatarInitial(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        shamellId.isNotEmpty
                            ? '$shamellLabel: $shamellId'
                            : (_profilePhone.trim().isNotEmpty
                                ? _profilePhone.trim()
                                : (l.isArabic
                                    ? 'عرض بيانات الحساب والمحفظة'
                                    : 'View your account and wallet details')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: .70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.qr_code_2_outlined),
                  onPressed: () => unawaited(_showInviteQr()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l.isArabic ? 'الحساب والخدمات' : 'Account & services',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          const SizedBox(height: 8),
          if (_caps.officialAccounts)
            ListTile(
              dense: true,
              leading: const Icon(Icons.notifications_none_outlined),
              title: Text(
                l.isArabic
                    ? 'إشعارات الحسابات الرسمية'
                    : 'Official notifications',
              ),
              subtitle: Text(
                l.isArabic
                    ? 'تعيين وضع الإشعارات لحساباتك الرسمية'
                    : 'Set notification mode for your official accounts',
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: _openOfficialNotifications,
            ),
          const SizedBox(height: 12),
          Text(
            l.isArabic ? 'المحتوى والتحديثات' : 'Content & updates',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            dense: true,
            leading: const Icon(Icons.bookmark_outline),
            title: Text(l.isArabic ? 'المفضلة' : 'Favorites'),
            subtitle: Text(
              l.isArabic
                  ? 'احفظ الروابط أو الملاحظات المهمة'
                  : 'Save important links or notes',
            ),
            onTap: () {
              _navPush(FavoritesPage(baseUrl: _baseUrl));
            },
          ),
          const SizedBox(height: 12),
          if (_walletId.isNotEmpty)
            Text(
              l.isArabic ? 'المحفظة والحملات' : 'Wallet & campaigns',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
          if (_walletId.isNotEmpty) const SizedBox(height: 4),
          if (_walletId.isNotEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.qr_code_2_outlined),
                    title: Text(
                      l.isArabic ? 'رمز الدفع الخاص بي' : 'My pay code',
                    ),
                    subtitle: Text(
                      l.isArabic
                          ? 'عرض رمز QR لاستلام المدفوعات عبر SyrChat Pay، مشابه لرمز SyrChat Pay.'
                          : 'Show a QR code to receive payments via SyrChat Pay, similar to a SyrChat Pay money code.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _navPush(
                        PaymentsPage(
                          _baseUrl,
                          _walletId,
                          deviceId,
                          initialSection: 'receive',
                          initialCurrency: _walletCurrency,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            l.isArabic ? 'الإعدادات والمساعدة' : 'Settings & help',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: Text(l.isArabic ? 'دليل سريع' : 'Quick guide'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openOnboarding,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings),
                  title: Text(l.settingsTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openShamellSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.isArabic ? 'الدعم والسلامة' : 'Support & safety',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface.withValues(alpha: .80),
            ),
          ),
          const SizedBox(height: 4),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text(l.menuEmergency),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showEmergency,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.report_problem_outlined),
                  title: Text(l.menuComplaints),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showComplaints,
                ),
              ],
            ),
          ),
          if (!kEnduserOnly && _showOps) ...[
            const SizedBox(height: 12),
            Text(
              l.isArabic ? 'لوحة المشغل والمسؤول' : 'Ops & admin workbench',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: .80),
              ),
            ),
            const SizedBox(height: 4),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.layers_outlined),
                    title: Text(l.menuSwitchMode),
                    subtitle: Text(
                      l.isArabic
                          ? 'التبديل بين مستخدم / مشغل / مسؤول'
                          : 'Switch between user / operator / admin modes',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _showModeSheet,
                  ),
                  if (!kEnduserOnly && _allowsAdminWorkbench)
                    const Divider(height: 1),
                  if (!kEnduserOnly && _allowsAdminWorkbench)
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: Text(l.menuAdminConsole),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _navPush(AdminDashboardPage(_baseUrl));
                      },
                    ),
                  if (!kEnduserOnly && _showSuperadmin)
                    const Divider(height: 1),
                  if (!kEnduserOnly && _showSuperadmin)
                    ListTile(
                      leading: const Icon(Icons.security),
                      title: Text(l.menuSuperadminConsole),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _navPush(
                          SuperadminDashboardPage(
                            _baseUrl,
                            walletId: _walletId,
                          ),
                        );
                      },
                    ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.opsTitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: .80,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildOpsWorkbenchShortcuts(context),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(l.menuLogout),
            subtitle: Text(
              l.menuLogoutSubtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            onTap: _logout,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              Icons.delete_forever,
              color: theme.colorScheme.error.withValues(alpha: .90),
            ),
            title: Text(
              l.menuLogoutForgetDevice,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error.withValues(alpha: .90),
              ),
            ),
            subtitle: Text(
              l.menuLogoutForgetDeviceSubtitle,
              style: theme.textTheme.bodySmall,
            ),
            onTap: _logoutForgetDevice,
          ),
        ],
      ),
    );
  }

  /// Compact SyrChat‑style grid of operator / admin shortcuts inside Me tab.
  Widget _buildOpsWorkbenchShortcuts(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    Widget tile({
      required IconData icon,
      required String label,
      required Color tint,
      required VoidCallback onTap,
    }) {
      return SizedBox(
        width: 88,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 24, color: tint.withValues(alpha: .95)),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    final shortcuts = <Widget>[];
    void showAdminLaunchError() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'تعذّر فتح صفحة الإدارة.'
                : 'Could not open the admin page.',
          ),
        ),
      );
    }

    Future<void> openTrustedAdminPath(List<String> pathSegments) async {
      final uri = shamellTrustedWebChildUri(
        baseUrl: _baseUrl,
        pathSegments: pathSegments,
      );
      if (uri == null) {
        showAdminLaunchError();
        return;
      }
      await launchWithSession(uri);
    }

    // Parametrics stays as the only extra web console here; risk/exports
    // already exist inside the Ops page itself.
    if (_allowsAdminWorkbench || _showSuperadmin) {
      shortcuts.add(
        tile(
          icon: Icons.analytics_outlined,
          label: l.isArabic ? 'المقاييس' : 'Parametrics',
          tint: Tokens.colorPayments,
          onTap: () {
            openTrustedAdminPath(const ['admin', 'overview']);
          },
        ),
      );
    }

    if (shortcuts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(spacing: 12, runSpacing: 12, children: shortcuts);
  }

  void _openOnboarding() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OnboardingPage()));
  }

  Future<void> _loadUnreadBadge() async {
    try {
      final unreadMap = await _chatStore.loadUnread(
        baseUrlOverride: _localStateBaseUrlOverride(),
      );
      final total = unreadMap.values.fold<int>(
        0,
        (sum, v) => sum + (v < 0 ? 1 : v),
      );
      if (!mounted) return;
      setState(() {
        _totalUnreadChats = total;
      });
    } catch (_) {}
  }

  Future<void> _loadServiceNotificationsBadge() async {
    if (!_caps.serviceNotifications) return;
    bool cached = false;
    try {
      cached = await _chatStore.loadServiceNotificationsHasUnread(
        baseUrlOverride: _localStateBaseUrlOverride(),
      );
    } catch (_) {}
    if (mounted && cached != _hasUnreadServiceNotifications) {
      setState(() {
        _hasUnreadServiceNotifications = cached;
      });
    }
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      // Lightweight probe: ask backend for unread-only template messages
      // and treat a non-empty list as "has unread service notifications".
      final uri = _homeApiUri(
        pathSegments: const <String>['me', 'official_template_messages'],
        queryParameters: const <String, String>{
          'unread_only': 'true',
          'limit': '1',
        },
      );
      if (uri == null) {
        return;
      }
      final r = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_startupDataRequestTimeout);
      if (r.statusCode < 200 || r.statusCode >= 300) {
        if (shamellIsCriticalAccountSessionHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          await _forceReauthDueToDeviceBindingDrift();
        }
        return;
      }
      final decoded = jsonDecode(r.body);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['messages'] is List) {
        raw = decoded['messages'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final hasUnread = raw.isNotEmpty;
      if (!mounted) return;
      setState(() {
        _hasUnreadServiceNotifications = hasUnread;
      });
      try {
        await _chatStore.saveServiceNotificationsHasUnread(
          hasUnread,
          baseUrlOverride: _localStateBaseUrlOverride(),
        );
      } catch (_) {}
    } catch (e) {
      await _handleCriticalAccountSessionError(e);
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _loadPrefs({bool refreshOnline = true}) async {
    final sp = await SharedPreferences.getInstance();
    final fallbackBaseUrl = normalizeSecureApiBaseUrl(
          const String.fromEnvironment(
            'BASE_URL',
            defaultValue: 'https://api.shamell.online',
          ),
        ) ??
        'https://api.shamell.online';
    final fallbackHost = Uri.tryParse(fallbackBaseUrl)?.host ?? '';
    final hasReachableFallback =
        fallbackBaseUrl.isNotEmpty && !isLocalhostHost(fallbackHost);

    final rawStoredBaseUrl = sp.getString('base_url') ?? '';
    var storedBaseUrl = preferredConfiguredApiBaseUrl(
          storedBaseUrl: rawStoredBaseUrl,
          fallbackBaseUrl: fallbackBaseUrl,
        ) ??
        '';
    final normalizedStoredBaseUrl =
        normalizeSecureApiBaseUrl(rawStoredBaseUrl.trim()) ?? '';
    final explicitBaseOverride = normalizeSecureApiBaseUrl(
      (widget.baseUrlOverride ?? '').trim(),
    );
    if (hasReachableFallback &&
        storedBaseUrl.isNotEmpty &&
        storedBaseUrl != normalizedStoredBaseUrl &&
        (explicitBaseOverride == null || explicitBaseOverride.isEmpty)) {
      try {
        await sp.setString('base_url', storedBaseUrl);
      } catch (_) {}
    }
    final runtimeBaseUrl =
        explicitBaseOverride != null && explicitBaseOverride.isNotEmpty
            ? explicitBaseOverride
            : storedBaseUrl;
    final storedPrivileges = await loadAccountPrivilegeSnapshotForBaseUrl(
      runtimeBaseUrl,
      sp: sp,
    );
    final storedMode = await loadStoredAppModePreference(
      sp: sp,
      baseUrlOverride: runtimeBaseUrl,
    );
    final storedProfile = await loadLegacyProfileSummary(
      sp: sp,
      baseUrlOverride: runtimeBaseUrl,
    );
    final shamellUserId =
        await loadShamellUserId(sp: sp, baseUrlOverride: runtimeBaseUrl) ?? '';
    final storedWalletId = await loadStoredWalletId(
      sp: sp,
      baseUrlOverride: runtimeBaseUrl,
    );
    final miniProgramShelfPrefs = await _loadMiniProgramShelfPrefs(sp);
    final pluginShowScan = await loadScopedPluginVisibilityPreference(
      key: _kShamellPluginShowScan,
      fallback: true,
      sp: sp,
      baseUrlOverride: runtimeBaseUrl,
    );
    // Best practice: start fail-closed and do not trust persisted capability
    // toggles to enable unfinished/internal modules. Capabilities are only
    // enabled via the cached/online `/me/home_snapshot`.
    final storedCaps = ShamellCapabilities.conservativeDefaults;
    // Start from lockedMode when provided; otherwise from currentAppMode and prefs.
    AppMode appMode =
        widget.lockedMode == AppMode.auto ? currentAppMode : widget.lockedMode;
    if (widget.lockedMode == AppMode.auto && storedMode != null) {
      appMode = storedMode;
    }
    final effectiveMode = kEnduserOnly ? AppMode.user : appMode;
    setState(() {
      _baseUrl = runtimeBaseUrl;
      _walletId = storedWalletId ?? _walletId;
      _pluginShowScan = pluginShowScan;
      _caps = storedCaps;
      _appMode = effectiveMode;
      _applyPrivilegeSnapshotHomeState(
        storedPrivileges,
        effectiveMode,
        hideWorkbench: kEnduserOnly,
      );
      _profileName = storedProfile.name;
      _profilePhone = storedProfile.phone;
      _profileShamellId = shamellUserId;
      _miniProgramShelfPinnedIds = miniProgramShelfPrefs.pinnedIds;
      _miniProgramShelfRecentIds = miniProgramShelfPrefs.recentIds;
    });
    shamellSetActiveBootstrapBaseUrl(_baseUrl);
    // Configure remote metrics after loading prefs
    final metricsRemote = await Perf.loadRemotePreference(
      sp: sp,
      baseUrlOverride: runtimeBaseUrl,
    );
    Perf.configure(
      baseUrl: _baseUrl,
      deviceId: deviceId,
      remote: metricsRemote,
    );
    if (!refreshOnline) return;
    // Ensure we have an authenticated session for account-scoped endpoints
    // (contacts invite QR, profile snapshots, etc.).
    final bootstrappedHomeSnapshot = await _ensureSessionForOnlineOps(
      baseUrl: runtimeBaseUrl,
    );
    if (_deviceBindingReauthTriggered || !mounted) return;
    await _completeOnlineHomeStartup(
      sp,
      appMode,
      bootstrappedHomeSnapshot: bootstrappedHomeSnapshot,
    );
  }

  Future<void> _completeOnlineHomeStartup(
    SharedPreferences sp,
    AppMode appMode, {
    required bool bootstrappedHomeSnapshot,
  }) async {
    // Optional: apply the cached snapshot so Home paints something useful
    // immediately even before the remaining startup reads finish.
    try {
      final cachedRaw = await loadCachedHomeSnapshotRaw(
        sp: sp,
        baseUrlOverride: _baseUrl,
      );
      if (cachedRaw != null && cachedRaw.isNotEmpty) {
        final cached = jsonDecode(cachedRaw) as Map<String, dynamic>;
        await _applyHomeSnapshot(cached, sp, appMode, persist: false);
      }
    } catch (_) {}
    await _refreshHomeStartupState(
      sp,
      appMode,
      skipHomeSnapshotRefresh: bootstrappedHomeSnapshot,
    );
  }

  Future<bool> _ensureSessionForOnlineOps({
    required String baseUrl,
    bool force = false,
  }) async {
    final base = baseUrl.trim();
    if (base.isEmpty || !isSecureApiBaseUrl(base)) return false;
    if (_deviceBindingReauthTriggered) return false;
    if (_sessionBootstrapInFlight) return false;

    final now = DateTime.now();
    final lastAttempt = _sessionBootstrapLastAttemptAt;
    if (!force &&
        lastAttempt != null &&
        now.difference(lastAttempt) < const Duration(seconds: 3)) {
      return false;
    }
    final lastSuccess = _sessionBootstrapLastSuccessAt;
    if (!force &&
        lastSuccess != null &&
        now.difference(lastSuccess) < const Duration(seconds: 20)) {
      return false;
    }

    var refreshedHomeSnapshot = false;
    _sessionBootstrapInFlight = true;
    _sessionBootstrapLastAttemptAt = now;

    try {
      var hasSession =
          (await getSessionCookieHeader(base) ?? '').trim().isNotEmpty;
      if (!hasSession && _debugSkipLogin) {
        hasSession = await shamellEnsureDebugSkipLoginSession(
          baseUrl: base,
          client: widget.client,
        );
      }
      if (force && !hasSession) {
        await _forceReauthDueToDeviceBindingDrift();
        return false;
      }

      if (_deviceBindingReauthTriggered) return false;
      if (!hasSession) return false;

      // Ensure the authenticated account always has an active chat device
      // binding, so SyrChat-ID contact lookup and invite flows work on first run.
      try {
        final svc = ChatService(base, httpClient: widget.client);
        try {
          await svc.ensureAccountChatReady();
        } finally {
          svc.close();
        }
      } catch (e) {
        if (await _handleCriticalAccountSessionError(e)) return false;
      }
      if (_deviceBindingReauthTriggered) return false;
      try {
        final snapshot = await refreshAndPersistAccountHomeSnapshot(
          baseUrl: base,
          client: widget.client,
          ensureSession: false,
        );
        final sp = await SharedPreferences.getInstance();
        await _applyHomeSnapshot(
          snapshot.payload,
          sp,
          _appMode,
          persist: true,
          preserveCachedShamellIdOnOmission: true,
        );
        refreshedHomeSnapshot = true;
      } catch (e) {
        if (await _handleCriticalAccountSessionError(e)) return false;
      }
      if (_deviceBindingReauthTriggered) return false;
      _sessionBootstrapLastSuccessAt = DateTime.now();
      _requestCallSignalingInit();
      unawaited(_ensureChatAccountReadyBestEffort());
      return refreshedHomeSnapshot;
    } catch (e) {
      if (await _handleCriticalAccountSessionError(e)) return false;
      // Keep flow resilient: later user actions can retry bootstrap.
    } finally {
      _sessionBootstrapInFlight = false;
    }
    return false;
  }

  Future<void> _applyHomeSnapshot(
    Map<String, dynamic> j,
    SharedPreferences sp,
    AppMode appMode, {
    required bool persist,
    bool preserveCachedShamellIdOnOmission = false,
  }) async {
    final shamellIdRaw =
        (j['shamell_id'] ?? '').toString().trim().toUpperCase();
    var nextShamellId = isValidShamellUserId(shamellIdRaw) ? shamellIdRaw : '';
    if (nextShamellId.isEmpty && preserveCachedShamellIdOnOmission) {
      final cached =
          ((await loadStoredShamellUserId(sp: sp, baseUrlOverride: _baseUrl)) ??
                  '')
              .trim()
              .toUpperCase();
      if (isValidShamellUserId(cached)) {
        nextShamellId = cached;
      }
    }
    final privilegeSnapshot = accountPrivilegeSnapshotFromPayload(j);
    if (persist) {
      await saveAccountPrivilegeSnapshot(
        roles: privilegeSnapshot.roles,
        isSuperadmin: privilegeSnapshot.isSuperadmin,
        operatorIds: privilegeSnapshot.operatorIds,
        permissions: privilegeSnapshot.permissions,
        products: privilegeSnapshot.products,
        officialAccountIds: privilegeSnapshot.officialAccountIds,
        officialAccountWildcard: privilegeSnapshot.officialAccountWildcard,
        hasPlatformScope: privilegeSnapshot.hasPlatformScope,
        isAdmin: privilegeSnapshot.isAdmin,
        sp: sp,
        baseUrlOverride: _baseUrl,
      );
    }
    if (persist) {
      await saveStoredShamellUserId(
        nextShamellId,
        sp: sp,
        baseUrlOverride: _baseUrl,
      );
    }
    if (mounted) {
      setState(() {
        _profileShamellId = nextShamellId;
      });
    }
    var w = (j['wallet_id'] ?? '').toString().trim();
    if (w.isEmpty) {
      final wallet = j['wallet'];
      if (wallet is Map<String, dynamic>) {
        w = (wallet['wallet_id'] ?? wallet['id'] ?? '').toString().trim();
      }
    }
    if (w.isEmpty) {
      w = ((await loadStoredWalletId(sp: sp, baseUrlOverride: _baseUrl)) ?? '')
          .trim();
    }
    if (persist) {
      await saveStoredWalletId(w, sp: sp, baseUrlOverride: _baseUrl);
    }
    if (mounted) {
      setState(() {
        if (w.isNotEmpty) {
          _walletId = w;
          if (j['wallet'] is Map<String, dynamic>) {
            if (!_applyWalletSummaryHomeState(j['wallet'])) {
              _clearWalletSummaryHomeState();
            }
          }
          _applyCurrencyWalletsHomeState(j['wallets']);
        } else {
          _clearWalletSnapshotHomeState();
        }
      });
    }
    if (mounted) {
      setState(() {
        _applyPrivilegeSnapshotHomeState(privilegeSnapshot, appMode);
      });
    }
    await _applyMiniProgramShelfHomeState(
      j['mini_program_shelf'],
      sp,
      persist: persist,
    );
    // Capabilities: fail-closed. Missing keys keep prior defaults.
    try {
      final nextCaps = ShamellCapabilities.mergeJson(j['capabilities'], _caps);
      if (persist) {
        await nextCaps.persistForBaseUrl(sp, _baseUrl);
      }
      if (mounted) {
        setState(() {
          _caps = nextCaps;
          _applyCapabilityDisabledHomeState(nextCaps);
        });
      }
    } catch (_) {}
    if (persist) {
      _kickOffCapabilityLoads();
    }
  }

  void _kickOffCapabilityLoads() {
    // Best practice: capability gated (fail-closed) and best-effort.
    // This may be called multiple times as /me/home_snapshot refreshes.
    if (_caps.friends) {
      unawaited(_refreshFriendsSurface());
    }
    unawaited(_loadDefaultOfficialAccountFlag());
    if (_caps.serviceNotifications) {
      unawaited(_loadServiceNotificationsBadge());
    }
  }

  Future<void> _refreshHomeStartupState(
    SharedPreferences sp,
    AppMode appMode, {
    bool skipHomeSnapshotRefresh = false,
  }) async {
    if (!skipHomeSnapshotRefresh) {
      await _refreshHomeSnapshotFromServer(sp, appMode);
    }
    if (_privilegeSnapshot.roles.isEmpty &&
        _privilegeSnapshot.permissions.isEmpty &&
        !_privilegeSnapshot.isAdmin &&
        !_privilegeSnapshot.isSuperadmin) {
      await _loadRoles();
    }
    if (_walletId.isNotEmpty && !_walletSummaryLoaded) {
      await _loadWalletSummary();
    }
  }

  @override
  void dispose() {
    if (shamellGetActiveBootstrapBaseUrl() ==
        shamellNormalizeBootstrapBaseUrl(_baseUrl)) {
      shamellSetActiveBootstrapBaseUrl(null);
    }
    _linksSub?.cancel();
    _flushTimer?.cancel();
    _contactsIndexHintTimer?.cancel();
    _currencyWalletsPageController.dispose();
    _contactsScrollCtrl.removeListener(_updateContactsStickyHeader);
    _contactsScrollCtrl.dispose();
    _callSignalingReconnectTimer?.cancel();
    try {
      _callSub?.cancel();
    } catch (_) {}
    try {
      _callClient?.close();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _loadWalletSummary() async {
    if (_walletId.isEmpty) return;
    setState(() => _walletLoading = true);
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      // Konsistente Nutzung des Wallet-Snapshots wie in den
      // Payments-Ansichten, um Serverlogik zentral zu halten.
      final uri = _homeApiUri(
        pathSegments: <String>['wallets', _walletId, 'snapshot'],
        queryParameters: const <String, String>{'limit': '1'},
      );
      if (uri == null) {
        return;
      }
      final r = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_startupDataRequestTimeout);
      if (r.statusCode == 200) {
        Perf.action('wallet_snapshot_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final w = j['wallet'];
        if (w is Map && _applyWalletSummaryHomeState(w)) {
          if (mounted) {
            setState(() {
              _walletLoading = false;
            });
          }
        }
      } else {
        Perf.action('wallet_snapshot_fail');
        if (shamellIsCriticalAccountSessionHttpFailure(
          statusCode: r.statusCode,
          rawBody: r.body,
        )) {
          await _forceReauthDueToDeviceBindingDrift();
          return;
        }
      }
    } catch (e) {
      Perf.action('wallet_snapshot_error');
      if (await _handleCriticalAccountSessionError(e)) return;
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
    if (mounted) {
      setState(() => _walletLoading = false);
    }
  }

  Widget _buildHomeRoute() {
    final actions = HomeActions(
      onScanPay: _quickScanPay,
      onTopup: _quickTopup,
      onSonic: () => _navPush(SonicPayPage(_baseUrl)),
      onP2P: _quickP2P,
      onOps: () => _navPush(OpsPage(_baseUrl)),
      onBills: () => unawaited(_openBillsQuick()),
      onWallet: _quickP2P,
      onHistory: () => unawaited(_openHistoryQuick()),
      onRide: _openRideMiniProgram,
      onChat: () => _openMod('chat'),
      // Inventory view
      onVouchers: () => _navPush(CashMandatePage(_baseUrl)),
      onRequests: () => _navPush(
        RequestsPage(
          baseUrl: _baseUrl,
          walletId: _walletId,
          deviceId: deviceId,
        ),
      ),
    );
    final child = HomeRouteGrid(
      actions: actions,
      showOps: _showOps,
      showSuperadmin: _showSuperadmin,
      showSonic: _caps.paymentsSonic,
      showVouchers: _caps.paymentsCashVouchers,
      showBills: _caps.paymentsBills,
    );
    return AnimatedSwitcher(duration: Tokens.motionBase, child: child);
  }

  AppLinks? _appLinks;
  StreamSubscription<Uri>? _linksSub;
  Future<void> _setupLinks() async {
    try {
      _appLinks = AppLinks();
      final uri = await _appLinks!.getInitialLink();
      if (uri != null) {
        unawaited(_handleUri(uri, source: _ShamellInboundUriSource.appLink));
      }
      _linksSub = _appLinks!.uriLinkStream.listen((uri) {
        if (uri != null) {
          unawaited(_handleUri(uri, source: _ShamellInboundUriSource.appLink));
        }
      });
    } catch (_) {}
  }

  Future<void> _confirmDeviceLoginRequest({
    required String token,
    String? label,
  }) async {
    final l = L10n.of(context);
    final t = token.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(t)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'رمز تسجيل الدخول غير صالح.'
                : 'Invalid device-login token.',
          ),
        ),
      );
      return;
    }
    final deviceLabel = sanitizeDeviceLoginLabel(label) ?? '';
    final uri = _homeApiUri(
      pathSegments: const <String>['auth', 'device_login', 'approve'],
    );
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_invalidServerUrlMessage())));
      return;
    }
    if (!_beginDeviceLoginApproval()) {
      return;
    }

    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l.isArabic ? 'تسجيل دخول جهاز' : 'Device login'),
              content: Text(
                deviceLabel.isNotEmpty
                    ? (l.isArabic
                        ? 'هل تريد الموافقة على تسجيل دخول هذا الجهاز: \"$deviceLabel\"؟'
                        : 'Approve signing in this device: \"$deviceLabel\"?')
                    : (l.isArabic
                        ? 'هل تريد الموافقة على تسجيل دخول هذا الجهاز؟'
                        : 'Approve signing in this device?'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l.shamellDialogCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l.isArabic ? 'موافقة' : 'Approve'),
                ),
              ],
            ),
          ) ??
          false;
      if (!ok) return;

      final resp = await httpClient
          .post(
            uri,
            headers: await _hdr(json: true, baseUrl: _baseUrl),
            body: jsonEncode(<String, Object?>{'token': t}),
          )
          .timeout(_sessionMgmtRequestTimeout);
      if (await shamellForceReauthIfCriticalAccountSessionHttpFailure(
        context,
        statusCode: resp.statusCode,
        rawBody: resp.body,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        widget.onCriticalDeviceLoginSessionFailure?.call();
        return;
      }
      if (!mounted) return;
      if (resp.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تمت الموافقة على تسجيل الدخول.'
                  : 'Device login approved.',
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sanitizeHttpError(
              statusCode: resp.statusCode,
              rawBody: resp.body,
              isArabic: l.isArabic,
            ),
          ),
        ),
      );
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        widget.onCriticalDeviceLoginSessionFailure?.call();
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sanitizeExceptionForUi(error: e, isArabic: l.isArabic)),
        ),
      );
    } finally {
      if (closeClient) {
        try {
          httpClient.close();
        } catch (_) {}
      }
      _endDeviceLoginApproval();
    }
  }

  Future<bool> _confirmInviteRedeemRequest() async {
    final l = L10n.of(context);
    return (await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.isArabic ? 'دعوة جهة اتصال' : 'Contact invite'),
            content: Text(
              l.isArabic
                  ? 'هل تريد إضافة جهة الاتصال عبر رابط الدعوة هذا؟'
                  : 'Add this contact using the invite link?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.shamellDialogCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.isArabic ? 'إضافة' : 'Add'),
              ),
            ],
          ),
        )) ??
        false;
  }

  Future<void> _refreshHomeSnapshotFromServer(
    SharedPreferences sp,
    AppMode appMode,
  ) async {
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final uri = _homeApiUri(
        pathSegments: const <String>['me', 'home_snapshot'],
      );
      if (uri == null) {
        await _applyFailClosedHomeSnapshotState(sp, appMode);
        return;
      }
      final r = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_startupDataRequestTimeout);
      if (r.statusCode == 200) {
        Perf.action('home_snapshot_ok');
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        await saveCachedHomeSnapshotRaw(
          r.body,
          sp: sp,
          baseUrlOverride: _baseUrl,
        );
        await _applyHomeSnapshot(j, sp, appMode, persist: true);
        return;
      }
      Perf.action('home_snapshot_fail');
      if (shamellIsCriticalAccountSessionHttpFailure(
        statusCode: r.statusCode,
        rawBody: r.body,
      )) {
        await _forceReauthDueToDeviceBindingDrift();
        return;
      }
      // Fail closed: if we can't refresh server state, do not keep stale
      // capabilities that might expose internal/unfinished modules.
      await _applyFailClosedHomeSnapshotState(sp, appMode);
    } catch (e) {
      Perf.action('home_snapshot_error');
      if (await _handleCriticalAccountSessionError(e)) return;
      await _applyFailClosedHomeSnapshotState(sp, appMode);
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<void> _handleUri(
    Uri uri, {
    _ShamellInboundUriSource source = _ShamellInboundUriSource.appLink,
  }) async {
    try {
      if (_shamellInboundUriExceedsMaxChars(uri)) {
        return;
      }
      final originalScheme = uri.scheme.toLowerCase();
      uri = normalizeInboundShamellUri(uri);
      final scheme = uri.scheme.toLowerCase();
      final host = uri.host.toLowerCase();
      if (scheme == 'http' || scheme == 'https') {
        return;
      }
      if (scheme == 'shamell') {
        if (!shamellIsSafeCustomSchemeInboundUri(uri)) {
          return;
        }
        if (!_shamellIsSupportedInboundHost(host)) {
          return;
        }
        if (source == _ShamellInboundUriSource.appLink &&
            originalScheme == 'shamell' &&
            !shamellAllowsCustomSchemeInboundHost(host)) {
          if (!mounted) return;
          final l = L10n.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l.isArabic
                    ? 'هذا الرابط لم يعد مدعوماً. استخدم رابط SyrChat الآمن أو امسح رمز QR من داخل التطبيق.'
                    : 'This link is no longer supported. Use the secure SyrChat link or scan the QR from inside the app.',
              ),
            ),
          );
          return;
        }
        if (host == 'device_login') {
          final token = (uri.queryParameters['token'] ?? '').trim();
          final label = sanitizeDeviceLoginLabel(uri.queryParameters['label']);
          if (token.isEmpty) return;
          await _confirmDeviceLoginRequest(token: token, label: label);
          return;
        }
        if (host == 'invite') {
          final token =
              (uri.queryParameters['token'] ?? '').trim().toLowerCase();
          if (token.isEmpty) return;
          if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
            if (!mounted) return;
            final l = L10n.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  l.isArabic ? 'رمز الدعوة غير صالح.' : 'Invalid invite token.',
                ),
              ),
            );
            return;
          }
          if (!_beginInviteRedeem()) return;
          final l = L10n.of(context);
          try {
            if (!mounted) return;
            final confirmed = await _confirmInviteRedeemRequest();
            if (!confirmed || !mounted) {
              return;
            }
            // Contact invite redemption must keep the current authenticated
            // account stable. Forcing account-create here can rotate the
            // SyrChat ID/device binding and immediately invalidate the invite
            // target the user is trying to redeem.
            await _ensureSessionForOnlineOps(baseUrl: _baseUrl);
            if (_deviceBindingReauthTriggered || !mounted) return;
            final svc = ChatService(_baseUrl, httpClient: widget.client);
            try {
              final peerId = await svc.redeemContactInviteTokenEnsured(token);
              if (peerId.isEmpty) return;
              try {
                final peer = await svc.resolveDevice(peerId);
                await _chatStore.upsertContact(peer, baseUrlOverride: _baseUrl);
              } catch (_) {}
              unawaited(_refreshContactsRosterFromLocalCache());
              _navPush(
                ShamellChatPage(baseUrl: _baseUrl, initialPeerId: peerId),
              );
            } finally {
              svc.close();
            }
          } catch (e) {
            final forcedReauth = await _handleCriticalAccountSessionError(e);
            if (forcedReauth || _deviceBindingReauthTriggered || !mounted) {
              return;
            }
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _chatOperationErrorForUi(e, isArabic: l.isArabic),
                ),
              ),
            );
          } finally {
            _endInviteRedeem();
          }
          return;
        }
        if (host == 'friend') {
          final l = L10n.of(context);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  l.isArabic
                      ? 'رمز الصديق لم يعد مدعوماً. اطلب رمز دعوة جديد.'
                      : 'This friend QR is no longer supported. Ask for a new invite QR.',
                ),
              ),
            );
          }
          return;
        }
        if (host == 'chat') {
          // Hardening: disable rich chat deep-links (peer/group/message). This
          // avoids stable-identifier link sharing and enforces invite-capability
          // contact onboarding.
          _navPush(ShamellChatPage(baseUrl: _baseUrl));
          return;
        }
        if (host == 'ride' || host == 'taxi') {
          final rideId = (uri.queryParameters['ride_id'] ??
                  uri.queryParameters['id'] ??
                  '')
              .trim();
          final safeRideId =
              RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(rideId) ? rideId : '';
          _openTaxiMiniProgram(rideId: safeRideId.isEmpty ? null : safeRideId);
          return;
        }
        if (host == 'coach' || host == 'bus') {
          _openCoachMiniProgram(
            initialFrom: _normalizeCoachMiniProgramLocation(
              uri.queryParameters['from'] ?? uri.queryParameters['origin'],
            ),
            initialTo: _normalizeCoachMiniProgramLocation(
              uri.queryParameters['to'] ?? uri.queryParameters['destination'],
            ),
            initialDepartureDate: _normalizeCoachMiniProgramDate(
              uri.queryParameters['departure_date'] ??
                  uri.queryParameters['date'],
            ),
            initialPassengers: _parseCoachMiniProgramPassengers(
              uri.queryParameters['passengers'] ??
                  uri.queryParameters['pax'] ??
                  uri.queryParameters['passenger_count'],
            ),
          );
          return;
        }
        final miniTarget = parseMiniProgramDeepLink(uri);
        if (miniTarget != null) {
          if (miniTarget.id == 'green_paket') {
            _openGreenPaket(initialGreenPaketId: miniTarget.resourceId);
          } else {
            _openMod(miniTarget.id);
          }
          return;
        }
        if (host == 'moduleapp' || host == 'moduleapps') {
          final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          final id = (uri.queryParameters['id'] ??
                  (segs.isNotEmpty ? segs.last : null) ??
                  uri.queryParameters['moduleapp'] ??
                  uri.queryParameters['app_id'])
              ?.trim()
              .toLowerCase();
          if (id != null && id.isNotEmpty) {
            _openMod(id);
            return;
          }
        }
        if (host == 'official') {
          dispatchOfficialDeepLink(
            uri,
            capabilityEnabled: _caps.officialAccounts,
            onUnavailable: () {
              final l = L10n.of(context);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    l.isArabic
                        ? 'هذه الميزة غير متاحة على هذا الخادم.'
                        : 'This feature is not available on this server.',
                  ),
                ),
              );
            },
            onOpenAccount: _openOfficialDeepLink,
            onOpenItem: _openOfficialItemDeepLink,
          );
          return;
        }
        if (host == 'moments') {
          _handleMomentsDeepLink();
          return;
        }
        // host == 'shake' no longer routes — route legacy Shake deep
        // links to People-Nearby so existing QR codes still land usefully.
        if (host == 'shake') {
          _openPeopleNearby();
          return;
        }
      }
      String? mod = uri.queryParameters['mod'];
      if (mod == null) {
        final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segs.isNotEmpty) mod = segs.last;
      }
      // offline sync removed; ignore syncnow
      if (mod == null) return;
      _openMod(mod.toLowerCase());
    } catch (_) {}
  }

  @visibleForTesting
  Future<void> debugHandleUri(Uri uri) async {
    await _handleUri(uri);
  }

  @visibleForTesting
  Future<void> debugShowInviteQr() async {
    await _showInviteQr();
  }

  @visibleForTesting
  Future<void> debugHandleScanResult(String raw) async {
    await _handleScanResult(raw);
  }

  @visibleForTesting
  Future<void> debugLoadFriendsSummary() async {
    await _loadFriendsSummary();
  }

  @visibleForTesting
  Future<void> debugLoadContactsRoster({bool force = false}) async {
    await _loadContactsRoster(force: force);
  }

  @visibleForTesting
  Future<void> debugRefreshFriendsSurface({bool forceRoster = false}) async {
    await _refreshFriendsSurface(forceRoster: forceRoster);
  }

  @visibleForTesting
  Future<void> debugConsumePendingNotificationPayload() async {
    await _consumePendingNotificationPayload();
  }

  @visibleForTesting
  Future<void> debugRegisterDeviceBestEffort() async {
    await _registerDeviceBestEffort();
  }

  @visibleForTesting
  Future<void> debugLoadServiceNotificationsBadge() async {
    await _loadServiceNotificationsBadge();
  }

  @visibleForTesting
  Future<void> debugLoadUnreadBadge() async {
    await _loadUnreadBadge();
  }

  @visibleForTesting
  int debugTotalUnreadChats() {
    return _totalUnreadChats;
  }

  @visibleForTesting
  bool debugHasUnreadServiceNotificationsBadge() {
    return _hasUnreadServiceNotifications;
  }

  @visibleForTesting
  Map<String, int> debugFriendsSummaryState() {
    return <String, int>{
      'friends': _friendsCount,
      'close_friends': _closeFriendsCount,
      'pending_requests': _friendRequestsPending,
    };
  }

  @visibleForTesting
  Map<String, Object?> debugPrivilegeState() {
    return <String, Object?>{
      'roles': List<String>.from(_roles),
      'show_ops': _showOps,
      'show_superadmin': _showSuperadmin,
    };
  }

  @visibleForTesting
  Map<String, Object?> debugWalletState() {
    return <String, Object?>{
      'wallet_id': _walletId,
      'wallet_balance_cents': _walletBalanceCents,
      'wallet_currency': _walletCurrency,
      'wallet_loading': _walletLoading,
    };
  }

  @visibleForTesting
  Map<String, Object?> debugCurrencyWalletsState() {
    return _currencyWallets.map(
      (currency, wallet) => MapEntry(currency, <String, Object?>{
        'wallet_id': wallet.walletId,
        'balance_cents': wallet.balanceCents,
      }),
    );
  }

  @visibleForTesting
  void debugSeedLegacyMeTabState({
    required bool strictUi,
    String walletId = '',
    bool? hasDefaultOfficialAccount,
    bool? hasUnreadServiceNotifications,
  }) {
    setState(() {
      _shamellStrictUi = strictUi;
      _walletId = walletId;
      if (hasDefaultOfficialAccount != null) {
        _hasDefaultOfficialAccount = hasDefaultOfficialAccount;
      }
      if (hasUnreadServiceNotifications != null) {
        _hasUnreadServiceNotifications = hasUnreadServiceNotifications;
      }
    });
  }

  @visibleForTesting
  bool debugHasDefaultOfficialAccount() {
    return _hasDefaultOfficialAccount;
  }

  @visibleForTesting
  Map<String, String> debugProfileIdentityState() {
    return <String, String>{
      'name': _profileName,
      'phone': _profilePhone,
      'shamell_id': _profileShamellId,
    };
  }

  @visibleForTesting
  Map<String, Object?> debugContactsState() {
    return <String, Object?>{
      'count': _contactsRoster.length,
      'loading': _contactsRosterLoading,
      'error': _contactsRosterError,
      'has_sticky_header': _contactsStickyHeader != null,
    };
  }

  @visibleForTesting
  Future<void> debugLoadDefaultOfficialAccountFlag() async {
    await _loadDefaultOfficialAccountFlag();
  }

  @visibleForTesting
  Future<void> debugLoadStoredProfileIdentity() async {
    final sp = await SharedPreferences.getInstance();
    final storedProfile = await loadLegacyProfileSummary(
      sp: sp,
      baseUrlOverride: _baseUrl,
    );
    final shamellUserId =
        await loadShamellUserId(sp: sp, baseUrlOverride: _baseUrl) ?? '';
    if (!mounted) return;
    setState(() {
      _profileName = storedProfile.name;
      _profilePhone = storedProfile.phone;
      _profileShamellId = shamellUserId;
    });
  }

  @visibleForTesting
  Future<void> debugLoadPrefs() async {
    await _loadPrefs(refreshOnline: false);
  }

  @visibleForTesting
  Future<void> debugRefreshHomeStartupState({
    bool skipHomeSnapshotRefresh = false,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await _refreshHomeStartupState(
      sp,
      _appMode,
      skipHomeSnapshotRefresh: skipHomeSnapshotRefresh,
    );
  }

  @visibleForTesting
  Future<void> debugCompleteOnlineHomeStartup({
    required bool bootstrappedHomeSnapshot,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await _completeOnlineHomeStartup(
      sp,
      _appMode,
      bootstrappedHomeSnapshot: bootstrappedHomeSnapshot,
    );
  }

  @visibleForTesting
  int debugCallSignalingInitRequestCount() {
    return _callSignalingInitRequestCount;
  }

  @visibleForTesting
  void debugSuppressCallSignalingInit(bool suppress) {
    _suppressCallSignalingInitForTesting = suppress;
  }

  @visibleForTesting
  void debugSeedContactsState({
    required List<Map<String, dynamic>> roster,
    String? error,
    bool loading = false,
    String? stickyHeader,
  }) {
    setState(() {
      _contactsRoster = List<Map<String, dynamic>>.from(roster);
      _contactsRosterError = error;
      _contactsRosterLoading = loading;
      _contactsStickyHeader = stickyHeader;
      _contactsStickyHeaderOffset = stickyHeader == null ? 0.0 : -4.0;
    });
  }

  @visibleForTesting
  Future<void> debugOpenOfficialNotifications() async {
    await _openOfficialNotifications();
  }

  @visibleForTesting
  Future<Map<String, Object?>> debugLoadOfficialNotificationSheetState() async {
    final state = await _loadOfficialNotificationSheetState();
    if (state == null) {
      return const <String, Object?>{};
    }
    return <String, Object?>{
      'accounts': state.accounts,
      'serviceMode': state.serviceMode.name,
      'nonServiceMode': state.nonServiceMode.name,
    };
  }

  @visibleForTesting
  Future<void> debugEnsureServiceOfficialFollow({
    required String officialId,
    required String chatPeerId,
  }) async {
    await _ensureServiceOfficialFollow(
      officialId: officialId,
      chatPeerId: chatPeerId,
    );
  }

  @visibleForTesting
  Future<void> debugApplyOfficialNotificationGroupMode({
    required List<Map<String, dynamic>> accounts,
    required AnalyticsOfficialGroup group,
    required OfficialNotificationMode mode,
  }) async {
    await _applyOfficialNotificationGroupMode(
      accounts: accounts,
      group: group,
      mode: mode,
    );
  }

  @visibleForTesting
  Future<void> debugLoadRoles() async {
    await _loadRoles();
  }

  @visibleForTesting
  Future<void> debugLoadWalletSummary(String walletId) async {
    _walletId = walletId;
    await _loadWalletSummary();
  }

  @visibleForTesting
  Future<void> debugRefreshHomeSnapshot() async {
    final sp = await SharedPreferences.getInstance();
    await _refreshHomeSnapshotFromServer(sp, _appMode);
  }

  @visibleForTesting
  Future<void> debugEnsureSessionBootstrap({bool force = false}) async {
    await _ensureSessionForOnlineOps(baseUrl: _baseUrl, force: force);
  }

  @visibleForTesting
  Future<void> debugHandleCallSignalingEvent(Map<String, dynamic> msg) async {
    await _handleCallSignalingStreamEvent(msg);
  }

  void _openOfficialDeepLink(String accountId) {
    if (accountId.isEmpty) return;
    _openMod('official');
  }

  void _handleMomentsDeepLink() {
    if (!_caps.moments) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'هذه الميزة غير متاحة على هذا الخادم.'
                : 'This feature is not available on this server.',
          ),
        ),
      );
      return;
    }
    _openMod('moments');
  }

  void _openOfficialItemDeepLink(String accountId, String itemId) {
    if (accountId.isEmpty || itemId.isEmpty) return;
    _openMod('official');
  }

  void _showEmergency() {
    showDialog(
      context: context,
      builder: (_) {
        final l = L10n.of(context);
        return AlertDialog(
          title: Text(l.emergencyTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.local_police_outlined),
                title: Text(l.emergencyPolice),
                subtitle: const Text('112'),
                onTap: () {
                  final uri = Uri.parse('tel:112');
                  launchUrl(uri, mode: shamellExternalLaunchMode(uri));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_hospital_outlined),
                title: Text(l.emergencyAmbulance),
                subtitle: const Text('110'),
                onTap: () {
                  final uri = Uri.parse('tel:110');
                  launchUrl(uri, mode: shamellExternalLaunchMode(uri));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_fire_department_outlined),
                title: Text(l.emergencyFire),
                subtitle: const Text('113'),
                onTap: () {
                  final uri = Uri.parse('tel:113');
                  launchUrl(uri, mode: shamellExternalLaunchMode(uri));
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showComplaints() {
    showDialog(
      context: context,
      builder: (_) {
        final l = L10n.of(context);
        return AlertDialog(
          title: Text(l.complaintsTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Email: $kShamellSupportEmail'),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final uri = shamellSupportEmailUri(subject: 'Complaint');
                  launchUrl(uri, mode: shamellExternalLaunchMode(uri));
                  Navigator.pop(context);
                },
                child: Text(l.complaintsEmailUs),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loadRoles() async {
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final uri = _homeApiUri(pathSegments: const <String>['me', 'roles']);
      if (uri == null) {
        return;
      }
      final r = await httpClient
          .get(uri, headers: await _hdr())
          .timeout(_startupDataRequestTimeout);
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final roles =
            (j['roles'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        final storedPrivileges = await loadAccountPrivilegeSnapshotForBaseUrl(
          _baseUrl,
        );
        final operatorIds =
            (j['operator_ids'] as List?)?.map((e) => e.toString()).toList() ??
                storedPrivileges.operatorIds;
        final mergedPrivileges = storedPrivileges.copyWith(
          roles: roles,
          operatorIds: operatorIds,
        );
        await saveAccountPrivilegeSnapshot(
          roles: mergedPrivileges.roles,
          isSuperadmin: mergedPrivileges.isSuperadmin,
          operatorIds: mergedPrivileges.operatorIds,
          permissions: mergedPrivileges.permissions,
          products: mergedPrivileges.products,
          officialAccountIds: mergedPrivileges.officialAccountIds,
          officialAccountWildcard: mergedPrivileges.officialAccountWildcard,
          hasPlatformScope: mergedPrivileges.hasPlatformScope,
          isAdmin: mergedPrivileges.isAdmin,
          baseUrlOverride: _baseUrl,
        );
        if (mounted) {
          setState(() {
            _applyPrivilegeSnapshotHomeState(mergedPrivileges, _appMode);
          });
        }
      } else if (shamellIsCriticalAccountSessionHttpFailure(
        statusCode: r.statusCode,
        rawBody: r.body,
      )) {
        await _forceReauthDueToDeviceBindingDrift();
      }
    } catch (e) {
      await _handleCriticalAccountSessionError(e);
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  void _openMod(String mod) {
    final id = mod.trim().toLowerCase();
    if (id.isEmpty) return;

    final l = L10n.of(context);
    void blocked({required String en, required String ar}) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.isArabic ? ar : en)));
    }

    // Native modules: keep Payments + Chat fully integrated.
    if (id == 'chat') {
      if (!_caps.chat) {
        blocked(
          en: 'Chat is disabled on this server.',
          ar: 'الدردشة معطّلة على هذا الخادم.',
        );
        return;
      }
      if (mounted) {
        setState(() {
          _tabIndex = 0;
        });
      }
      return;
    }
    if (id == 'payments' || id == 'pay' || id == 'wallet') {
      if (!_caps.payments) {
        blocked(
          en: 'Payments are disabled on this server.',
          ar: 'المدفوعات معطّلة على هذا الخادم.',
        );
        return;
      }
      if (mounted) {
        setState(() {
          _tabIndex = 2;
        });
      }
      if (_walletId.trim().isEmpty) {
        unawaited(_ensureWalletReady(interactive: false));
      }
      return;
    }
    if (id == 'moments' || id == 'updates') {
      if (!_caps.moments) {
        blocked(
          en: 'Moments are disabled on this server.',
          ar: 'اللحظات غير مفعّلة على هذا الخادم.',
        );
        return;
      }
      unawaited(_recordModuleUse('moments'));
      _navPush(ShamellMomentsPage(baseUrl: _baseUrl));
      return;
    }
    if (id == 'search' || id == 'global_search') {
      _openGlobalSearch();
      return;
    }
    if (id == 'favorites' ||
        id == 'saved' ||
        id == 'saved_items' ||
        id == 'bookmarks') {
      unawaited(_recordModuleUse('favorites'));
      _navPush(FavoritesPage(baseUrl: _baseUrl));
      return;
    }
    if (id == 'service_notifications' ||
        id == 'notifications' ||
        id == 'template_messages' ||
        id == 'service_inbox') {
      _openServiceNotificationsPage();
      return;
    }
    if (id == 'mini_programs' ||
        id == 'miniapps' ||
        id == 'apps' ||
        id == 'service_center') {
      unawaited(_showMiniProgramsQuickPanel());
      return;
    }
    if (id == 'official' ||
        id == 'official_accounts' ||
        id == 'officials' ||
        id == 'subscriptions') {
      if (!_caps.officialAccounts) {
        blocked(
          en: 'Official Accounts are disabled on this server.',
          ar: 'الحسابات الرسمية غير مفعّلة على هذا الخادم.',
        );
        return;
      }
      _openOfficialAccounts();
      return;
    }
    if (id == 'channels' || id == 'videos' || id == 'short_video') {
      _openChannels();
      return;
    }
    if (id == 'nearby' || id == 'people_nearby') {
      _openPeopleNearby();
      return;
    }
    // Retired mods — keep them recognised so deep links don't 404, but
    // route them to a still-existing surface (Nearby in the case of
    // shake, no-op for stickers since there's no equivalent surface).
    if (id == 'shake') {
      _openPeopleNearby();
      return;
    }
    if (id == 'stickers' || id == 'sticker_store') {
      // Sticker Store retired — silently drop. No replacement surface.
      return;
    }
    if (id == 'cards' ||
        id == 'offers' ||
        id == 'coupons' ||
        id == 'member_cards') {
      _openCardsOffers();
      return;
    }
    if (id == 'green_paket' ||
        id == 'green_packet' ||
        id == 'redpacket' ||
        id == 'red_packet' ||
        id == 'hongbao') {
      _openGreenPaket();
      return;
    }
    if (id == 'ride' || id == 'taxi' || id == 'hailing') {
      _openTaxiMiniProgram();
      return;
    }
    if (id == 'coach' ||
        id == 'bus' ||
        id == 'coach_bus' ||
        id == 'coachbus' ||
        id == 'fernbus') {
      _openCoachMiniProgram();
      return;
    }
    if (id == 'mobility') {
      _openRideMiniProgram();
      return;
    }
    // Mini-games (jump_jump, tic_tac_toe, …) fall through to the
    // `MiniAppRegistry.byId(id)` lookup below — the registry's
    // descriptor returns the right `MiniGameWebViewPage(...)` for
    // the requested gameId, no per-game branch needed here.
    if (id == 'gaming' || id == 'games' || id == 'minigames') {
      _openGamingMiniPrograms();
      return;
    }
    // Fallback: any Mini-App registered in MiniAppRegistry (e.g.
    // `hotels`, `hotels_admin`). Keeps the registry as the single
    // source of truth — new mini-apps don't need a hard-coded branch
    // here, they just register a descriptor + entry().
    final registered = MiniAppRegistry.byId(id);
    if (registered != null) {
      unawaited(_recordModuleUse(id));
      final api = SuperappAPI(
        baseUrl: _baseUrl,
        walletId: _walletId,
        deviceId: deviceId,
        openMod: _openMod,
        pushPage: _navPush,
        ensureServiceOfficialFollow: _ensureServiceOfficialFollow,
        recordModuleUse: _recordModuleUse,
      );
      _navPush(registered.entry(context, api));
      return;
    }
    blocked(
      en: 'This module shortcut is no longer supported.',
      ar: 'اختصار هذه الوحدة لم يعد مدعوماً.',
    );
  }

  /// Open the Mini Programs directory filtered to the Gaming category
  /// — the user's tile-tap entry for "Gaming" on Discover.
  void _openGamingMiniPrograms() {
    unawaited(_recordModuleUse('gaming'));
    _navPush(
      MiniProgramsDirectoryPage(
        baseUrl: _baseUrl,
        deviceId: deviceId,
        initialCategoryFilter: 'Gaming',
      ),
    );
  }

  void _openRideMiniProgram({String? rideId}) {
    final normalizedRideId = (rideId ?? '').trim();
    if (normalizedRideId.isNotEmpty) {
      _openTaxiMiniProgram(rideId: normalizedRideId);
      return;
    }
    unawaited(_recordModuleUse('mobility'));
    _navPush(
      MobilityHubPage(
        onOpenRide: () => _openTaxiMiniProgram(),
        onOpenCoach: _openCoachMiniProgram,
      ),
    );
  }

  void _openTaxiMiniProgram({String? rideId}) {
    unawaited(_recordModuleUse('ride'));
    final normalizedRideId = (rideId ?? '').trim();
    _navPush(
      RideHailingPage(
        baseUrl: _baseUrl,
        initialRideId: normalizedRideId.isEmpty ? null : normalizedRideId,
        runStartupTasks: widget.runStartupTasks,
      ),
    );
  }

  String? _normalizeCoachMiniProgramLocation(String? raw) {
    return coachMiniProgramNormalizeSyrianSearchLocation(raw);
  }

  String? _normalizeCoachMiniProgramDate(String? raw) {
    final normalized = (raw ?? '').trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }

  int? _parseCoachMiniProgramPassengers(String? raw) {
    final normalized = (raw ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    final value = int.tryParse(normalized);
    if (value == null) {
      return null;
    }
    if (value < 1) {
      return 1;
    }
    if (value > 9) {
      return 9;
    }
    return value;
  }

  void _openCoachMiniProgram({
    String? initialFrom,
    String? initialTo,
    String? initialDepartureDate,
    int? initialPassengers,
  }) {
    if (!_caps.coach) {
      final l = L10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'ميزة الحافلات غير مفعلة على هذا الخادم.'
                : 'Coach bus is not enabled on this server.',
          ),
        ),
      );
      return;
    }
    unawaited(_recordModuleUse('coach'));
    _navPush(
      CoachBusMiniProgramPage(
        baseUrl: _baseUrl,
        initialFrom: initialFrom,
        initialTo: initialTo,
        initialDepartureDate: initialDepartureDate,
        initialPassengers: initialPassengers ?? 1,
      ),
    );
  }

  void _quickScanPay() {
    unawaited(_quickScanPayAsync());
  }

  Future<void> _quickScanPayAsync() async {
    final walletId = await _requireWalletIdForPaymentsAction(interactive: true);
    if (walletId == null || walletId.isEmpty) return;
    unawaited(_recordModuleUse('payments'));
    unawaited(
      _ensureServiceOfficialFollow(
        officialId: 'shamell_pay',
        chatPeerId: 'shamell_pay',
      ),
    );
    _navPush(
      PaymentsPage(
        _baseUrl,
        walletId,
        deviceId,
        triggerScanOnOpen: true,
        initialCurrency: _walletCurrency,
      ),
    );
  }

  void _quickTopup() {
    unawaited(_quickTopupAsync());
  }

  Future<void> _quickTopupAsync() async {
    if (await _requireWalletIdForPaymentsAction(interactive: true) == null) {
      return;
    }
    unawaited(_recordModuleUse('topup'));
    _navPush(
      TopupPage(
        _baseUrl,
        triggerScanOnOpen: true,
        initialCurrency: _walletCurrency,
      ),
    );
  }

  void _quickP2P() {
    unawaited(_quickP2PAsync());
  }

  Future<void> _quickP2PAsync() async {
    final walletId = await _requireWalletIdForPaymentsAction(interactive: true);
    if (walletId == null || walletId.isEmpty) return;
    unawaited(_recordModuleUse('payments'));
    unawaited(
      _ensureServiceOfficialFollow(
        officialId: 'shamell_pay',
        chatPeerId: 'shamell_pay',
      ),
    );
    _navPush(
      PaymentsPage(
        _baseUrl,
        walletId,
        deviceId,
        initialSection: 'send',
        initialCurrency: _walletCurrency,
        client: widget.client,
      ),
    );
  }

  /// Opens the Wallet → "Overview" tab (PaymentsPage index 0) — the
  /// balances + recent-activity surface — instead of the Send tab.
  /// The Wallet-hub "Wallet overview" tile used to call `_quickP2P`
  /// which landed on Send; that mismatched the label and confused
  /// operators tracking down a transfer.
  void _quickWalletOverview() {
    unawaited(_quickWalletOverviewAsync());
  }

  Future<void> _quickWalletOverviewAsync() async {
    final walletId = await _requireWalletIdForPaymentsAction(interactive: true);
    if (walletId == null || walletId.isEmpty) return;
    unawaited(_recordModuleUse('payments'));
    _navPush(
      PaymentsPage(
        _baseUrl,
        walletId,
        deviceId,
        initialSection: 'overview',
        initialCurrency: _walletCurrency,
        client: widget.client,
      ),
    );
  }

  Future<void> _openHistoryQuick() async {
    final walletId = await _requireWalletIdForPaymentsAction(interactive: true);
    if (walletId == null || walletId.isEmpty) return;
    _navPush(HistoryPage(baseUrl: _baseUrl, walletId: walletId));
  }

  Future<void> _openBillsQuick() async {
    final walletId = await _requireWalletIdForPaymentsAction(interactive: true);
    if (walletId == null || walletId.isEmpty) return;
    _navPush(BillsPage(_baseUrl, walletId, deviceId));
  }

  Map<String, String> _parsePipePairs(String raw) {
    final parts = raw.split('|');
    final map = <String, String>{};
    for (final p in parts.skip(1)) {
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      final k = p.substring(0, idx).trim().toLowerCase();
      String v;
      try {
        v = Uri.decodeComponent(p.substring(idx + 1).trim());
      } catch (_) {
        continue;
      }
      if (k.isEmpty || v.isEmpty) continue;
      map[k] = v;
    }
    return map;
  }

  Future<void> _openShamellScanAndHandle() async {
    try {
      final res = await Navigator.of(
        context,
      ).push<String?>(MaterialPageRoute(builder: (_) => const ScanPage()));
      if (!mounted) return;
      _loadUnreadBadge();
      unawaited(_loadShamellPluginsPrefs());
      final raw = (res ?? '').trim();
      if (raw.isEmpty) return;
      await _handleScanResult(raw);
    } catch (_) {}
  }

  Future<void> _openShamellIdContactResolveDialog() async {
    if (_resolveByShamellIdInFlight) return;
    final l = L10n.of(context);
    final input = TextEditingController();
    try {
      final submitted = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(
              l.isArabic ? 'إضافة عبر معرّف SyrChat' : 'Add by SyrChat ID',
            ),
            content: TextField(
              controller: input,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              maxLength: 8,
              decoration: InputDecoration(
                hintText: l.isArabic ? 'SA123456' : 'SA123456',
              ),
              onSubmitted: (value) => Navigator.of(ctx).pop(value),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(l.isArabic ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(input.text),
                child: Text(l.isArabic ? 'إضافة' : 'Add'),
              ),
            ],
          );
        },
      );
      if (!mounted) return;
      final normalized = (submitted ?? '').trim().toUpperCase();
      if (normalized.isEmpty) return;
      await _resolveContactByShamellIdAndOpenChat(normalized);
    } finally {
      input.dispose();
    }
  }

  Future<void> _resolveContactByShamellIdAndOpenChat(String shamellId) async {
    final l = L10n.of(context);
    final normalized = shamellId.trim().toUpperCase();
    if (!isValidShamellUserId(normalized)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'معرّف SyrChat غير صالح. يجب أن يتكوّن من 8 محارف.'
                : 'Invalid SyrChat ID. It must be exactly 8 characters.',
          ),
        ),
      );
      return;
    }
    if (_resolveByShamellIdInFlight) return;
    _resolveByShamellIdInFlight = true;
    try {
      // SyrChat-ID contact resolution should only ensure an existing session.
      // Forcing account-create here rotates the active account/device and can
      // make the just-entered SyrChat ID resolve against stale local chat
      // identity state.
      await _ensureSessionForOnlineOps(baseUrl: _baseUrl);
      if (_deviceBindingReauthTriggered || !mounted) return;
      final svc = ChatService(_baseUrl, httpClient: widget.client);
      try {
        final peerId = await svc.resolveContactByShamellIdEnsured(normalized);
        if (peerId.isEmpty) return;
        try {
          final peer = await svc.resolveDevice(peerId);
          await _chatStore.upsertContact(peer, baseUrlOverride: _baseUrl);
        } catch (_) {}
        unawaited(_refreshContactsRosterFromLocalCache());
        unawaited(_refreshFriendsSurface(forceRoster: true));
        _navPush(ShamellChatPage(baseUrl: _baseUrl, initialPeerId: peerId));
      } finally {
        svc.close();
      }
    } catch (e) {
      final forcedReauth = await _handleCriticalAccountSessionError(e);
      if (forcedReauth || _deviceBindingReauthTriggered || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_chatOperationErrorForUi(e, isArabic: l.isArabic)),
        ),
      );
    } finally {
      _resolveByShamellIdInFlight = false;
    }
  }

  Future<void> _showScanResultSheet(String raw) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.isArabic ? 'نتيجة المسح' : 'Scan result',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: .35,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: SelectableText(raw, style: theme.textTheme.bodyMedium),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    try {
                      await shamellCopyToClipboard(raw, sensitive: true);
                    } catch (_) {}
                    if (!ctx.mounted) return;
                    Navigator.pop(ctx);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l.isArabic ? 'تم النسخ' : 'Copied'),
                      ),
                    );
                  },
                  child: Text(l.isArabic ? 'نسخ' : 'Copy'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l.isArabic ? 'إغلاق' : 'Close'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleScanResult(String raw) async {
    final l = L10n.of(context);
    final text = raw.trim();
    if (text.isEmpty) return;
    if (text.length > _shamellScanPayloadMaxChars) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.shamellUnrecognizedQr)));
      return;
    }

    final upper = text.toUpperCase();
    final scanUri = Uri.tryParse(text);
    final isPaymentQrCandidate = upper.startsWith('PAY|') ||
        upper.startsWith('CASH|') ||
        upper.startsWith('TOPUP|') ||
        (scanUri != null &&
            scanUri.scheme.trim().toLowerCase() == 'shamell' &&
            const <String>{
              'pay',
              'payment',
              'topup',
            }.contains(scanUri.host.trim().toLowerCase()));
    final paymentQr =
        isPaymentQrCandidate ? parseShamellPaymentQrPayload(text) : null;
    if (paymentQr != null &&
        (paymentQr.walletId ?? paymentQr.alias ?? '').trim().isNotEmpty) {
      if (paymentQr.type == ShamellPaymentQrPayloadType.topup) {
        unawaited(_recordModuleUse('topup'));
        _navPush(
          TopupPage(
            _baseUrl,
            triggerScanOnOpen: true,
            scanLauncher: (_) async => text,
            initialCurrency: paymentQr.currency ?? _walletCurrency,
          ),
        );
        return;
      }

      final alias = (paymentQr.alias ?? '').trim();
      final wallet = (paymentQr.walletId ?? '').trim();
      final recipient = (alias.isNotEmpty ? alias : wallet).trim();
      final rawCurrency = (paymentQr.currency ?? _walletCurrency).trim();
      if (rawCurrency.isNotEmpty &&
          !shamellIsSupportedWalletCurrency(rawCurrency)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'عملة QR غير مدعومة: $rawCurrency'
                  : 'Unsupported QR currency: $rawCurrency',
            ),
          ),
        );
        return;
      }
      final currency = shamellNormalizeWalletCurrency(rawCurrency);
      String fromWallet = _walletId.trim();
      if (currency != _walletCurrency) {
        final currencyWallet = _currencyWallets[currency];
        final currencyWalletId = (currencyWallet?.walletId ?? '').trim();
        if (currencyWalletId.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l.isArabic
                    ? 'افتح محفظة $currency أولاً.'
                    : 'Open your $currency wallet first.',
              ),
            ),
          );
          return;
        }
        fromWallet = currencyWalletId;
      }
      if (fromWallet.isEmpty) {
        final ensuredWalletId = await _requireWalletIdForPaymentsAction(
          interactive: true,
        );
        if (ensuredWalletId == null || ensuredWalletId.isEmpty) {
          return;
        }
        fromWallet = ensuredWalletId;
      }

      unawaited(_recordModuleUse('payments'));
      unawaited(
        _ensureServiceOfficialFollow(
          officialId: 'shamell_pay',
          chatPeerId: 'shamell_pay',
        ),
      );
      _navPush(
        PaymentsPage(
          _baseUrl,
          fromWallet,
          deviceId,
          initialRecipient: recipient.isNotEmpty ? recipient : null,
          initialAmountCents: paymentQr.amountCents,
          initialSection: 'send',
          initialCurrency: currency,
          contextLabel: (paymentQr.label ?? '').trim().isNotEmpty
              ? paymentQr.label
              : null,
        ),
      );
      return;
    }
    if (upper.startsWith('PAY|') || upper.startsWith('CASH|')) {
      final kv = _parsePipePairs(text);
      final alias = (kv['to_alias'] ?? kv['alias'] ?? '').trim();
      final phone = (kv['to_phone'] ?? kv['phone'] ?? '').trim();
      final wallet =
          (kv['to_wallet_id'] ?? kv['wallet'] ?? kv['to'] ?? '').trim();
      final recipient =
          (alias.isNotEmpty ? alias : (phone.isNotEmpty ? phone : wallet))
              .trim();
      final amountRaw = (kv['amount'] ?? '').trim();
      final amountCents = parseCents(amountRaw);
      final label = (kv['label'] ?? kv['merchant'] ?? kv['name'] ?? '').trim();

      String fromWallet = _walletId.trim();
      if (fromWallet.isEmpty) {
        try {
          fromWallet =
              (await loadStoredWalletId(baseUrlOverride: _baseUrl) ?? '')
                  .trim();
        } catch (_) {}
      }
      if (fromWallet.isEmpty) {
        final ensuredWalletId = await _requireWalletIdForPaymentsAction(
          interactive: true,
        );
        if (ensuredWalletId == null || ensuredWalletId.isEmpty) {
          return;
        }
        fromWallet = ensuredWalletId;
      }

      unawaited(_recordModuleUse('payments'));
      unawaited(
        _ensureServiceOfficialFollow(
          officialId: 'shamell_pay',
          chatPeerId: 'shamell_pay',
        ),
      );
      _navPush(
        PaymentsPage(
          _baseUrl,
          fromWallet,
          deviceId,
          initialRecipient: recipient.isNotEmpty ? recipient : null,
          initialAmountCents: amountCents > 0 ? amountCents : null,
          initialSection: 'send',
          initialCurrency: _walletCurrency,
          contextLabel: label.isNotEmpty ? label : null,
        ),
      );
      return;
    }

    if (upper.startsWith('MINIPROGRAM|') ||
        upper.startsWith('MINI_PROGRAM|') ||
        upper.startsWith('MINIAPP|') ||
        upper.startsWith('APP|') ||
        upper.startsWith('MODULEAPP|')) {
      final miniTarget = parseMiniProgramPipePayload(text);
      if (miniTarget != null) {
        if (miniTarget.id == 'green_paket') {
          _openGreenPaket(initialGreenPaketId: miniTarget.resourceId);
        } else {
          _openMod(miniTarget.id);
        }
        return;
      }
    }

    final uri = Uri.tryParse(text);
    if (uri != null && uri.scheme.isNotEmpty) {
      final normalized = normalizeInboundShamellUri(uri);
      if (normalized.scheme.toLowerCase() == 'shamell') {
        await _handleUri(
          normalized,
          source: _ShamellInboundUriSource.scanResult,
        );
        return;
      }
    }

    await _showScanResultSheet(text);
  }

  Future<void> _recordModuleUse(String moduleId) async {
    try {
      final sp = await SharedPreferences.getInstance();
      // Do not persist local module-usage history; scrub any legacy cache.
      await clearLegacyRecentModules(sp);
    } catch (_) {}
    await ShamellAppActivity.record(
      baseUrl: _baseUrl,
      eventType: 'module_open',
      moduleId: moduleId,
      action: 'open',
      client: widget.client,
    );
  }

  Widget _buildDiscoverPromoChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool showUnreadDot = false,
    IconData? badgeIcon,
    String? badgeLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, size: 18),
            if (showUnreadDot)
              Positioned(
                right: -4,
                top: -4,
                child: Icon(
                  Icons.brightness_1,
                  size: 8,
                  color: Colors.redAccent,
                ),
              ),
            if (!showUnreadDot && badgeIcon != null)
              Positioned(
                right: -4,
                top: -4,
                child: Icon(badgeIcon, size: 10, color: Colors.redAccent),
              ),
          ],
        ),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            if (badgeLabel != null && badgeLabel.isNotEmpty) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          ],
        ),
        onPressed: onTap,
      ),
    );
  }

  Future<void> _loadShamellPluginsPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final showScan = await loadScopedPluginVisibilityPreference(
        key: _kShamellPluginShowScan,
        fallback: true,
        sp: sp,
        baseUrlOverride: _baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _pluginShowScan = showScan;
      });
    } catch (_) {}
  }

  bool _requiresAuthSessionForPage(Widget page) {
    return page is OfficialTemplateMessagesPage;
  }

  Future<bool> _ensureAuthSessionForGuardedNav() async {
    final cookie = (await _getCurrentBaseCookie())?.trim() ?? '';
    if (cookie.isNotEmpty) return true;
    if (!mounted) return false;
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          l.isArabic
              ? 'هذه الصفحة تتطلب تسجيل الدخول أولاً.'
              : 'This page requires sign in first.',
        ),
        action: SnackBarAction(
          label: l.isArabic ? 'تسجيل الدخول' : 'Sign in',
          onPressed: () {
            if (!mounted) return;
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const LoginPage()));
          },
        ),
      ),
    );
    return false;
  }

  void _navPush(Widget page, {VoidCallback? onReturn}) {
    unawaited(_navPushGuarded(page, onReturn: onReturn));
  }

  Future<void> _navPushGuarded(Widget page, {VoidCallback? onReturn}) async {
    if (_requiresAuthSessionForPage(page) &&
        !await _ensureAuthSessionForGuardedNav()) {
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
            child: page,
          ),
        ),
      ),
    );
    if (!mounted) return;
    _loadUnreadBadge();
    unawaited(_loadShamellPluginsPrefs());
    onReturn?.call();
  }

  @visibleForTesting
  Future<bool> debugEnsureAuthSessionForGuardedNav() async {
    return await _ensureAuthSessionForGuardedNav();
  }

  Future<void> _postSessionManagedAuthPath(
    List<String> pathSegments, {
    String? cookie,
  }) async {
    if (_hasInvalidExplicitBaseOverride) {
      return;
    }
    final uri = secureApiChildUri(
      baseUrl: _baseUrl,
      pathSegments: pathSegments,
    );
    if (uri == null) return;
    final httpClient = widget.client ?? shamellHttpClient();
    final closeClient = widget.client == null;
    try {
      final trimmedCookie = (cookie ?? '').trim();
      await httpClient
          .post(
            uri,
            headers: await shamellSessionHeadersForBaseUrl(
              _baseUrl,
              includeSessionCookie: false,
              extra: <String, String>{
                if (trimmedCookie.isNotEmpty) 'cookie': trimmedCookie,
              },
            ),
          )
          .timeout(_sessionMgmtRequestTimeout);
    } catch (_) {
    } finally {
      if (closeClient) {
        httpClient.close();
      }
    }
  }

  Future<String?> _getCurrentBaseCookie() async {
    if (_hasInvalidExplicitBaseOverride) {
      return null;
    }
    try {
      return await getSessionCookieHeader(_baseUrl);
    } catch (_) {
      return null;
    }
  }

  Future<void> _logout() async {
    if (_hasInvalidExplicitBaseOverride) {
      // Same soft-logout semantics as the normal path below: keep the
      // user's identity / contacts / chats / friend annotations across
      // a re-login. The full wipe lives in `_logoutForgetDevice`.
      unawaited(
        wipeLocalAccountData(
          preserveDevicePrefs: true,
          preserveContactsAndChats: true,
        ).catchError((_) {}),
      );
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        ),
      );
      return;
    }
    String? cookie;
    try {
      cookie = await _getCurrentBaseCookie();
      await bestEffortUnregisterCurrentChatPushToken(
        baseUrl: _baseUrl,
        client: widget.client,
      );
      await _postSessionManagedAuthPath(const <String>[
        'auth',
        'logout',
      ], cookie: cookie);
    } catch (_) {}
    // Soft logout: keep the user's chat identity, contacts, message
    // history, friend annotations, and per-thread notify prefs so the
    // next login resumes the same account state. "Forget Device" still
    // wipes everything; that path lives in `_logoutForgetDevice`.
    unawaited(
      wipeLocalAccountData(
        preserveDevicePrefs: true,
        preserveContactsAndChats: true,
      ).catchError((_) {}),
    );
    if (!mounted) return;
    unawaited(
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      ),
    );
  }

  Future<void> _logoutForgetDevice({bool skipConfirmation = false}) async {
    final l = L10n.of(context);
    final ok = skipConfirmation
        ? true
        : await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l.menuLogoutForgetDeviceConfirmTitle),
                content: Text(l.menuLogoutForgetDeviceConfirmBody),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: Text(l.shamellDialogCancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFA5151),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(l.menuLogoutForgetDeviceConfirmAction),
                  ),
                ],
              ),
            ) ??
            false;
    if (!ok) return;

    if (_hasInvalidExplicitBaseOverride) {
      await wipeLocalForForgetDevice();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
      return;
    }

    var cookie = '';
    try {
      cookie = (await _getCurrentBaseCookie())?.trim() ?? '';
    } catch (_) {}

    try {
      await bestEffortUnregisterCurrentChatPushToken(
        baseUrl: _baseUrl,
        client: widget.client,
      );
    } catch (_) {}

    try {
      final did =
          (await loadStableDeviceId(baseUrlOverride: _baseUrl) ?? '').trim();
      await forgetDeviceOnServer(
        baseUrl: _baseUrl,
        deviceId: did,
        sessionCookie: cookie,
        isArabic: l.isArabic,
        client: widget.client,
      );
    } on ForgetDeviceException catch (e) {
      if (e.isCriticalAccountSessionFailure) {
        await _forceReauthDueToDeviceBindingDrift();
        return;
      }
      if (await _handleCriticalAccountSessionError(e)) return;
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    try {
      await _postSessionManagedAuthPath(const <String>[
        'auth',
        'logout',
      ], cookie: cookie);
    } catch (_) {}

    await wipeLocalForForgetDevice();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @visibleForTesting
  Future<void> debugLogout() => _logout();

  @visibleForTesting
  Future<void> debugLogoutForgetDevice() =>
      _logoutForgetDevice(skipConfirmation: true);

  // removed duplicate dispose; handled earlier for timers

  Future<void> _changeAppMode(AppMode mode) async {
    final sp = await SharedPreferences.getInstance();
    await saveStoredAppModePreference(mode, sp: sp, baseUrlOverride: _baseUrl);
    if (!mounted) return;
    setState(() {
      _appMode = mode;
      _applyPrivilegeSnapshotHomeState(_privilegeSnapshot, _appMode);
    });
  }

  void _showModeSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final modes = <AppMode>[AppMode.user, AppMode.operator, AppMode.admin];
        return GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: Container(
            color: Colors.black54,
            child: GestureDetector(
              onTap: () {},
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: .98),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 4,
                          width: 44,
                          margin: const EdgeInsets.only(bottom: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const Text(
                          'App mode',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        ...modes.map((m) {
                          final selectedMode = _appMode == AppMode.auto
                              ? AppMode.user
                              : _appMode;
                          final isSelected = selectedMode == m;
                          return ListTile(
                            leading: Icon(
                              appModeIcon(m),
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            title: Text(appModeLabel(m)),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle)
                                : const SizedBox.shrink(),
                            onTap: () {
                              Navigator.pop(ctx);
                              _changeAppMode(m);
                            },
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShamellHomeBottomBarItem {
  final Widget icon;
  final Widget activeIcon;
  final String label;

  const _ShamellHomeBottomBarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class _ShamellGlassAppBarBackdrop extends StatelessWidget {
  const _ShamellGlassAppBarBackdrop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? Tokens.darkScaffold : Tokens.lightScaffold,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: isDark ? .50 : .86),
            width: .7,
          ),
        ),
      ),
    );
  }
}

class _ShamellHomeBottomBar extends StatelessWidget {
  final int currentIndex;
  final List<_ShamellHomeBottomBarItem> items;
  final ValueChanged<int> onTap;

  const _ShamellHomeBottomBar({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isDark = theme.brightness == Brightness.dark;
    final compact = width < 430;
    final barHeight = compact ? 54.0 : 56.0;
    final selectedColor = theme.bottomNavigationBarTheme.selectedItemColor ??
        theme.colorScheme.primary;
    final unselectedColor =
        theme.bottomNavigationBarTheme.unselectedItemColor ??
            theme.colorScheme.onSurface.withValues(alpha: .54);
    final surfaceColor = theme.bottomNavigationBarTheme.backgroundColor ??
        (isDark ? const Color(0xFF121B18) : Colors.white);
    final iconSize = compact ? 21.0 : 22.0;
    final selectedStyle = theme.textTheme.labelSmall?.copyWith(
      color: selectedColor,
      fontSize: compact ? 10.8 : 11.2,
      fontWeight: FontWeight.w700,
      height: 1.05,
    );
    final unselectedStyle = theme.textTheme.labelSmall?.copyWith(
      color: unselectedColor,
      fontSize: compact ? 10.6 : 10.8,
      fontWeight: FontWeight.w600,
      height: 1.05,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: isDark ? .50 : .86),
            width: .7,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 1),
        child: Material(
          color: surfaceColor,
          child: SizedBox(
            height: barHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: _ShamellHomeBottomBarButton(
                      item: items[i],
                      selected: i == currentIndex,
                      selectedColor: selectedColor,
                      unselectedColor: unselectedColor,
                      iconSize: iconSize,
                      selectedStyle: selectedStyle,
                      unselectedStyle: unselectedStyle,
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShamellHomeBottomBarButton extends StatelessWidget {
  final _ShamellHomeBottomBarItem item;
  final bool selected;
  final Color selectedColor;
  final Color unselectedColor;
  final double iconSize;
  final TextStyle? selectedStyle;
  final TextStyle? unselectedStyle;
  final VoidCallback onTap;

  const _ShamellHomeBottomBarButton({
    required this.item,
    required this.selected,
    required this.selectedColor,
    required this.unselectedColor,
    required this.iconSize,
    required this.selectedStyle,
    required this.unselectedStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? selectedColor : unselectedColor;
    final style = selected ? selectedStyle : unselectedStyle;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: Tokens.motionBase,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: selected ? 4 : 2,
              vertical: 3,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme.merge(
                  data: IconThemeData(color: color, size: iconSize),
                  child: selected ? item.activeIcon : item.icon,
                ),
                const SizedBox(height: 2),
                DefaultTextStyle.merge(
                  style: style,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShamellBottomNavBadgeIcon extends StatelessWidget {
  final IconData icon;
  final bool showBadge;

  const _ShamellBottomNavBadgeIcon({
    required this.icon,
    required this.showBadge,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (showBadge)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
