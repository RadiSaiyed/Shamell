import 'dart:convert';

import 'chat/chat_service.dart';

String _extractDeviceBindingDetail(String? rawBody) {
  final text = (rawBody ?? '').trim();
  if (text.isEmpty) return '';
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      final detail = (decoded['detail'] ?? '').toString().trim();
      if (detail.isNotEmpty) return detail;
    }
  } catch (_) {}
  return text;
}

bool shamellContainsCriticalDeviceBindingDetail(String? rawDetail) {
  final detail = _extractDeviceBindingDetail(rawDetail).toLowerCase();
  return detail.contains('device_id mismatch') ||
      detail.contains('client_device_id mismatch');
}

bool shamellContainsCriticalAccountSessionDetail(String? rawDetail) {
  final detail = _extractDeviceBindingDetail(rawDetail).toLowerCase();
  return shamellContainsCriticalDeviceBindingDetail(detail) ||
      detail.contains('auth session required') ||
      detail.contains('authentication required') ||
      detail.contains('unauthorized');
}

bool shamellIsCriticalDeviceBindingDriftError(Object error) {
  if (error is ChatHttpException) {
    return shamellIsCriticalDeviceBindingMismatch(
      statusCode: error.statusCode,
      rawBody: error.body,
    );
  }
  return shamellContainsCriticalDeviceBindingDetail(error.toString());
}

bool shamellIsCriticalAccountSessionError(Object error) {
  if (error is ChatHttpException) {
    return shamellIsCriticalAccountSessionHttpFailure(
      statusCode: error.statusCode,
      rawBody: error.body,
    );
  }
  return shamellContainsCriticalAccountSessionDetail(error.toString());
}

bool shamellIsCriticalAccountSessionHttpFailure({
  required int statusCode,
  String? rawBody,
}) {
  if (statusCode == 401) return true;
  if (statusCode < 400) return false;
  return shamellContainsCriticalAccountSessionDetail(rawBody);
}

bool shamellIsCriticalDeviceBindingMismatch({
  required int statusCode,
  String? rawBody,
}) {
  if (statusCode < 400) return false;
  return shamellContainsCriticalDeviceBindingDetail(rawBody);
}
