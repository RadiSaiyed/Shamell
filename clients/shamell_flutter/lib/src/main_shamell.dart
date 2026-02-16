part of '../main.dart';

class ProfilePage extends StatefulWidget {
  final String baseUrl;
  const ProfilePage(this.baseUrl, {super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String phone = '';
  String walletId = '';
  String name = '';
  String shamellId = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      try {
        final sp = await SharedPreferences.getInstance();
        name = sp.getString('last_login_name') ?? '';
        phone = sp.getString('last_login_phone') ?? '';
        walletId = sp.getString('wallet_id') ?? '';
        if (shamellId.trim().isEmpty) {
          shamellId = await getOrCreateShamellUserId(sp: sp);
        }
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Uri _inviteUri(String token) {
    return Uri(
      scheme: 'shamell',
      host: 'invite',
      queryParameters: <String, String>{'token': token},
    );
  }

  void _showInviteQr() {
    final l = L10n.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<String>(
            future: ChatService(widget.baseUrl).createContactInviteToken(maxUses: 1),
            builder: (ctx, snap) {
              final token = (snap.data ?? '').toString().trim();
              final payload =
                  token.isNotEmpty ? _inviteUri(token).toString() : '';

              Widget qrContent() {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(
                    width: 220,
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final err = snap.error;
                if (err != null) {
                  return Text(
                    sanitizeExceptionForUi(error: err, isArabic: l.isArabic),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  );
                }
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 220,
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    l.isArabic ? 'رمز الدعوة' : 'Invite QR code',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  qrContent(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: payload.isEmpty
                              ? null
                              : () async {
                                  try {
                                    await Clipboard.setData(
                                      ClipboardData(text: payload),
                                    );
                                  } catch (_) {}
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l.isArabic
                                            ? 'تم نسخ الرابط.'
                                            : 'Invite link copied.',
                                      ),
                                    ),
                                  );
                                },
                          child: Text(l.isArabic ? 'نسخ' : 'Copy'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: payload.isEmpty
                              ? null
                              : () async {
                                  try {
                                    await Share.share(payload);
                                  } catch (_) {}
                                },
                          child: Text(l.isArabic ? 'مشاركة' : 'Share'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.isArabic
                        ? 'اطلب من صديقك مسح هذا الرمز لإضافتك.'
                        : 'Ask a friend to scan this code to add you.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: .70),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    String _avatarInitial() {
      final n = name.trim();
      if (n.isNotEmpty) {
        return n.characters.first.toUpperCase();
      }
      final p = phone.trim();
      if (p.isNotEmpty) {
        return p.characters.last;
      }
      return '?';
    }

    final content = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _showInviteQr,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  child: Text(
                    _avatarInitial(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? l.labelName : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l.isArabic ? 'معرّف Shamell' : 'Shamell ID',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .70),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            shamellId.isEmpty ? '-' : shamellId,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          phone,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: .70),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.qr_code_2_outlined),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          l.isArabic ? 'الحساب' : 'Account',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: .80),
          ),
        ),
        const SizedBox(height: 4),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(l.labelWalletId),
          subtitle: Text(walletId.isEmpty ? '-' : walletId),
          trailing: walletId.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: walletId));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l.msgWalletCopied),
                        ),
                      );
                    }
                  },
                ),
        ),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(l.labelName),
          subtitle: Text(name.isEmpty ? '-' : name),
        ),
        ListTile(
          leading: const Icon(Icons.phone_iphone),
          title: Text(l.labelPhone),
          subtitle: Text(phone.isEmpty ? '-' : phone),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l.profileTitle),
        elevation: 0,
      ),
      body: SafeArea(
        child: content,
      ),
    );
  }
}

