part of '../main.dart';

class ProfilePage extends StatefulWidget {
  final String baseUrl;
  const ProfilePage(this.baseUrl, {super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SafeSetStateMixin<ProfilePage> {
  String phone = '';
  String walletId = '';
  String name = '';
  String shamellId = '';
  String username = '';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      try {
        final sp = await SharedPreferences.getInstance();
        final profile = await loadLegacyProfileSummary(
          sp: sp,
          baseUrlOverride: widget.baseUrl,
        );
        name = profile.name;
        phone = profile.phone;
        // Auth username — the handle the user typed at signup/signin,
        // shown under the display name on the Profile hero so the
        // account is identifiable independently of the SyrChat-ID.
        username = (await loadProfileUsername(sp: sp)) ?? '';
        walletId =
            await loadStoredWalletId(sp: sp, baseUrlOverride: widget.baseUrl) ??
                '';
        if (shamellId.trim().isEmpty) {
          shamellId = await loadShamellUserId(
                sp: sp,
                baseUrlOverride: widget.baseUrl,
              ) ??
              '';
        }
        final normalizedBase = normalizeSecureApiBaseUrl(widget.baseUrl.trim());
        final hasSession = normalizedBase != null &&
            ((await getSessionCookieHeader(normalizedBase) ?? '')
                .trim()
                .isNotEmpty);
        if (shamellId.trim().isEmpty && hasSession) {
          try {
            final snapshot = await refreshAndPersistAccountHomeSnapshot(
              baseUrl: normalizedBase,
              ensureSession: false,
            );
            final snapShamellId = snapshot.shamellId.trim();
            if (snapShamellId.isNotEmpty) {
              shamellId = snapShamellId;
            }
            if (walletId.trim().isEmpty &&
                snapshot.walletId.trim().isNotEmpty) {
              walletId = snapshot.walletId.trim();
            }
          } catch (e) {
            if (await shamellForceReauthIfCriticalDeviceBindingDrift(
              context,
              error: e,
              loginPageBuilder: (_) => const LoginPage(),
            )) {
              return;
            }
          }
        }
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Uri _inviteUri(String token) {
    return buildShamellInviteAppLink(token);
  }

  Future<String> _createInviteTokenWithBootstrap() async {
    final svc = ChatService(widget.baseUrl);
    try {
      return await svc.createContactInviteTokenEnsured(
        maxUses: 1,
      );
    } catch (e) {
      if (await shamellForceReauthIfCriticalDeviceBindingDrift(
        context,
        error: e,
        loginPageBuilder: (_) => const LoginPage(),
      )) {
        return '';
      }
      rethrow;
    } finally {
      svc.close();
    }
  }

  Future<void> _showInviteQr() async {
    final l = L10n.of(context);
    var showing = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ).whenComplete(() => showing = false),
    );

    try {
      final token = await _createInviteTokenWithBootstrap();
      final payload = token.isNotEmpty ? _inviteUri(token).toString() : '';
      if (!mounted) return;
      if (showing) {
        Navigator.of(context, rootNavigator: true).pop();
        showing = false;
      }
      if (payload.isEmpty) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ShamellMyQrCodePage(
            payload: payload,
            profileName: name,
            // Invite QR is a bearer capability; keep stable IDs off the QR page.
            profileShamellId: '',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (showing) {
        Navigator.of(context, rootNavigator: true).pop();
        showing = false;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sanitizeExceptionForUi(error: e, isArabic: l.isArabic)),
        ),
      );
    } finally {
      if (mounted && showing) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget reveal({required int order, required Widget child}) {
      if (reduceMotion) return child;
      final start = (order * 0.12).clamp(0.0, 0.7).toDouble();
      return TweenAnimationBuilder<double>(
        key: ValueKey<String>('profile-reveal-$order'),
        duration: const Duration(milliseconds: 440),
        curve: Interval(start, 1, curve: Curves.easeOutCubic),
        tween: Tween<double>(begin: 0, end: 1),
        child: child,
        builder: (context, value, child) {
          final y = (1 - value) * 14;
          return Opacity(
            opacity: value,
            child: Transform.translate(offset: Offset(0, y), child: child),
          );
        },
      );
    }

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

    final isDark = theme.brightness == Brightness.dark;
    final bgColor =
        isDark ? theme.colorScheme.surface : ShamellPalette.background;
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: .66),
    );
    final valueStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: .62),
    );
    final shamellLabel = l.isArabic ? 'معرّف SyrChat' : 'SyrChat ID';

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .48),
        );

    Widget avatarBox() {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ShamellPalette.green.withValues(alpha: isDark ? .18 : .10),
          ),
          child: SizedBox(
            width: 62,
            height: 62,
            child: Center(
              child: Text(
                _avatarInitial(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget infoTile({
      required IconData icon,
      required Color color,
      required String title,
      required String value,
      VoidCallback? onCopy,
    }) {
      final v = value.trim();
      return ListTile(
        dense: true,
        leading: ShamellLeadingIcon(icon: icon, background: color),
        title: Text(title),
        subtitle: Text(
          v.isEmpty ? '-' : v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: valueStyle,
        ),
        trailing: onCopy == null
            ? null
            : IconButton(
                tooltip: l.isArabic ? 'نسخ' : 'Copy',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_outlined, size: 19),
                onPressed: onCopy,
              ),
      );
    }

    final content = ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        reveal(
          order: 0,
          child: ShamellSection(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            borderRadius: BorderRadius.circular(10),
            dividerIndent: 86,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                leading: avatarBox(),
                title: Text(
                  name.isEmpty ? l.profileTitle : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // Subtitle layout: "@username" on top, "SyrChat-ID: …"
                // below it. The auth username is the human handle a
                // teammate would type to find you; the SyrChat-ID is
                // the cross-account discovery code we still want to
                // surface for the QR + share flow but it's no longer
                // the primary identity line under the name.
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      username.isNotEmpty
                          ? '@$username'
                          : (shamellId.isEmpty
                              ? (l.isArabic
                                  ? 'اسم المستخدم غير مضبوط'
                                  : 'Username not set')
                              : '@${shamellId.toLowerCase()}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      shamellId.isEmpty
                          ? (l.isArabic
                              ? '$shamellLabel: غير مضبوط'
                              : '$shamellLabel: Not set')
                          : '$shamellLabel: $shamellId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.qr_code_2_outlined,
                      color: theme.colorScheme.onSurface.withValues(alpha: .68),
                    ),
                    const SizedBox(width: 4),
                    chevron(),
                  ],
                ),
                onTap: () => unawaited(_showInviteQr()),
              ),
            ],
          ),
        ),
        reveal(
          order: 1,
          child: ShamellSection(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            borderRadius: BorderRadius.circular(10),
            dividerIndent: 72,
            children: [
              ListTile(
                dense: true,
                leading: const ShamellLeadingIcon(
                  icon: Icons.qr_code_2_outlined,
                  background: Color(0xFF111827),
                ),
                title:
                    Text(l.isArabic ? 'رمز SyrChat الخاص بي' : 'My SyrChat QR'),
                subtitle: Text(
                  l.isArabic
                      ? 'شارك رمز دعوة آمن لإضافتك.'
                      : 'Share a secure invite code to add you.',
                  style: subtitleStyle,
                ),
                trailing: chevron(),
                onTap: () => unawaited(_showInviteQr()),
              ),
            ],
          ),
        ),
        reveal(
          order: 2,
          child: ShamellSection(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            borderRadius: BorderRadius.circular(10),
            dividerIndent: 72,
            children: [
              infoTile(
                icon: Icons.account_balance_wallet_outlined,
                color: const Color(0xFF07C160),
                title: l.labelWalletId,
                value: walletId,
                onCopy: walletId.isEmpty
                    ? null
                    : () async {
                        await shamellCopyToClipboard(
                          walletId,
                          sensitive: true,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.msgWalletCopied)),
                          );
                        }
                      },
              ),
              infoTile(
                icon: Icons.badge_outlined,
                color: const Color(0xFF2563EB),
                title: shamellLabel,
                value: shamellId,
                onCopy: shamellId.isEmpty
                    ? null
                    : () async {
                        await shamellCopyToClipboard(
                          shamellId,
                          sensitive: true,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text(l.isArabic ? 'تم النسخ.' : 'Copied.'),
                            ),
                          );
                        }
                      },
              ),
              infoTile(
                icon: Icons.person_outline,
                color: const Color(0xFF7C3AED),
                title: l.labelName,
                value: name,
              ),
              infoTile(
                icon: Icons.phone_iphone,
                color: const Color(0xFF14B8A6),
                title: l.labelPhone,
                value: phone,
              ),
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(l.profileTitle),
        backgroundColor: bgColor,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: content,
      ),
    );
  }
}

