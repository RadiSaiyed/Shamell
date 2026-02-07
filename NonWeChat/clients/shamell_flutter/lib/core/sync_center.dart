import 'dart:convert';
import 'package:flutter/material.dart';
import 'offline_queue.dart';
import 'l10n.dart';

class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({super.key});
  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  bool _flushing = false;
  int _lastDelivered = 0;
  DateTime? _lastTs;
  final Map<String, int> _tagProgDone = {};
  final Map<String, int> _tagProgTotal = {};

  Map<String, List<OfflineTask>> _grouped() {
    final m = <String, List<OfflineTask>>{};
    for (final t in OfflineQueue.pending()) {
      (m[t.tag] ??= []).add(t);
    }
    return m;
  }

  Future<void> _flush() async {
    setState(() => _flushing = true);
    final n = await OfflineQueue.flush();
    _lastDelivered = n;
    _lastTs = DateTime.now();
    if (mounted) {
      setState(() => _flushing = false);
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Synced: $n actions')));
    }
  }

  Future<void> _syncTag(String tag) async {
    final items = OfflineQueue.pending(tag: tag);
    setState(() {
      _tagProgDone[tag] = 0;
      _tagProgTotal[tag] = items.length;
    });
    int done = 0;
    for (final t in items) {
      final ok = await OfflineQueue.flushOne(t.id);
      done += ok ? 1 : 0;
      setState(() => _tagProgDone[tag] = done);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Tag "$tag": $done/${items.length} synchronisiert')));
    }
    setState(() {
      _tagProgDone.remove(tag);
      _tagProgTotal.remove(tag);
    });
  }

  String _summ(OfflineTask t) {
    try {
      final j = jsonDecode(t.body);
      if (j is Map) {
        if (j.containsKey('amount_cents'))
          return 'amount: ${j['amount_cents']}';
        if (j.containsKey('token'))
          return 'token: ${(j['token'] ?? '').toString().substring(0, 6)}…';
      }
    } catch (_) {}
    return t.body.length > 64 ? t.body.substring(0, 64) + '…' : t.body;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final g = _grouped();
    final tags = g.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text(l.isArabic ? 'مركز المزامنة' : 'Sync Center')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                  child: Text(
                      '${l.isArabic ? 'المعلّقة' : 'Pending'}: ${OfflineQueue.pending().length}',
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              if (_lastTs != null)
                Text(
                    '${l.isArabic ? 'آخر' : 'Last'}: ${_lastDelivered} @ ${_lastTs!.toLocal().toIso8601String().substring(11, 19)}',
                    style: const TextStyle(color: Colors.white70)),
              const SizedBox(width: 12),
              FilledButton(
                  onPressed: _flushing ? null : _flush,
                  child: _flushing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(l.isArabic ? 'مزامنة الآن' : 'Sync now')),
            ])),
        const Divider(height: 1),
        Expanded(
            child: ListView.builder(
                itemCount: tags.length,
                itemBuilder: (_, i) {
                  final tag = tags[i];
                  final items = g[tag]!
                    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
                  final now = DateTime.now().millisecondsSinceEpoch;
                  final prog = _tagProgDone[tag];
                  final total = _tagProgTotal[tag];
                  final head = Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(children: [
                              Text('$tag (${items.length})',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const Spacer(),
                              TextButton(
                                  onPressed: (prog != null)
                                      ? null
                                      : () async {
                                          await _syncTag(tag);
                                        },
                                  child: Text(
                                      l.isArabic ? 'مزامنة الكل' : 'Sync all')),
                              const SizedBox(width: 6),
                              TextButton(
                                  onPressed: (prog != null)
                                      ? null
                                      : () async {
                                          final n =
                                              await OfflineQueue.removeTag(tag);
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(SnackBar(
                                                    content: Text(l.isArabic
                                                        ? 'تم حذف الوسم "$tag": $n'
                                                        : 'Tag "$tag" removed: $n')));
                                            setState(() {});
                                          }
                                        },
                                  child: Text(
                                      l.isArabic ? 'حذف الكل' : 'Remove all'))
                            ]),
                            if (prog != null && total != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: LinearProgressIndicator(
                                      value: total == 0
                                          ? 0
                                          : (prog / total)
                                              .clamp(0, 1)
                                              .toDouble())),
                          ]));
                  return ExpansionTile(
                      title: head,
                      children: items.map((t) {
                        final remainMs = (t.nextAt - now).clamp(0, 99999999);
                        final remain = (remainMs / 1000).ceil();
                        final hint = remain > 0
                            ? (l.isArabic
                                ? 'المحاولة التالية خلال ~${remain}ث'
                                : 'next retry in ~${remain}s')
                            : (l.isArabic ? 'جاهز' : 'ready');
                        return ListTile(
                          title: Text(_summ(t)),
                          subtitle: Text(
                              '$hint • retries: ${t.retries} • ${DateTime.fromMillisecondsSinceEpoch(t.nextAt).toLocal().toIso8601String().substring(11, 19)} • ${t.url}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          trailing: Wrap(spacing: 6, children: [
                            IconButton(
                                tooltip:
                                    l.isArabic ? 'إعادة المحاولة' : 'Retry',
                                icon: const Icon(Icons.refresh),
                                onPressed: () async {
                                  final ok = await OfflineQueue.flushOne(t.id);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(ok
                                                ? (l.isArabic
                                                    ? 'تم بنجاح'
                                                    : 'Success')
                                                : (l.isArabic
                                                    ? 'خطأ، حاول لاحقًا'
                                                    : 'Error, try later'))));
                                    setState(() {});
                                  }
                                }),
                            IconButton(
                                tooltip: l.isArabic ? 'حذف' : 'Remove',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  final ok = await OfflineQueue.remove(t.id);
                                  if (ok && context.mounted) {
                                    setState(() {});
                                  }
                                }),
                          ]),
                        );
                      }).toList());
                })),
      ]),
    );
  }
}
