import 'dart:async';

import 'package:flutter/material.dart';

import 'mini_app_contract.dart';
import 'mini_app_descriptor.dart';
import 'mini_program_models.dart';
import 'mini_program_runtime.dart';
import 'superapp_api.dart';

class MiniAppRegistry {
  // Bus-only build: keep a single mini-app registration.
  static final List<_MiniAppRegistration> _registrations = [
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