class ShamellSettingsPage extends StatelessWidget {
  final String baseUrl;
  final String walletId;
  final String deviceId;
  final String profileShamellId;
  final bool showDev;
  final bool hasDefaultOfficialAccount;
  final Future<void> Function() onLogout;
  final Future<void> Function() onLogoutForgetDevice;
  final void Function(Widget page) pushPage;

  const ShamellSettingsPage({
    super.key,
    required this.baseUrl,
    required this.walletId,
    required this.deviceId,
    required this.profileShamellId,
    required this.showDev,
    required this.hasDefaultOfficialAccount,
    required this.onLogout,
    required this.onLogoutForgetDevice,
    required this.pushPage,
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color bgColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: .96)
        : ShamellPalette.background;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Widget reveal({required int order, required Widget child}) {
      if (reduceMotion) return child;
      final start = (order * 0.09).clamp(0.0, 0.72).toDouble();
      return TweenAnimationBuilder<double>(
        key: ValueKey<String>('settings-reveal-$order'),
        duration: const Duration(milliseconds: 460),
        curve: Interval(start, 1, curve: Curves.easeOutCubic),
        tween: Tween<double>(begin: 0, end: 1),
        child: child,
        builder: (context, value, child) {
          final y = (1 - value) * 14;
          return Opacity(
            opacity: value,
            child: Transform.translate(offset: Offset(0, y), child: child),
          );
        },
      );
    }

    Widget settingsSection({
      required int order,
      required List<Widget> children,
      EdgeInsets margin = const EdgeInsets.only(top: 8),
    }) {
      return reveal(
        order: order,
        child: ShamellListSection(
          margin: margin,
          dividerIndent: 16,
          dividerEndIndent: 16,
          children: children,
        ),
      );
    }

    Icon chevron() => Icon(
          l.isArabic ? Icons.chevron_left : Icons.chevron_right,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: .52),
        );

