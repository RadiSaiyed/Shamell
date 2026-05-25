import 'package:flutter/material.dart';

enum ShamellAppSurface {
  superapp,
  ride,
  driver,
  operator,
  busOperator,
  hotelOperator,
  syrcom,
}

const String _configuredAppSurfaceRaw = String.fromEnvironment(
  'SHAMELL_APP_SURFACE',
  defaultValue: 'superapp',
);

ShamellAppSurface _activeAppSurface =
    shamellParseAppSurface(_configuredAppSurfaceRaw);

ShamellAppSurface shamellParseAppSurface(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'ride':
    case 'rides':
    case 'taxi':
      return ShamellAppSurface.ride;
    case 'driver':
    case 'ride_driver':
    case 'taxi_driver':
      return ShamellAppSurface.driver;
    case 'operator':
    case 'ops':
    case 'ride_operator':
    case 'taxi_operator':
      return ShamellAppSurface.operator;
    case 'bus_operator':
    case 'busoperator':
    case 'bus_ops':
    case 'busops':
    case 'coach_operator':
    case 'bus':
      return ShamellAppSurface.busOperator;
    case 'hotel_operator':
    case 'hoteloperator':
    case 'hotel_ops':
    case 'hotelops':
    case 'hotels_operator':
    case 'hotels_admin':
    case 'hotel':
      return ShamellAppSurface.hotelOperator;
    case 'syrcom':
    case 'sirkom':
    case 'work':
    case 'enterprise':
      return ShamellAppSurface.syrcom;
    case 'superapp':
    default:
      return ShamellAppSurface.superapp;
  }
}

ShamellAppSurface get shamellConfiguredAppSurface =>
    shamellParseAppSurface(_configuredAppSurfaceRaw);

ShamellAppSurface get shamellActiveAppSurface => _activeAppSurface;

void shamellSetActiveAppSurface(ShamellAppSurface surface) {
  _activeAppSurface = surface;
}

bool shamellIsRideRiderSurface([ShamellAppSurface? surface]) =>
    (surface ?? shamellActiveAppSurface) == ShamellAppSurface.ride;

bool shamellIsRideDriverSurface([ShamellAppSurface? surface]) =>
    (surface ?? shamellActiveAppSurface) == ShamellAppSurface.driver;

bool shamellIsRideOperatorSurface([ShamellAppSurface? surface]) =>
    (surface ?? shamellActiveAppSurface) == ShamellAppSurface.operator;

bool shamellIsBusOperatorSurface([ShamellAppSurface? surface]) =>
    (surface ?? shamellActiveAppSurface) == ShamellAppSurface.busOperator;

bool shamellIsHotelOperatorSurface([ShamellAppSurface? surface]) =>
    (surface ?? shamellActiveAppSurface) == ShamellAppSurface.hotelOperator;

bool shamellIsSyrComSurface([ShamellAppSurface? surface]) =>
    (surface ?? shamellActiveAppSurface) == ShamellAppSurface.syrcom;

bool shamellIsAnyOperatorSurface([ShamellAppSurface? surface]) =>
    shamellIsRideOperatorSurface(surface) ||
    shamellIsBusOperatorSurface(surface) ||
    shamellIsHotelOperatorSurface(surface);

bool shamellIsManagedAccountSurface([ShamellAppSurface? surface]) =>
    shamellIsAnyOperatorSurface(surface) || shamellIsSyrComSurface(surface);

bool shamellIsRideStandaloneSurface([ShamellAppSurface? surface]) {
  final current = surface ?? shamellActiveAppSurface;
  return current == ShamellAppSurface.ride ||
      current == ShamellAppSurface.driver ||
      current == ShamellAppSurface.operator;
}

bool shamellSurfaceAllowsPublicAccountCreate([ShamellAppSurface? surface]) =>
    !shamellIsManagedAccountSurface(surface);

bool shamellSurfaceUsesUsernamePasswordAuth([ShamellAppSurface? surface]) =>
    !shamellIsManagedAccountSurface(surface);

