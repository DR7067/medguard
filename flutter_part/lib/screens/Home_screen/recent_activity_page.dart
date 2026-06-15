import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Home_screen/activity_service.dart';
import 'package:flutter_part/screens/Home_screen/recent_activity.dart';

const Color kPrimaryColor = Color(0xFF2F6FED);
const Color kPrimaryLightColor = Color(0xFF4B7BFF);
const Color kPrimaryDark = Color(0xFF1D4ED8);
const Color kBackgroundColor = Color(0xFFF3F4F6);

class RecentActivitiesPage extends StatelessWidget {
  const RecentActivitiesPage({super.key});

  // ------------------ Responsive Scale Helper ------------------
  double _rs(
    BuildContext context, {
    required double base,
    double min = 12,
    double max = 24,
  }) {
    final width = MediaQuery.of(context).size.width;
    final scale = width / 375; // base width reference (iPhone 11)
    final scaled = base * scale;
    return scaled.clamp(min, max);
  }

  IconData _iconForType(ActivityType type) {
    switch (type) {
      case ActivityType.medicine:
        return Icons.medication;
      case ActivityType.reminder:
        return Icons.alarm;
      case ActivityType.document:
        return Icons.description;
      case ActivityType.profile:
        return Icons.person;
      case ActivityType.general:
        return Icons.history;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "All Recent Activities",
          style: TextStyle(fontSize: _rs(context, base: 18, min: 16, max: 22)),
        ),
        backgroundColor: kPrimaryColor,
      ),
      body: ValueListenableBuilder<List<RecentActivity>>(
        valueListenable: ActivityService.instance.activities,
        builder: (context, activities, _) {
          return ListView.separated(
            padding: EdgeInsets.all(_rs(context, base: 16, min: 12, max: 20)),
            itemCount: activities.length,
            separatorBuilder: (_, __) =>
                SizedBox(height: _rs(context, base: 12, min: 8, max: 16)),
            itemBuilder: (context, index) {
              final activity = activities[index];
              return Container(
                padding: EdgeInsets.all(
                  _rs(context, base: 12, min: 8, max: 16),
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(
                    _rs(context, base: 12, min: 8, max: 16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: _rs(context, base: 5, min: 3, max: 8),
                      offset: Offset(0, _rs(context, base: 2, min: 1, max: 4)),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      _iconForType(activity.type),
                      color: kPrimaryColor,
                      size: _rs(context, base: 24, min: 20, max: 32),
                    ),
                    SizedBox(width: _rs(context, base: 12, min: 8, max: 16)),
                    Expanded(
                      child: Text(
                        activity.description,
                        style: TextStyle(
                          fontSize: _rs(context, base: 14, min: 12, max: 18),
                        ),
                      ),
                    ),
                    Text(
                      "${activity.timestamp.hour.toString().padLeft(2, '0')}:${activity.timestamp.minute.toString().padLeft(2, '0')}",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: _rs(context, base: 12, min: 10, max: 14),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
