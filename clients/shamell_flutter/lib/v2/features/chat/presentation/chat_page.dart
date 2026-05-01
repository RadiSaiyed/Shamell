import 'package:flutter/material.dart';

import '../../../design/components/v2_primary_button.dart';
import '../../../design/components/v2_status_panel.dart';
import '../../../design/components/v2_surface_card.dart';
import '../../../design/tokens.dart';
import 'chat_controller.dart';

class ChatPage extends StatefulWidget {
  final ChatController controller;
  final String currentUser;
  final VoidCallback? onOpenFullChatWorkspace;

  const ChatPage({
    super.key,
    required this.controller,
    required this.currentUser,
    this.onOpenFullChatWorkspace,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_listener);
    widget.controller.load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_listener);
    _textController.dispose();
    super.dispose();
  }

  void _listener() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _send() async {
    final rawText = _textController.text;
    final trimmedText = rawText.trim();
    if (trimmedText != rawText) {
      _textController.value = _textController.value.copyWith(
        text: trimmedText,
        selection: TextSelection.collapsed(offset: trimmedText.length),
        composing: TextRange.empty,
      );
    }
    if (trimmedText.isEmpty) {
      return;
    }
    final didSend = await widget.controller.send(
      text: trimmedText,
      sender: widget.currentUser,
    );
    if (!mounted || !didSend) {
      return;
    }
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Scaffold(
      backgroundColor: V2Tokens.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(V2Tokens.spacingLg),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'Chat',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const Spacer(),
                  if (widget.onOpenFullChatWorkspace != null)
                    TextButton.icon(
                      onPressed: widget.onOpenFullChatWorkspace,
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('Open full chat'),
                    ),
                ],
              ),
              const SizedBox(height: V2Tokens.spacingSm),
              Expanded(
                child: c.loading
                    ? const Center(child: CircularProgressIndicator())
                    : c.messages.isEmpty
                        ? Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: const V2StatusPanel(
                                icon: Icons.inbox_outlined,
                                title: 'No messages yet',
                                message:
                                    'Start the conversation by sending your first message.',
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: c.messages.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: V2Tokens.spacingSm),
                            itemBuilder: (_, index) {
                              final m = c.messages[index];
                              return V2SurfaceCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.sender,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(m.text),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              if (c.error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: V2Tokens.spacingSm),
                  child: V2StatusPanel(
                    icon: Icons.error_outline,
                    title: 'Chat issue',
                    message: c.error,
                    color: V2Tokens.critical,
                  ),
                ),
              if (c.needsPeerSelection)
                const Padding(
                  padding: EdgeInsets.only(bottom: V2Tokens.spacingSm),
                  child: V2StatusPanel(
                    icon: Icons.info_outline,
                    title: 'No chat contact selected',
                    message:
                        'Open a contact in the main chat flow first, then return here.',
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      enabled: !c.needsPeerSelection,
                      decoration: const InputDecoration(
                        hintText: 'Write a message',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: V2Tokens.spacingSm),
                  V2PrimaryButton(
                    label: 'Send',
                    busy: c.sending,
                    onPressed: c.needsPeerSelection ? null : _send,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
