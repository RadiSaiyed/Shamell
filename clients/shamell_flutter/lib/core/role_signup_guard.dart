import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'account_privilege_store.dart';
import 'role_signup_api.dart';
import 'role_signup_gate.dart';
import 'session_cookie_store.dart';

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
    // 1. Cached snapshot — fast, always works offline.
    AccountPrivilegeSnapshot snap = AccountPrivilegeSnapshot.empty;
    try {
      snap = await loadAccountPrivilegeSnapshotForBaseUrl(widget.baseUrl);
    } catch (_) {/* stale-cache fallback handled below */}

    // 2. Live overlay from /me/access-context. The local snapshot is
    // only written on login — if an admin grants this user the role
    // AFTER they signed in, the cache stays stale and the gate would
    // keep showing the signup form even though the role is already
    // attached. The live fetch closes that window: any role-grant
    // becomes visible on the next page-mount without needing a fresh
    // login. Soft-fail keeps the cached snapshot if the live call
    // can't reach the BFF.
    try {
      final headers = await shamellSessionHeadersForBaseUrl(widget.baseUrl);
      final resp = await http
          .get(
            Uri.parse('${widget.baseUrl}/me/access-context'),
            headers: {...headers, 'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200) {
        final parsed = json.decode(resp.body) as Map<String, dynamic>;
        final liveRoles = (parsed['roles'] as List?)
                ?.map((e) => e.toString())
                .toList(growable: false) ??
            const <String>[];
        final liveIsSuperadmin = parsed['is_superadmin'] == true;
        final liveIsAdmin = parsed['is_admin'] == true;
        // Merge live + cached; live wins where they overlap.
        snap = AccountPrivilegeSnapshot(
          roles: liveRoles.isNotEmpty ? liveRoles : snap.roles,
          isSuperadmin: liveIsSuperadmin || snap.isSuperadmin,
          isAdmin: liveIsAdmin || snap.isAdmin,
          operatorIds: snap.operatorIds,
        );
      }
    } catch (_) {/* live fetch optional; cached snapshot already loaded */}

    if (!mounted) return;
    setState(() {
      _privileges = snap;
      _loading = false;
    });
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