String shamellSurfaceAppTitle({
  required bool isArabic,
  ShamellAppSurface? surface,
}) {
  if (shamellIsRideDriverSurface(surface)) {
    return isArabic ? 'سرتشات درايفر' : 'SyrChat Driver';
  }
  if (shamellIsBusOperatorSurface(surface)) {
    return isArabic ? 'سرتشات باص' : 'SyrChat Bus';
  }
  if (shamellIsRideOperatorSurface(surface)) {
    return isArabic ? 'سرتشات كونترول' : 'SyrChat Control';
  }
  if (shamellIsRideRiderSurface(surface)) {
    return isArabic ? 'سرتشات رايد' : 'SyrChat Ride';
  }
  if (shamellIsSyrComSurface(surface)) {
    return isArabic ? 'سركم' : 'SyrCom';
  }
  return isArabic ? 'سرتشات' : 'SyrChat';
}

String shamellSurfaceAutomaticSetupDescription({
  required bool isArabic,
  ShamellAppSurface? surface,
}) {
  if (shamellIsRideDriverSurface(surface)) {
    return isArabic
        ? 'أنشئ حساب السائق أو سجّل الدخول باستخدام اسم المستخدم وكلمة المرور.'
        : 'Create your SyrChat driver account or sign in with your username and password.';
  }
  if (shamellIsBusOperatorSurface(surface)) {
    return isArabic
        ? 'تتطلب وحدة عمليات الحافلات حساب مشغّل حافلات مصرحاً به على سرتشات.'
        : 'The bus operations console requires an authorized SyrChat bus-operator account.';
  }
  if (shamellIsRideOperatorSurface(surface)) {
    return isArabic
        ? 'تتطلب هذه الواجهة حساب تشغيل مصرحاً به على سرتشات.'
        : 'This console requires an authorized SyrChat operations account.';
  }
  if (shamellIsRideRiderSurface(surface)) {
    return isArabic
        ? 'أنشئ حساب الراكب أو سجّل الدخول باستخدام اسم المستخدم وكلمة المرور.'
        : 'Create your SyrChat rider account or sign in with your username and password.';
  }
  if (shamellIsSyrComSurface(surface)) {
    return isArabic
        ? 'سركم تطبيق مؤسسي. لا يمكن إنشاء حسابات بشكل عام؛ يجب أن يوفّر لك مسؤول الشركة بيانات الدخول.'
        : 'SyrCom is an enterprise app. Public account creation is disabled — your company administrator must provision your sign-in credentials.';
  }
  return isArabic
      ? 'أنشئ حساب SyrChat أو سجّل الدخول باستخدام اسم المستخدم وكلمة المرور.'
      : 'Create your SyrChat account or sign in with your username and password.';
}

String shamellSurfaceBiometricActionLabel({
  required bool isArabic,
  ShamellAppSurface? surface,
}) {
  final appTitle = shamellSurfaceAppTitle(
    isArabic: isArabic,
    surface: surface,
  );
  return isArabic ? 'تسجيل الدخول إلى $appTitle' : 'Sign in to $appTitle';
}

String shamellSurfaceSetupActionLabel({
  required bool isArabic,
  ShamellAppSurface? surface,
}) {
  final appTitle = shamellSurfaceAppTitle(
    isArabic: isArabic,
    surface: surface,
  );
  return isArabic ? 'إعداد $appTitle' : 'Set up $appTitle';
}

String shamellSurfaceManagedSignInActionLabel({
  required bool isArabic,
  ShamellAppSurface? surface,
}) {
  if (shamellIsAnyOperatorSurface(surface)) {
    return isArabic ? 'فتح تسجيل الدخول المعتمد' : 'Open approved sign-in';
  }
  return shamellSurfaceBiometricActionLabel(
    isArabic: isArabic,
    surface: surface,
  );
}

