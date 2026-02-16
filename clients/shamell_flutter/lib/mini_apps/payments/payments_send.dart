import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/glass.dart';
import '../../core/capabilities.dart';
import 'payments_utils.dart';
import '../../core/offline_queue.dart';
import '../../core/format.dart' show fmtCents;
import '../../core/friends_page.dart';
import '../../core/l10n.dart';
import '../../core/perf.dart';
import '../../core/status_banner.dart';
import '../../core/ui_kit.dart';
import 'package:shamell_flutter/core/session_cookie_store.dart';

class FavoritesDropdown extends StatelessWidget {
  final List<Map<String, dynamic>> favorites;
  final void Function(String value) onSelected;
  const FavoritesDropdown(
      {super.key, required this.favorites, required this.onSelected});
  @override
  Widget build(BuildContext context) {
    if (favorites.isEmpty) return const SizedBox.shrink();
    final l = L10n.of(context);
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(labelText: l.payFavoritesLabel),
      isExpanded: true,
      items: favorites.map((f) {
        final alias = (f['alias'] ?? '').toString();
        final id = (f['favorite_wallet_id'] ?? '').toString();
        final label = alias.isNotEmpty ? '$alias  ·  $id' : id;
        return DropdownMenuItem(
            value: id, child: Text(label, overflow: TextOverflow.ellipsis));
      }).toList(),
      onChanged: (v) {
        if (v != null) onSelected(v);
      },
    );
  }
}

class QuickAmountChips extends StatelessWidget {
  final List<int> presets;
  final VoidCallback onClear;
  final void Function(int add) onAdd; // add in whole SYP
  const QuickAmountChips(
      {super.key,
      this.presets = const [5, 10, 25, 50, 100],
      required this.onClear,
      required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final v in presets)
        ActionChip(label: Text('+$v'), onPressed: () => onAdd(v)),
      ActionChip(label: Text(L10n.of(context).clearLabel), onPressed: onClear),
    ]);
  }
}

class PaymentSendTab extends StatefulWidget {
  final String baseUrl;
  final String fromWalletId;
  final String deviceId;
  final String? initialRecipient;
  final int? initialAmountCents;

  /// Optional human‑readable context for the payment target (e.g. merchant or mini‑program).
  final String? contextLabel;
  const PaymentSendTab({
    super.key,
    required this.baseUrl,
    required this.fromWalletId,
    required this.deviceId,
    this.initialRecipient,
    this.initialAmountCents,
    this.contextLabel,
  });
  @override
  State<PaymentSendTab> createState() => _PaymentSendTabState();
}

class _PaymentSendTabState extends State<PaymentSendTab> {
  final toCtrl = TextEditingController();
  final amtCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  String myWallet = '';
  int? _balanceCents;
  bool _loadingWallet = false;
  String _curSym = 'SYP';
  List<String> recents = [];
  List<Map<String, dynamic>> favorites = [];
  String _toResolvedHint = '';
  int _sendCooldownSec = 0;
  Timer? _cooldownTimer;
  String _bannerMsg = '';
  StatusKind _bannerKind = StatusKind.info;

