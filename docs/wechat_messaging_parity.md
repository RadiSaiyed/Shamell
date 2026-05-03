# WeChat Messaging Parity

Updated: 2026-03-09

## Scope

- In scope: chat shell, 1:1 threads, group chats, message actions, voice playback, media and search, friend QR flows, favorites, 1:1 calls, and messaging-supporting settings.
- Excluded from this document: mini-programs and official accounts.
- Not required: group video calls with more than 2 participants.
- Notes: Moments and Channels are currently fail-closed in the repo and are not broken into messaging tasks in this pass.

## Baseline

- WeChat International version: TBD
- Devices: TBD
- Shamell baseline: `clients/shamell_flutter/lib/core/` plus V2 shell wiring in `clients/shamell_flutter/lib/v2/app/v2_shell_page.dart`.

## Surface Matrix

| Surface | Status | File pointers | Current read |
| --- | --- | --- | --- |
| Chat shell and chat list | PARTIAL | `clients/shamell_flutter/lib/v2/app/v2_shell_page.dart`, `clients/shamell_flutter/lib/v2/features/chat/presentation/chat_page.dart`, `clients/shamell_flutter/lib/core/chat/shamell_chat_page.dart` | V2 now exposes WeChat-style top-level tab placement and direct advanced chat workspace entry; pixel-level list density and motion still need final pass. |
| 1:1 messaging | PARTIAL | `clients/shamell_flutter/lib/core/chat/shamell_chat_page.dart`, `clients/shamell_flutter/lib/core/chat/chat_service.dart` | Core send, reply, forward, recall, translate, favorites, and typing indicators are present, but state polish remains open. |
| Group messaging | PARTIAL | `clients/shamell_flutter/lib/core/group_chats_page.dart`, `clients/shamell_flutter/lib/core/shamell_group_chat_info_page.dart`, `clients/shamell_flutter/lib/core/chat/chat_service.dart` | Group chat surfaces and group typing indicators exist, but device QA and detailed spacing or hierarchy review are still pending. |
| Voice messages | QA | `clients/shamell_flutter/lib/core/chat/shamell_chat_page.dart`, `clients/shamell_flutter/lib/core/group_chats_page.dart` | Proximity-based speaker or earpiece switching is implemented and now needs physical-device validation. |
| Calls | QA | `clients/shamell_flutter/lib/core/voip_call_page.dart`, `clients/shamell_flutter/lib/core/incoming_call_page.dart`, `clients/shamell_flutter/lib/core/call_signaling.dart` | 1:1 call surfaces exist, but background wake-up, reconnect, and full device reliability are not signed off. |
| Contacts and invite QR | PARTIAL | `clients/shamell_flutter/lib/v2/features/contacts/presentation/v2_contacts_page.dart`, `clients/shamell_flutter/lib/core/friends_page.dart`, `clients/shamell_flutter/lib/core/shamell_contact_info_page.dart`, `clients/shamell_flutter/lib/core/shamell_my_qr_page.dart`, `clients/shamell_flutter/lib/core/scan_page.dart` | New Friends, Group Chats, Tags, and invite QR entry points are now directly available in V2; final visual and accessibility pass remains. |
| Search and media | PARTIAL | `clients/shamell_flutter/lib/core/global_search_page.dart`, `clients/shamell_flutter/lib/core/global_media_page.dart`, `clients/shamell_flutter/lib/core/history_page.dart` | Search and media exist, but loading, empty, and error-state refinement is still open. |
| Favorites | PARTIAL | `clients/shamell_flutter/lib/core/favorites_page.dart`, `clients/shamell_flutter/lib/core/chat/shamell_chat_page.dart` | Favorites are available, but the saved-item model is still narrower than WeChat-style richer favorites support. |
| Messaging settings and devices | PARTIAL | `clients/shamell_flutter/lib/core/devices_page.dart`, `clients/shamell_flutter/lib/core/shamell_settings_hub_page.dart`, `clients/shamell_flutter/lib/core/shamell_settings_account_security_page.dart`, `clients/shamell_flutter/lib/core/shamell_settings_privacy_page.dart`, `clients/shamell_flutter/lib/core/shamell_new_message_notification_page.dart` | The support surfaces are present, but hierarchy cleanup and accessibility QA are still required. |

## Open Messaging Gaps

- Record the exact WeChat International build and device matrix used for comparison.
- Run a visual pass on list density, composer spacing, bubble sizing, icon weights, and motion timing on the V2 shell and embedded legacy chat surfaces.
- Run a state-view pass for loading, empty, and error states across chats, media, search, and contact onboarding.
- Expand favorites parity beyond the current message and location coverage.
- Validate notification, background-call, and reconnect behavior on physical devices.

## QA Focus

- iPhone and Android message send and receive reliability
- voice message playback with speaker or earpiece switching
- invite QR create, scan, and unsupported legacy QR fallback paths
- group chat creation, membership, and chat-info flows
- VoiceOver, TalkBack, large text, high contrast, and reduced motion