class CardsOffersPage extends StatelessWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;

  const CardsOffersPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'البطاقات والعروض' : 'Cards & Offers'),
        elevation: 0,
      ),
      body: Container(
        color: bgColor,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            ShamellSection(
              margin: const EdgeInsets.only(top: 0),
              children: [
                ListTile(
                  dense: true,
                  leading: const ShamellLeadingIcon(
                    icon: Icons.card_giftcard_outlined,
                    background: Color(0xFFF59E0B),
                  ),
                  title: Text(l.isArabic ? 'قسائم' : 'Vouchers'),
                  trailing: chevron(),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CashMandatePage(baseUrl),
                      ),
                    );
                  },
                ),
                if (walletId.trim().isNotEmpty)
                  ListTile(
                    dense: true,
                    leading: const ShamellLeadingIcon(
                      icon: Icons.pending_actions_outlined,
                      background: Color(0xFF3B82F6),
                    ),
                    title:
                        Text(l.isArabic ? 'طلبات الدفع' : 'Payment requests'),
                    trailing: chevron(),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RequestsPage(
                            baseUrl: baseUrl,
                            walletId: walletId,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ShamellSettingsPage extends StatelessWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final String profileName;
  final String profilePhone;
  final String profileShamellId;
  final bool showOps;
  final bool showSuperadmin;
  final bool hasDefaultOfficialAccount;
  final int miniProgramsCount;
  final int miniProgramsTotalUsage;
  final int miniProgramsMoments30d;
  final Future<void> Function() onOpenOfficialNotifications;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutForgetDevice;
  final void Function(Widget page) pushPage;
  final void Function(String modId) onOpenMod;

  const ShamellSettingsPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.profileName,
    required this.profilePhone,
    required this.profileShamellId,
    required this.showOps,
    required this.showSuperadmin,
    required this.hasDefaultOfficialAccount,
    required this.miniProgramsCount,
    required this.miniProgramsTotalUsage,
    required this.miniProgramsMoments30d,
    required this.onOpenOfficialNotifications,
    required this.onLogout,
    required this.onLogoutForgetDevice,
    required this.pushPage,
    required this.onOpenMod,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    Future<void> openOfficialOwnerConsole() async {
      try {
        final sp = await SharedPreferences.getInstance();
        final accId = sp.getString('official.default_account_id') ?? '';
        final accName = sp.getString('official.default_account_name') ?? '';
        if (accId.isEmpty) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l.isArabic
                    ? 'لا يوجد حساب رسمي مرتبط لهذا المستخدم.'
                    : 'No default official account linked to this user.',
              ),
            ),
          );
          return;
        }
        pushPage(
          OfficialOwnerConsolePage(
            baseUrl: baseUrl,
            accountId: accId,
            accountName: accName.isNotEmpty ? accName : accId,
          ),
        );
      } catch (_) {}
    }

    final showDev = showOps || showSuperadmin;
    final showMiniDev = miniProgramsCount > 0 || showOps;

    Future<void> confirmSwitchAccount() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(l.isArabic ? 'تبديل الحساب' : 'Switch Account'),
            content: Text(
              l.isArabic
                  ? 'سيتم تسجيل الخروج من هذا الحساب ثم يمكنك تسجيل الدخول بحساب آخر.'
                  : 'You will be logged out, then you can sign in with another account.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l.shamellDialogCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l.isArabic ? 'تبديل' : 'Switch'),
              ),
            ],
          );
        },
      );
      if (ok != true) return;
      await onLogout();
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.settingsTitle),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          ShamellSection(
            margin: const EdgeInsets.only(top: 0),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'أمان الحساب' : 'Account Security',
                ),
                trailing: chevron(),
                onTap: () {
                  pushPage(
                    ShamellSettingsAccountSecurityPage(
                      baseUrl: baseUrl,
                      deviceId: deviceId,
                      profileName: profileName,
                      profileId: profileShamellId,
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic
                      ? 'إشعار الرسائل الجديدة'
                      : 'New Message Notification',
                ),
                trailing: chevron(),
                onTap: () {
                  pushPage(
                    shamell_settings_notif.ShamellNewMessageNotificationPage(
                      baseUrl: baseUrl,
                    ),
                  );
                },
                onLongPress: showDev
                    ? () {
                        pushPage(
                          OfficialNotificationsDebugPage(baseUrl: baseUrl),
                        );
                      }
                    : null,
              ),
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'إشعارات الخدمات' : 'Service notifications',
                ),
                trailing: chevron(),
                onTap: () {
                  pushPage(OfficialTemplateMessagesPage(baseUrl: baseUrl));
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الخصوصية' : 'Privacy'),
                trailing: chevron(),
                onTap: () {
                  pushPage(
                    ShamellSettingsPrivacyPage(
                      baseUrl: baseUrl,
                      deviceId: deviceId,
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'عام' : 'General'),
                trailing: chevron(),
                onTap: () {
                  pushPage(const ShamellSettingsGeneralPage());
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                    l.isArabic ? 'المساعدة والملاحظات' : 'Help & Feedback'),
                trailing: chevron(),
                onTap: () {
                  pushPage(const ShamellHelpFeedbackPage());
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'حول شامل' : 'About Shamell'),
                trailing: chevron(),
                onTap: () {
                  pushPage(const ShamellSettingsAboutPage());
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الإضافات' : 'Plugins'),
                trailing: chevron(),
                onTap: () {
                  pushPage(const ShamellPluginsPage());
                },
              ),
            ],
          ),
          if (hasDefaultOfficialAccount || showMiniDev || showDev)
            ShamellSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                if (hasDefaultOfficialAccount)
                  ListTile(
                    dense: true,
                    title: Text(
                      l.isArabic
                          ? 'مركز الحساب الرسمي'
                          : 'Official account console',
                    ),
                    trailing: chevron(),
                    onTap: () async {
                      await openOfficialOwnerConsole();
                    },
                  ),
                if (showMiniDev)
                  ListTile(
                    dense: true,
                    title: Text(
                      l.isArabic ? 'برامجي المصغّرة' : 'My mini‑programs',
                    ),
                    subtitle: miniProgramsCount > 0
                        ? Text(
                            l.isArabic
                                ? 'عدد البرامج: $miniProgramsCount · الفتحات: $miniProgramsTotalUsage · اللحظات (٣٠ يوماً): $miniProgramsMoments30d'
                                : 'Mini‑programs: $miniProgramsCount · Opens: $miniProgramsTotalUsage · Moments (30d): $miniProgramsMoments30d',
                          )
                        : null,
                    trailing: chevron(),
                    onTap: () {
                      pushPage(
                        MyMiniProgramsPage(
                          baseUrl: baseUrl,
                          walletId: walletId,
                          deviceId: deviceId,
                          onOpenMod: onOpenMod,
                        ),
                      );
                    },
                  ),
                if (showDev)
                  ListTile(
                    dense: true,
                    title: Text(l.isArabic ? 'إعدادات المطور' : 'Developer'),
                    trailing: chevron(),
                    onTap: () {
                      pushPage(
                        SettingsPage(baseUrl: baseUrl, walletId: walletId),
                      );
                    },
                  ),
              ],
            ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'تبديل الحساب' : 'Switch Account'),
                trailing: chevron(),
                onTap: confirmSwitchAccount,
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Center(
                  child: Text(
                    l.isArabic ? 'تسجيل الخروج' : 'Log out',
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                onTap: () async {
                  await onLogout();
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.menuLogoutForgetDevice,
                  style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  l.menuLogoutForgetDeviceSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFEF4444).withValues(alpha: .80),
                  ),
                ),
                onTap: () async {
                  await onLogoutForgetDevice();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellHelpFeedbackPage extends StatelessWidget {
  const ShamellHelpFeedbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    void snack(String msg) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(msg)));
    }

    Future<void> openHelpCenter() async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ShamellHelpCenterPage(),
        ),
      );
    }

    Future<void> sendFeedback() async {
      const email = 'radisaiyed@icloud.com';
      final subject = Uri.encodeComponent('Shamell Feedback');
      final uri = Uri.parse('mailto:$email?subject=$subject');
      try {
        final ok = await launchUrl(uri);
        if (!ok) {
          snack(l.isArabic ? 'تعذّر فتح البريد.' : 'Could not open email.');
        }
      } catch (_) {
        snack(l.isArabic ? 'تعذّر فتح البريد.' : 'Could not open email.');
      }
    }

    Future<void> contactSupport() async {
      const phone = '+963996428955';
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final t = Theme.of(ctx);
          final isDark2 = t.brightness == Brightness.dark;
          final sheetBg = isDark2 ? t.colorScheme.surface : Colors.white;
          Icon sheetChevron() => Icon(
                l.isArabic ? Icons.chevron_left : Icons.chevron_right,
                size: 18,
                color: t.colorScheme.onSurface.withValues(alpha: .40),
              );

          Widget card(List<Widget> children) {
            return Material(
              color: sheetBg,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            );
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  card([
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'اتصال' : 'Call'),
                      subtitle: const Text(phone),
                      trailing: sheetChevron(),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        try {
                          await launchUrl(Uri.parse('tel:$phone'));
                        } catch (_) {}
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'البريد الإلكتروني' : 'Email'),
                      subtitle: const Text('radisaiyed@icloud.com'),
                      trailing: sheetChevron(),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await sendFeedback();
                      },
                    ),
                  ]),
                  const SizedBox(height: 8),
                  card([
                    ListTile(
                      dense: true,
                      title: Center(
                        child: Text(
                          l.shamellDialogCancel,
                          style: TextStyle(
                            color: t.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'المساعدة والملاحظات' : 'Help & Feedback'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'مركز المساعدة' : 'Help center'),
                trailing: chevron(),
                onTap: () => openHelpCenter(),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'إرسال ملاحظات' : 'Feedback'),
                trailing: chevron(),
                onTap: () => sendFeedback(),
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الاتصال بالدعم' : 'Contact support'),
                trailing: chevron(),
                onTap: () => contactSupport(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellHelpCenterPage extends StatelessWidget {
  const ShamellHelpCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    TextStyle? hintStyle() => theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: .60),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'مركز المساعدة' : 'Help center'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            margin: const EdgeInsets.only(top: 8),
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'تسجيل الدخول' : 'Sign in'),
                subtitle: Text(
                  l.isArabic
                      ? 'استخدم القياسات الحيوية على جهازك لتسجيل الدخول.'
                      : 'Sign in using biometrics on your device.',
                  style: hintStyle(),
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الإشعارات' : 'Notifications'),
                subtitle: Text(
                  l.isArabic
                      ? 'يمكنك تعديل المعاينة/الصوت/الاهتزاز/عدم الإزعاج من الإعدادات.'
                      : 'Adjust preview/sound/vibrate/DND in Settings.',
                  style: hintStyle(),
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الخصوصية' : 'Privacy'),
                subtitle: Text(
                  l.isArabic
                      ? 'تحكم في طرق الإضافة وقائمة الحظر من صفحة الخصوصية.'
                      : 'Manage add‑me methods and blocked list in Privacy.',
                  style: hintStyle(),
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs'),
                subtitle: Text(
                  l.isArabic
                      ? 'افتح مركز البرامج المصغّرة من الاستكشاف أو من سحب الدردشة للأسفل.'
                      : 'Open the Mini‑Programs hub from Discover or Chat pull‑down.',
                  style: hintStyle(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellPluginsPage extends StatefulWidget {
  const ShamellPluginsPage({super.key});

  @override
  State<ShamellPluginsPage> createState() => _ShamellPluginsPageState();
}

class _ShamellPluginsPageState extends State<ShamellPluginsPage> {
  bool _loading = true;
  bool _moments = true;
  bool _channels = true;
  bool _scan = true;
  bool _miniPrograms = true;
  bool _cardsOffers = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _moments = sp.getBool(_kShamellPluginShowMoments) ?? true;
        _channels = sp.getBool(_kShamellPluginShowChannels) ?? true;
        _scan = sp.getBool(_kShamellPluginShowScan) ?? true;
        _miniPrograms = sp.getBool(_kShamellPluginShowMiniPrograms) ?? true;
        _cardsOffers = sp.getBool(_kShamellPluginShowCardsOffers) ?? true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _setBool(String key, bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, v);
    } catch (_) {}
  }

  Future<void> _toggle({
    required String key,
    required bool value,
    required void Function(bool v) assign,
  }) async {
    final next = !value;
    setState(() => assign(next));
    await _setBool(key, next);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'الإضافات' : 'Plugins'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ShamellSection(
                  dividerIndent: 16,
                  dividerEndIndent: 16,
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'اللحظات' : 'Moments'),
                      trailing: Switch(
                        value: _moments,
                        onChanged: (v) async {
                          setState(() => _moments = v);
                          await _setBool(_kShamellPluginShowMoments, v);
                        },
                      ),
                      onTap: () => _toggle(
                        key: _kShamellPluginShowMoments,
                        value: _moments,
                        assign: (v) => _moments = v,
                      ),
                    ),
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'القنوات' : 'Channels'),
                      trailing: Switch(
                        value: _channels,
                        onChanged: (v) async {
                          setState(() => _channels = v);
                          await _setBool(_kShamellPluginShowChannels, v);
                        },
                      ),
                      onTap: () => _toggle(
                        key: _kShamellPluginShowChannels,
                        value: _channels,
                        assign: (v) => _channels = v,
                      ),
                    ),
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'مسح' : 'Scan'),
                      trailing: Switch(
                        value: _scan,
                        onChanged: (v) async {
                          setState(() => _scan = v);
                          await _setBool(_kShamellPluginShowScan, v);
                        },
                      ),
                      onTap: () => _toggle(
                        key: _kShamellPluginShowScan,
                        value: _scan,
                        assign: (v) => _scan = v,
                      ),
                    ),
                    ListTile(
                      dense: true,
                      title: Text(
                          l.isArabic ? 'البرامج المصغّرة' : 'Mini‑programs'),
                      trailing: Switch(
                        value: _miniPrograms,
                        onChanged: (v) async {
                          setState(() => _miniPrograms = v);
                          await _setBool(_kShamellPluginShowMiniPrograms, v);
                        },
                      ),
                      onTap: () => _toggle(
                        key: _kShamellPluginShowMiniPrograms,
                        value: _miniPrograms,
                        assign: (v) => _miniPrograms = v,
                      ),
                    ),
                  ],
                ),
                ShamellSection(
                  dividerIndent: 16,
                  dividerEndIndent: 16,
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(
                          l.isArabic ? 'البطاقات والعروض' : 'Cards & Offers'),
                      trailing: Switch(
                        value: _cardsOffers,
                        onChanged: (v) async {
                          setState(() => _cardsOffers = v);
                          await _setBool(_kShamellPluginShowCardsOffers, v);
                        },
                      ),
                      onTap: () => _toggle(
                        key: _kShamellPluginShowCardsOffers,
                        value: _cardsOffers,
                        assign: (v) => _cardsOffers = v,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Text(
                    l.isArabic
                        ? 'تتحكم الإضافات بما يظهر في تبويبي الاستكشاف/أنا.'
                        : 'Plugins control what shows up in Discover/Me tabs.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: .55),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class ShamellAccountSecurityPage extends StatefulWidget {
  final String baseUrl;
  final String profileName;
  final String profilePhone;
  final String profileShamellId;

  const ShamellAccountSecurityPage({
    super.key,
    required this.baseUrl,
    required this.profileName,
    required this.profilePhone,
    required this.profileShamellId,
  });

  @override
  State<ShamellAccountSecurityPage> createState() =>
      _ShamellAccountSecurityPageState();
}

class ShamellNewMessageNotificationPage extends StatefulWidget {
  const ShamellNewMessageNotificationPage({super.key});

  @override
  State<ShamellNewMessageNotificationPage> createState() =>
      _ShamellNewMessageNotificationPageState();
}

class _ShamellNewMessageNotificationPageState
    extends State<ShamellNewMessageNotificationPage> {
  final ChatLocalStore _store = ChatLocalStore();

  bool _loading = true;
  bool _enabled = true;
  bool _preview = false;
  bool _sound = true;
  bool _vibrate = true;
  bool _dnd = false;
  int _dndStartMinutes = 22 * 60;
  int _dndEndMinutes = 8 * 60;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await _store.loadNotifyConfig();
      if (!mounted) return;
      setState(() {
        _enabled = prefs.enabled;
        _preview = prefs.preview;
        _sound = prefs.sound;
        _vibrate = prefs.vibrate;
        _dnd = prefs.dnd;
        _dndStartMinutes = prefs.dndStart;
        _dndEndMinutes = prefs.dndEnd;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  String _formatMinutes(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _formatDndRange() =>
      '${_formatMinutes(_dndStartMinutes)} - ${_formatMinutes(_dndEndMinutes)}';

  Future<void> _setEnabled(bool v) async {
    setState(() => _enabled = v);
    await _store.setNotifyEnabled(v);
  }

  Future<void> _setPreview(bool v) async {
    setState(() => _preview = v);
    await _store.setNotifyPreview(v);
  }

  Future<void> _setSound(bool v) async {
    setState(() => _sound = v);
    await _store.setNotifySound(v);
  }

  Future<void> _setVibrate(bool v) async {
    setState(() => _vibrate = v);
    await _store.setNotifyVibrate(v);
  }

  Future<void> _setDnd(bool v) async {
    setState(() => _dnd = v);
    await _store.setNotifyDndEnabled(v);
  }

  Future<void> _pickDndSchedule() async {
    final start = TimeOfDay(
      hour: (_dndStartMinutes ~/ 60) % 24,
      minute: _dndStartMinutes % 60,
    );
    final end = TimeOfDay(
      hour: (_dndEndMinutes ~/ 60) % 24,
      minute: _dndEndMinutes % 60,
    );

    final pickedStart = await showTimePicker(
      context: context,
      initialTime: start,
    );
    if (pickedStart == null || !mounted) return;

    final pickedEnd = await showTimePicker(
      context: context,
      initialTime: end,
    );
    if (pickedEnd == null || !mounted) return;

    final startMinutes =
        (pickedStart.hour * 60 + pickedStart.minute) % (24 * 60);
    final endMinutes = (pickedEnd.hour * 60 + pickedEnd.minute) % (24 * 60);
    setState(() {
      _dndStartMinutes = startMinutes;
      _dndEndMinutes = endMinutes;
    });
    await _store.setNotifyDndSchedule(
      startMinutes: startMinutes,
      endMinutes: endMinutes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron({bool enabled = true}) => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface
              .withValues(alpha: enabled ? .40 : .20),
        );

    Widget trailingValueChevron(String value, {required bool enabled}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(
                alpha: enabled ? .55 : .30,
              ),
            ),
          ),
          const SizedBox(width: 6),
          chevron(enabled: enabled),
        ],
      );
    }

    final canAdjust = _enabled;
    final canAdjustDndSchedule = _enabled && _dnd;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'إشعار الرسائل الجديدة' : 'New Message Notification',
        ),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ShamellSection(
                  dividerIndent: 16,
                  dividerEndIndent: 16,
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(
                        l.isArabic
                            ? 'إشعار الرسائل الجديدة'
                            : 'New Message Notification',
                      ),
                      trailing: Switch.adaptive(
                        value: _enabled,
                        onChanged: _setEnabled,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onTap: () => _setEnabled(!_enabled),
                    ),
                  ],
                ),
                ShamellSection(
                  dividerIndent: 16,
                  dividerEndIndent: 16,
                  children: [
                    ListTile(
                      dense: true,
                      enabled: canAdjust,
                      title: Text(
                          l.isArabic ? 'معاينة الرسائل' : 'Message preview'),
                      trailing: Switch.adaptive(
                        value: _preview,
                        onChanged: canAdjust ? _setPreview : null,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onTap: canAdjust ? () => _setPreview(!_preview) : null,
                    ),
                    ListTile(
                      dense: true,
                      enabled: canAdjust,
                      title: Text(l.isArabic ? 'الصوت' : 'Sound'),
                      trailing: Switch.adaptive(
                        value: _sound,
                        onChanged: canAdjust ? _setSound : null,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onTap: canAdjust ? () => _setSound(!_sound) : null,
                    ),
                    ListTile(
                      dense: true,
                      enabled: canAdjust,
                      title: Text(l.isArabic ? 'الاهتزاز' : 'Vibrate'),
                      trailing: Switch.adaptive(
                        value: _vibrate,
                        onChanged: canAdjust ? _setVibrate : null,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onTap: canAdjust ? () => _setVibrate(!_vibrate) : null,
                    ),
                  ],
                ),
                ShamellSection(
                  dividerIndent: 16,
                  dividerEndIndent: 16,
                  children: [
                    ListTile(
                      dense: true,
                      enabled: canAdjust,
                      title:
                          Text(l.isArabic ? 'عدم الإزعاج' : 'Do Not Disturb'),
                      trailing: Switch.adaptive(
                        value: _dnd,
                        onChanged: canAdjust ? _setDnd : null,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onTap: canAdjust ? () => _setDnd(!_dnd) : null,
                    ),
                    ListTile(
                      dense: true,
                      enabled: canAdjustDndSchedule,
                      title:
                          Text(l.isArabic ? 'الفترة الزمنية' : 'Time Period'),
                      trailing: trailingValueChevron(
                        _formatDndRange(),
                        enabled: canAdjustDndSchedule,
                      ),
                      onTap: canAdjustDndSchedule ? _pickDndSchedule : null,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Text(
                    l.isArabic
                        ? 'عند إيقاف معاينة الرسائل ستظهر الإشعارات \"رسالة جديدة\" فقط.\nعدم الإزعاج يكتم التنبيهات خلال الفترة الزمنية.\nقد تتجاوز إعدادات النظام هذه الخيارات.'
                        : 'When Message preview is off, notifications show “New message” only.\nDo Not Disturb mutes alerts during the time period.\nSystem notification settings may override these options.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: .55),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ShamellAccountSecurityPageState extends State<ShamellAccountSecurityPage> {
  bool _requireBiometrics = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final require = sp.getBool('require_biometrics') ?? false;
      if (!mounted) return;
      setState(() {
        _requireBiometrics = require;
      });
    } catch (_) {}
  }

  Future<void> _setRequireBiometrics(bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('require_biometrics', v);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _requireBiometrics = v;
    });
  }

  Future<void> _copy(String text, String message) async {
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      await Clipboard.setData(ClipboardData(text: t));
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    final shamellId = widget.profileShamellId.trim();
    final phone = widget.profilePhone.trim();

    Widget trailingValue(String value) {
      final v = value.trim();
      return Text(
        v.isEmpty ? (l.isArabic ? 'غير مضبوط' : 'Not set') : v,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'أمان الحساب' : 'Account Security'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'معرّف شامل' : 'Shamell ID'),
                trailing: trailingValue(shamellId),
                onTap: () {
                  _copy(
                    shamellId,
                    l.isArabic ? 'تم نسخ المعرّف.' : 'Shamell ID copied.',
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'رقم الهاتف' : 'Phone'),
                trailing: trailingValue(phone),
                onTap: () {
                  _copy(
                    phone,
                    l.isArabic ? 'تم نسخ رقم الهاتف.' : 'Phone number copied.',
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'كلمة المرور' : 'Password'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellSettingsPasswordPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الأجهزة المرتبطة' : 'Linked devices'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DevicesPage(baseUrl: widget.baseUrl),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(
                    l.isArabic ? 'جهة اتصال الطوارئ' : 'Emergency contact'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ShamellSettingsEmergencyContactPage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'مركز الأمان' : 'Security Center'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShamellSettingsSecurityCenterPage(
                        baseUrl: widget.baseUrl,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'تسجيل الدخول بالبصمة' : 'Login with biometrics',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'اطلب المصادقة عند فتح التطبيق.'
                      : 'Require authentication when opening the app.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
                trailing: Switch(
                  value: _requireBiometrics,
                  onChanged: _setRequireBiometrics,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellPrivacyPage extends StatefulWidget {
  final String baseUrl;
  final String deviceId;

  const ShamellPrivacyPage({
    super.key,
    required this.baseUrl,
    required this.deviceId,
  });

  @override
  State<ShamellPrivacyPage> createState() => _ShamellPrivacyPageState();
}

class _ShamellPrivacyPageState extends State<ShamellPrivacyPage> {
  static const _kFriendVerification = 'shamell.privacy.friend_verification';
  bool _friendVerification = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getBool(_kFriendVerification);
      if (!mounted) return;
      setState(() {
        _friendVerification = v ?? true;
      });
    } catch (_) {}
  }

  Future<void> _setFriendVerification(bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kFriendVerification, v);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _friendVerification = v;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'الخصوصية' : 'Privacy'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'تأكيد الأصدقاء' : 'Friend verification',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'يتطلب تأكيداً عند إضافة صديق.'
                      : 'Require confirmation when adding a friend.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: .55),
                  ),
                ),
                trailing: Switch(
                  value: _friendVerification,
                  onChanged: _setFriendVerification,
                ),
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'طرق إضافة صديق' : 'Ways to add me'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellPrivacyAddMePage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'اللحظات والحالة' : 'Moments & Status',
                ),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellPrivacyMomentsPage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'القائمة المحظورة' : 'Blocked list'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShamellPrivacyBlockedListPage(
                        baseUrl: widget.baseUrl,
                        deviceId: widget.deviceId,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellPrivacyAddMePage extends StatefulWidget {
  const ShamellPrivacyAddMePage({super.key});

  @override
  State<ShamellPrivacyAddMePage> createState() => _ShamellPrivacyAddMePageState();
}

class _ShamellPrivacyAddMePageState extends State<ShamellPrivacyAddMePage> {
  static const _kAddById = 'shamell.privacy.add_me.by_id';
  static const _kAddByQr = 'shamell.privacy.add_me.by_qr';
  static const _kAddByGroup = 'shamell.privacy.add_me.by_group';
  static const _kAddByCard = 'shamell.privacy.add_me.by_card';

  bool _byId = true;
  bool _byQr = true;
  bool _byGroup = true;
  bool _byCard = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _byId = sp.getBool(_kAddById) ?? true;
        _byQr = sp.getBool(_kAddByQr) ?? true;
        _byGroup = sp.getBool(_kAddByGroup) ?? true;
        _byCard = sp.getBool(_kAddByCard) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _set(String key, bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    TextStyle? hintStyle() => theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'طرق إضافة صديق' : 'Ways to add me'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'معرّف شامل' : 'Shamell ID'),
                subtitle: Text(
                  l.isArabic
                      ? 'السماح بالإضافة عبر المعرّف.'
                      : 'Allow adding me via ID.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _byId,
                  onChanged: (v) async {
                    setState(() => _byId = v);
                    await _set(_kAddById, v);
                  },
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'رمز QR' : 'QR code'),
                subtitle: Text(
                  l.isArabic
                      ? 'السماح بالإضافة عبر رمز QR.'
                      : 'Allow adding me via QR.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _byQr,
                  onChanged: (v) async {
                    setState(() => _byQr = v);
                    await _set(_kAddByQr, v);
                  },
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الدردشة الجماعية' : 'Group chats'),
                subtitle: Text(
                  l.isArabic
                      ? 'السماح بالإضافة عبر المجموعات.'
                      : 'Allow adding me via group chats.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _byGroup,
                  onChanged: (v) async {
                    setState(() => _byGroup = v);
                    await _set(_kAddByGroup, v);
                  },
                ),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'بطاقة الاسم' : 'Business card'),
                subtitle: Text(
                  l.isArabic
                      ? 'السماح بالإضافة عبر بطاقة الاسم.'
                      : 'Allow adding me via business card.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _byCard,
                  onChanged: (v) async {
                    setState(() => _byCard = v);
                    await _set(_kAddByCard, v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellPrivacyMomentsPage extends StatefulWidget {
  const ShamellPrivacyMomentsPage({super.key});

  @override
  State<ShamellPrivacyMomentsPage> createState() =>
      _ShamellPrivacyMomentsPageState();
}

class _ShamellPrivacyMomentsPageState extends State<ShamellPrivacyMomentsPage> {
  static const _kStrangersTenPosts =
      'shamell.privacy.moments.allow_strangers_ten_posts';
  static const _kUpdateReminders = 'shamell.privacy.moments.update_reminders';
  static const _kStatusVisible = 'shamell.privacy.status.visible_to_others';

  bool _strangersTenPosts = true;
  bool _updateReminders = true;
  bool _statusVisible = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _strangersTenPosts = sp.getBool(_kStrangersTenPosts) ?? true;
        _updateReminders = sp.getBool(_kUpdateReminders) ?? true;
        _statusVisible = sp.getBool(_kStatusVisible) ?? true;
      });
    } catch (_) {}
  }

  Future<void> _setBool(String key, bool v) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(key, v);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    TextStyle? hintStyle() => theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'اللحظات والحالة' : 'Moments & Status'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic
                      ? 'السماح للغرباء بمشاهدة 10 منشورات'
                      : 'Allow strangers to view ten posts',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'يمكن لغير الأصدقاء رؤية آخر 10 منشورات في اللحظات.'
                      : 'Non-friends can view your last 10 Moments posts.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _strangersTenPosts,
                  onChanged: (v) async {
                    setState(() => _strangersTenPosts = v);
                    await _setBool(_kStrangersTenPosts, v);
                  },
                ),
              ),
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic ? 'تذكير بالتحديثات' : 'Update reminders',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'اعرض تذكيرات عند نشر الأصدقاء تحديثات في اللحظات.'
                      : 'Show reminders when friends post in Moments.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _updateReminders,
                  onChanged: (v) async {
                    setState(() => _updateReminders = v);
                    await _setBool(_kUpdateReminders, v);
                  },
                ),
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l.isArabic
                      ? 'عرض الحالة للآخرين'
                      : 'Show my Status to others',
                ),
                subtitle: Text(
                  l.isArabic
                      ? 'اسمح للآخرين بمشاهدة حالتك.'
                      : 'Allow others to view your Status.',
                  style: hintStyle(),
                ),
                trailing: Switch(
                  value: _statusVisible,
                  onChanged: (v) async {
                    setState(() => _statusVisible = v);
                    await _setBool(_kStatusVisible, v);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellPrivacyBlockedListPage extends StatefulWidget {
  final String baseUrl;
  final String deviceId;

  const ShamellPrivacyBlockedListPage({
    super.key,
    required this.baseUrl,
    required this.deviceId,
  });

  @override
  State<ShamellPrivacyBlockedListPage> createState() =>
      _ShamellPrivacyBlockedListPageState();
}

class _ShamellPrivacyBlockedListPageState
    extends State<ShamellPrivacyBlockedListPage> {
  final ChatLocalStore _store = ChatLocalStore();
  late final ChatService _service;

  bool _loading = true;
  List<ChatContact> _blocked = const <ChatContact>[];
  Map<String, String> _aliases = const <String, String>{};

  @override
  void initState() {
    super.initState();
    _service = ChatService(widget.baseUrl);
    _load();
  }

  Future<void> _load() async {
    try {
      final contacts = await _store.loadContacts();
      final aliases = await _loadAliases();
      final blocked = contacts.where((c) => c.blocked).toList()
        ..sort((a, b) => _displayFor(a, aliases)
            .toLowerCase()
            .compareTo(_displayFor(b, aliases).toLowerCase()));
      if (!mounted) return;
      setState(() {
        _blocked = blocked;
        _aliases = aliases;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<Map<String, String>> _loadAliases() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final rawAliases = sp.getString('friends.aliases') ?? '{}';
      final decoded = jsonDecode(rawAliases);
      if (decoded is Map) {
        final out = <String, String>{};
        decoded.forEach((k, v) {
          final key = (k ?? '').toString().trim();
          final val = (v ?? '').toString().trim();
          if (key.isNotEmpty && val.isNotEmpty) {
            out[key] = val;
          }
        });
        return out;
      }
    } catch (_) {}
    return <String, String>{};
  }

  String _displayFor(ChatContact c, Map<String, String> aliases) {
    final alias = aliases[c.id]?.trim();
    if (alias != null && alias.isNotEmpty) return alias;
    final name = (c.name ?? '').trim();
    if (name.isNotEmpty) return name;
    return c.id;
  }

  Widget _avatar(String display) {
    final initial =
        display.trim().isNotEmpty ? display.trim()[0].toUpperCase() : '?';
    final seed = display.hashCode;
    final colors = <Color>[
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6),
      const Color(0xFFEF4444),
    ];
    final bg = colors[seed.abs() % colors.length];
    return SizedBox(
      width: 40,
      height: 40,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          color: bg.withValues(alpha: .92),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setBlocked(ChatContact c, bool blocked) async {
    try {
      final contacts = await _store.loadContacts();
      final idx = contacts.indexWhere((x) => x.id == c.id);
      if (idx != -1) {
        final updated = contacts[idx].copyWith(
          blocked: blocked,
          blockedAt: DateTime.now(),
        );
        contacts[idx] = updated;
        await _store.saveContacts(contacts);
        try {
          await _service.setBlock(
            deviceId: widget.deviceId,
            peerId: c.id,
            blocked: blocked,
            hidden: updated.hidden,
          );
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> _unblock(ChatContact c) async {
    final l = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final prior = List<ChatContact>.from(_blocked);
    setState(() => _blocked = _blocked.where((x) => x.id != c.id).toList());

    await _setBlocked(c, false);

    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(l.isArabic ? 'تمت الإزالة.' : 'Removed.'),
          action: SnackBarAction(
            label: l.isArabic ? 'تراجع' : 'Undo',
            onPressed: () {
              if (!mounted) return;
              setState(() => _blocked = prior);
              unawaited(_setBlocked(c, true));
            },
          ),
        ),
      );
  }

  Future<void> _showActions(ChatContact c, String display) async {
    final l = L10n.of(context);
    final theme = Theme.of(context);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        Widget actionTile({
          required IconData icon,
          required String title,
          Color? color,
          required VoidCallback onTap,
        }) {
          return ListTile(
            dense: true,
            leading: Icon(icon, color: color ?? theme.colorScheme.onSurface),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color ?? theme.colorScheme.onSurface,
              ),
            ),
            onTap: onTap,
          );
        }

        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: .75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    display,
                    style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ) ??
                        const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              const Divider(height: 16),
              actionTile(
                icon: Icons.chat_bubble_outline,
                title: l.isArabic ? 'فتح الدردشة' : 'Open chat',
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShamellChatPage(
                        baseUrl: widget.baseUrl,
                        initialPeerId: c.id,
                      ),
                    ),
                  );
                },
              ),
              actionTile(
                icon: Icons.block_outlined,
                title: l.shamellUnblock,
                color: theme.colorScheme.error.withValues(alpha: .95),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _unblock(c);
                },
              ),
              const SizedBox(height: 10),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  dense: true,
                  title: Center(
                    child: Text(
                      l.shamellDialogCancel,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    final aliases = _aliases;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'القائمة المحظورة' : 'Blocked list'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _blocked.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Text(
                            l.isArabic
                                ? 'لا يوجد أحد هنا.'
                                : 'No blocked users.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: .60),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      children: [
                        ShamellSection(
                          dividerIndent: 72,
                          dividerEndIndent: 16,
                          children: [
                            for (final c in _blocked)
                              Builder(
                                builder: (ctx) {
                                  final display = _displayFor(c, aliases);
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 6,
                                    ),
                                    leading: _avatar(display),
                                    title: Text(
                                      display,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      c.id,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: .55),
                                      ),
                                    ),
                                    onTap: () async {
                                      await _showActions(c, display);
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
            ),
    );
  }
}

class ShamellGeneralPage extends StatelessWidget {
  const ShamellGeneralPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    Widget valueChevron(String value) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              color: theme.colorScheme.onSurface.withValues(alpha: .55),
            ),
          ),
          const SizedBox(width: 6),
          chevron(),
        ],
      );
    }

    String languageLabel(Locale? locale) {
      final code = locale?.languageCode.toLowerCase() ?? 'system';
      switch (code) {
        case 'ar':
          return l.isArabic ? 'العربية' : 'Arabic';
        case 'en':
          return 'English';
        case 'system':
        default:
          return l.isArabic ? 'لغة النظام' : 'System';
      }
    }

    String fontSizeLabel(double scale) {
      if (scale <= 1.05) {
        return l.isArabic ? 'افتراضي' : 'Standard';
      }
      if (scale <= 1.22) {
        return l.isArabic ? 'كبير' : 'Large';
      }
      return l.isArabic ? 'كبير جداً' : 'Extra Large';
    }

    String darkModeLabel(ThemeMode mode) {
      switch (mode) {
        case ThemeMode.system:
          return l.isArabic ? 'اتّباع النظام' : 'Follow System';
        case ThemeMode.dark:
          return l.isArabic ? 'تشغيل' : 'On';
        case ThemeMode.light:
        default:
          return l.isArabic ? 'إيقاف' : 'Off';
      }
    }

    Future<void> clearAllChatHistory() async {
      final sp = await SharedPreferences.getInstance();
      final keys = sp.getKeys();
      final toRemove = <String>{
        ...keys.where(
          (k) =>
              k.startsWith('chat.msgs.') ||
              k.startsWith('chat.grp.msgs.') ||
              k.startsWith('chat.voice.played.') ||
              k.startsWith('chat.grp.voice.played.'),
        ),
        'chat.unread',
        'chat.active',
        'chat.grp.seen',
        'chat.pinned_messages',
      };
      for (final k in toRemove) {
        await sp.remove(k);
      }
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'عام' : 'General'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'اللغة' : 'Language'),
                trailing: ValueListenableBuilder<Locale?>(
                  valueListenable: uiLocale,
                  builder: (context, locale, _) {
                    return valueChevron(languageLabel(locale));
                  },
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellLanguagePage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'حجم الخط' : 'Font Size'),
                trailing: ValueListenableBuilder<double>(
                  valueListenable: uiTextScale,
                  builder: (context, scale, _) {
                    return valueChevron(fontSizeLabel(scale));
                  },
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellFontSizePage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الوضع الداكن' : 'Dark Mode'),
                trailing: ValueListenableBuilder<ThemeMode>(
                  valueListenable: uiThemeMode,
                  builder: (context, mode, _) {
                    return valueChevron(darkModeLabel(mode));
                  },
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellDarkModePage(),
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.shamellSettingsStorage),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellStorageManagementPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.shamellClearChatHistory),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) {
                      return AlertDialog(
                        title: Text(l.shamellClearChatHistory),
                        content: Text(
                          l.isArabic
                              ? 'سيتم حذف جميع رسائل الدردشة من هذا الجهاز.'
                              : 'This will delete all chat messages from this device.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(l.shamellDialogCancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(l.shamellDialogOk),
                          ),
                        ],
                      );
                    },
                  );
                  if (ok != true) return;
                  await clearAllChatHistory();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(l.isArabic ? 'تم.' : 'Done.'),
                      ),
                    );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ShamellStorageManagementPage extends StatefulWidget {
  const ShamellStorageManagementPage({super.key});

  @override
  State<ShamellStorageManagementPage> createState() =>
      _ShamellStorageManagementPageState();
}

class _ShamellStorageManagementPageState
    extends State<ShamellStorageManagementPage> {
  bool _loading = true;
  int _chatBytes = 0;
  int _groupBytes = 0;
  int _pinnedBytes = 0;
  int _favoritesBytes = 0;
  int _chatThreads = 0;
  int _groupThreads = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _bytesForString(String? s) {
    if (s == null || s.isEmpty) return 0;
    return utf8.encode(s).length;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final fixed = value >= 10 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fixed)} ${units[unit]}';
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final keys = sp.getKeys();
      var chatBytes = 0;
      var groupBytes = 0;
      var pinnedBytes = 0;
      var favoritesBytes = 0;
      var chatThreads = 0;
      var groupThreads = 0;

      for (final k in keys) {
        if (k.startsWith('chat.msgs.')) {
          chatThreads++;
          chatBytes += _bytesForString(sp.getString(k));
          continue;
        }
        if (k.startsWith('chat.grp.msgs.')) {
          groupThreads++;
          groupBytes += _bytesForString(sp.getString(k));
          continue;
        }
        if (k == 'chat.pinned_messages') {
          pinnedBytes = _bytesForString(sp.getString(k));
          continue;
        }
        if (k == 'favorites_items') {
          favoritesBytes = _bytesForString(sp.getString(k));
          continue;
        }
      }

      if (!mounted) return;
      setState(() {
        _chatBytes = chatBytes;
        _groupBytes = groupBytes;
        _pinnedBytes = pinnedBytes;
        _favoritesBytes = favoritesBytes;
        _chatThreads = chatThreads;
        _groupThreads = groupThreads;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _clearAllChatHistory() async {
    final sp = await SharedPreferences.getInstance();
    final keys = sp.getKeys();
    final toRemove = <String>{
      ...keys.where(
        (k) =>
            k.startsWith('chat.msgs.') ||
            k.startsWith('chat.grp.msgs.') ||
            k.startsWith('chat.voice.played.') ||
            k.startsWith('chat.grp.voice.played.'),
      ),
      'chat.unread',
      'chat.active',
      'chat.grp.seen',
      'chat.pinned_messages',
    };
    for (final k in toRemove) {
      await sp.remove(k);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    TextStyle? trailingStyle() => theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );

    final chatHistoryBytes = _chatBytes + _groupBytes + _pinnedBytes;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.shamellSettingsStorage),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                ShamellSection(
                  dividerIndent: 16,
                  dividerEndIndent: 16,
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'سجل الدردشة' : 'Chat history'),
                      subtitle: Text(
                        l.isArabic
                            ? 'دردشات: $_chatThreads · مجموعات: $_groupThreads'
                            : 'Chats: $_chatThreads · Groups: $_groupThreads',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: .55),
                        ),
                      ),
                      trailing: Text(
                        _formatBytes(chatHistoryBytes),
                        style: trailingStyle(),
                      ),
                      onTap: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) {
                            return AlertDialog(
                              title: Text(l.shamellClearChatHistory),
                              content: Text(
                                l.isArabic
                                    ? 'سيتم حذف جميع رسائل الدردشة من هذا الجهاز.'
                                    : 'This will delete all chat messages from this device.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(l.shamellDialogCancel),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(l.shamellDialogOk),
                                ),
                              ],
                            );
                          },
                        );
                        if (ok != true) return;
                        await _clearAllChatHistory();
                        if (!context.mounted) return;
                        setState(() => _loading = true);
                        await _load();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(l.isArabic ? 'تم.' : 'Done.'),
                            ),
                          );
                      },
                    ),
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'الذاكرة المؤقتة' : 'Cache'),
                      trailing: Text('0 B', style: trailingStyle()),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const ShamellSettingsStorageManagementPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                ShamellSection(
                  dividerIndent: 16,
                  dividerEndIndent: 16,
                  children: [
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'المفضلة' : 'Favorites'),
                      trailing: Text(
                        _formatBytes(_favoritesBytes),
                        style: trailingStyle(),
                      ),
                      onTap: () {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                l.isArabic
                                    ? 'تُدار المفضلة من تبويب "أنا".'
                                    : 'Favorites are managed from the Me tab.',
                              ),
                            ),
                          );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class ShamellLanguagePage extends StatelessWidget {
  const ShamellLanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    TextStyle? subtitleStyle() => theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        );

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'اللغة' : 'Language'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ValueListenableBuilder<Locale?>(
        valueListenable: uiLocale,
        builder: (context, locale, _) {
          final selected = locale?.languageCode.toLowerCase() ?? 'system';

          Widget tile({
            required String code,
            required String title,
            String? subtitle,
          }) {
            final isSelected = selected == code;
            return ListTile(
              dense: true,
              title: Text(title),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      style: subtitleStyle(),
                    ),
              trailing: isSelected
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () async {
                await setUiLocaleCode(code);
              },
            );
          }

          return ListView(
            children: [
              ShamellSection(
                dividerIndent: 16,
                dividerEndIndent: 16,
                children: [
                  tile(
                    code: 'system',
                    title: l.isArabic ? 'لغة النظام' : 'Follow System',
                    subtitle: l.isArabic
                        ? 'استخدم لغة الجهاز.'
                        : 'Use device language.',
                  ),
                  tile(
                    code: 'en',
                    title: 'English',
                    subtitle: l.isArabic ? 'الإنجليزية' : null,
                  ),
                  tile(
                    code: 'ar',
                    title: 'العربية',
                    subtitle: l.isArabic ? null : 'Arabic',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class ShamellFontSizePage extends StatelessWidget {
  const ShamellFontSizePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'حجم الخط' : 'Font Size'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ValueListenableBuilder<double>(
        valueListenable: uiTextScale,
        builder: (context, scale, _) {
          bool isSelected(double v) => (scale - v).abs() < 0.02;

          Widget tile({
            required double value,
            required String title,
            String? subtitle,
          }) {
            return ListTile(
              dense: true,
              title: Text(title),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .55),
                      ),
                    ),
              trailing: isSelected(value)
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () async {
                await setUiTextScale(value);
              },
            );
          }

          return ListView(
            children: [
              ShamellSection(
                dividerIndent: 16,
                dividerEndIndent: 16,
                children: [
                  tile(
                    value: 1.0,
                    title: l.isArabic ? 'افتراضي' : 'Standard',
                    subtitle: l.isArabic ? 'الموصى به.' : 'Recommended.',
                  ),
                  tile(
                    value: 1.15,
                    title: l.isArabic ? 'كبير' : 'Large',
                  ),
                  tile(
                    value: 1.3,
                    title: l.isArabic ? 'كبير جداً' : 'Extra Large',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class ShamellDarkModePage extends StatelessWidget {
  const ShamellDarkModePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'الوضع الداكن' : 'Dark Mode'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: uiThemeMode,
        builder: (context, mode, _) {
          Widget tile({
            required ThemeMode value,
            required String title,
            String? subtitle,
          }) {
            final isSelected = mode == value;
            return ListTile(
              dense: true,
              title: Text(title),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .55),
                      ),
                    ),
              trailing: isSelected
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: theme.colorScheme.primary,
                    )
                  : null,
              onTap: () async {
                await setUiThemeMode(value);
              },
            );
          }

          return ListView(
            children: [
              ShamellSection(
                dividerIndent: 16,
                dividerEndIndent: 16,
                children: [
                  tile(
                    value: ThemeMode.system,
                    title: l.isArabic ? 'اتّباع النظام' : 'Follow System',
                    subtitle: l.isArabic
                        ? 'استخدم إعدادات المظهر في الجهاز.'
                        : 'Use device appearance settings.',
                  ),
                  tile(
                    value: ThemeMode.light,
                    title: l.isArabic ? 'إيقاف' : 'Off',
                  ),
                  tile(
                    value: ThemeMode.dark,
                    title: l.isArabic ? 'تشغيل' : 'On',
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class ShamellAboutPage extends StatelessWidget {
  const ShamellAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .40),
        );

    final appVersion = const String.fromEnvironment('APP_VERSION');
    final build = const String.fromEnvironment('APP_BUILD');

    String versionText() {
      final parts = <String>[
        if (appVersion.trim().isNotEmpty) appVersion.trim(),
        if (build.trim().isNotEmpty) build.trim(),
      ];
      return parts.join(' ');
    }

    final version = versionText();

    Widget trailingVersion() {
      return Text(
        version.isEmpty ? '—' : version,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: .55),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.isArabic ? 'حول شامل' : 'About Shamell'),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ShamellLeadingIcon(
                    icon: Icons.chat_bubble_rounded,
                    background: ShamellPalette.green,
                    size: 64,
                    iconSize: 34,
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l.appTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (version.isNotEmpty)
                    Text(
                      '${l.isArabic ? 'الإصدار' : 'Version'} $version',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .55),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الإصدار' : 'Version'),
                trailing: trailingVersion(),
              ),
              ListTile(
                dense: true,
                title: Text(l.isArabic ? 'الترخيص' : 'Licenses'),
                trailing: chevron(),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: l.appTitle,
                  );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(
                    l.isArabic ? 'المساعدة والملاحظات' : 'Help & Feedback'),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const OnboardingPage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(
                    l.isArabic ? 'التحقق من التحديثات' : 'Check for updates'),
                trailing: chevron(),
                onTap: () {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        content: Text(
                          l.isArabic
                              ? 'لا توجد تحديثات.'
                              : 'No updates available.',
                        ),
                      ),
                    );
                },
              ),
            ],
          ),
          ShamellSection(
            dividerIndent: 16,
            dividerEndIndent: 16,
            children: [
              ListTile(
                dense: true,
                title: Text(l.shamellSettingsTerms),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellTermsOfServicePage(),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                title: Text(l.shamellSettingsPrivacyPolicy),
                trailing: chevron(),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ShamellPrivacyPolicyPage(),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
