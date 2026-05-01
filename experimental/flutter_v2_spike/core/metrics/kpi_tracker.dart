import '../analytics/analytics_event.dart';
import '../analytics/analytics_service.dart';
import '../analytics/v2_event_catalog.dart';

class KpiTracker {
  final AnalyticsService analytics;

  DateTime? _activationStartedAt;
  bool _activationCompleted = false;

  KpiTracker({required this.analytics});

  Future<void> markActivationStarted({
    required String source,
    required String userRole,
  }) async {
    _activationStartedAt ??= DateTime.now();
    await analytics.track(
      AnalyticsEvent(
        name: V2EventCatalog.activationStarted,
        timestamp: DateTime.now(),
        properties: <String, Object?>{
          'source': source,
          'user_role': userRole,
        },
      ),
    );
  }

  Future<void> markFirstSuccess({required String flow}) async {
    if (_activationCompleted) {
      return;
    }
    final started = _activationStartedAt ?? DateTime.now();
    final elapsedMs = DateTime.now().difference(started).inMilliseconds;
    _activationCompleted = true;
    await analytics.track(
      AnalyticsEvent(
        name: V2EventCatalog.activationCompleted,
        timestamp: DateTime.now(),
        properties: <String, Object?>{
          'first_flow': flow,
          'elapsed_ms': elapsedMs,
        },
      ),
    );
  }
}
