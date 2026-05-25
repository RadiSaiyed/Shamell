import 'package:flutter/material.dart';

import 'l10n.dart';
import 'ui_kit.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final title = l.isArabic ? 'ابدأ مع SyrChat' : 'SyrChat – quick guide';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormSection(
              title: l.isArabic
                  ? 'الخطوات الأساسية'
                  : '1. Getting started & sign‑in',
              children: [
                Text(
                  l.isArabic
                      ? '١) افتح SyrChat وحدّد \"مستخدم\" في الأعلى.\n٢) اضغط \"تسجيل الدخول\" ثم أكّد عبر Face ID / Touch ID.\n٣) إذا كان هذا الجهاز غير مُسجّل بعد، اربطه عبر تسجيل دخول الجهاز (QR) أو اطلب من المشرف تفعيل الوصول.'
                      : '1) Open SyrChat and select the role \"User\".\n2) Tap \"Sign in\" and approve Face ID / Touch ID.\n3) If this device is not enrolled yet, pair it via QR device login or ask an admin to provision access.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSection(
              title: l.isArabic ? 'محفظتك والمدفوعات' : '2. Wallet & payments',
              children: [
                Text(
                  l.isArabic
                      ? '١) من الشاشة الرئيسية اختر \"Payments\".\n٢) سترى رصيد محفظتك بالعملة المحلية.\n٣) استخدم \"Scan & Pay\" لمسح رمز QR، أو أرسل مبلغاً صغيراً إلى صديق.'
                      : '1) On the home screen open the module \"Payments\".\n2) At the top you see your wallet balance in local currency.\n3) Use \"Scan & Pay\" for QR codes or send a small amount to a known number.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSection(
              title:
                  l.isArabic ? 'الدردشة وجهات الاتصال' : '3. Chats & contacts',
              children: [
                Text(
                  l.isArabic
                      ? '١) افتح \"Chats\" لبدء محادثة مع جهات اتصالك.\n٢) من تبويب \"Contacts\" أضف جهة جديدة عبر رمز دعوة أو QR.\n٣) أنشئ مجموعة عند الحاجة لإدارة المحادثات الجماعية.'
                      : '1) Open \"Chats\" to start conversations with your contacts.\n2) In \"Contacts\", add a new contact via an invite token or QR.\n3) Create a group when you need shared conversations.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSection(
              title:
                  l.isArabic ? 'الإعدادات والخصوصية' : '4. Settings & privacy',
              children: [
                Text(
                  l.isArabic
                      ? '١) من تبويب \"Settings\" اضبط الإشعارات والخصوصية.\n٢) فعّل قفل التطبيق والخيارات الأمنية المناسبة.\n٣) راجع إدارة التخزين عند الحاجة.'
                      : '1) In \"Settings\", configure notifications and privacy.\n2) Enable app lock and security options as needed.\n3) Review storage management when required.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSection(
              title: l.isArabic ? 'الخدمات داخل التطبيق' : '5. In-app services',
              children: [
                Text(
                  l.isArabic
                      ? '١) استخدم \"Payments\" للتحويلات والمدفوعات.\n٢) راجع السجل من داخل المحفظة.\n٣) الخدمات المتاحة قد تختلف حسب إعدادات الخادم وحسابك.'
                      : '1) Use \"Payments\" for transfers and payments.\n2) Review history from inside your wallet.\n3) Available services may vary by server and account settings.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSection(
              title: l.isArabic ? 'نصيحة' : 'Note for operator & admin',
              children: [
                Text(
                  l.isArabic
                      ? 'كمستخدم نهائي ترى فقط الأجزاء المخصصة لك. للمشغلين والمديرين واجهات مستقلة لإدارة النظام.'
                      : 'As an end user, you only see enabled areas. Operators and admins use separate system management consoles.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
