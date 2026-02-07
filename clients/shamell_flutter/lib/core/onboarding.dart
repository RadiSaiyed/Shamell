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
              title: l.isArabic ? 'أول رحلة تاكسي' : '3. First taxi ride',
              children: [
                Text(
                  l.isArabic
                      ? '١) افتح شاشة الراكب في التاكسي.\n٢) اختر نقطة الانطلاق والوصول.\n٣) شاهد السعر التقديري ثم اطلب الرحلة وادفع من المحفظة.'
                      : '1) On the home screen open \"Taxi Rider\".\n2) Choose pickup and dropoff on the map or via coordinates.\n3) Check the estimated fare, request the ride and pay from your wallet.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSection(
              title: l.isArabic ? 'الباصات والطعام' : '4. Buses & food',
              children: [
                Text(
                  l.isArabic
                      ? '١) من الشاشة الرئيسية اختر Bus للحجوزات بين المدن.\n٢) اختر مدينة الانطلاق والوصول والتاريخ ثم احجز وادفع.\n٣) لطلب الطعام افتح \"Food\"، اختر مطعماً، ثم أضف الطلب وادفع من المحفظة.'
                      : '1) For intercity buses open \"Bus\" and select origin, destination and date.\n2) Pick a connection and book it directly with your wallet.\n3) For food orders open \"Food\", choose a restaurant and pay the order from your balance.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FormSection(
              title: l.isArabic ? 'الفنادق والإقامات' : '5. Hotels & stays',
              children: [
                Text(
                  l.isArabic
                      ? '١) افتح \"Hotels & Stays\" للبحث عن أماكن إقامة.\n٢) استخدم الفلاتر (المدينة، النوع، التاريخ) ثم اطلب عرض سعر.\n٣) عند رضاك عن السعر، أكمل الحجز وادفع من المحفظة.'
                      : '1) Open \"Hotels & Stays\" to search for accommodation.\n2) Use filters (city, type, dates) and request a quote.\n3) If the price looks good, confirm the booking and pay from the wallet.',
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
                      ? 'كمستخدم نهائي ترى فقط التطبيقات المخصصة لك. المشغلون والمديرون لديهم واجهات منفصلة لكل مجال (مثل مشغل الفنادق أو مشغل الباص).'
                      : 'As an end user you only see the parts that are enabled for you. Operators and admins have their own consoles per domain (for example hotel operator, bus operator).',
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
