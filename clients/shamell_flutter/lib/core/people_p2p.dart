import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';

import 'friend_annotations_store.dart';
import 'legacy_sensitive_pref_store.dart';
import 'l10n.dart';
import 'ui_kit.dart';
import 'payments/payments_shell.dart';
import 'chat/shamell_chat_page.dart';
import 'skeleton.dart';

class PeopleP2PPage extends StatefulWidget {
  final String baseUrl;
  final String fromWalletId;
  final String deviceId;
  const PeopleP2PPage(
    this.baseUrl,
    this.fromWalletId,
    this.deviceId, {
    super.key,
  });

  @override
  State<PeopleP2PPage> createState() => _PeopleP2PPageState();
}

class _PeopleP2PPageState extends State<PeopleP2PPage> {
  bool _loading = true;
  List<Map<String, String>> _shortlist = [];
  List<String> _rawShortlistEntries = const <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cached = await loadLegacyContactShortlistEntries(
        baseUrlOverride: widget.baseUrl,
      );
      final list = _buildShortlist(
        cached,
        aliases: const <String, String>{},
      );
      if (!mounted) return;
      setState(() {
        _rawShortlistEntries = cached;
        _shortlist = list;
        _loading = false;
      });
      unawaited(_loadAliases());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rawShortlistEntries = const <String>[];
        _shortlist = const [];
        _loading = false;
      });
    }
  }

  Future<void> _loadAliases() async {
    try {
      final aliases = await loadFriendAliases(baseUrlOverride: widget.baseUrl);
      if (!mounted) return;
      setState(() {
        _shortlist = _buildShortlist(_rawShortlistEntries, aliases: aliases);
      });
    } catch (_) {}
  }

  List<Map<String, String>> _buildShortlist(
    List<String> cached, {
    required Map<String, String> aliases,
  }) {
    final list = <Map<String, String>>[];
    for (final s in cached) {
      try {
        final m = jsonDecode(s) as Map<String, dynamic>;
        final phone = (m['phone'] ?? '').toString();
        var name = (m['name'] ?? '').toString();
        final alias = aliases[phone];
        if (alias != null && alias.isNotEmpty) {
          name = alias;
        }
        list.add({'name': name, 'phone': phone});
      } catch (_) {
        if (s.trim().isNotEmpty) {
          list.add({'name': '', 'phone': s.trim()});
        }
      }
    }
    return list;
  }

  void _openP2P(String phone) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentsPage(
          widget.baseUrl,
          widget.fromWalletId,
          widget.deviceId,
          initialRecipient: phone,
        ),
      ),
    );
  }

  void _openChats() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShamellChatPage(baseUrl: widget.baseUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final body = _loading
        ? ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: 6,
            itemBuilder: (_, __) => const SkeletonListTile(),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FormSection(
                title: l.isArabic ? 'التحويل إلى الأشخاص' : 'Send to people',
                subtitle: l.isArabic
                    ? 'اختر جهة اتصال لإرسال أموال بسرعة'
                    : 'Pick a person to send money quickly',
                children: [
                  if (_shortlist.isEmpty)
                    Text(
                      l.isArabic
                          ? 'لا توجد جهات اتصال محفوظة بعد. استخدم قسم الإرسال في المدفوعات لإضافة جهات اتصال.'
                          : 'No saved contacts yet. Use the Send tab in Payments to add contacts.',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: .70),
                      ),
                    ),
                  if (_shortlist.isNotEmpty)
                    ..._shortlist.map((m) {
                      final name = m['name'] ?? '';
                      final phone = m['phone'] ?? '';
                      final title = name.isNotEmpty
                          ? name
                          : (phone.isNotEmpty ? phone : l.unknownLabel);
                      final subtitle =
                          name.isNotEmpty && phone.isNotEmpty ? phone : '';
                      return StandardListTile(
                        leading: CircleAvatar(
                          child: Text(
                            title.isNotEmpty
                                ? title.characters.first.toUpperCase()
                                : '?',
                          ),
                        ),
                        title: Text(title),
                        subtitle: subtitle.isEmpty ? null : Text(subtitle),
                        trailing: IconButton(
                          icon: const Icon(Icons.send_outlined),
                          onPressed:
                              phone.isEmpty ? null : () => _openP2P(phone),
                        ),
                        onTap: phone.isEmpty ? null : () => _openP2P(phone),
                      );
                    }),
                ],
              ),
              FormSection(
                title: l.isArabic ? 'المحادثات والجهات' : 'Chats & contacts',
                subtitle: l.isArabic
                    ? 'افتح SyrChat للدردشة والاتصال الآمن'
                    : 'Open SyrChat for secure chat and contacts',
                children: [
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(l.homeChat),
                    onTap: _openChats,
                  ),
                ],
              ),
            ],
          );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l.isArabic ? 'الأشخاص والمدفوعات' : 'People & P2P',
        ),
        backgroundColor: Colors.transparent,
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(color: Colors.white),
          SafeArea(child: body),
        ],
      ),
    );
  }
}
