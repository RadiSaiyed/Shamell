import 'dart:convert';

int? parseRetryAfterSecondsFromHttpErrorBody(String? rawBody) {
  final detail = _extractDetail(rawBody).trim().toLowerCase();
  if (detail.isEmpty) return null;

  String? rawSeconds;
  final explicitMatch =
      RegExp(r'retry_after_secs\s*=\s*(\d{1,10})').firstMatch(detail);
  if (explicitMatch != null) {
    rawSeconds = explicitMatch.group(1);
  } else {
    final genericMatch =
        RegExp(r'retry[-_ ]?after(?:\s+secs?)?\s*[:=]?\s*(\d{1,10})')
            .firstMatch(detail);
    rawSeconds = genericMatch?.group(1);
  }
  final seconds = int.tryParse(rawSeconds ?? '');
  if (seconds == null || seconds <= 0) return null;
  return seconds;
}

String sanitizeHttpError({
  required int statusCode,
  String? rawBody,
  bool isArabic = false,
}) {
  final detail = _extractDetail(rawBody).toLowerCase();

  if (detail.contains('attestation required')) {
    return isArabic
        ? 'مطلوب التحقق من الجهاز.'
        : 'Device verification required.';
  }
  if (detail.contains('cannot redeem own invite')) {
    return isArabic
        ? 'لا يمكنك إضافة نفسك كجهة اتصال. امسح رمز QR لشخص آخر.'
        : 'You cannot add yourself as a contact. Scan another person\'s invite QR.';
  }
  if (detail.contains('cannot add own shamell id')) {
    return isArabic
        ? 'لا يمكنك إضافة معرف SyrChat الخاص بك.'
        : 'You cannot add your own SyrChat ID.';
  }
  if (detail.contains('invalid token')) {
    return isArabic ? 'رمز الدعوة غير صالح.' : 'Invalid invite token.';
  }
  if (detail.contains('chat device not registered')) {
    return isArabic
        ? 'الجهاز غير مرتبط بالحساب بعد. أعد المحاولة.'
        : 'This device is not linked to the account yet. Please try again.';
  }

  if (statusCode == 401 || statusCode == 403) {
    return isArabic ? 'تسجيل الدخول مطلوب.' : 'Sign-in required.';
  }
  if (statusCode == 404) {
    return isArabic ? 'العنصر غير موجود.' : 'Not found.';
  }
  if (statusCode == 429) {
    final retryAfterSeconds = parseRetryAfterSecondsFromHttpErrorBody(rawBody);
    if (retryAfterSeconds != null) {
      return isArabic
          ? 'محاولات كثيرة. أعد المحاولة بعد $retryAfterSeconds ثانية.'
          : 'Too many requests. Try again in ${retryAfterSeconds}s.';
    }
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
  if (detail.contains('direct message too large')) {
    return isArabic
        ? 'الرسالة كبيرة جدًا للإرسال الآمن.'
        : 'Message is too large to send securely.';
  }
  if (detail.contains('invalid thumb_url') ||
      detail.contains('thumb_url too long')) {
    return isArabic
        ? 'استخدم رابط صورة صالحًا عبر https، أو http محلي للتطوير فقط.'
        : 'Use a valid https image URL, or localhost http for development only.';
  }
  if (detail.contains('group avatar too large')) {
    return isArabic
        ? 'صورة المجموعة كبيرة جدًا. اختر صورة أصغر.'
        : 'Group photo is too large. Choose a smaller image.';
  }
  if (detail.contains('invalid avatar_mime') ||
      detail.contains('avatar_mime required')) {
    return isArabic
        ? 'صيغة صورة المجموعة غير مدعومة.'
        : 'Unsupported group photo format.';
  }
  if (detail.contains('invalid avatar_b64') ||
      detail.contains('avatar_b64 required')) {
    return isArabic
        ? 'تعذّر معالجة صورة المجموعة.'
        : 'Could not process the group photo.';
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
  if (text.contains('too many requests') || text.contains('retry_after_secs')) {
    final retryAfterSeconds = parseRetryAfterSecondsFromHttpErrorBody(text);
    if (retryAfterSeconds != null) {
      return isArabic
          ? 'محاولات كثيرة. أعد المحاولة بعد $retryAfterSeconds ثانية.'
          : 'Too many requests. Try again in ${retryAfterSeconds}s.';
    }
    return isArabic
        ? 'محاولات كثيرة. حاول لاحقًا.'
        : 'Too many requests. Try again later.';
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
  if (text.contains('device attestation unavailable')) {
    return isArabic
        ? 'تعذّر التحقق من هذا الجهاز.'
        : 'This device could not be verified.';
  }
  if (text.contains('attestation required')) {
    return isArabic
        ? 'مطلوب التحقق من الجهاز.'
        : 'Device verification required.';
  }
  if (text.contains('cannot redeem own invite')) {
    return isArabic
        ? 'لا يمكنك إضافة نفسك كجهة اتصال. امسح رمز QR لشخص آخر.'
        : 'You cannot add yourself as a contact. Scan another person\'s invite QR.';
  }
  if (text.contains('cannot add own shamell id')) {
    return isArabic
        ? 'لا يمكنك إضافة معرف SyrChat الخاص بك.'
        : 'You cannot add your own SyrChat ID.';
  }
  if (text.contains('invalid token')) {
    return isArabic ? 'رمز الدعوة غير صالح.' : 'Invalid invite token.';
  }
  if (text.contains('contact invite required')) {
    return isArabic
        ? 'إضافة جهة اتصال جديدة تتطلب رمز دعوة أو QR من الطرف الآخر.'
        : 'Adding a new contact requires an invite token or QR from the other person.';
  }
  if (text.contains('contact not found or not ready')) {
    return isArabic
        ? 'لم يتم العثور على معرّف SyrChat، أو أن جهة الاتصال لم تفتح الدردشة بعد.'
        : 'SyrChat ID not found, or this contact has not opened chat yet.';
  }
  if (text.contains('direct message too large')) {
    return isArabic
        ? 'الرسالة كبيرة جدًا للإرسال الآمن.'
        : 'Message is too large to send securely.';
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
  if (text.contains('invalid server url') ||
      text.contains('same-origin http') ||
      text.contains('only allows same-origin')) {
    return isArabic ? 'عنوان الخادم غير صالح.' : 'Invalid server URL.';
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
