import 'dart:async';

import 'package:flutter/material.dart';

import 'mini_app_contract.dart';
import 'mini_app_descriptor.dart';
import 'mini_program_models.dart';
import 'mini_program_runtime.dart';
import 'superapp_api.dart';

class MiniAppRegistry {
  static final List<_MiniAppRegistration> _registrations = [
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'freight',
        manifestFallback: _freightManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'freight',
        icon: Icons.local_shipping_outlined,
        titleEn: 'Freight',
        titleAr: 'الشحن',
        categoryEn: 'Logistics',
        categoryAr: 'اللوجستيات',
        enabled: true,
        rating: 4.1,
        usageScore: 45,
        runtimeAppId: 'freight',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'taxi_rider',
        manifestFallback: _taxiRiderManifest,
        followOfficialId: 'shamell_taxi',
        followChatPeerId: 'shamell_taxi',
      ),
      descriptor: const MiniAppDescriptor(
        id: 'taxi_rider',
        icon: Icons.local_taxi_outlined,
        titleEn: 'Taxi (Rider)',
        titleAr: 'تاكسي',
        categoryEn: 'Mobility',
        categoryAr: 'التنقل',
        rating: 4.8,
        usageScore: 90,
        runtimeAppId: 'taxi_rider',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'taxi_driver',
        manifestFallback: _taxiDriverManifest,
        followOfficialId: 'shamell_taxi',
        followChatPeerId: 'shamell_taxi',
      ),
      descriptor: const MiniAppDescriptor(
        id: 'taxi_driver',
        icon: Icons.local_taxi_outlined,
        titleEn: 'Taxi (Driver)',
        titleAr: 'سائق التاكسي',
        categoryEn: 'Mobility',
        categoryAr: 'التنقل',
        rating: 4.6,
        usageScore: 40,
        runtimeAppId: 'taxi_driver',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'taxi_operator',
        manifestFallback: _taxiOperatorManifest,
        followOfficialId: 'shamell_taxi',
        followChatPeerId: 'shamell_taxi',
      ),
      descriptor: const MiniAppDescriptor(
        id: 'taxi_operator',
        icon: Icons.support_agent_outlined,
        titleEn: 'Taxi (Operator)',
        titleAr: 'مشغل التاكسي',
        categoryEn: 'Operations',
        categoryAr: 'العمليات',
        rating: 4.4,
        usageScore: 25,
        runtimeAppId: 'taxi_operator',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'taxi_demo',
        manifestFallback: _taxiDemoManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'taxi_demo',
        icon: Icons.code,
        titleEn: 'Taxi mini‑program demo',
        titleAr: 'عرض مصغر لبرنامج التاكسي',
        categoryEn: 'Developer',
        categoryAr: 'للمطورين',
        beta: true,
        rating: 5.0,
        usageScore: 5,
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'bus',
        manifestFallback: _busManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'bus',
        icon: Icons.directions_bus_filled_outlined,
        titleEn: 'Bus',
        titleAr: 'الحافلات',
        categoryEn: 'Mobility',
        categoryAr: 'التنقل',
        rating: 4.6,
        usageScore: 60,
        runtimeAppId: 'bus',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'food',
        manifestFallback: _foodManifest,
        followOfficialId: 'shamell_food',
        followChatPeerId: 'shamell_food',
      ),
      descriptor: const MiniAppDescriptor(
        id: 'food',
        icon: Icons.restaurant_outlined,
        titleEn: 'Food',
        titleAr: 'الطعام',
        categoryEn: 'Lifestyle',
        categoryAr: 'أسلوب الحياة',
        rating: 4.7,
        usageScore: 70,
        runtimeAppId: 'food',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'stays',
        manifestFallback: _staysManifest,
        followOfficialId: 'shamell_stays',
        followChatPeerId: 'shamell_stays',
      ),
      descriptor: const MiniAppDescriptor(
        id: 'stays',
        icon: Icons.hotel,
        titleEn: 'Stays',
        titleAr: 'الإقامات',
        categoryEn: 'Lifestyle',
        categoryAr: 'أسلوب الحياة',
        rating: 4.5,
        usageScore: 55,
        runtimeAppId: 'stays',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'courier',
        manifestFallback: _courierManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'courier',
        icon: Icons.local_shipping_outlined,
        titleEn: 'Courier',
        titleAr: 'التوصيل',
        categoryEn: 'Logistics',
        categoryAr: 'اللوجستيات',
        rating: 4.2,
        usageScore: 35,
        runtimeAppId: 'courier',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'equipment',
        manifestFallback: _equipmentManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'equipment',
        icon: Icons.engineering_outlined,
        titleEn: 'Equipment',
        titleAr: 'المعدات',
        categoryEn: 'Marketplace',
        categoryAr: 'السوق',
        rating: 4.0,
        usageScore: 30,
        runtimeAppId: 'equipment',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'carmarket',
        manifestFallback: _carmarketManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'carmarket',
        icon: Icons.directions_car_outlined,
        titleEn: 'Cars',
        titleAr: 'السيارات',
        categoryEn: 'Marketplace',
        categoryAr: 'السوق',
        rating: 4.2,
        usageScore: 40,
        runtimeAppId: 'carmarket',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'carrental',
        manifestFallback: _carrentalManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'carrental',
        icon: Icons.time_to_leave_outlined,
        titleEn: 'Car rental',
        titleAr: 'تأجير السيارات',
        categoryEn: 'Mobility',
        categoryAr: 'التنقل',
        rating: 4.1,
        usageScore: 35,
        runtimeAppId: 'carrental',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'realestate',
        manifestFallback: _realestateManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'realestate',
        icon: Icons.home_work_outlined,
        titleEn: 'Real estate',
        titleAr: 'العقارات',
        categoryEn: 'Marketplace',
        categoryAr: 'السوق',
        rating: 4.0,
        usageScore: 30,
        runtimeAppId: 'realestate',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'doctors',
        manifestFallback: _doctorsManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'doctors',
        icon: Icons.medical_services_outlined,
        titleEn: 'Doctors',
        titleAr: 'الأطباء',
        categoryEn: 'Health',
        categoryAr: 'الصحة',
        rating: 4.3,
        usageScore: 45,
        runtimeAppId: 'doctors',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'flights',
        manifestFallback: _flightsManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'flights',
        icon: Icons.flight_takeoff_outlined,
        titleEn: 'Flights',
        titleAr: 'الرحلات',
        categoryEn: 'Travel',
        categoryAr: 'السفر',
        rating: 4.0,
        usageScore: 20,
        runtimeAppId: 'flights',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'jobs',
        manifestFallback: _jobsManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'jobs',
        icon: Icons.work_outline,
        titleEn: 'Jobs',
        titleAr: 'الوظائف',
        categoryEn: 'Work',
        categoryAr: 'العمل',
        rating: 3.9,
        usageScore: 15,
        runtimeAppId: 'jobs',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'agriculture',
        manifestFallback: _agricultureManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'agriculture',
        icon: Icons.grass_outlined,
        titleEn: 'Agri market',
        titleAr: 'السوق الزراعي',
        categoryEn: 'Marketplace',
        categoryAr: 'السوق',
        rating: 3.8,
        usageScore: 10,
        runtimeAppId: 'agriculture',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'livestock',
        manifestFallback: _livestockManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'livestock',
        icon: Icons.pets_outlined,
        titleEn: 'Livestock',
        titleAr: 'الثروة الحيوانية',
        categoryEn: 'Marketplace',
        categoryAr: 'السوق',
        rating: 3.8,
        usageScore: 10,
        runtimeAppId: 'livestock',
      ),
    ),
    _MiniAppRegistration(
      app: _RuntimeMiniApp(
        id: 'commerce',
        manifestFallback: _commerceManifest,
      ),
      descriptor: const MiniAppDescriptor(
        id: 'commerce',
        icon: Icons.storefront_outlined,
        titleEn: 'Commerce',
        titleAr: 'السوق',
        categoryEn: 'Marketplace',
        categoryAr: 'السوق',
        rating: 4.0,
        usageScore: 25,
        runtimeAppId: 'commerce',
      ),
    ),
  ];

  static MiniApp? byId(String id) {
    for (final r in _registrations) {
      if (r.app.id == id) return r.app;
    }
    return null;
  }

  static List<MiniAppDescriptor> get descriptors =>
      _registrations.map((r) => r.descriptor).toList(growable: false);

  static MiniProgramManifest? localManifestById(String id) =>
      byId(id)?.manifest();
}