String shamellSurfaceManagedSignInDescription({
  required bool isArabic,
  ShamellAppSurface? surface,
}) {
  if (shamellIsBusOperatorSurface(surface)) {
    return isArabic
        ? 'استخدم جهازاً معتمداً مسبقاً، أو افتح تدفق تسجيل الدخول الخاص بمشغّل الحافلات من SyrChat Bus. لا يمكن إنشاء حسابات مشغّلي الحافلات بشكل عام من هذا التطبيق.'
        : 'Use a device that is already approved, or open the managed bus-operator sign-in flow from SyrChat Bus. Public bus-operator accounts cannot be created from this app.';
  }
  if (shamellIsRideOperatorSurface(surface)) {
    return isArabic
        ? 'استخدم جهازاً سبق اعتماده، أو افتح تدفق تسجيل الدخول المعتمد من SyrChat Control. لا يمكن إنشاء حسابات تشغيل عامة من هذا التطبيق.'
        : 'Use a device that is already approved, or open the managed sign-in flow from SyrChat Control. Public operations accounts cannot be created from this app.';
  }
  if (shamellIsSyrComSurface(surface)) {
    return isArabic
        ? 'استخدم جهازاً سبق اعتماده من مؤسستك، أو افتح تدفق تسجيل الدخول الذي زوّدك به مسؤول سركم. لا يمكن إنشاء حسابات سركم بشكل عام من هذا التطبيق.'
        : 'Use a device that is already approved by your organization, or open the managed sign-in flow provided by your SyrCom administrator. Public SyrCom accounts cannot be created from this app.';
  }
  return shamellSurfaceAutomaticSetupDescription(
    isArabic: isArabic,
    surface: surface,
  );
}

String shamellSurfaceAccountCreateBusyLabel({
  required bool isArabic,
  ShamellAppSurface? surface,
}) {
  if (shamellIsRideDriverSurface(surface)) {
    return isArabic
        ? 'جارٍ إعداد حساب السائق…'
        : 'Setting up your driver account…';
  }
  if (shamellIsBusOperatorSurface(surface)) {
    return isArabic
        ? 'جارٍ فتح وحدة عمليات الحافلات…'
        : 'Opening bus-operations console…';
  }
  if (shamellIsRideOperatorSurface(surface)) {
    return isArabic ? 'جارٍ فتح وحدة التشغيل…' : 'Opening operations console…';
  }
  if (shamellIsRideRiderSurface(surface)) {
    return isArabic
        ? 'جارٍ إعداد حساب الراكب…'
        : 'Setting up your rider account…';
  }
  if (shamellIsSyrComSurface(surface)) {
    return isArabic
        ? 'جارٍ فتح سركم…'
        : 'Opening SyrCom…';
  }
  return isArabic ? 'جارٍ إنشاء معرّف جديد…' : 'Creating a new SyrChat ID…';
}

String shamellSurfaceAccountCreateSuccessLabel({
  required bool isArabic,
  required String shamellId,
  ShamellAppSurface? surface,
}) {
  if (shamellIsRideDriverSurface(surface)) {
    return isArabic
        ? 'تم إعداد حساب السائق: $shamellId'
        : 'Driver account ready: $shamellId';
  }
  if (shamellIsBusOperatorSurface(surface)) {
    return isArabic
        ? 'تم فتح وحدة عمليات الحافلات: $shamellId'
        : 'Bus-operations console ready: $shamellId';
  }
  if (shamellIsRideOperatorSurface(surface)) {
    return isArabic
        ? 'تم فتح وحدة التشغيل: $shamellId'
        : 'Operations console ready: $shamellId';
  }
  if (shamellIsRideRiderSurface(surface)) {
    return isArabic
        ? 'تم إعداد حساب الراكب: $shamellId'
        : 'Rider account ready: $shamellId';
  }
  if (shamellIsSyrComSurface(surface)) {
    return isArabic
        ? 'تم فتح سركم: $shamellId'
        : 'SyrCom ready: $shamellId';
  }
  return isArabic
      ? 'تم إنشاء معرّف SyrChat: $shamellId'
      : 'Created SyrChat ID: $shamellId';
}

IconData shamellSurfaceBrandIcon([ShamellAppSurface? surface]) {
  if (shamellIsRideDriverSurface(surface)) {
    return Icons.drive_eta_outlined;
  }
  if (shamellIsBusOperatorSurface(surface)) {
    return Icons.directions_bus_outlined;
  }
  if (shamellIsRideOperatorSurface(surface)) {
    return Icons.monitor_outlined;
  }
  if (shamellIsSyrComSurface(surface)) {
    return Icons.business_center_outlined;
  }
  return shamellIsRideStandaloneSurface(surface)
      ? Icons.local_taxi_outlined
      : Icons.chat_bubble_outline;
}

String shamellRidePageTitle({
  required bool isArabic,
  required bool standaloneApp,
}) {
  if (standaloneApp) {
    return isArabic ? 'سرتشات رايد' : 'SyrChat Ride';
  }
  return isArabic ? 'ميني برنامج التاكسي' : 'Taxi mini program';
}
