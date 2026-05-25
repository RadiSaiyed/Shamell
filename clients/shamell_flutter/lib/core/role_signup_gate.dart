// Cycle 101 — Driver / Operator role-signup gate widget.
//
// Used by `ride_driver_page.dart` and `ride_operator_console_page.dart`
// when the current user does not yet hold the role the app requires.
// Renders one of three states based on the user's signup history:
//
//   * No request on file       → renders the signup form so the user
//                                can submit their profile.
//   * Pending request          → renders a "we're reviewing your
//                                application" status card.
//   * Rejected most-recent     → renders the rejection reason and a
//                                button that reopens the form.
//
// The widget owns its own polling so the host page just embeds it.
// On successful submission it calls `onSubmitted` so the host can
// refresh privileges right away when the admin approves.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'role_signup_api.dart';

/// Profile field that the gate's signup form should collect. The
/// host page passes a list of these; the gate handles state and
/// validation.
class RoleSignupFormField {
  final String key;
  final String label;
  final String labelArabic;
  final String? hint;
  final String? hintArabic;
  // Cycle 109 — optional starting value seeded into the
  // controller when the form first opens. Used to pre-fill the
  // Syria country code on the phone field so users only have to
  // type their local number.
  final String? defaultValue;
  final int minLength;
  final int maxLength;
  final TextInputType keyboard;
  final bool required;

  const RoleSignupFormField({
    required this.key,
    required this.label,
    required this.labelArabic,
    this.hint,
    this.hintArabic,
    this.defaultValue,
    this.minLength = 2,
    this.maxLength = 80,
    this.keyboard = TextInputType.text,
    this.required = true,
  });
}

/// Standard field sets for the two roles we ship today. Kept here so
/// the host pages don't have to re-declare them.
class RoleSignupFormFields {
  /// Driver onboarding — name, phone, car plate, license number.
  static const List<RoleSignupFormField> driver = <RoleSignupFormField>[
    RoleSignupFormField(
      key: 'full_name',
      label: 'Full name',
      labelArabic: 'الاسم الكامل',
      keyboard: TextInputType.name,
      maxLength: 96,
    ),
    RoleSignupFormField(
      key: 'phone',
      label: 'Phone (with country code)',
      labelArabic: 'رقم الهاتف (مع رمز الدولة)',
      hint: '+963 9XX XXX XXX',
      hintArabic: '+963 9XX XXX XXX',
      // Cycle 109 — pre-fill the Syria dial prefix so users only
      // need to add their local number; cursor lands after the
      // prefix in `initState`.
      defaultValue: '+963 ',
      keyboard: TextInputType.phone,
      maxLength: 32,
    ),
    RoleSignupFormField(
      key: 'car_plate',
      label: 'Car plate',
      labelArabic: 'لوحة السيارة',
      maxLength: 24,
    ),
    RoleSignupFormField(
      key: 'license_number',
      label: 'Driver license number',
      labelArabic: 'رقم رخصة القيادة',
      maxLength: 48,
    ),
  ];

  /// Operator onboarding — name, phone, reason for access.
  static const List<RoleSignupFormField> operator = <RoleSignupFormField>[
    RoleSignupFormField(
      key: 'full_name',
      label: 'Full name',
      labelArabic: 'الاسم الكامل',
      keyboard: TextInputType.name,
      maxLength: 96,
    ),
    RoleSignupFormField(
      key: 'phone',
      label: 'Phone (with country code)',
      labelArabic: 'رقم الهاتف (مع رمز الدولة)',
      hint: '+963 9XX XXX XXX',
      hintArabic: '+963 9XX XXX XXX',
      // Cycle 109 — pre-fill the Syria dial prefix so users only
      // need to add their local number; cursor lands after the
      // prefix in `initState`.
      defaultValue: '+963 ',
      keyboard: TextInputType.phone,
      maxLength: 32,
    ),
    RoleSignupFormField(
      key: 'reason',
      label: 'Why do you need operator access?',
      labelArabic: 'لماذا تحتاج صلاحية المشغّل؟',
      maxLength: 240,
      minLength: 10,
    ),
  ];
}