    Future<void> openOfficialOwnerConsole() async {
      try {
        final sp = await SharedPreferences.getInstance();
        final official = await loadLegacyDefaultOfficialAccountContext(
          sp: sp,
          baseUrlOverride: baseUrl,
        );
        final accId = official.accountId;
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
          ),
        );
      } catch (_) {}
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: shamellSettingsAppBar(
        context,
        title: l.settingsTitle,
        backgroundColor: bgColor,
      ),
      body: shamellSettingsListTheme(
        context,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            settingsSection(
              order: 0,
              margin: EdgeInsets.zero,
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
                        profileId: profileShamellId,
                      ),
                    );
                  },
                ),
                ListTile(
                  dense: true,
                  title: Text(
                    l.isArabic ? 'الخصوصية' : 'Privacy',
                  ),
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
            settingsSection(
              order: 1,
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
            settingsSection(
              order: 2,
              children: [
                ListTile(
                  dense: true,
                  title: Text(l.isArabic ? 'عام' : 'General'),
                  trailing: chevron(),
                  onTap: () {
                    pushPage(ShamellSettingsGeneralPage(baseUrl: baseUrl));
                  },
                ),
                ListTile(
                  dense: true,
                  title: Text(l.isArabic ? 'الإضافات' : 'Plugins'),
                  trailing: chevron(),
                  onTap: () {
                    pushPage(ShamellPluginsPage(baseUrl: baseUrl));
                  },
                ),
              ],
            ),
            settingsSection(
              order: 3,
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
                ListTile(
                  dense: true,
                  title: Text(l.isArabic ? 'حول سرتشات' : 'About SyrChat'),
                  trailing: chevron(),
                  onTap: () {
                    pushPage(const ShamellSettingsAboutPage());
                  },
                ),
              ],
            ),
            if (hasDefaultOfficialAccount || showDev)
              settingsSection(
                order: 4,
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
            settingsSection(
              order: 5,
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
            settingsSection(
              order: 6,
              children: [
                ListTile(
                  dense: true,
                  title: Text(
                    l.menuLogoutForgetDevice,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    l.menuLogoutForgetDeviceSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
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

    TextStyle? hintStyle() => theme.textTheme.bodySmall?.copyWith(
          fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: .60),
        );

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

    Future<void> sendFeedback() async {
      final uri = shamellSupportEmailUri(subject: 'SyrChat Feedback');
      try {
        final ok = await launchUrl(
          uri,
          mode: shamellExternalLaunchMode(uri),
        );
        if (!ok) {
          snack(l.isArabic ? 'تعذّر فتح البريد.' : 'Could not open email.');
        }
      } catch (_) {
        snack(l.isArabic ? 'تعذّر فتح البريد.' : 'Could not open email.');
      }
    }

    Future<void> contactSupport() async {
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
                      subtitle: const Text(kShamellSupportPhone),
                      trailing: sheetChevron(),
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        try {
                          final uri = shamellSupportPhoneUri();
                          await launchUrl(
                            uri,
                            mode: shamellExternalLaunchMode(uri),
                          );
                        } catch (_) {}
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      dense: true,
                      title: Text(l.isArabic ? 'البريد الإلكتروني' : 'Email'),
                      subtitle: const Text(kShamellSupportEmail),
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
      appBar: shamellSettingsAppBar(
        context,
        title: l.isArabic ? 'المساعدة والملاحظات' : 'Help & Feedback',
        backgroundColor: bgColor,
      ),
      body: shamellSettingsListTheme(
        context,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            ShamellListSection(
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
                        ? 'راجع سياسة الدعوة أولاً وقائمة الحظر من صفحة الخصوصية.'
                        : 'Review the invite-first policy and blocked list in Privacy.',
                    style: hintStyle(),
                  ),
                ),
                ListTile(
                  dense: true,
                  title: Text(l.isArabic ? 'إرسال ملاحظات' : 'Feedback'),
                  trailing: chevron(),
                  onTap: () => sendFeedback(),
                ),
              ],
            ),
            ShamellListSection(
              dividerIndent: 16,
              dividerEndIndent: 16,
              children: [
                ListTile(
                  dense: true,
                  title:
                      Text(l.isArabic ? 'الاتصال بالدعم' : 'Contact support'),
                  trailing: chevron(),
                  onTap: () => contactSupport(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ShamellPluginsPage extends StatefulWidget {
  final String baseUrl;

  const ShamellPluginsPage({
    super.key,
    required this.baseUrl,
  });

  @override
  State<ShamellPluginsPage> createState() => _ShamellPluginsPageState();
}

class _ShamellPluginsPageState extends State<ShamellPluginsPage> {
  bool _loading = true;
  bool _scan = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final scan = await loadScopedPluginVisibilityPreference(
        key: _kShamellPluginShowScan,
        fallback: true,
        sp: sp,
        baseUrlOverride: widget.baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _scan = scan;
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
      await saveScopedPluginVisibilityPreference(
        key: key,
        value: v,
        sp: sp,
        baseUrlOverride: widget.baseUrl,
      );
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
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                  child: Text(
                    l.isArabic
                        ? 'تتحكم الإضافات حالياً في المسح داخل تبويب التطبيقات.'
                        : 'Plugins currently control Scan in the Apps tab.',
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
