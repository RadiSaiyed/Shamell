import 'analytics_event.dart';
import 'analytics_service.dart';
import 'v2_event_catalog.dart';

class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  Future<void> track(AnalyticsEvent event) async {
    V2EventCatalog.validate(
      name: event.name,
      properties: event.properties,
    );
  }
}
