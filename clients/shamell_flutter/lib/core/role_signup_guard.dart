import 'dart:async';

import 'package:flutter/material.dart';

import 'account_privilege_store.dart';
import 'role_signup_api.dart';
import 'role_signup_gate.dart';

/// Wraps a console page with the self-service role-signup gate so the
/// page only renders for users that already hold [roleId] (or are
/// platform admins/superadmins). Anyone else sees [RoleSignupGate]
/// instead, submits a request via [RoleSignupApi], and the gate
/// flips to the wrapped page on the next privilege refresh after an
/// admin approves them from the operator console's Signups workspace.
///
/// Used for the standalone-app flavors (Bus / Carrier / Hotel / Taxi
/// operator) where the dispatcher in `shamellBuildSignedInHome`
/// would otherwise drop signed-in-but-unprivileged users straight
/// into a 401/empty page.
class RoleSignupGuard extends StatefulWidget {
  final String baseUrl;
  final String roleId;
  final String roleLabel;
  final String roleLabelArabic;
  final List<RoleSignupFormField> fields;
  final WidgetBuilder builder;

  const RoleSignupGuard({
    super.key,
    required this.baseUrl,
    required this.roleId,
    required this.roleLabel,
    required this.roleLabelArabic,
    required this.fields,
    required this.builder,
  });

  @override
  State<RoleSignupGuard> createState() => _RoleSignupGuardState();
}

class _RoleSignupGuardState extends State<RoleSignupGuard> {
  bool _loading = true;
  AccountPrivilegeSnapshot _privileges = AccountPrivilegeSnapshot.empty;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPrivileges());
  }

  bool get _accessAllowed =>
      _privileges.isSuperadmin ||
      _privileges.isAdmin ||
      _privileges.roles.contains(widget.roleId);

  Future<void> _loadPrivileges() async {
    try {
      final snap =
          await loadAccountPrivilegeSnapshotForBaseUrl(widget.baseUrl);
      if (!mounted) return;
      setState(() {
        _privileges = snap;
        _loading = false;
      });
    } catch (_) {
      // Soft-fail: stale snapshot is fine — the gate's "no role"
      // branch is the safer default to render. The user can still
      // submit a request; admin approval refreshes the snapshot.
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_accessAllowed) {
      return widget.builder(context);
    }
    // Wrap the gate in a Scaffold so it gets a proper safe area and
    // a back-affordance via the system bar — the gate widget itself
    // is just a form, not a full page.
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? widget.roleLabelArabic : widget.roleLabel),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: RoleSignupGate(
            roleId: widget.roleId,
            roleLabel: widget.roleLabel,
            roleLabelArabic: widget.roleLabelArabic,
            fields: widget.fields,
            api: RoleSignupApi(baseUrl: widget.baseUrl),
            isArabic: isArabic,
            onSubmitted: () => unawaited(_loadPrivileges()),
          ),
        ),
      ),
    );
  }
}
