import 'package:flutter/material.dart';

import '../l10n.dart';
import 'syrcom_access_admin_page.dart';
import 'syrcom_dev_login_sheet.dart';
import 'syrcom_module_stub_page.dart';
import 'syrcom_theme.dart';
import 'workforce_dev_auth_api.dart';
import 'workforce_snapshot.dart';

class SyrComWorkbenchPage extends StatefulWidget {
  const SyrComWorkbenchPage({
    super.key,
    this.baseUrl,
    this.workforceApi,
  });

  /// BFF base URL passed in from the surface router. May be null in tests
  /// or when the device hasn't completed its base-URL bootstrap; the page
  /// then renders in legacy-permissive mode (all tiles visible, no
  /// snapshot-aware gating).
  final String? baseUrl;

  /// Injectable for widget tests. When null, the page constructs a real
  /// `WorkforceAccessApi` against `baseUrl`. Tests pass a fake that returns
  /// a fixed snapshot without any HTTP traffic.
  final WorkforceAccessApi? workforceApi;

  @override
  State<SyrComWorkbenchPage> createState() => _SyrComWorkbenchPageState();
}

class _SyrComWorkbenchPageState extends State<SyrComWorkbenchPage> {
  WorkforceAccessSnapshot? _snapshot;
  bool _snapshotLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
  }

  WorkforceAccessApi _api() {
    return widget.workforceApi ??
        WorkforceAccessApi(baseUrl: widget.baseUrl);
  }

  Future<void> _loadSnapshot() async {
    final api = _api();
    final perms = await api.fetchPermissions();
    if (!mounted) return;
    if (perms == null) {
      // Consumer / legacy session, or transient error. Stop the loading
      // indicator so tiles render in legacy-permissive mode.
      setState(() {
        _snapshot = null;
        _snapshotLoading = false;
      });
      return;
    }
    final enriched = await api.enrichWithAccessContext(perms);
    if (!mounted) return;
    setState(() {
      _snapshot = enriched;
      _snapshotLoading = false;
    });
  }

  Future<void> _onRefresh() async {
    setState(() {
      _snapshotLoading = true;
    });
    await _loadSnapshot();
  }

  Future<void> _openDevSignIn() async {
    final base = widget.baseUrl;
    if (base == null || base.isEmpty) return;
    final signedIn = await showSyrComDevLoginSheet(context, baseUrl: base);
    if (!mounted) return;
    if (signedIn) {
      setState(() {
        _snapshotLoading = true;
      });
      await _loadSnapshot();
    }
  }

  void _openModule(_SyrComModule module) {
    final isArabic = L10n.of(context).isArabic;
    // Modules with real backends route to their concrete page; everything
    // else falls through to the generic "coming soon" stub. New first-class
    // modules drop in here as additional branches.
    final base = widget.baseUrl;
    if (module.id == 'access_admin' && base != null && base.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SyrComAccessAdminPage(
            baseUrl: base,
            callerSnapshot: _snapshot,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SyrComModuleStubPage(
          title: isArabic ? module.titleAr : module.titleEn,
          icon: module.icon,
        ),
      ),
    );
  }

  /// Filter a fixed module catalog by the workforce snapshot.
  ///
  /// Gating rules (matches the architecture's "frontends may hide buttons,
  /// but they must never be the source of truth for permissions" principle —
  /// every server endpoint will re-check on its own):
  ///   • snapshot == null → show every tile. This covers loading state,
  ///     consumer sessions, and transient errors. The Workbench stays
  ///     usable; the server still rejects unauthorized calls.
  ///   • snapshot != null → show tiles whose `requiredPermission` is null
  ///     (no gating yet) or for which `snapshot.can(perm)` is true.
  List<_SyrComModule> _gateModules(List<_SyrComModule> modules) {
    final snapshot = _snapshot;
    if (snapshot == null) return modules;
    return modules
        .where((m) =>
            m.requiredPermission == null ||
            snapshot.can(m.requiredPermission!))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    final isArabic = l.isArabic;

    final commonModules = _gateModules(_kCommonModules);
    final gatedSections = _kCategorySections
        .map((s) => _SyrComSection(
              titleEn: s.titleEn,
              titleAr: s.titleAr,
              modules: _gateModules(s.modules),
            ))
        .where((s) => s.modules.isNotEmpty)
        .toList(growable: false);

    final showDevSignIn = workforceDevAuthAvailable() &&
        _snapshot == null &&
        !_snapshotLoading &&
        (widget.baseUrl ?? '').isNotEmpty;

    return Scaffold(
      floatingActionButton: showDevSignIn
          ? FloatingActionButton.extended(
              backgroundColor: kSyrComPrimary,
              foregroundColor: Colors.white,
              onPressed: _openDevSignIn,
              icon: const Icon(Icons.developer_mode_outlined),
              label: Text(isArabic ? 'تسجيل دخول مطوّر' : 'Dev sign-in'),
            )
          : null,
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF0E1116)
          : const Color(0xFFF2F4F7),
      body: SafeArea(
        child: RefreshIndicator(
          color: kSyrComPrimary,
          onRefresh: _onRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _SyrComHeader(
                  isArabic: isArabic,
                  snapshot: _snapshot,
                  snapshotLoading: _snapshotLoading,
                ),
              ),
              SliverToBoxAdapter(
                child: _SyrComTodayCard(isArabic: isArabic),
              ),
              if (commonModules.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: _SyrComSectionHeader(
                    title: isArabic ? 'التطبيقات الشائعة' : 'Common apps',
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  sliver: _SyrComAppGrid(
                    modules: commonModules,
                    isArabic: isArabic,
                    onTap: _openModule,
                  ),
                ),
              ],
              for (final section in gatedSections) ...[
                SliverToBoxAdapter(
                  child: _SyrComSectionHeader(
                    title: isArabic ? section.titleAr : section.titleEn,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  sliver: _SyrComAppGrid(
                    modules: section.modules,
                    isArabic: isArabic,
                    onTap: _openModule,
                  ),
                ),
              ],
              if (commonModules.isEmpty && gatedSections.isEmpty)
                SliverToBoxAdapter(
                  child: _SyrComEmptyState(isArabic: isArabic),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyrComHeader extends StatelessWidget {
  const _SyrComHeader({
    required this.isArabic,
    required this.snapshot,
    required this.snapshotLoading,
  });

  final bool isArabic;
  final WorkforceAccessSnapshot? snapshot;
  final bool snapshotLoading;

  String _primaryOrgLabel() {
    final snap = snapshot;
    if (snap == null) return isArabic ? 'مساحة العمل المؤسسية' : 'Workbench';
    final primary = snap.organizations
            .where((m) => m.isPrimary && m.status == 'active')
            .toList()
        ..addAll(snap.organizations
            .where((m) => !m.isPrimary && m.status == 'active'));
    if (primary.isEmpty) {
      return isArabic ? 'مساحة العمل المؤسسية' : 'Workbench';
    }
    return primary.first.organizationDisplayName;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = Colors.white;
    final subtitle = _primaryOrgLabel();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.brightness == Brightness.dark
              ? const [Color(0xFF0B3B86), Color(0xFF1156C2)]
              : const [Color(0xFF1E6FFF), Color(0xFF3B82F6)],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: onPrimary.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.business_center_outlined,
                  color: onPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'سركم' : 'SyrCom',
                      style: TextStyle(
                        color: onPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: onPrimary.withValues(alpha: .82),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (snapshotLoading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        onPrimary.withValues(alpha: .9),
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: isArabic ? 'مسح' : 'Scan',
                onPressed: null,
                icon: Icon(
                  Icons.qr_code_scanner_outlined,
                  color: onPrimary.withValues(alpha: .92),
                ),
              ),
              IconButton(
                tooltip: isArabic ? 'الإشعارات' : 'Notifications',
                onPressed: null,
                icon: Icon(
                  Icons.notifications_none_outlined,
                  color: onPrimary.withValues(alpha: .92),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SyrComSearchPlaceholder(isArabic: isArabic),
        ],
      ),
    );
  }
}

class _SyrComSearchPlaceholder extends StatelessWidget {
  const _SyrComSearchPlaceholder({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .95),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.search, size: 20, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isArabic
                      ? 'ابحث في الأشخاص أو التطبيقات أو الرسائل'
                      : 'Search people, apps, messages',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyrComTodayCard extends StatelessWidget {
  const _SyrComTodayCard({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 8),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F27) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: isDark ? .5 : .85),
          width: .7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isArabic ? 'نظرة سريعة' : 'Today',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SyrComStatTile(
                value: '0',
                label: isArabic ? 'موافقات' : 'Approvals',
                icon: Icons.task_alt_outlined,
              ),
              _SyrComStatTile(
                value: '0',
                label: isArabic ? 'اجتماعات' : 'Meetings',
                icon: Icons.event_outlined,
              ),
              _SyrComStatTile(
                value: '0',
                label: isArabic ? 'مهام' : 'Tasks',
                icon: Icons.checklist_outlined,
              ),
              _SyrComStatTile(
                value: '0',
                label: isArabic ? 'إشعارات' : 'Alerts',
                icon: Icons.notifications_active_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyrComStatTile extends StatelessWidget {
  const _SyrComStatTile({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: kSyrComPrimary, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SyrComSectionHeader extends StatelessWidget {
  const _SyrComSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface.withValues(alpha: .85),
        ),
      ),
    );
  }
}

class _SyrComEmptyState extends StatelessWidget {
  const _SyrComEmptyState({required this.isArabic});

  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      child: Column(
        children: [
          Icon(
            Icons.lock_outline,
            color: theme.colorScheme.onSurface.withValues(alpha: .45),
            size: 36,
          ),
          const SizedBox(height: 12),
          Text(
            isArabic
                ? 'لا تتوفر وحدات لحسابك بعد. تواصل مع مسؤول سركم لإسناد الصلاحيات.'
                : 'No SyrCom modules are available for your account yet. Contact your SyrCom administrator to be granted access.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: .72),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SyrComAppGrid extends StatelessWidget {
  const _SyrComAppGrid({
    required this.modules,
    required this.isArabic,
    required this.onTap,
  });

  final List<_SyrComModule> modules;
  final bool isArabic;
  final ValueChanged<_SyrComModule> onTap;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.9,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final m = modules[index];
          return _SyrComAppTile(
            module: m,
            label: isArabic ? m.titleAr : m.titleEn,
            onTap: () => onTap(m),
          );
        },
        childCount: modules.length,
      ),
    );
  }
}

class _SyrComAppTile extends StatelessWidget {
  const _SyrComAppTile({
    required this.module,
    required this.label,
    required this.onTap,
  });

  final _SyrComModule module;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kSyrComPrimary.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                module.icon,
                color: kSyrComPrimary,
                size: 24,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11.5,
                color: theme.colorScheme.onSurface.withValues(alpha: .85),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _SyrComModule {
  final String id;
  final String titleEn;
  final String titleAr;
  final IconData icon;

  /// Permission ID required to see this module. `null` means the module has
  /// no real backend yet — visible to anyone with a workforce session as a
  /// placeholder until the corresponding permission is added to the
  /// canonical catalog. Server still re-checks every privileged call.
  final String? requiredPermission;

  const _SyrComModule({
    required this.id,
    required this.titleEn,
    required this.titleAr,
    required this.icon,
    this.requiredPermission,
  });
}

class _SyrComSection {
  final String titleEn;
  final String titleAr;
  final List<_SyrComModule> modules;

  const _SyrComSection({
    required this.titleEn,
    required this.titleAr,
    required this.modules,
  });
}

const _kCommonModules = <_SyrComModule>[
  _SyrComModule(
    id: 'approvals',
    titleEn: 'Approvals',
    titleAr: 'الموافقات',
    icon: Icons.task_alt_outlined,
    requiredPermission: 'support.case.read',
  ),
  _SyrComModule(
    id: 'meetings',
    titleEn: 'Meetings',
    titleAr: 'الاجتماعات',
    icon: Icons.event_outlined,
  ),
  _SyrComModule(
    id: 'drive',
    titleEn: 'Drive',
    titleAr: 'الملفات',
    icon: Icons.folder_outlined,
  ),
  _SyrComModule(
    id: 'reports',
    titleEn: 'Reports',
    titleAr: 'التقارير',
    icon: Icons.bar_chart_outlined,
    requiredPermission: 'finance.journal.read',
  ),
];

const _kCategorySections = <_SyrComSection>[
  _SyrComSection(
    titleEn: 'Office',
    titleAr: 'المكتب',
    modules: [
      _SyrComModule(
        id: 'access_admin',
        titleEn: 'Access Admin',
        titleAr: 'إدارة الصلاحيات',
        icon: Icons.admin_panel_settings_outlined,
        requiredPermission: 'access.assignment.write',
      ),
      _SyrComModule(
        id: 'tasks',
        titleEn: 'Tasks',
        titleAr: 'المهام',
        icon: Icons.checklist_outlined,
      ),
      _SyrComModule(
        id: 'docs',
        titleEn: 'Docs',
        titleAr: 'المستندات',
        icon: Icons.description_outlined,
      ),
      _SyrComModule(
        id: 'forms',
        titleEn: 'Forms',
        titleAr: 'النماذج',
        icon: Icons.assignment_outlined,
      ),
      _SyrComModule(
        id: 'announcements',
        titleEn: 'News',
        titleAr: 'الإعلانات',
        icon: Icons.campaign_outlined,
      ),
    ],
  ),
  _SyrComSection(
    titleEn: 'People',
    titleAr: 'الموارد البشرية',
    modules: [
      _SyrComModule(
        id: 'attendance',
        titleEn: 'Attendance',
        titleAr: 'الحضور',
        icon: Icons.fingerprint_outlined,
      ),
      _SyrComModule(
        id: 'leave',
        titleEn: 'Leave',
        titleAr: 'الإجازات',
        icon: Icons.beach_access_outlined,
      ),
      _SyrComModule(
        id: 'payroll',
        titleEn: 'Payroll',
        titleAr: 'الرواتب',
        icon: Icons.payments_outlined,
        requiredPermission: 'finance.journal.read',
      ),
      _SyrComModule(
        id: 'org',
        titleEn: 'Org chart',
        titleAr: 'الهيكل التنظيمي',
        icon: Icons.account_tree_outlined,
      ),
    ],
  ),
  _SyrComSection(
    titleEn: 'Customers',
    titleAr: 'العملاء',
    modules: [
      _SyrComModule(
        id: 'external_contacts',
        titleEn: 'Contacts',
        titleAr: 'جهات الاتصال',
        icon: Icons.contacts_outlined,
      ),
      _SyrComModule(
        id: 'customer_groups',
        titleEn: 'Groups',
        titleAr: 'المجموعات',
        icon: Icons.groups_2_outlined,
      ),
      _SyrComModule(
        id: 'crm',
        titleEn: 'CRM',
        titleAr: 'إدارة العملاء',
        icon: Icons.support_agent_outlined,
        requiredPermission: 'support.case.read',
      ),
      _SyrComModule(
        id: 'moments',
        titleEn: 'Moments',
        titleAr: 'اللحظات',
        icon: Icons.photo_library_outlined,
      ),
    ],
  ),
];