  Timer? _resolveTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final sp = await SharedPreferences.getInstance();
    myWallet = sp.getString('wallet_id') ?? widget.fromWalletId;
    recents = sp.getStringList('pay_recents') ?? [];
    final cs = sp.getString('currency_symbol');
    if (cs != null && cs.isNotEmpty) {
      _curSym = cs;
    }
    if (widget.initialRecipient != null &&
        widget.initialRecipient!.trim().isNotEmpty) {
      toCtrl.text = widget.initialRecipient!.trim();
    }
    if (widget.initialAmountCents != null && widget.initialAmountCents! > 0) {
      final major = widget.initialAmountCents! / 100.0;
      amtCtrl.text = major.toStringAsFixed(2);
    }
    setState(() {});
    await _loadFavorites();
    await _loadWallet();
    _attachResolver();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _resolveTimer?.cancel();
    super.dispose();
  }

  void _attachResolver() {
    toCtrl.removeListener(_onResolveChanged);
    toCtrl.addListener(_onResolveChanged);
  }

  void _onResolveChanged() {
    _resolveTimer?.cancel();
    _resolveTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _resolveTarget();
    });
  }

  Future<void> _resolveTarget() async {
    final v = toCtrl.text.trim();
    _toResolvedHint = '';
    setState(() {});
    if (v.isEmpty) return;
    final l = L10n.of(context);
    try {
      final isPhone = v.startsWith('+') || RegExp(r'^\d{6,}$').hasMatch(v);
      final isAlias = v.startsWith('@') && v.length > 1;
      if (isPhone) {
        // Permanently disabled: do not route payments by phone number.
        _toResolvedHint = l.isArabic
            ? 'أرقام الهاتف غير مدعومة. استخدم مُعرّف المحفظة أو @اسم.'
            : 'Phone numbers are not supported. Use a wallet ID or @alias.';
        setState(() {});
      } else if (isAlias) {
        // Best practice: do not expose an alias enumeration endpoint.
        // Alias resolution happens server-side when sending.
        _toResolvedHint = l.isArabic
            ? 'سيتم حل @الاسم على الخادم عند الإرسال.'
            : 'Alias will be resolved on the server when sending.';
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _loadWallet() async {
    if (myWallet.isEmpty) return;
    setState(() => _loadingWallet = true);
    try {
      final r = await http.get(
          Uri.parse('${widget.baseUrl}/payments/wallets/' +
              Uri.encodeComponent(myWallet)),
          headers: await _hdrPS(widget.baseUrl));
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body);
        _balanceCents = (j['balance_cents'] ?? 0) as int;
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingWallet = false);
  }

  Future<void> _loadFavorites() async {
    if (myWallet.isEmpty) return;
    try {
      final r = await http.get(
          Uri.parse('${widget.baseUrl}/payments/favorites?owner_wallet_id=' +
              Uri.encodeComponent(myWallet)),
          headers: await _hdrPS(widget.baseUrl));
      if (r.statusCode == 200) {
        favorites = (jsonDecode(r.body) as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveRecent(String w) async {
    if (w.isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final cur = sp.getStringList('pay_recents') ?? [];
    cur.removeWhere((x) => x == w);
    cur.insert(0, w);
    while (cur.length > 5) cur.removeLast();
    await sp.setStringList('pay_recents', cur);
    setState(() => recents = cur);
  }

  void _startCooldown(int secs) {
    if (secs <= 0) return;
    _cooldownTimer?.cancel();
    setState(() => _sendCooldownSec = secs);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_sendCooldownSec <= 1) {
        t.cancel();
        setState(() => _sendCooldownSec = 0);
      } else
        setState(() => _sendCooldownSec -= 1);
    });
  }

  double _parseMajor(String s) {
    try {
      final t = s.trim().replaceAll(',', '.');
      return double.parse(t);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _sendManual() async {
    final l = L10n.of(context);
    String to = toCtrl.text.trim();
    final amountMajor = _parseMajor(amtCtrl.text.trim());
    if (to.isEmpty || amountMajor <= 0) {
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = l.payCheckInputs;
      });
      return;
    }
    final uri = Uri.parse('${widget.baseUrl}/payments/transfer');
    final ikey = 'tw-${DateTime.now().millisecondsSinceEpoch}';
    final target = buildTransferTarget(to);
    if (target.isEmpty) {
      setState(() {
        _bannerKind = StatusKind.error;
        _bannerMsg = l.isArabic
            ? 'الرجاء إدخال مُعرّف محفظة صالح أو @اسم. أرقام الهاتف غير مدعومة.'
            : 'Enter a valid wallet ID or @alias. Phone numbers are not supported.';
      });
      return;
    }
    final payload = <String, dynamic>{
      'from_wallet_id': myWallet,
      'amount': double.parse(amountMajor.toStringAsFixed(2)),
      if (noteCtrl.text.trim().isNotEmpty) 'reference': noteCtrl.text.trim(),
      ...target
    };
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      final headers = (await _hdrPS(widget.baseUrl, json: true))
        ..addAll({'Idempotency-Key': ikey, 'X-Device-ID': widget.deviceId});
      final resp =
          await http.post(uri, headers: headers, body: jsonEncode(payload));
      if (resp.statusCode == 429) {
        try {
          final j = jsonDecode(resp.body);
          final ms = (j['retry_after_ms'] ?? 0) as int;
          final sec = (ms / 1000).ceil();
          _startCooldown(sec > 0 ? sec : 15);
        } catch (_) {
          _startCooldown(15);
        }
      }
      if (resp.statusCode >= 500) {
        Perf.action('pay_send_queued');
        await OfflineQueue.enqueue(OfflineTask(
            id: ikey,
            method: 'POST',
            url: uri.toString(),
            headers: headers,
            body: jsonEncode(payload),
            tag: 'payments_transfer',
            createdAt: DateTime.now().millisecondsSinceEpoch));
        final msg = l.payOfflineQueued;
        setState(() {
          _bannerKind = StatusKind.warning;
          _bannerMsg = msg;
        });
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        Perf.action('pay_send_ok');
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.sample('pay_send_ms', dt);
        try {
          HapticFeedback.mediumImpact();
        } catch (_) {}
        await _loadWallet();
        await _saveRecent(to);
        final msg = l.isArabic
            ? 'تم إرسال ${amountMajor.toStringAsFixed(2)} $_curSym إلى $to'
            : 'Sent ${amountMajor.toStringAsFixed(2)} $_curSym to $to';
        setState(() {
          _bannerKind = StatusKind.success;
          _bannerMsg = msg;
        });
      } else if (resp.statusCode >= 400) {
        Perf.action('pay_send_fail');
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.sample('pay_send_ms', dt);
        String msg = l.paySendFailed;
        try {
          final ct = resp.headers['content-type'] ?? '';
          if (ct.startsWith('application/json')) {
            final body = jsonDecode(resp.body);
            final detail = body is Map<String, dynamic> ? body['detail'] : null;
            final detailStr = detail == null ? '' : detail.toString();
            if (detailStr.contains('amount exceeds guardrail')) {
              msg = l.payGuardrailAmount;
            } else if (detailStr.contains('velocity guardrail (wallet)')) {
              msg = l.payGuardrailVelocityWallet;
            } else if (detailStr.contains('velocity guardrail (device)')) {
              msg = l.payGuardrailVelocityDevice;
            }
          }
        } catch (_) {/* best-effort only */}
        setState(() {
          _bannerKind = StatusKind.error;
          _bannerMsg = msg;
        });
      }
    } catch (_) {
      final headers = (await _hdrPS(widget.baseUrl, json: true))
        ..addAll({'Idempotency-Key': ikey, 'X-Device-ID': widget.deviceId});
      await OfflineQueue.enqueue(OfflineTask(
          id: ikey,
          method: 'POST',
          url: uri.toString(),
          headers: headers,
          body: jsonEncode(payload),
          tag: 'payments_transfer',
          createdAt: DateTime.now().millisecondsSinceEpoch));
      Perf.action('pay_send_queued');
      final msg =
          '${l.payOfflineSavedPrefix}: $to, ${amountMajor.toStringAsFixed(2)} $_curSym';
      setState(() {
        _bannerKind = StatusKind.warning;
        _bannerMsg = msg;
      });
    }
  }

  Future<void> _reviewAndSend() async {
    final l = L10n.of(context);
    final to = toCtrl.text.trim();
    final amountMajor = _parseMajor(amtCtrl.text.trim());
    if (to.isEmpty || amountMajor <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.payCheckInputs)));
      return;
    }
    final fmt = '${amountMajor.toStringAsFixed(2)} $_curSym';
    final hint = _toResolvedHint;
    final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (_) {
          return buildReviewSheet(
              context: context,
              to: to,
              hint: hint,
              amountFmt: fmt,
              note: noteCtrl.text.trim());
        });
    if (ok == true) {
      await _sendManual();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final ctxLabel = (widget.contextLabel ?? '').trim();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_bannerMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: StatusBanner(
                kind: _bannerKind, message: _bannerMsg, dense: true),
          ),
        FormSection(
          title: l.isArabic ? 'محفظتك' : 'Wallet & balance',
          children: [
            _walletHero(),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'المستلم والمبلغ' : 'Recipient & amount',
          children: [
            if (ctxLabel.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.storefront_outlined, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l.isArabic ? 'الدفع إلى $ctxLabel' : 'Paying $ctxLabel',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: .80),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            if (favorites.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FavoritesDropdown(
                  favorites: favorites,
                  onSelected: (v) {
                    toCtrl.text = v;
                    setState(() {});
                  },
                ),
              ),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: toCtrl,
                  decoration: InputDecoration(labelText: l.payRecipientLabel),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: amtCtrl,
                  decoration: InputDecoration(labelText: l.payAmountLabel),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            QuickAmountChips(
              onClear: () {
                amtCtrl.text = '';
                setState(() {});
              },
              onAdd: (v) {
                final cur = _parseMajor(amtCtrl.text.trim());
                amtCtrl.text = (cur + v).toStringAsFixed(2);
                setState(() {});
                try {
                  HapticFeedback.selectionClick();
                } catch (_) {}
              },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Builder(
                builder: (_) {
                  final c = _parseMajor(amtCtrl.text.trim());
                  final s = c > 0 ? '${c.toStringAsFixed(2)} ${_curSym}' : '';
                  return Text(
                    s,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: .70),
                    ),
                  );
                },
              ),
            ),
            if (_toResolvedHint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _toResolvedHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: .60),
                  ),
                ),
              ),
          ],
        ),
        FormSection(
          title: l.isArabic ? 'تفاصيل إضافية' : 'Details & contacts',
          children: [
            TextField(
              controller: noteCtrl,
              decoration: InputDecoration(
                labelText: l.payNoteLabel,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Semantics(
                  button: true,
                  label: l.isArabic ? 'إرسال دفعة' : 'Send payment',
                  child: SendButton(
                    cooldownSec: _sendCooldownSec,
                    onTap: _reviewAndSend,
                  ),
                ),
              ],
            ),
            if (favorites.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: favorites.map((f) {
                    final label = (f['alias'] ?? '').toString().isNotEmpty
                        ? (f['alias'] as String)
                        : (f['favorite_wallet_id'] as String);
                    return ActionChip(
                      avatar: CircleAvatar(child: Text(label.characters.first)),
                      label: Text(label, overflow: TextOverflow.ellipsis),
                      onPressed: () {
                        toCtrl.text = label;
                        setState(() {});
                      },
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _walletHero() {
    final bal = _balanceCents;
    final l = L10n.of(context);
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: .90),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.account_balance_wallet_outlined, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.homeWallet,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    myWallet.isEmpty ? l.notSet : myWallet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: l.isArabic ? 'نسخ رقم المحفظة' : 'Copy wallet ID',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: myWallet.isEmpty
                      ? null
                      : () {
                          try {
                            Clipboard.setData(ClipboardData(text: myWallet));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.copiedLabel)),
                            );
                          } catch (_) {}
                        },
                ),
              ],
            ),
          ],
        )),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(l.isArabic ? 'الرصيد' : 'Balance'),
            Text(
              bal == null
                  ? (_loadingWallet ? '…' : '—')
                  : '${fmtCents(bal)} ${_curSym}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ],
        ),
      ]),
    );
  }
}

