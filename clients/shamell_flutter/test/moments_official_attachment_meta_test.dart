import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/moments_official_attachment_meta.dart';

void main() {
  group('momentOfficialAttachmentMeta', () {
    test('builds WeChat-style official attachment chrome', () {
      final chrome = momentOfficialAttachmentChromeMeta();

      expect(chrome.darkSurfaceAlpha, .42);
      expect(chrome.darkBorderAlpha, .50);
      expect(chrome.lightBorderAlpha, .86);
      expect(chrome.borderWidth, .5);
      expect(chrome.splashAlpha, .08);
      expect(chrome.highlightAlpha, .04);
      expect(chrome.horizontalPadding, 8);
      expect(chrome.verticalPadding, 8);
      expect(chrome.fallbackIconFillDarkAlpha, .30);
      expect(chrome.fallbackIconFillLightAlpha, .12);
      expect(chrome.iconTextGap, 10);
      expect(chrome.titleFontWeight, FontWeight.w600);
      expect(chrome.subtitleTopGap, 2);
      expect(chrome.mutedTextAlpha, .58);
      expect(chrome.actionGap, 8);
      expect(chrome.actionWrapSpacing, 2);
      expect(chrome.actionWrapRunSpacing, 2);
    });

    test('builds compact attachment icon action chrome', () {
      final chrome = momentAttachmentIconActionChromeMeta();

      expect(chrome.defaultIconAlpha, .64);
      expect(chrome.visualDensity, VisualDensity.compact);
      expect(chrome.padding, EdgeInsets.zero);
      expect(chrome.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
    });

    test('builds official update meta with item title', () {
      final meta = momentOfficialAttachmentMeta(
        accountName: 'City Transit',
        accountKind: 'service',
        itemId: 'notice_1',
        itemTitle: 'Delay on line 4',
        linkedMiniProgramId: 'bus',
        isArabic: false,
      );

      expect(meta.title, 'Delay on line 4');
      expect(meta.subtitle, 'City Transit · Service account');
      expect(meta.serviceActionLabel, 'Open bus');
      expect(meta.channelsActionLabel, 'Channels');
      expect(meta.followActionLabel, 'Follow');
      expect(meta.chatActionLabel, 'Chat');
      expect(meta.isServiceAccount, isTrue);
      expect(meta.serviceActionIcon, Icons.directions_bus_outlined);
      expect(meta.channelsActionIcon, Icons.article_outlined);
      expect(meta.followActionIcon, Icons.person_add_alt_1_outlined);
      expect(meta.chatActionIcon, Icons.chat_bubble_outline);
      expect(meta.fallbackIcon, Icons.verified_outlined);
      expect(meta.chevronIcon, Icons.chevron_right);
      expect(meta.avatarRadius, 17);
      expect(meta.fallbackIconBoxSize, 34);
      expect(meta.fallbackIconSize, 18);
      expect(meta.fallbackIconRadius, 7);
      expect(meta.titleFontSize, 13);
      expect(meta.subtitleFontSize, 11);
      expect(meta.actionsMaxWidth, 112);
      expect(meta.actionButtonSize, 30);
      expect(meta.actionIconSize, 17);
      expect(meta.chevronSize, 18);
    });

    test('falls back for account cards without item', () {
      final meta = momentOfficialAttachmentMeta(
        accountName: 'Creator Daily',
        accountKind: 'subscription',
        itemId: null,
        itemTitle: null,
        linkedMiniProgramId: null,
        isArabic: false,
      );

      expect(meta.title, 'Official account');
      expect(meta.subtitle, 'Creator Daily · Subscription account');
      expect(meta.serviceActionLabel, 'Open service');
      expect(meta.serviceActionIcon, Icons.apps_outlined);
      expect(meta.isServiceAccount, isFalse);
    });

    test('localizes official attachment action labels', () {
      final meta = momentOfficialAttachmentMeta(
        accountName: 'SyrChat Pay',
        accountKind: 'service',
        itemId: 'wallet_1',
        itemTitle: null,
        linkedMiniProgramId: 'wallet',
        isArabic: true,
      );

      expect(meta.serviceActionLabel, 'فتح المحفظة');
      expect(meta.channelsActionLabel, 'القناة');
      expect(meta.followActionLabel, 'متابعة');
      expect(meta.chatActionLabel, 'دردشة');
      expect(meta.serviceActionIcon, Icons.account_balance_wallet_outlined);
    });

    test('extracts item title from Moment text safely', () {
      expect(
        officialAttachmentItemTitleFromMomentText(
          'New menu today\nshamell://official/shop/item_1',
        ),
        'New menu today',
      );
      expect(
        officialAttachmentItemTitleFromMomentText(
          'From Coffee Shop\nshamell://official/shop/item_1',
        ),
        isNull,
      );
      expect(
        officialAttachmentItemTitleFromMomentText(
          'shamell://official/shop/item_1',
        ),
        isNull,
      );
    });
  });
}
