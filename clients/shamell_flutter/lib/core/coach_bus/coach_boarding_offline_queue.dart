import 'dart:convert';

import '../base_url.dart';
import '../offline_queue.dart';
import 'coach_platform_contracts.dart';

const String _coachBoardingOfflineTag = 'coach_boarding_record';

class CoachOfflineBoardingScan {
  final String queueId;
  final String tripId;
  final String ticketId;
  final CoachBoardingScanStatus scanStatus;
  final bool offlineCaptured;
  final String? deviceId;
  final String? note;
  final String idempotencyKey;
  final int createdAtEpochMs;
  final int retries;
  final int nextAttemptAtEpochMs;

  const CoachOfflineBoardingScan({
    required this.queueId,
    required this.tripId,
    required this.ticketId,
    required this.scanStatus,
    required this.offlineCaptured,
    required this.deviceId,
    required this.note,
    required this.idempotencyKey,
    required this.createdAtEpochMs,
    required this.retries,
    required this.nextAttemptAtEpochMs,
  });
}

String? _coachOfflineHeaderValue(Map<String, String> headers, String key) {
  final normalizedKey = key.trim().toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.trim().toLowerCase() == normalizedKey) {
      final value = entry.value.trim();
      if (value.isNotEmpty) return value;
    }
  }
  return null;
}

String _coachOfflineTripIdFromUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  if (uri == null) return '';
  final segments = uri.pathSegments;
  for (var i = 0; i < segments.length - 1; i++) {
    if (segments[i] == 'trips') {
      return segments[i + 1].trim();
    }
  }
  return '';
}

CoachOfflineBoardingScan? _coachOfflineBoardingScanFromTask(OfflineTask task) {
  if (task.tag != _coachBoardingOfflineTag) return null;
  try {
    final decoded = jsonDecode(task.body);
    if (decoded is! Map) return null;
    final tripId = _coachOfflineTripIdFromUrl(task.url);
    final ticketId = (decoded['ticket_id'] ?? '').toString().trim();
    final scanStatus = coachBoardingScanStatusFromWire(
      (decoded['scan_status'] ?? '').toString().trim(),
    );
    final offlineCaptured = decoded['offline_captured'];
    final deviceId = (decoded['device_id'] ?? '').toString().trim();
    final note = (decoded['note'] ?? '').toString().trim();
    final idempotencyKey =
        _coachOfflineHeaderValue(task.headers, 'Idempotency-Key') ?? '';
    if (tripId.isEmpty ||
        ticketId.isEmpty ||
        scanStatus == null ||
        offlineCaptured is! bool ||
        idempotencyKey.isEmpty) {
      return null;
    }
    return CoachOfflineBoardingScan(
      queueId: task.id,
      tripId: tripId,
      ticketId: ticketId,
      scanStatus: scanStatus,
      offlineCaptured: offlineCaptured,
      deviceId: deviceId.isEmpty ? null : deviceId,
      note: note.isEmpty ? null : note,
      idempotencyKey: idempotencyKey,
      createdAtEpochMs: task.createdAt,
      retries: task.retries,
      nextAttemptAtEpochMs: task.nextAt,
    );
  } catch (_) {
    return null;
  }
}

Future<void> initCoachBoardingOfflineQueue({
  required String baseUrl,
}) async {
  await OfflineQueue.init(baseUrlOverride: baseUrl);
}

Future<List<CoachOfflineBoardingScan>> loadPendingCoachBoardingScans({
  required String baseUrl,
  String? tripId,
}) async {
  await initCoachBoardingOfflineQueue(baseUrl: baseUrl);
  final normalizedTripId = (tripId ?? '').trim();
  final scans = OfflineQueue.pending(
    tag: _coachBoardingOfflineTag,
    baseUrlOverride: baseUrl,
  )
      .map(_coachOfflineBoardingScanFromTask)
      .whereType<CoachOfflineBoardingScan>();
  final filtered = normalizedTripId.isEmpty
      ? scans
      : scans.where((scan) => scan.tripId == normalizedTripId);
  final items = filtered.toList(growable: false);
  items.sort(
    (left, right) => right.createdAtEpochMs.compareTo(left.createdAtEpochMs),
  );
  return items;
}

Future<CoachOfflineBoardingScan> enqueuePendingCoachBoardingScan({
  required String baseUrl,
  required String tripId,
  required String ticketId,
  required CoachBoardingScanStatus scanStatus,
  required bool offlineCaptured,
  required String idempotencyKey,
  String? deviceId,
  String? note,
}) async {
  final uri = secureApiChildUri(
    baseUrl: baseUrl,
    pathSegments: <String>[
      'me',
      'coach',
      'crew',
      'trips',
      tripId,
      'boardings',
    ],
  );
  if (uri == null) {
    throw const FormatException('secure base URL required');
  }
  await initCoachBoardingOfflineQueue(baseUrl: baseUrl);
  final task = OfflineTask(
    id: idempotencyKey.trim(),
    method: 'POST',
    url: uri.toString(),
    headers: <String, String>{
      'Content-Type': 'application/json',
      'Idempotency-Key': idempotencyKey.trim(),
    },
    body: jsonEncode(<String, Object?>{
      'ticket_id': ticketId.trim(),
      'scan_status': coachBoardingScanStatusWireValue(scanStatus),
      'offline_captured': offlineCaptured,
      if ((deviceId ?? '').trim().isNotEmpty) 'device_id': deviceId!.trim(),
      if ((note ?? '').trim().isNotEmpty) 'note': note!.trim(),
    }),
    tag: _coachBoardingOfflineTag,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
  await OfflineQueue.enqueue(task, baseUrlOverride: baseUrl);
  return _coachOfflineBoardingScanFromTask(task)!;
}

Future<int> flushPendingCoachBoardingScans({
  required String baseUrl,
}) async {
  await initCoachBoardingOfflineQueue(baseUrl: baseUrl);
  return OfflineQueue.flushTag(
    _coachBoardingOfflineTag,
    baseUrlOverride: baseUrl,
  );
}