class SendButton extends StatelessWidget {
  final int cooldownSec;
  final VoidCallback onTap;
  const SendButton({super.key, required this.cooldownSec, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final label = cooldownSec > 0 ? l.paySendAfter(cooldownSec) : l.sendLabel;
    return Opacity(
      opacity: cooldownSec > 0 ? .55 : 1,
      child: PrimaryButton(
        icon: Icons.send_outlined,
        label: label,
        expanded: true,
        onPressed: () {
          if (cooldownSec > 0) {
            final msg = l.payWaitSeconds(cooldownSec);
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(msg)));
          } else {
            onTap();
          }
        },
      ),
    );
  }
}

Widget buildReviewSheet(
    {required BuildContext context,
    required String to,
    required String hint,
    required String amountFmt,
    String? note}) {
  final l = L10n.of(context);
  return Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: GlassPanel(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Row(children: [
              const Icon(Icons.person_outline),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(to,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              if (hint.isNotEmpty)
                Text(hint, style: const TextStyle(color: Colors.white70))
            ]),
            const SizedBox(height: 12),
            Center(
                child: Text(amountFmt,
                    style: const TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w800))),
            if ((note ?? '').trim().isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(
                      child: Text(note!.trim(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black)))),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: PrimaryButton(
                  label: l.isArabic ? 'إلغاء' : 'Cancel',
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  label: l.isArabic ? 'إرسال' : 'Send',
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ]),
          ])),
    ),
  );
}

