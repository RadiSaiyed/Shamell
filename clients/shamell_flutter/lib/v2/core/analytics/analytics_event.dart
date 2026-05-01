class AnalyticsEvent {
  final String name;
  final DateTime timestamp;
  final Map<String, Object?> properties;

  const AnalyticsEvent({
    required this.name,
    required this.timestamp,
    required this.properties,
  });
}
