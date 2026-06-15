enum ActivityType { medicine, reminder, document, profile, general }

class RecentActivity {
  final String description;
  final DateTime timestamp;
  final ActivityType type;

  RecentActivity({
    required this.description,
    required this.timestamp,
    this.type = ActivityType.general,
  });
}