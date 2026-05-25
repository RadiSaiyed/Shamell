// Cycle 262 — Coach Operator Disruption Broadcast composer.
//
// Operator-side page: compose a journey-level disruption notice,
// see recent broadcasts, and revoke ones that have outlived their
// usefulness.
//
// Composer is intentionally light: severity (3-way pill),
// headline (160 char single line), body (multi-line), TTL preset
// chips (30 min / 2 h / 12 h / 24 h). Channels default to `in_app`;
// future toggles (push / SMS) drop in as additional chips.
//
// The page is journey-scoped at the *publishing* level — the
// composer asks for journey_id and operator_id. When launched from
// a context that already knows the journey (e.g. the operator
// console's "trip detail" panel), those fields are pre-filled and
// disabled.

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import 'coach_disruption_broadcast_api.dart';

class CoachOperatorDisruptionBroadcastPage extends StatefulWidget {
  final String baseUrl;
  final String? lockedJourneyId;
  final String? lockedOperatorId;

  const CoachOperatorDisruptionBroadcastPage({
    required this.baseUrl,
    this.lockedJourneyId,
    this.lockedOperatorId,
    super.key,
  });

  @override
  State<CoachOperatorDisruptionBroadcastPage> createState() =>
      _CoachOperatorDisruptionBroadcastPageState();
}