class RoleSignupGate extends StatefulWidget {
  final String roleId;
  final String roleLabel;
  final String roleLabelArabic;
  final List<RoleSignupFormField> fields;
  final RoleSignupApi api;
  final bool isArabic;
  final VoidCallback? onSubmitted;

  const RoleSignupGate({
    super.key,
    required this.roleId,
    required this.roleLabel,
    required this.roleLabelArabic,
    required this.fields,
    required this.api,
    required this.isArabic,
    this.onSubmitted,
  });

  @override
  State<RoleSignupGate> createState() => _RoleSignupGateState();
}

class _RoleSignupGateState extends State<RoleSignupGate> {
  bool _loading = true;
  bool _submitting = false;
  RoleSignupRequest? _latest;
  String? _error;
  bool _forceFormOpen = false;
  late final Map<String, TextEditingController> _controllers;
  // Cycle 107 — per-field FocusNodes so the keyboard "Next" button
  // chains through the form, and so we can auto-focus the first
  // input as soon as the gate renders the form. Saves the user a
  // tap before they start typing.
  late final Map<String, FocusNode> _focusNodes;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _controllers = <String, TextEditingController>{
      for (final field in widget.fields)
        field.key: TextEditingController(text: field.defaultValue ?? ''),
    };
    _focusNodes = <String, FocusNode>{
      for (final field in widget.fields) field.key: FocusNode(),
    };
    // Cycle 115 — live form-validity tracking. Each controller
    // listener bumps `_formRev` so the submit button can compute
    // its enabled state from `_isFormValid()` on every keystroke.
    for (final controller in _controllers.values) {
      controller.addListener(_handleFieldChanged);
    }
    unawaited(_loadHistory());
    // Light poll so an admin's approval lands in-app without the
    // user having to re-open the page. 20 s matches the rest of the
    // driver / operator console polling cadence.
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted || _submitting) return;
      unawaited(_loadHistory(silent: true));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    for (final controller in _controllers.values) {
      controller.removeListener(_handleFieldChanged);
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Cycle 115 — controller listener; rebuilds the form so the
  /// submit button's enabled state tracks current input.
  ///
  /// Cycle 116 — also clear any inline error so the user can see
  /// their corrections take effect; the error reappears only on the
  /// next failing submit.
  void _handleFieldChanged() {
    if (!mounted) return;
    setState(() {
      if (_error != null) _error = null;
    });
  }

  /// Cycle 115 — true when every required field meets its min-length.
  bool _isFormValid() {
    for (final field in widget.fields) {
      if (!field.required) continue;
      final value = _controllers[field.key]?.text.trim() ?? '';
      if (value.length < field.minLength) return false;
    }
    return true;
  }

  Future<void> _loadHistory({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final history = await widget.api.selfList();
      if (!mounted) return;
      final forRole = history
          .where((r) => r.requestedRoleId == widget.roleId)
          .toList(growable: false);
      RoleSignupRequest? latest;
      if (forRole.isNotEmpty) {
        latest = forRole.first; // self-list is DESC by submitted_at
      }
      // Cycle 104 — notify the host on pending → approved
      // transitions so the privilege snapshot can be re-fetched and
      // the gate is unmounted as soon as the admin signs off.
      // Without this hook, the driver / operator app would sit on
      // the "pending" card for up to the host's poll interval before
      // realising access was granted.
      final wasPending = _latest?.isPending ?? false;
      final isNowApproved = latest?.isApproved ?? false;
      setState(() {
        _latest = latest;
        _loading = false;
        // If admin approved, host page will refresh privileges and
        // unmount this gate. Until then we want to show the approval
        // confirmation, not a fresh form, so don't auto-clear here.
      });
      if (wasPending && isNowApproved) {
        // Reuse the submit callback to trigger the host's full
        // refresh path; once privileges land, the gate is unmounted.
        widget.onSubmitted?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) {
          _error =
              widget.isArabic ? 'تعذّر تحميل الحالة' : 'Could not load status';
        }
      });
    }
  }

  Future<void> _submit() async {
    final profile = <String, dynamic>{};
    for (final field in widget.fields) {
      final value = _controllers[field.key]!.text.trim();
      if (field.required && value.length < field.minLength) {
        setState(() {
          _error = widget.isArabic
              ? 'يرجى ملء جميع الحقول'
              : 'Please fill all required fields';
        });
        return;
      }
      if (value.isNotEmpty) {
        profile[field.key] = value;
      }
    }
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = await widget.api.submitRequest(
        requestedRoleId: widget.roleId,
        profile: profile,
      );
      if (!mounted) return;
      setState(() {
        _latest = created;
        _submitting = false;
        _forceFormOpen = false;
      });
      widget.onSubmitted?.call();
    } on RoleSignupApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = err.detail.isNotEmpty
            ? err.detail
            : (widget.isArabic ? 'فشل الإرسال' : 'Submission failed');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = widget.isArabic
            ? 'تعذّر إرسال الطلب'
            : 'Could not submit request';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final latest = _latest;
    if (latest != null && latest.isPending) {
      return _buildPendingCard(context, latest);
    }
    if (latest != null && latest.isApproved) {
      // Cycle 110 — explicit approved state. Without this branch
      // the build() fell through to `_buildForm()` during the brief
      // window between the gate polling in the approval and the
      // host re-fetching privileges + unmounting the gate. The
      // result was a confusing "back to the signup form!" flash.
      return _buildApprovedCard(context, latest);
    }
    if (latest != null && latest.isRejected && !_forceFormOpen) {
      return _buildRejectedCard(context, latest);
    }
    return _buildForm(context);
  }

  Widget _buildApprovedCard(BuildContext context, RoleSignupRequest request) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withValues(alpha: .14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.check_circle_rounded,
                color: Color(0xFF2E7D32)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    isArabic
                        ? 'تمت الموافقة! جارٍ تجهيز التطبيق…'
                        : 'Approved! Preparing your app…',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isArabic
                        ? 'حصلت على صلاحية ${_roleLabel(true)}.'
                        : 'You now have ${_roleLabel(false)} access.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingCard(BuildContext context, RoleSignupRequest request) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFA000).withValues(alpha: .18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.hourglass_top_rounded,
                    color: Color(0xFFB45309)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isArabic
                        ? 'طلب التسجيل قيد المراجعة'
                        : 'Application under review',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isArabic
                  ? 'سيقوم مسؤول سرتشات بمراجعة الطلب ${_roleLabel(isArabic)} قريباً. لا حاجة لإرسال الطلب مرة أخرى.'
                  : 'A SyrChat admin will review your ${_roleLabel(isArabic)} application shortly. No need to submit again.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            // Cycle 106 — friendly relative timestamp instead of the
            // raw ISO string the server returns. Users see "Submitted
            // 2 minutes ago" rather than "2026-05-16T10:30:45Z".
            Text(
              _relativeSubmittedLabel(request.submittedAt,
                  isArabic: isArabic),
              style: TextStyle(
                fontSize: 11,
                color:
                    theme.colorScheme.onSurface.withValues(alpha: .60),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRejectedCard(BuildContext context, RoleSignupRequest request) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: .38),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.cancel_outlined,
                    color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isArabic
                        ? 'تم رفض طلب التسجيل'
                        : 'Application rejected',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if ((request.reviewerNotes ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${isArabic ? "السبب" : "Reason"}: ${request.reviewerNotes}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            const SizedBox(height: 4),
            FilledButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label:
                  Text(isArabic ? 'تقديم طلب جديد' : 'Submit a new application'),
              onPressed: () {
                // Cycle 128 — selection haptic on the "re-apply"
                // button so the user feels the gesture register
                // before the form animates in.
                unawaited(HapticFeedback.selectionClick());
                setState(() => _forceFormOpen = true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = widget.isArabic;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: .32),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.person_add_alt_1_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isArabic
                        ? 'سجّل للحصول على صلاحية ${_roleLabel(isArabic)}'
                        : 'Register for ${_roleLabel(isArabic)} access',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isArabic
                  ? 'سيقوم المسؤول بمراجعة الطلب. بعد الموافقة، ستحصل على الصلاحية فوراً.'
                  : 'An admin will review your application. Once approved, you get access immediately.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .78),
              ),
            ),
            const SizedBox(height: 12),
            // Cycle 107 — chain the keyboard "Next" through the
            // fields and submit on "Done". Auto-focus the first
            // field so the user can start typing immediately when
            // the gate renders the form.
            for (var i = 0; i < widget.fields.length; i++) ...<Widget>[
              Builder(builder: (_) {
                final field = widget.fields[i];
                final isLast = i == widget.fields.length - 1;
                return TextField(
                  controller: _controllers[field.key],
                  focusNode: _focusNodes[field.key],
                  autofocus: i == 0,
                  keyboardType: field.keyboard,
                  maxLength: field.maxLength,
                  enabled: !_submitting,
                  textInputAction: isLast
                      ? TextInputAction.done
                      : TextInputAction.next,
                  onSubmitted: (_) {
                    if (isLast) {
                      unawaited(_submit());
                    } else {
                      final nextKey = widget.fields[i + 1].key;
                      _focusNodes[nextKey]?.requestFocus();
                    }
                  },
                  decoration: InputDecoration(
                    labelText: isArabic ? field.labelArabic : field.label,
                    hintText: isArabic ? field.hintArabic : field.hint,
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    counterText: '',
                    border: const OutlineInputBorder(),
                  ),
                );
              }),
              const SizedBox(height: 10),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                // Cycle 115 — disable the submit button until every
                // required field meets its min-length, so the user
                // gets immediate "this form isn't ready" feedback
                // instead of waiting for an inline error after tap.
                onPressed: (_submitting || !_isFormValid()) ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: Text(
                  _submitting
                      ? (isArabic ? 'جارٍ الإرسال…' : 'Submitting…')
                      : (isArabic ? 'إرسال الطلب' : 'Submit application'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(bool isArabic) =>
      isArabic ? widget.roleLabelArabic : widget.roleLabel;

  /// Cycle 106 — render the signup submission timestamp as a
  /// friendly relative phrase. Falls back to the raw ISO string on
  /// parse failure so we still show something useful.
  String _relativeSubmittedLabel(String iso, {required bool isArabic}) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return isArabic ? 'تم الإرسال في: $iso' : 'Submitted: $iso';
    }
    final now = DateTime.now().toUtc();
    final stamp = parsed.toUtc();
    final diff = now.difference(stamp);
    if (diff.isNegative || diff.inSeconds < 45) {
      return isArabic ? 'تم الإرسال للتو' : 'Submitted just now';
    }
    if (diff.inMinutes < 1) {
      return isArabic
          ? 'تم الإرسال منذ ${diff.inSeconds} ثانية'
          : 'Submitted ${diff.inSeconds}s ago';
    }
    if (diff.inMinutes < 60) {
      return isArabic
          ? 'تم الإرسال منذ ${diff.inMinutes} د'
          : 'Submitted ${diff.inMinutes} min ago';
    }
    if (diff.inHours < 24) {
      return isArabic
          ? 'تم الإرسال منذ ${diff.inHours} س'
          : 'Submitted ${diff.inHours} h ago';
    }
    return isArabic
        ? 'تم الإرسال منذ ${diff.inDays} يوم'
        : 'Submitted ${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  }
}
