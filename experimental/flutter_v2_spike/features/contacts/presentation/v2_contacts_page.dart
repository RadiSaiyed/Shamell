import 'package:flutter/material.dart';

import '../../../../core/chat/chat_models.dart' as legacy_chat;
import '../../../../core/chat/chat_service.dart';
import '../../../design/components/v2_status_panel.dart';
import '../../../design/components/v2_surface_card.dart';
import '../../../design/tokens.dart';

typedef V2ContactsBaseUrlResolver = Future<String> Function();

class V2ContactsPage extends StatefulWidget {
  final V2ContactsBaseUrlResolver baseUrlResolver;
  final ValueChanged<String> onOpenChatWithPeer;
  final VoidCallback? onOpenNewFriends;
  final VoidCallback? onOpenFriendsManager;
  final VoidCallback? onOpenFriendTags;
  final VoidCallback? onOpenGroupChats;
  final ValueChanged<legacy_chat.ChatContact>? onOpenContactDetails;

  const V2ContactsPage({
    super.key,
    required this.baseUrlResolver,
    required this.onOpenChatWithPeer,
    this.onOpenNewFriends,
    this.onOpenFriendsManager,
    this.onOpenFriendTags,
    this.onOpenGroupChats,
    this.onOpenContactDetails,
  });

  @override
  State<V2ContactsPage> createState() => _V2ContactsPageState();
}

class _V2ContactsPageState extends State<V2ContactsPage> {
  bool _loading = false;
  String _error = '';
  List<legacy_chat.ChatContact> _contacts = const <legacy_chat.ChatContact>[];

  String _initialForTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final baseUrl = await widget.baseUrlResolver();
      final all = await ChatLocalStore().loadContacts(
        baseUrlOverride: baseUrl,
      );
      final cleaned = all
          .where((c) =>
              c.id.trim().isNotEmpty &&
              !c.hidden &&
              !c.archived &&
              !c.id.startsWith('__official_'))
          .toList()
        ..sort((a, b) {
          final left = (a.name ?? '').trim().toLowerCase();
          final right = (b.name ?? '').trim().toLowerCase();
          if (left.isNotEmpty && right.isNotEmpty) {
            return left.compareTo(right);
          }
          return a.id.toLowerCase().compareTo(b.id.toLowerCase());
        });
      if (!mounted) return;
      setState(() {
        _contacts = cleaned;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '').trim();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _openChat(legacy_chat.ChatContact contact) async {
    final peerId = contact.id.trim();
    if (peerId.isEmpty) return;
    try {
      final baseUrl = await widget.baseUrlResolver();
      await ChatLocalStore().setActivePeer(
        peerId,
        baseUrlOverride: baseUrl,
      );
    } catch (_) {}
    widget.onOpenChatWithPeer(peerId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: V2Tokens.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(V2Tokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Contacts',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Refresh contacts',
                    onPressed: _loading ? null : _loadContacts,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              if (widget.onOpenNewFriends != null ||
                  widget.onOpenFriendsManager != null ||
                  widget.onOpenFriendTags != null ||
                  widget.onOpenGroupChats != null) ...[
                const SizedBox(height: V2Tokens.spacingSm),
                V2SurfaceCard(
                  child: Column(
                    children: [
                      if (widget.onOpenNewFriends != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.person_add_alt_1_outlined),
                          title: const Text('New friends'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: widget.onOpenNewFriends,
                        ),
                      if (widget.onOpenNewFriends != null &&
                          (widget.onOpenFriendsManager != null ||
                              widget.onOpenGroupChats != null ||
                              widget.onOpenFriendTags != null))
                        const Divider(height: 1),
                      if (widget.onOpenFriendsManager != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.people_outline),
                          title: const Text('Friends manager'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: widget.onOpenFriendsManager,
                        ),
                      if (widget.onOpenFriendsManager != null &&
                          (widget.onOpenGroupChats != null ||
                              widget.onOpenFriendTags != null))
                        const Divider(height: 1),
                      if (widget.onOpenGroupChats != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.group_outlined),
                          title: const Text('Group chats'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: widget.onOpenGroupChats,
                        ),
                      if (widget.onOpenGroupChats != null &&
                          widget.onOpenFriendTags != null)
                        const Divider(height: 1),
                      if (widget.onOpenFriendTags != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.sell_outlined),
                          title: const Text('Tags'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: widget.onOpenFriendTags,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: V2Tokens.spacingSm),
              if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Tokens.spacingSm),
                  child: V2StatusPanel(
                    icon: Icons.error_outline,
                    title: 'Contacts unavailable',
                    message: _error,
                    color: V2Tokens.critical,
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _contacts.isEmpty
                        ? const Center(
                            child: V2SurfaceCard(
                              child: V2StatusPanel(
                                icon: Icons.person_add_alt_1_outlined,
                                title: 'No contacts yet',
                                message:
                                    'Add or select contacts in the main Shamell chat flow first.',
                              ),
                            ),
                          )
                        : V2SurfaceCard(
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: _contacts.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, index) {
                                final contact = _contacts[index];
                                final title =
                                    (contact.name ?? '').trim().isEmpty
                                        ? contact.id
                                        : contact.name!.trim();
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        V2Tokens.brand.withValues(alpha: 0.14),
                                    child: Text(
                                      _initialForTitle(title),
                                      style: const TextStyle(
                                        color: V2Tokens.brand,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    contact.id,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _openChat(contact),
                                  onLongPress:
                                      widget.onOpenContactDetails == null
                                          ? null
                                          : () => widget.onOpenContactDetails!(
                                                contact,
                                              ),
                                );
                              },
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
