import 'package:flutter/services.dart';

import '../screens/Medicine_screen/reminder.dart';

class NativeAlarmService {
  static const MethodChannel _channel = MethodChannel(
    'medguard/alarm_scheduler',
  );

  static Future<void> syncReminderAlarms(List<Reminder> reminders) async {
    final now = DateTime.now();
    final alarms = <Map<String, dynamic>>[];

    for (final reminder in reminders) {
      var day = DateTime(
        reminder.startDate.year,
        reminder.startDate.month,
        reminder.startDate.day,
      );
      final end = DateTime(
        reminder.endDate.year,
        reminder.endDate.month,
        reminder.endDate.day,
      );

      while (!day.isAfter(end)) {
        for (final time in reminder.times) {
          final trigger = DateTime(
            day.year,
            day.month,
            day.day,
            time.hour,
            time.minute,
          );
          if (trigger.isAfter(now)) {
            final key =
                '${reminder.medicineName}|${reminder.dosage}|${day.year}-${day.month}-${day.day}|${time.hour}:${time.minute}';
            alarms.add({
              'id': _stableId(key),
              'triggerAtMillis': trigger.millisecondsSinceEpoch,
              'medicineName': reminder.medicineName,
              'dosage': reminder.dosage,
            });
          }
        }
        day = day.add(const Duration(days: 1));
      }
    }

    await _channel.invokeMethod('replaceReminderAlarms', {'alarms': alarms});
  }

  static int _stableId(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash & 0x7fffffff;
  }
}
