import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Medicine_screen/reminder.dart';

class ActivityItem {
  final String title;
  final String subtitle;
  final DateTime time;

  ActivityItem({
    required this.title,
    required this.subtitle,
    required this.time,
  });
}

class UpcomingReminder {
  final Reminder reminder;
  final DateTime time;

  UpcomingReminder({required this.reminder, required this.time});
}

UpcomingReminder? getNextUpcomingReminder(List<Reminder> reminders) {
  DateTime now = DateTime.now();
  UpcomingReminder? nearest;

  for (var reminder in reminders) {
    if (reminder.endDate.isBefore(now)) {
      continue;
    }

    final DateTime startDate = DateTime(
      reminder.startDate.year,
      reminder.startDate.month,
      reminder.startDate.day,
    );
    final DateTime endDate = DateTime(
      reminder.endDate.year,
      reminder.endDate.month,
      reminder.endDate.day,
      23,
      59,
      59,
    );

    for (int dayOffset = 0; dayOffset <= 1; dayOffset++) {
      final DateTime day = DateTime(now.year, now.month, now.day + dayOffset);
      if (day.isBefore(startDate) || day.isAfter(endDate)) {
        continue;
      }

      for (var time in reminder.times) {
        final scheduled = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        );

        if (scheduled.isAfter(now)) {
          if (nearest == null || scheduled.isBefore(nearest.time)) {
            nearest = UpcomingReminder(reminder: reminder, time: scheduled);
          }
        }
      }
    }
  }

  return nearest;
}

String formatExactTime(DateTime time) {
  final hour = time.hour > 12 ? time.hour - 12 : time.hour;
  final minute = time.minute.toString().padLeft(2, '0');
  final period = time.hour >= 12 ? "PM" : "AM";
  return "$hour:$minute $period";
}

Color getUrgencyColor(DateTime next) {
  Duration diff = next.difference(DateTime.now());

  if (diff.isNegative) {
    return Colors.red.shade700;
  } else if (diff.inMinutes <= 15) {
    return Colors.red;
  } else if (diff.inHours < 1) {
    return Colors.orange;
  } else {
    return Colors.blue;
  }
}

String formatTimeRemaining(DateTime next) {
  Duration diff = next.difference(DateTime.now());

  if (diff.isNegative) {
    return "Missed Dose";
  }

  if (diff.inMinutes <= 15) {
    return "Due Soon";
  }

  int hours = diff.inHours;
  int minutes = diff.inMinutes.remainder(60);

  if (hours > 0) {
    return "Next in $hours hr $minutes min";
  } else {
    return "Next in $minutes min";
  }
}
