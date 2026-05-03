import 'analytics_event.dart';

abstract class AnalyticsService {
  Future<void> track(AnalyticsEvent event);
}