class _MiniAppRegistration {
  final MiniApp app;
  final MiniAppDescriptor descriptor;

  const _MiniAppRegistration({
    required this.app,
    required this.descriptor,
  });
}

class _RuntimeMiniApp implements MiniApp {
  @override
  final String id;
  final MiniProgramManifest? manifestFallback;
  final String? followOfficialId;
  final String? followChatPeerId;

  const _RuntimeMiniApp({
    required this.id,
    this.manifestFallback,
    this.followOfficialId,
    this.followChatPeerId,
  });

  @override
  MiniProgramManifest? manifest() => manifestFallback;

  @override
  Widget entry(BuildContext context, SuperappAPI api) {
    if (followOfficialId != null && followChatPeerId != null) {
      unawaited(api.ensureServiceOfficialFollow(
        officialId: followOfficialId!,
        chatPeerId: followChatPeerId!,
      ));
    }
    unawaited(api.recordModuleUse(id));
    return MiniProgramPage(
      id: id,
      baseUrl: api.baseUrl,
      walletId: api.walletId,
      deviceId: api.deviceId,
      onOpenMod: api.openMod,
    );
  }
}

const MiniProgramManifest _taxiDemoManifest = MiniProgramManifest(
  id: 'taxi_demo',
  titleEn: 'Taxi mini‑program demo',
  titleAr: 'عرض مصغر لبرنامج التاكسي',
  descriptionEn: 'This is a small WeChat‑style mini‑program inside Shamell.\n'
      'From here you can jump into the real Taxi service module.',
  descriptionAr: 'هذا مثال صغير لبرنامج مصغر على نمط WeChat داخل شامل.\n'
      'من هنا يمكنك الانتقال إلى خدمة التاكسي الحقيقية في التطبيق.',
  actions: [
    MiniProgramAction(
      id: 'open_taxi',
      labelEn: 'Open Taxi service',
      labelAr: 'فتح خدمة التاكسي',
      kind: MiniProgramActionKind.openMod,
      modId: 'taxi_rider',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _taxiRiderManifest = MiniProgramManifest(
  id: 'taxi_rider',
  titleEn: 'Shamell Taxi',
  titleAr: 'شامل تاكسي',
  descriptionEn: 'Book rides, view trip history and pay with Shamell Pay.',
  descriptionAr: 'احجز رحلات تاكسي، راقب سجل الرحلات وادفع عبر محفظة شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_taxi',
      labelEn: 'Open Taxi',
      labelAr: 'فتح التاكسي',
      kind: MiniProgramActionKind.openUrl,
      url: '/taxi/rider',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _taxiDriverManifest = MiniProgramManifest(
  id: 'taxi_driver',
  titleEn: 'Taxi Driver',
  titleAr: 'سائق التاكسي',
  descriptionEn: 'Driver console for accepting and completing rides.',
  descriptionAr: 'لوحة السائق لقبول الرحلات وإنهائها.',
  actions: [
    MiniProgramAction(
      id: 'open_taxi_driver',
      labelEn: 'Open driver console',
      labelAr: 'فتح لوحة السائق',
      kind: MiniProgramActionKind.openUrl,
      url: '/taxi/driver',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _taxiOperatorManifest = MiniProgramManifest(
  id: 'taxi_operator',
  titleEn: 'Taxi Operator',
  titleAr: 'مشغل التاكسي',
  descriptionEn: 'Operator dashboard for taxi fleet and ride monitoring.',
  descriptionAr: 'لوحة المشغل لمراقبة الأسطول والرحلات.',
  actions: [
    MiniProgramAction(
      id: 'open_taxi_operator',
      labelEn: 'Open operator dashboard',
      labelAr: 'فتح لوحة المشغل',
      kind: MiniProgramActionKind.openUrl,
      url: '/taxi/admin',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _foodManifest = MiniProgramManifest(
  id: 'food',
  titleEn: 'Shamell Food',
  titleAr: 'شامل فود',
  descriptionEn: 'Order food, track deliveries and pay in one place.',
  descriptionAr: 'اطلب الطعام، تابع التوصيل وادفع في مكان واحد داخل شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_food',
      labelEn: 'Open Food',
      labelAr: 'فتح خدمة الطعام',
      kind: MiniProgramActionKind.openUrl,
      url: '/food',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _staysManifest = MiniProgramManifest(
  id: 'stays',
  titleEn: 'Shamell Stays',
  titleAr: 'شامل ستايز',
  descriptionEn: 'Browse and book hotels and stays via Shamell.',
  descriptionAr: 'استعرض واحجز الفنادق والإقامات من خلال شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_stays',
      labelEn: 'Open Stays',
      labelAr: 'فتح خدمة الإقامات',
      kind: MiniProgramActionKind.openUrl,
      url: '/stays',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _busManifest = MiniProgramManifest(
  id: 'bus',
  titleEn: 'Shamell Bus',
  titleAr: 'شامل باص',
  descriptionEn: 'Plan and manage intercity bus trips with Shamell.',
  descriptionAr: 'خطط وأدر رحلات الحافلات بين المدن عبر شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_bus',
      labelEn: 'Open Bus',
      labelAr: 'فتح خدمة الحافلات',
      kind: MiniProgramActionKind.openUrl,
      url: '/bus',
    ),
    MiniProgramAction(
      id: 'open_bus_admin',
      labelEn: 'Bus admin',
      labelAr: 'إدارة الحافلات',
      kind: MiniProgramActionKind.openUrl,
      url: '/bus/admin',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _carmarketManifest = MiniProgramManifest(
  id: 'carmarket',
  titleEn: 'Shamell Cars',
  titleAr: 'شامل للسيارات',
  descriptionEn: 'Browse and sell cars in the Shamell marketplace.',
  descriptionAr: 'تصفح وبِع السيارات في سوق شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_carmarket',
      labelEn: 'Open car market',
      labelAr: 'فتح سوق السيارات',
      kind: MiniProgramActionKind.openUrl,
      url: '/carmarket',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _carrentalManifest = MiniProgramManifest(
  id: 'carrental',
  titleEn: 'Shamell Car rental',
  titleAr: 'تأجير السيارات في شامل',
  descriptionEn: 'Find and reserve rental cars through Shamell.',
  descriptionAr: 'ابحث واحجز سيارات الإيجار من خلال شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_carrental',
      labelEn: 'Open car rental',
      labelAr: 'فتح تأجير السيارات',
      kind: MiniProgramActionKind.openUrl,
      url: '/carrental',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _realestateManifest = MiniProgramManifest(
  id: 'realestate',
  titleEn: 'Shamell Real estate',
  titleAr: 'شامل للعقارات',
  descriptionEn: 'Explore and list properties in the Shamell real estate hub.',
  descriptionAr: 'استكشف وأضف العقارات ضمن مركز العقارات في شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_realestate',
      labelEn: 'Open real estate',
      labelAr: 'فتح العقارات',
      kind: MiniProgramActionKind.openUrl,
      url: '/realestate',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _doctorsManifest = MiniProgramManifest(
  id: 'doctors',
  titleEn: 'Shamell Doctors',
  titleAr: 'أطباء شامل',
  descriptionEn: 'Find doctors and manage appointments inside Shamell.',
  descriptionAr: 'ابحث عن الأطباء ونظم المواعيد داخل شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_doctors',
      labelEn: 'Open doctors',
      labelAr: 'فتح خدمة الأطباء',
      kind: MiniProgramActionKind.openUrl,
      url: '/doctors',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _flightsManifest = MiniProgramManifest(
  id: 'flights',
  titleEn: 'Flights',
  titleAr: 'الرحلات',
  descriptionEn: 'Flights operator mini‑program for Shamell.',
  descriptionAr: 'برنامج مصغر لإدارة الرحلات داخل شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_flights',
      labelEn: 'Open flights',
      labelAr: 'فتح الرحلات',
      kind: MiniProgramActionKind.openUrl,
      url: '/flights',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _jobsManifest = MiniProgramManifest(
  id: 'jobs',
  titleEn: 'Shamell Jobs',
  titleAr: 'وظائف شامل',
  descriptionEn: 'Browse and post jobs in the Shamell ecosystem.',
  descriptionAr: 'تصفح وأعلن عن الوظائف ضمن منظومة شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_jobs',
      labelEn: 'Open jobs',
      labelAr: 'فتح الوظائف',
      kind: MiniProgramActionKind.openUrl,
      url: '/jobs',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _agricultureManifest = MiniProgramManifest(
  id: 'agriculture',
  titleEn: 'Agri market',
  titleAr: 'السوق الزراعي',
  descriptionEn: 'Agriculture marketplace mini‑program for Shamell.',
  descriptionAr: 'برنامج مصغر لسوق المنتجات الزراعية ضمن شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_agriculture',
      labelEn: 'Open agri market',
      labelAr: 'فتح السوق الزراعي',
      kind: MiniProgramActionKind.openUrl,
      url: '/agriculture',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _livestockManifest = MiniProgramManifest(
  id: 'livestock',
  titleEn: 'Livestock market',
  titleAr: 'سوق الثروة الحيوانية',
  descriptionEn: 'Livestock marketplace mini‑program inside Shamell.',
  descriptionAr: 'برنامج مصغر لسوق الثروة الحيوانية داخل شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_livestock',
      labelEn: 'Open livestock',
      labelAr: 'فتح الثروة الحيوانية',
      kind: MiniProgramActionKind.openUrl,
      url: '/livestock',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _commerceManifest = MiniProgramManifest(
  id: 'commerce',
  titleEn: 'Shamell Commerce',
  titleAr: 'تجارة شامل',
  descriptionEn: 'General commerce mini‑program for shops and offers.',
  descriptionAr: 'برنامج مصغر للتجارة العامة والعروض داخل شامل.',
  actions: [
    MiniProgramAction(
      id: 'open_commerce',
      labelEn: 'Open commerce',
      labelAr: 'فتح التجارة',
      kind: MiniProgramActionKind.openUrl,
      url: '/commerce',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _courierManifest = MiniProgramManifest(
  id: 'courier',
  titleEn: 'Courier',
  titleAr: 'التوصيل',
  descriptionEn: 'Courier console for tracking and operations.',
  descriptionAr: 'لوحة التوصيل للتتبع والعمليات.',
  actions: [
    MiniProgramAction(
      id: 'open_courier',
      labelEn: 'Open courier',
      labelAr: 'فتح التوصيل',
      kind: MiniProgramActionKind.openUrl,
      url: '/courier_console',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _freightManifest = MiniProgramManifest(
  id: 'freight',
  titleEn: 'Freight',
  titleAr: 'الشحن',
  descriptionEn: 'Freight quotes, booking and shipment status.',
  descriptionAr: 'عروض أسعار الشحن والحجز وحالة الشحنة.',
  actions: [
    MiniProgramAction(
      id: 'open_freight',
      labelEn: 'Open freight',
      labelAr: 'فتح الشحن',
      kind: MiniProgramActionKind.openUrl,
      url: '/freight',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);

const MiniProgramManifest _equipmentManifest = MiniProgramManifest(
  id: 'equipment',
  titleEn: 'Equipment',
  titleAr: 'المعدات',
  descriptionEn: 'Browse equipment and availability.',
  descriptionAr: 'تصفح المعدات والتوفر.',
  actions: [
    MiniProgramAction(
      id: 'open_equipment',
      labelEn: 'Open equipment',
      labelAr: 'فتح المعدات',
      kind: MiniProgramActionKind.openUrl,
      url: '/equipment',
    ),
    MiniProgramAction(
      id: 'close',
      labelEn: 'Close',
      labelAr: 'إغلاق',
      kind: MiniProgramActionKind.close,
    ),
  ],
);