class _CoachOperatorDisruptionBroadcastPageState
    extends State<CoachOperatorDisruptionBroadcastPage> {
  late final CoachDisruptionBroadcastApi _api;
  late final TextEditingController _journeyCtrl;
  late final TextEditingController _operatorCtrl;
  final TextEditingController _headlineCtrl = TextEditingController();
  final TextEditingController _bodyCtrl = TextEditingController();
  CoachDisruptionSeverity _severity = CoachDisruptionSeverity.warning;
  int _ttlSeconds = 12 * 3600;
  bool _publishing = false;
  bool _loading = true;
  String? _error;
  CoachDisruptionListResponse? _list;

  @override
  void initState() {
    super.initState();
    _api = CoachDisruptionBroadcastApi(baseUrl: widget.baseUrl);
    _journeyCtrl = TextEditingController(text: widget.lockedJourneyId ?? '');
    _operatorCtrl = TextEditingController(text: widget.lockedOperatorId ?? '');
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _journeyCtrl.dispose();
    _operatorCtrl.dispose();
    _headlineCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listOperatorBroadcasts();
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } on CoachDisruptionApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = err.toString();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = L10n.of(context).isArabic
            ? 'تعذّر تحميل القائمة'
            : 'Could not load broadcasts';
      });
    }
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final isArabic = L10n.of(context).isArabic;
    final journeyId = _journeyCtrl.text.trim();
    final operatorId = _operatorCtrl.text.trim();
    final headline = _headlineCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (journeyId.isEmpty || operatorId.isEmpty) {
      _snack(isArabic
          ? 'الرحلة والمشغّل مطلوبان'
          : 'Journey and operator are required');
      return;
    }
    if (headline.isEmpty || body.isEmpty) {
      _snack(isArabic
          ? 'العنوان والنص مطلوبان'
          : 'Headline and body are required');
      return;
    }
    setState(() => _publishing = true);
    try {
      await _api.publish(
        journeyId: journeyId,
        operatorId: operatorId,
        severity: _severity,
        headline: headline,
        body: body,
        expiresInSeconds: _ttlSeconds,
      );
      if (!mounted) return;
      _headlineCtrl.clear();
      _bodyCtrl.clear();
      setState(() => _publishing = false);
      _snack(isArabic ? 'تم النشر' : 'Broadcast published', ok: true);
      unawaited(_refresh());
    } on CoachDisruptionApiException catch (err) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _snack(err.toString());
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = false);
      _snack(isArabic ? 'فشل النشر' : 'Publish failed');
    }
  }

  Future<void> _revoke(CoachDisruptionBroadcast b) async {
    final isArabic = L10n.of(context).isArabic;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isArabic ? 'سحب البلاغ؟' : 'Revoke broadcast?'),
        content: Text(b.headline),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB71C1C)),
            child: Text(isArabic ? 'سحب' : 'Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.revoke(id: b.id);
      if (!mounted) return;
      _snack(isArabic ? 'تم السحب' : 'Revoked', ok: true);
      unawaited(_refresh());
    } on CoachDisruptionApiException catch (err) {
      if (!mounted) return;
      _snack(err.toString());
    } catch (_) {
      if (!mounted) return;
      _snack(isArabic ? 'فشل السحب' : 'Revoke failed');
    }
  }

  void _snack(String msg, {bool ok = false}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.removeCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            ok ? const Color(0xFF1B5E20) : const Color(0xFFB71C1C),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _shortTime(String iso) {
    final p = DateTime.tryParse(iso);
    if (p == null) return '';
    final l = p.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mn = l.minute.toString().padLeft(2, '0');
    return '$dd.$mm $hh:$mn';
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = L10n.of(context).isArabic;
    final journeyLocked = widget.lockedJourneyId != null;
    final operatorLocked = widget.lockedOperatorId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'بلاغات التعطّل' : 'Disruption broadcasts'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: isArabic ? 'تحديث' : 'Refresh',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          _composerCard(
            isArabic: isArabic,
            journeyLocked: journeyLocked,
            operatorLocked: operatorLocked,
          ),
          const SizedBox(height: 20),
          _sectionHeader(isArabic ? 'البلاغات الأخيرة' : 'Recent broadcasts'),
          const SizedBox(height: 8),
          if (_loading && _list == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && _list == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!,
                    style: const TextStyle(color: Colors.black54)),
              ),
            )
          else if (_list?.broadcasts.isEmpty ?? true)
            _emptyState(isArabic: isArabic)
          else
            ..._list!.broadcasts
                .map((b) => _broadcastCard(b, isArabic: isArabic)),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: .8,
        ),
      ),
    );
  }

  Widget _composerCard({
    required bool isArabic,
    required bool journeyLocked,
    required bool operatorLocked,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isArabic ? 'بلاغ جديد' : 'New broadcast',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _journeyCtrl,
              readOnly: journeyLocked,
              decoration: InputDecoration(
                labelText: isArabic ? 'معرّف الرحلة' : 'Journey id',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _operatorCtrl,
              readOnly: operatorLocked,
              decoration: InputDecoration(
                labelText: isArabic ? 'معرّف المشغّل' : 'Operator id',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isArabic ? 'الخطورة' : 'Severity',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: <Widget>[
                _severityChip(CoachDisruptionSeverity.info,
                    isArabic ? 'معلومة' : 'Info'),
                _severityChip(CoachDisruptionSeverity.warning,
                    isArabic ? 'تحذير' : 'Warning'),
                _severityChip(CoachDisruptionSeverity.critical,
                    isArabic ? 'حرج' : 'Critical'),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _headlineCtrl,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: isArabic ? 'العنوان' : 'Headline',
                hintText: isArabic
                    ? 'مثال: تأخير 20 دقيقة بسبب الطقس'
                    : 'e.g. 20 min delay — weather',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _bodyCtrl,
              minLines: 3,
              maxLines: 6,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: isArabic ? 'النص' : 'Body',
                hintText: isArabic
                    ? 'تفاصيل للركاب: السبب، التوقيت، الإجراء التالي'
                    : 'Details for passengers: cause, timing, next action',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isArabic ? 'مدّة الصلاحية' : 'Visible for',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black54,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: <Widget>[
                _ttlChip(30 * 60, isArabic ? '30 د' : '30 m'),
                _ttlChip(2 * 3600, isArabic ? 'ساعتان' : '2 h'),
                _ttlChip(12 * 3600, isArabic ? '12 س' : '12 h'),
                _ttlChip(24 * 3600, isArabic ? 'يوم' : '24 h'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _publishing ? null : _publish,
                icon: _publishing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.campaign_rounded),
                label: Text(
                  isArabic ? 'انشر البلاغ' : 'Publish broadcast',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _severityChip(CoachDisruptionSeverity s, String label) {
    final selected = _severity == s;
    final color = _colorForSeverity(s);
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
            color: selected ? Colors.white : color,
            fontWeight: FontWeight.w800,
          )),
      selected: selected,
      selectedColor: color,
      backgroundColor: color.withValues(alpha: .12),
      side: BorderSide(color: color.withValues(alpha: .6)),
      onSelected: (_) => setState(() => _severity = s),
    );
  }

  Widget _ttlChip(int seconds, String label) {
    final selected = _ttlSeconds == seconds;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w700)),
      selected: selected,
      selectedColor: Theme.of(context).colorScheme.primary,
      onSelected: (_) => setState(() => _ttlSeconds = seconds),
    );
  }

  Color _colorForSeverity(CoachDisruptionSeverity s) {
    switch (s) {
      case CoachDisruptionSeverity.info:
        return const Color(0xFF1976D2);
      case CoachDisruptionSeverity.warning:
        return const Color(0xFFE65100);
      case CoachDisruptionSeverity.critical:
        return const Color(0xFFB71C1C);
    }
  }

  IconData _iconForSeverity(CoachDisruptionSeverity s) {
    switch (s) {
      case CoachDisruptionSeverity.info:
        return Icons.info_outline_rounded;
      case CoachDisruptionSeverity.warning:
        return Icons.warning_amber_rounded;
      case CoachDisruptionSeverity.critical:
        return Icons.report_problem_rounded;
    }
  }

  Widget _broadcastCard(CoachDisruptionBroadcast b, {required bool isArabic}) {
    final color = _colorForSeverity(b.severity);
    final icon = _iconForSeverity(b.severity);
    final active = b.isActive;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  coachDisruptionSeverityWire(b.severity).toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: .6,
                  ),
                ),
                const Spacer(),
                if (!active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      isArabic ? 'منتهي' : 'Expired',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: .4,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              b.headline,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              b.body,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 13,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  isArabic
                      ? 'نُشِر ${_shortTime(b.createdAt)}'
                      : 'Published ${_shortTime(b.createdAt)}',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  isArabic
                      ? 'ينتهي ${_shortTime(b.expiresAt)}'
                      : 'expires ${_shortTime(b.expiresAt)}',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                if (active)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB71C1C),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _revoke(b),
                    icon: const Icon(Icons.undo_rounded, size: 16),
                    label: Text(isArabic ? 'سحب' : 'Revoke'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({required bool isArabic}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: <Widget>[
            Icon(Icons.notifications_none_rounded,
                size: 36,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: .35)),
            const SizedBox(height: 10),
            Text(
              isArabic
                  ? 'لا توجد بلاغات بعد. أنشئ الأول من النموذج أعلاه.'
                  : 'No broadcasts yet. Compose one from the form above.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
