import 'package:flutter/material.dart';

import 'l10n.dart';
import 'ui_kit.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final title = l.isArabic ? 'ابدأ مع Shamell' : 'Shamell – quick guide';
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
                      ? '١) افتح التطبيق وحدّد \"مستخدم\" في الأعلى.\n٢) أدخل رقم هاتفك واضغط على \"طلب رمز\".\n٣) أدخل رمز الـ SMS وستتم عملية تسجيل الدخول.'
                      : '1) At the top, select the role \"User\".\n2) Enter your phone number and tap \"Request code\".\n3) Type the SMS code – then you are signed in.',
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
              title: l.isArabic ? 'التنقل والرحلات' : '3. Journeys & mobility',
              children: [
                Text(
                  l.isArabic
                      ? '١) افتح صفحة \"Journey\" من الشاشة الرئيسية.\n٢) راجع ملخص التنقل وسجل رحلات الباص.\n٣) استخدمها لمتابعة حجوزاتك وتنقلاتك.'
                      : '1) On the home screen open \"Journey\".\n2) Review your mobility overview and bus trip history.\n3) Use it to track bookings and trips.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSection(
              title: l.isArabic ? 'حجز الباص' : '4. Bus booking',
              children: [
                Text(
                  l.isArabic
                      ? '١) من الشاشة الرئيسية اختر \"Bus\" للحجوزات بين المدن.\n٢) اختر مدينة الانطلاق والوصول والتاريخ ثم احجز وادفع من محفظتك.\n٣) راجع حجوزاتك من \"Journey\" أو \"My trips\".'
                      : '1) On the home screen open \"Bus\" for intercity bookings.\n2) Select origin, destination and date, then book and pay from your wallet.\n3) Review bookings in \"Journey\" or \"My trips\".',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSection(
              title:
                  l.isArabic ? 'الحسابات الرسمية والخدمات' : '5. Official accounts',
              children: [
                Text(
                  l.isArabic
                      ? '١) افتح \"Contacts\" ثم \"Service accounts\".\n٢) تابع \"Shamell Bus\" للحصول على التحديثات.\n٣) استخدم \"Shamell Pay\" للتحويلات ورؤية المعاملات.'
                      : '1) Open \"Contacts\" then \"Service accounts\".\n2) Follow \"Shamell Bus\" for updates.\n3) Use \"Shamell Pay\" for transfers and transaction history.',
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
                      ? 'كمستخدم نهائي ترى فقط الأجزاء المخصصة لك. المشغلون والمديرون لديهم واجهات منفصلة (مثل مشغل الباص).'
                      : 'As an end user you only see the parts that are enabled for you. Operators and admins have their own consoles (for example bus operator).',
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
