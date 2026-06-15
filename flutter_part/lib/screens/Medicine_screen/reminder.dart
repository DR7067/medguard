import 'package:flutter/material.dart';

class Reminder {
  final String medicineName;
  final String type; // Tablet, Syrup, Capsule
  final String dosage; // e.g., "2 pills"
  final List<TimeOfDay> times; // times per day
  final DateTime startDate;
  final DateTime endDate;
  final String? notes;
  DateTime? nextDose;
  final bool isInterval;
  final int? intervalHours;
  final TimeOfDay? intervalStartTime;

  Reminder({
    required this.medicineName,
    required this.type,
    required this.dosage,
    required this.times,
    required this.startDate,
    required this.endDate,
    this.notes,
    this.nextDose,
    this.isInterval = false,
    this.intervalHours,
    this.intervalStartTime,
  });

  Map<String, dynamic> toJson() {
    return {
      'medicineName': medicineName,
      'type': type,
      'dosage': dosage,
      'times': times
          .map((time) => {'hour': time.hour, 'minute': time.minute})
          .toList(),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'notes': notes,
      'nextDose': nextDose?.toIso8601String(),
      'isInterval': isInterval,
      'intervalHours': intervalHours,
      'intervalStartTime': intervalStartTime == null
          ? null
          : {
              'hour': intervalStartTime!.hour,
              'minute': intervalStartTime!.minute,
            },
    };
  }

  factory Reminder.fromJson(Map<String, dynamic> json) {
    final timesJson = (json['times'] as List<dynamic>? ?? []);
    final intervalStart = json['intervalStartTime'];

    return Reminder(
      medicineName: json['medicineName'] as String? ?? '',
      type: json['type'] as String? ?? 'Tablet',
      dosage: json['dosage'] as String? ?? '',
      times: timesJson
          .map(
            (time) => TimeOfDay(
              hour: (time['hour'] as num?)?.toInt() ?? 0,
              minute: (time['minute'] as num?)?.toInt() ?? 0,
            ),
          )
          .toList(),
      startDate:
          DateTime.tryParse(json['startDate'] as String? ?? '') ??
          DateTime.now(),
      endDate:
          DateTime.tryParse(json['endDate'] as String? ?? '') ?? DateTime.now(),
      notes: json['notes'] as String?,
      nextDose: DateTime.tryParse(json['nextDose'] as String? ?? ''),
      isInterval: json['isInterval'] as bool? ?? false,
      intervalHours: (json['intervalHours'] as num?)?.toInt(),
      intervalStartTime: intervalStart is Map
          ? TimeOfDay(
              hour: (intervalStart['hour'] as num?)?.toInt() ?? 0,
              minute: (intervalStart['minute'] as num?)?.toInt() ?? 0,
            )
          : null,
    );
  }
}
