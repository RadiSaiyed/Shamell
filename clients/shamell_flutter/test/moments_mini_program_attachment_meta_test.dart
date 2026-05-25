import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shamell_flutter/core/mini_app_descriptor.dart';
import 'package:shamell_flutter/core/moments_mini_program_attachment_meta.dart';

void main() {
  group('momentMiniProgramContextMeta', () {
    test('builds WeChat-style context bar chrome', () {
      final chrome = momentMiniProgramContextChromeMeta();

      expect(chrome.darkBorderAlpha, .46);
      expect(chrome.lightBorderAlpha, .70);
      expect(chrome.borderWidth, .6);
      expect(chrome.horizontalPadding, 12);
      expect(chrome.verticalPadding, 9);
      expect(chrome.iconFillDarkAlpha, .22);
      expect(chrome.iconFillLightAlpha, .12);
      expect(chrome.iconTitleGap, 10);
      expect(chrome.titleFontWeight, FontWeight.w700);
      expect(chrome.categoryTopGap, 2);
      expect(chrome.categoryAlpha, .58);
      expect(chrome.actionGap, 8);
      expect(chrome.actionMinWidth, 0);
      expect(chrome.actionHeight, 32);
      expect(chrome.actionHorizontalPadding, 8);
      expect(chrome.actionVisualDensity, VisualDensity.compact);
      expect(chrome.actionIconGap, 2);
      expect(chrome.actionIconSize, 15);
    });

    test('uses descriptor for Moments context title and category', () {
      final meta = momentMiniProgramContextMeta(
        id: 'payments',
        descriptor: const MiniAppDescriptor(
          id: 'payments',
          icon: Icons.account_balance_wallet_outlined,
          titleEn: 'SyrChat Pay',
          titleAr: 'سرتشات باي',
          categoryEn: 'Wallet & commerce',
          categoryAr: 'المحفظة والتجارة',
        ),
        isArabic: false,
      );

      expect(meta?.id, 'payments');
      expect(meta?.title, 'SyrChat Pay');
      expect(meta?.category, 'Wallet & commerce');
      expect(meta?.momentsTitle, 'SyrChat Pay Moments');
      expect(meta?.allLabel, 'All');
      expect(meta?.icon, Icons.account_balance_wallet_outlined);
      expect(meta?.allIcon, Icons.chevron_right);
      expect(meta?.allPerfKey, 'moments_mini_program_context_all');
      expect(meta?.iconBoxSize, 34);
      expect(meta?.iconSize, 20);
      expect(meta?.iconRadius, 7);
      expect(meta?.titleFontSize, 13);
      expect(meta?.categoryFontSize, 11);
    });

    test('humanizes unknown mini-program context ids', () {
      final meta = momentMiniProgramContextMeta(
        id: 'merchant_loyalty',
        descriptor: null,
        isArabic: false,
      );

      expect(meta?.title, 'Merchant Loyalty');
      expect(meta?.category, 'Mini Program');
      expect(meta?.momentsTitle, 'Merchant Loyalty Moments');
      expect(meta?.icon, Icons.widgets_outlined);
    });

    test('omits context when no mini-program id is active', () {
      final meta = momentMiniProgramContextMeta(
        id: ' ',
        descriptor: null,
        isArabic: false,
      );

      expect(meta, isNull);
    });
  });

  group('momentMiniProgramAttachmentMeta', () {
    test('resolves the shared WeChat-style mini-program accent palette', () {
      expect(
          momentMiniProgramAccentColor(' payments '), const Color(0xFF07C160));
      expect(momentMiniProgramAccentColor('MERCHANT'), const Color(0xFF07C160));
      expect(
        momentMiniProgramAccentColor('green_paket'),
        const Color(0xFF16A34A),
      );
      expect(momentMiniProgramAccentColor('cards'), const Color(0xFFB7791F));
      expect(momentMiniProgramAccentColor('moments'), const Color(0xFF2563EB));
      expect(
        momentMiniProgramAccentColor('official_accounts'),
        const Color(0xFF0EA5E9),
      );
      expect(momentMiniProgramAccentColor('channels'), const Color(0xFFEF4444));
      expect(momentMiniProgramAccentColor('taxi'), const Color(0xFF0EA5E9));
      expect(momentMiniProgramAccentColor('unknown'), const Color(0xFF64748B));
    });

    test('builds WeChat-style attachment card chrome', () {
      final chrome = momentMiniProgramAttachmentChromeMeta();

      expect(chrome.darkSurfaceAlpha, .42);
      expect(chrome.darkBorderAlpha, .50);
      expect(chrome.lightBorderAlpha, .86);
      expect(chrome.borderWidth, .5);
      expect(chrome.splashAlpha, .08);
      expect(chrome.highlightAlpha, .04);
      expect(chrome.horizontalPadding, 8);
      expect(chrome.verticalPadding, 8);
      expect(chrome.iconFillDarkAlpha, .22);
      expect(chrome.iconFillLightAlpha, .12);
      expect(chrome.iconTextGap, 10);
      expect(chrome.titleFontWeight, FontWeight.w700);
      expect(chrome.subtitleTopGap, 2);
      expect(chrome.footerTopGap, 3);
      expect(chrome.mutedTextAlpha, .58);
      expect(chrome.actionGap, 8);
      expect(chrome.chevronSize, 18);
    });

    test('uses descriptor title and category without resource context', () {
      final meta = momentMiniProgramAttachmentMeta(
        id: 'payments',
        resourceId: '',
        descriptor: const MiniAppDescriptor(
          id: 'payments',
          icon: Icons.account_balance_wallet_outlined,
          titleEn: 'SyrChat Pay',
          titleAr: 'سرتشات باي',
          categoryEn: 'Wallet & commerce',
          categoryAr: 'المحفظة والتجارة',
        ),
        isArabic: false,
      );

      expect(meta.title, 'SyrChat Pay');
      expect(meta.category, 'Wallet & commerce');
      expect(meta.subtitle, 'Wallet & commerce');
      expect(meta.footer, 'SyrChat Mini Program');
      expect(meta.icon, Icons.account_balance_wallet_outlined);
      expect(meta.openIcon, Icons.open_in_new);
      expect(meta.openTooltip, 'Open');
      expect(meta.chevronIcon, Icons.chevron_right);
      expect(meta.iconBoxSize, 36);
      expect(meta.iconSize, 21);
      expect(meta.iconRadius, 7);
      expect(meta.titleFontSize, 13);
      expect(meta.subtitleFontSize, 11);
      expect(meta.footerFontSize, 10);
    });

    test('keeps Green Paket resource context visible', () {
      final meta = momentMiniProgramAttachmentMeta(
        id: 'green_paket',
        resourceId: 'packet_123',
        descriptor: null,
        isArabic: false,
      );

      expect(meta.title, 'Green Paket');
      expect(meta.category, 'Mini Program');
      expect(meta.subtitle, 'Open or claim inside SyrChat');
    });

    test('humanizes unknown ids', () {
      final meta = momentMiniProgramAttachmentMeta(
        id: 'merchant_loyalty',
        resourceId: 'offer_1',
        descriptor: null,
        isArabic: false,
      );

      expect(meta.title, 'Merchant Loyalty');
      expect(meta.subtitle, 'Open linked item inside SyrChat');
      expect(meta.icon, Icons.widgets_outlined);
    });

    test('localizes attachment action labels', () {
      final meta = momentMiniProgramAttachmentMeta(
        id: 'payments',
        resourceId: '',
        descriptor: null,
        isArabic: true,
      );

      expect(meta.openTooltip, 'فتح');
      expect(meta.footer, 'برنامج SyrChat مصغّر');
    });
  });
}
