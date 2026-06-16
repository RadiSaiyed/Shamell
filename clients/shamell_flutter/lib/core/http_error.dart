import 'dart:convert';

String sanitizeHttpError({
  required int statusCode,
  String? rawBody,
  bool isArabic = false,
}) {
  final detail = _extractDetail(rawBody).toLowerCase();

  if (statusCode == 401 || statusCode == 403) {
    return isArabic ? 'تسجيل الدخول مطلوب.' : 'Sign-in required.';
  }
  if (statusCode == 404) {
    return isArabic ? 'العنصر غير موجود.' : 'Not found.';
  }
  if (statusCode == 429) {
    return isArabic
        ? 'محاولات كثيرة. حاول لاحقًا.'
        : 'Too many requests. Try again later.';
  }
  if (statusCode >= 500) {
    return isArabic
        ? 'خطأ في الخادم. حاول لاحقًا.'
        : 'Server error. Try again later.';
  }

  if (detail.contains('unauthorized') ||
      detail.contains('forbidden') ||
      detail.contains('internal auth required') ||
      detail.contains('auth session required')) {
    return isArabic ? 'تسجيل الدخول مطلوب.' : 'Sign-in required.';
  }
  if (detail.contains('timeout')) {
    return isArabic ? 'انتهت مهلة الطلب.' : 'Request timed out.';
  }

  return isArabic
      ? 'تعذر إكمال الطلب (HTTP $statusCode).'
      : 'Request failed (HTTP $statusCode).';
}

String sanitizeExceptionForUi({
  Object? error,
  bool isArabic = false,
  String? fallbackEn,
  String? fallbackAr,
}) {
  final text = (error ?? '').toString().trim().toLowerCase();
  if (text.contains('timeout')) {
    return isArabic ? 'انتهت مهلة الطلب.' : 'Request timed out.';
  }
  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('connection')) {
    return isArabic ? 'خطأ في الشبكة.' : 'Network error.';
  }
  if (text.contains('unauthorized') ||
      text.contains('forbidden') ||
      text.contains('internal auth required') ||
      text.contains('auth session required') ||
      text.contains('authentication required') ||
      text.contains('failed: 401') ||
      text.contains('failed: 403')) {
    return isArabic ? 'تسجيل الدخول مطلوب.' : 'Sign-in required.';
  }
  if (text.contains('failed: 404') || text.contains('not found')) {
    return isArabic ? 'العنصر غير موجود.' : 'Not found.';
  }
  if (text.contains('chat device not registered') ||
      text.contains('failed: 409')) {
    return isArabic
        ? 'الجهاز غير مرتبط بالحساب بعد. أعد المحاولة.'
        : 'This device is not linked to the account yet. Please try again.';
  }
  return isArabic
      ? (fallbackAr ?? 'تعذّر إكمال العملية.')
      : (fallbackEn ?? 'Could not complete the request.');
}

String _extractDetail(String? rawBody) {
  final text = (rawBody ?? '').trim();
  if (text.isEmpty) return '';
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
    }
  } catch (_) {}
  return text;
}