class GroupPayPage extends StatefulWidget {
  final String baseUrl;
  final String fromWalletId;
  final String deviceId;
  const GroupPayPage({
    super.key,
    required this.baseUrl,
    required this.fromWalletId,
    required this.deviceId,
  });
  @override
  State<GroupPayPage> createState() => _GroupPayPageState();
}

class _GroupPayPageState extends State<GroupPayPage> {
  final TextEditingController _recipientsCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _noteCtrl = TextEditingController();

  String _walletId = '';
  int? _balanceCents;
  bool _loadingWallet = false;
  bool _submitting = false;
  String _out = '';
  final List<String> _selectedFriends = <String>[];
  bool _allowFriendsPicker = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final caps = ShamellCapabilities.fromPrefsForBaseUrl(sp, widget.baseUrl);
      _allowFriendsPicker = caps.friends;
      final localWallet = (sp.getString('wallet_id') ?? '').trim();
      _walletId = localWallet.isNotEmpty ? localWallet : widget.fromWalletId;
    } catch (_) {
      _walletId = widget.fromWalletId;
    }
    if (mounted) {
      setState(() {});
    }
    await _loadWallet();
  }

  Future<void> _loadWallet() async {
    final wid = _walletId.trim();
    if (wid.isEmpty) return;
    setState(() => _loadingWallet = true);
    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/payments/wallets/' + Uri.encodeComponent(wid));
      final r = await http.get(uri, headers: await _hdrPS(widget.baseUrl));
      if (r.statusCode == 200) {
        final body = jsonDecode(r.body);
        if (body is Map<String, dynamic>) {
          final bal = body['balance_cents'];
          if (bal is int) {
            _balanceCents = bal;
          } else if (bal is num) {
            _balanceCents = bal.toInt();
          }
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loadingWallet = false);
    }
  }

  @override
  void dispose() {
    _recipientsCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  List<String> _parseRecipients() {
    final set = <String>{};
    for (final f in _selectedFriends) {
      final v = f.trim();
      if (v.isNotEmpty) set.add(v);
    }
    final raw = _recipientsCtrl.text;
    final parts = raw
        .split(RegExp(r'[,\n;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    set.addAll(parts);
    final list = set.toList();
    list.sort();
    return list;
  }

  List<int> _computeSplits(int totalCents, int count) {
    if (count <= 0 || totalCents <= 0) {
      return List<int>.filled(count, 0);
    }
    final per = totalCents ~/ count;
    final rem = totalCents % count;
    final out = List<int>.filled(count, per);
    for (var i = 0; i < rem; i++) {
      out[i] = out[i] + 1;
    }
    return out;
  }

  Future<_GroupSendOutcome> _createRequestForOne(
      String to, int amountCents) async {
    final wid =
        _walletId.trim().isEmpty ? widget.fromWalletId : _walletId.trim();
    if (wid.isEmpty || amountCents <= 0) return _GroupSendOutcome.failed;
    final l = L10n.of(context);
    final note = _noteCtrl.text.trim();
    final basePayload = <String, Object?>{
      'from_wallet_id': wid,
      'amount_cents': amountCents,
      if (note.isNotEmpty) 'message': note,
      'expires_in_secs': 24 * 3600,
    };
    final raw = to.trim();
    final isPhone = raw.startsWith('+') || RegExp(r'^[0-9]{6,}$').hasMatch(raw);
    if (isPhone) return _GroupSendOutcome.failed;

    final uri = Uri.parse('${widget.baseUrl}/payments/requests');
    Map<String, Object?> payload;
    if (raw.startsWith('@')) {
      payload = {
        ...basePayload,
        'to_alias': raw,
      };
    } else {
      payload = {
        ...basePayload,
        'to_wallet_id': raw,
      };
    }
    try {
      final headers = await _hdrPS(widget.baseUrl, json: true);
      final resp =
          await http.post(uri, headers: headers, body: jsonEncode(payload));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        Perf.action('pay_group_req_ok');
        return _GroupSendOutcome.success;
      }
      if (resp.statusCode >= 500) {
        Perf.action('pay_group_req_fail_server');
      } else {
        Perf.action('pay_group_req_fail_client');
      }
      return _GroupSendOutcome.failed;
    } catch (_) {
      Perf.action('pay_group_req_error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l.isArabic
                  ? 'تعذر إنشاء بعض طلبات السداد.'
                  : 'Could not create some split‑bill requests.',
            ),
          ),
        );
      }
      return _GroupSendOutcome.failed;
    }
  }

  Future<_GroupSendOutcome> _sendOne(String to, int amountCents) async {
    final wid =
        _walletId.trim().isEmpty ? widget.fromWalletId : _walletId.trim();
    if (wid.isEmpty) return _GroupSendOutcome.failed;
    final raw = to.trim();
    final isPhone = raw.startsWith('+') || RegExp(r'^[0-9]{6,}$').hasMatch(raw);
    if (isPhone) {
      // Best practice: do not route transfers by phone number in group flows.
      return _GroupSendOutcome.failed;
    }
    final uri = Uri.parse('${widget.baseUrl}/payments/transfer');
    final amountMajor = amountCents / 100.0;
    final target = buildTransferTarget(raw);
    if (target.isEmpty) {
      return _GroupSendOutcome.failed;
    }
    final payload = <String, dynamic>{
      'from_wallet_id': wid,
      'amount': double.parse(amountMajor.toStringAsFixed(2)),
      if (_noteCtrl.text.trim().isNotEmpty) 'reference': _noteCtrl.text.trim(),
      ...target,
    };
    final ikey =
        'twg-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${to.hashCode}';
    final t0 = DateTime.now().millisecondsSinceEpoch;
    try {
      final headers = (await _hdrPS(widget.baseUrl, json: true))
        ..addAll({'Idempotency-Key': ikey, 'X-Device-ID': widget.deviceId});
      final resp =
          await http.post(uri, headers: headers, body: jsonEncode(payload));
      if (resp.statusCode == 429) {
        Perf.action('pay_group_send_rate_limited');
        return _GroupSendOutcome.failed;
      }
      if (resp.statusCode >= 500) {
        await OfflineQueue.enqueue(OfflineTask(
          id: ikey,
          method: 'POST',
          url: uri.toString(),
          headers: headers,
          body: jsonEncode(payload),
          tag: 'payments_transfer',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        Perf.action('pay_group_send_queued');
        return _GroupSendOutcome.queued;
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        Perf.action('pay_group_send_ok');
        final dt = DateTime.now().millisecondsSinceEpoch - t0;
        Perf.sample('pay_group_send_ms', dt);
        return _GroupSendOutcome.success;
      }
      Perf.action('pay_group_send_fail');
      return _GroupSendOutcome.failed;
    } catch (_) {
      try {
        final headers = (await _hdrPS(widget.baseUrl, json: true))
          ..addAll({'Idempotency-Key': ikey, 'X-Device-ID': widget.deviceId});
        await OfflineQueue.enqueue(OfflineTask(
          id: ikey,
          method: 'POST',
          url: uri.toString(),
          headers: headers,
          body: jsonEncode(payload),
          tag: 'payments_transfer',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
        Perf.action('pay_group_send_queued');
        return _GroupSendOutcome.queued;
      } catch (_) {
        return _GroupSendOutcome.failed;
      }
    }
  }

  Future<void> _submit() async {
    final l = L10n.of(context);
    final recipients = _parseRecipients();
    final totalCents = parseCents(_amountCtrl.text.trim());
    if (recipients.length < 2 || totalCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.payCheckInputs)),
      );
      return;
    }
    final hasPhone = recipients.any(
      (r) => r.startsWith('+') || RegExp(r'^[0-9]{6,}$').hasMatch(r),
    );
    if (hasPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'أرقام الهاتف غير مدعومة. استخدم مُعرّفات المحافظ أو @أسماء.'
                : 'Phone numbers are not supported. Use wallet IDs or @aliases.',
          ),
        ),
      );
      return;
    }
    final splits = _computeSplits(totalCents, recipients.length);
    final totalMajor = totalCents / 100.0;
    final perPreviewMajor = splits.first / 100.0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title:
              Text(l.isArabic ? 'تأكيد السداد الجماعي' : 'Confirm group pay'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic
                    ? 'إجمالي المبلغ: ${totalMajor.toStringAsFixed(2)} SYP'
                    : 'Total amount: ${totalMajor.toStringAsFixed(2)} SYP',
              ),
              const SizedBox(height: 4),
              Text(
                l.isArabic
                    ? 'عدد المستلمين: ${recipients.length}'
                    : 'Recipients: ${recipients.length}',
              ),
              const SizedBox(height: 4),
              Text(
                l.isArabic
                    ? 'حصة تقريبية لكل شخص: ${perPreviewMajor.toStringAsFixed(2)} SYP'
                    : 'Approx. per person: ${perPreviewMajor.toStringAsFixed(2)} SYP',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.shamellDialogCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.shamellDialogOk),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    setState(() {
      _submitting = true;
      _out = '';
    });

    int success = 0;
    int queued = 0;
    int failed = 0;

    for (var i = 0; i < recipients.length; i++) {
      final res = await _sendOne(recipients[i], splits[i]);
      if (res == _GroupSendOutcome.success) {
        success++;
      } else if (res == _GroupSendOutcome.queued) {
        queued++;
      } else {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
      final parts = <String>[];
      if (success > 0) {
        parts.add(
          l.isArabic ? 'عمليات ناجحة: $success' : 'Successful: $success',
        );
      }
      if (queued > 0) {
        parts.add(
          l.isArabic
              ? 'في الانتظار (بدون اتصال): $queued'
              : 'Queued (offline): $queued',
        );
      }
      if (failed > 0) {
        parts.add(
          l.isArabic ? 'فشلت: $failed' : 'Failed: $failed',
        );
      }
      _out = parts.isEmpty ? l.paySendFailed : parts.join(' · ');
    });
  }

  Future<void> _submitAsRequests() async {
    final l = L10n.of(context);
    final recipients = _parseRecipients();
    final totalCents = parseCents(_amountCtrl.text.trim());
    if (recipients.length < 2 || totalCents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.payCheckInputs)),
      );
      return;
    }
    final hasPhone = recipients.any(
      (r) => r.startsWith('+') || RegExp(r'^[0-9]{6,}$').hasMatch(r),
    );
    if (hasPhone) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l.isArabic
                ? 'أرقام الهاتف غير مدعومة. استخدم مُعرّفات المحافظ أو @أسماء.'
                : 'Phone numbers are not supported. Use wallet IDs or @aliases.',
          ),
        ),
      );
      return;
    }
    final splits = _computeSplits(totalCents, recipients.length);
    final totalMajor = totalCents / 100.0;
    final perPreviewMajor = splits.first / 100.0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            l.isArabic
                ? 'إنشاء طلبات سداد جماعي'
                : 'Create split‑bill requests',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.isArabic
                    ? 'إجمالي المبلغ: ${totalMajor.toStringAsFixed(2)} SYP'
                    : 'Total amount: ${totalMajor.toStringAsFixed(2)} SYP',
              ),
              const SizedBox(height: 4),
              Text(
                l.isArabic
                    ? 'عدد المستلمين: ${recipients.length}'
                    : 'Recipients: ${recipients.length}',
              ),
              const SizedBox(height: 4),
              Text(
                l.isArabic
                    ? 'سيتم إنشاء طلب لكل شخص بحصة تقريبية ${perPreviewMajor.toStringAsFixed(2)} SYP.'
                    : 'One request per person with ~${perPreviewMajor.toStringAsFixed(2)} SYP.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l.shamellDialogCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l.shamellDialogOk),
            ),
          ],
        );
      },
    );
    if (ok != true) return;

    setState(() {
      _submitting = true;
      _out = '';
    });

    int success = 0;
    int failed = 0;
    for (var i = 0; i < recipients.length; i++) {
      final res = await _createRequestForOne(recipients[i], splits[i]);
      if (res == _GroupSendOutcome.success) {
        success++;
      } else {
        failed++;
      }
    }

    if (!mounted) return;
    setState(() {
      _submitting = false;
      final parts = <String>[];
      if (success > 0) {
        parts.add(
          l.isArabic
              ? 'تم إنشاء طلبات: $success'
              : 'Requests created: $success',
        );
      }
      if (failed > 0) {
        parts.add(
          l.isArabic ? 'فشلت: $failed' : 'Failed: $failed',
        );
      }
      _out = parts.isEmpty
          ? (l.isArabic
              ? 'تعذر إنشاء طلبات السداد.'
              : 'Could not create split‑bill requests.')
          : parts.join(' · ');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final bal = _balanceCents;
    final totalCents = parseCents(_amountCtrl.text.trim());
    final recipients = _parseRecipients();
    final perCents =
        recipients.isNotEmpty ? totalCents ~/ recipients.length : 0;
    final perMajor = perCents / 100.0;
    final widLabel =
        _walletId.trim().isEmpty ? (l.walletNotSetShort) : _walletId.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(l.isArabic ? 'تقسيم الفاتورة' : 'Split bill'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormSection(
              title: l.isArabic ? 'ملخّص السداد الجماعي' : 'Group pay summary',
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      bal == null
                          ? (_loadingWallet ? '…' : '—')
                          : '${fmtCents(bal)} SYP',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.isArabic ? 'إجمالي المبلغ' : 'Total amount',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: .70),
                                    ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            totalCents > 0
                                ? '${(totalCents / 100.0).toStringAsFixed(2)} SYP'
                                : '—',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.isArabic ? 'عدد الأشخاص' : 'Participants',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: .70),
                                    ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            recipients.length.toString(),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.isArabic ? 'حصة تقريبية' : 'Approx. per person',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: .70),
                                    ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (perMajor > 0 && recipients.length >= 2)
                                ? '${perMajor.toStringAsFixed(2)} SYP'
                                : '—',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_out.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _out,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .80),
                      ),
                ),
              ),
            const SizedBox(height: 8),
            FormSection(
              title: l.isArabic ? 'المبلغ الإجمالي' : 'Total amount',
              children: [
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: l.payAmountLabel,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            FormSection(
              title: l.isArabic ? 'المستلمون' : 'Recipients',
              children: [
                Row(
                  children: [
                    if (_allowFriendsPicker)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.group_outlined, size: 18),
                          label: Text(
                            l.isArabic
                                ? 'اختيار من الأصدقاء'
                                : 'Choose from friends',
                          ),
                          onPressed: () async {
                            final res = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FriendsPage(widget.baseUrl),
                              ),
                            );
                            if (!mounted) return;
                            if (res is String && res.trim().isNotEmpty) {
                              setState(() {
                                _selectedFriends.add(res.trim());
                              });
                            }
                          },
                        ),
                      ),
                    if (_allowFriendsPicker) const SizedBox(width: 8),
                    IconButton(
                      tooltip: l.isArabic ? 'مسح القائمة' : 'Clear list',
                      onPressed: () {
                        setState(() {
                          _selectedFriends.clear();
                          _recipientsCtrl.clear();
                        });
                      },
                      icon: const Icon(Icons.clear_all_outlined),
                    ),
                  ],
                ),
                if (_selectedFriends.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selectedFriends.map((v) {
                      return Chip(
                        label: Text(
                          v,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onDeleted: () {
                          setState(() {
                            _selectedFriends.remove(v);
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: _recipientsCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: l.isArabic
                        ? 'معرّف المحفظة أو @اسم في كل سطر'
                        : 'Wallet ID or @alias per line',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
            FormSection(
              title: l.isArabic ? 'ملاحظة' : 'Note',
              children: [
                TextField(
                  controller: _noteCtrl,
                  decoration: InputDecoration(
                    labelText: l.payNoteLabel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: _submitting
                  ? (l.isArabic ? 'جارٍ العمل…' : 'Working…')
                  : (l.isArabic ? 'دفع الحصة الآن' : 'Pay shares now'),
              onPressed: _submitting ? null : _submit,
              expanded: true,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _submitting ? null : _submitAsRequests,
              child: Text(
                l.isArabic
                    ? 'أو إنشاء طلبات سداد للفاتورة'
                    : 'Or create split‑bill requests',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _GroupSendOutcome { success, queued, failed }

Future<String?> _getCookiePS(String baseUrl) async {
  return await getSessionCookieHeader(baseUrl);
}

Future<Map<String, String>> _hdrPS(String baseUrl, {bool json = false}) async {
  final h = <String, String>{};
  if (json) h['content-type'] = 'application/json';
  final c = await _getCookiePS(baseUrl);
  if (c != null && c.isNotEmpty) h['cookie'] = c;
  return h;
}

class PayActionButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final EdgeInsets padding;
  final double radius;
  final Color? tint;
  const PayActionButton(
      {super.key,
      this.icon,
      required this.label,
      required this.onTap,
      this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      this.radius = 10,
      this.tint});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final Color base = tint ?? theme.colorScheme.primary;
    final Color bg =
        isDark ? base.withValues(alpha: .18) : base.withValues(alpha: .12);
    final Color border = isDark
        ? Colors.white.withValues(alpha: .18)
        : Colors.black.withValues(alpha: .10);
    final Color textColor = base;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 18, color: textColor.withValues(alpha: .95)),
        if (icon != null) const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: padding,
          child: Center(child: content),
        ),
      ),
    );
  }
}
