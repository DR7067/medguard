import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/Medicine_screen/reminder.dart';
import '../screens/Medicine_screen/reminder_alert_screen.dart';
import '../services/care_event_service.dart';

class DueReminderItem {
  final Reminder reminder;
  final TimeOfDay time;
  final DateTime triggerDate;

  DueReminderItem({
    required this.reminder,
    required this.time,
    required this.triggerDate,
  });

  String get uniqueKey {
    final y = triggerDate.year;
    final m = triggerDate.month.toString().padLeft(2, '0');
    final d = triggerDate.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '${reminder.medicineName}|$y-$m-$d|$hh:$mm';
  }
}

class ReminderAlertService {
  ReminderAlertService._();

  static final ReminderAlertService instance = ReminderAlertService._();
  final ValueNotifier<int> takenUpdates = ValueNotifier<int>(0);
  final ValueNotifier<int> summaryUpdates = ValueNotifier<int>(0);

  static const String _remindersStorageKey = 'saved_reminders';
  static const String _stateStorageKey = 'reminder_summary_state';
  String? _activeRecipientUid;

  String _scopedRemindersKey() {
    final uid = _activeRecipientUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return '${_remindersStorageKey}_guest';
    }
    return '${_remindersStorageKey}_$uid';
  }

  String _scopedStateKey() {
    final uid = _activeRecipientUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return '${_stateStorageKey}_guest';
    }
    return '${_stateStorageKey}_$uid';
  }

  Future<void> setActiveRecipientUid(String? uid) async {
    if (_activeRecipientUid == uid) return;
    _activeRecipientUid = uid;
    await _loadState();
    summaryUpdates.value = summaryUpdates.value + 1;
  }

  GlobalKey<NavigatorState>? _navigatorKey;
  Timer? _timer;
  bool _started = false;
  bool _isShowing = false;
  String? _activeDayKey;
  final Set<String> _shownKeysForDay = <String>{};
  final Map<String, int> _snoozeCounts = <String, int>{};
  final Map<String, DateTime> _snoozedUntilByReminder = <String, DateTime>{};
  final Set<String> _takenMedicineKeysForDay = <String>{};
  int _takenCountForDay = 0;
  final CareEventService _careEventService = CareEventService();
  bool _stateLoaded = false;

  void start(GlobalKey<NavigatorState> navigatorKey) {
    if (_started) return;
    _started = true;
    _navigatorKey = navigatorKey;

    _tick();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  void _resetDailyStateIfNeeded(DateTime now) {
    final dayKey = _dayKey(now);
    if (_activeDayKey != dayKey) {
      _activeDayKey = dayKey;
      _shownKeysForDay.clear();
      _snoozeCounts.clear();
      _snoozedUntilByReminder.clear();
      _takenMedicineKeysForDay.clear();
      _takenCountForDay = 0;
      _saveState();
      summaryUpdates.value = summaryUpdates.value + 1;
    }
  }

  Future<void> _loadState() async {
    _stateLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedStateKey());
    if (raw == null || raw.isEmpty) {
      _activeDayKey = null;
      _shownKeysForDay.clear();
      _snoozeCounts.clear();
      _snoozedUntilByReminder.clear();
      _takenMedicineKeysForDay.clear();
      _takenCountForDay = 0;
      return;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _activeDayKey = decoded['dayKey']?.toString();
      _shownKeysForDay
        ..clear()
        ..addAll(
          (decoded['shownKeys'] as List<dynamic>? ?? const [])
              .map((e) => e.toString()),
        );
      _snoozeCounts
        ..clear()
        ..addAll(
          (decoded['snoozeCounts'] as Map? ?? const {})
              .map((key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0)),
        );
      _snoozedUntilByReminder
        ..clear()
        ..addAll(
          (decoded['snoozedUntil'] as Map? ?? const {})
              .map((key, value) => MapEntry(
                    key.toString(),
                    DateTime.tryParse(value.toString()) ?? DateTime.now(),
                  )),
        );
      _takenMedicineKeysForDay
        ..clear()
        ..addAll(
          (decoded['takenKeys'] as List<dynamic>? ?? const [])
              .map((e) => e.toString()),
        );
      _takenCountForDay = (decoded['takenCount'] as num?)?.toInt() ?? 0;
    } catch (_) {
      _activeDayKey = null;
      _shownKeysForDay.clear();
      _snoozeCounts.clear();
      _snoozedUntilByReminder.clear();
      _takenMedicineKeysForDay.clear();
      _takenCountForDay = 0;
    }
  }

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'dayKey': _activeDayKey,
      'shownKeys': _shownKeysForDay.toList(),
      'snoozeCounts': _snoozeCounts,
      'snoozedUntil': _snoozedUntilByReminder.map(
        (key, value) => MapEntry(key, value.toIso8601String()),
      ),
      'takenKeys': _takenMedicineKeysForDay.toList(),
      'takenCount': _takenCountForDay,
    };
    await prefs.setString(_scopedStateKey(), jsonEncode(payload));
  }

  bool _isOwnerScope() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) return false;
    if (_activeRecipientUid == null) return true;
    return _activeRecipientUid == currentUid;
  }

  bool isTakenToday(String medicineName) {
    _resetDailyStateIfNeeded(DateTime.now());
    return _takenMedicineKeysForDay.contains(medicineName.trim().toLowerCase());
  }

  String reminderIdentity(Reminder reminder) {
    return '${reminder.medicineName.trim().toLowerCase()}|'
        '${reminder.dosage.trim().toLowerCase()}|'
        '${reminder.type.trim().toLowerCase()}';
  }

  Future<Map<String, DateTime>> getTodaySnoozedUntilMap() async {
    _resetDailyStateIfNeeded(DateTime.now());
    return Map<String, DateTime>.from(_snoozedUntilByReminder);
  }

  Map<String, dynamic> _reminderToJson(Reminder reminder) {
    return {
      'medicineName': reminder.medicineName,
      'type': reminder.type,
      'dosage': reminder.dosage,
      'times': reminder.times
          .map((t) => {'hour': t.hour, 'minute': t.minute})
          .toList(),
      'startDate': reminder.startDate.toIso8601String(),
      'endDate': reminder.endDate.toIso8601String(),
      'notes': reminder.notes,
      'nextDose': reminder.nextDose?.toIso8601String(),
      'isInterval': reminder.isInterval,
      'intervalHours': reminder.intervalHours,
      'intervalStartTime': reminder.intervalStartTime == null
          ? null
          : {
              'hour': reminder.intervalStartTime!.hour,
              'minute': reminder.intervalStartTime!.minute,
            },
    };
  }

  Reminder _reminderFromJson(Map<String, dynamic> json) {
    final timesJson = (json['times'] as List<dynamic>? ?? const []);
    final intervalStart = json['intervalStartTime'];

    return Reminder(
      medicineName: (json['medicineName'] ?? '').toString(),
      type: (json['type'] ?? 'Tablet').toString(),
      dosage: (json['dosage'] ?? '').toString(),
      times: timesJson.map((time) {
        final map = Map<String, dynamic>.from(time as Map);
        return TimeOfDay(
          hour: (map['hour'] as num?)?.toInt() ?? 0,
          minute: (map['minute'] as num?)?.toInt() ?? 0,
        );
      }).toList(),
      startDate:
          DateTime.tryParse((json['startDate'] ?? '').toString()) ??
          DateTime.now(),
      endDate:
          DateTime.tryParse((json['endDate'] ?? '').toString()) ??
          DateTime.now(),
      notes: json['notes']?.toString(),
      nextDose: DateTime.tryParse((json['nextDose'] ?? '').toString()),
      isInterval: json['isInterval'] == true,
      intervalHours: (json['intervalHours'] as num?)?.toInt(),
      intervalStartTime: intervalStart is Map
          ? TimeOfDay(
              hour: (intervalStart['hour'] as num?)?.toInt() ?? 0,
              minute: (intervalStart['minute'] as num?)?.toInt() ?? 0,
            )
          : null,
    );
  }

  DateTime? nextDoseAfter(Reminder reminder, DateTime after) {
    if (reminder.isInterval &&
        reminder.intervalStartTime != null &&
        (reminder.intervalHours ?? 0) > 0) {
      final endOfRange = DateTime(
        reminder.endDate.year,
        reminder.endDate.month,
        reminder.endDate.day,
        23,
        59,
        59,
      );
      var candidate = DateTime(
        reminder.startDate.year,
        reminder.startDate.month,
        reminder.startDate.day,
        reminder.intervalStartTime!.hour,
        reminder.intervalStartTime!.minute,
      );
      while (!candidate.isAfter(endOfRange)) {
        if (candidate.isAfter(after)) return candidate;
        candidate = candidate.add(Duration(hours: reminder.intervalHours!));
      }
      return null;
    }

    if (reminder.times.isEmpty) return null;

    final sortedTimes = [...reminder.times]
      ..sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
      );

    final startDay = DateTime(
      reminder.startDate.year,
      reminder.startDate.month,
      reminder.startDate.day,
    );
    final endDay = DateTime(
      reminder.endDate.year,
      reminder.endDate.month,
      reminder.endDate.day,
    );

    var day = DateTime(after.year, after.month, after.day);
    if (day.isBefore(startDay)) day = startDay;

    while (!day.isAfter(endDay)) {
      for (final t in sortedTimes) {
        final candidate = DateTime(day.year, day.month, day.day, t.hour, t.minute);
        if (candidate.isAfter(after)) return candidate;
      }
      day = day.add(const Duration(days: 1));
    }
    return null;
  }

  Future<void> updateSavedRemindersAfterTaken(List<DueReminderItem> dueItems) async {
    if (dueItems.isEmpty) return;
    _resetDailyStateIfNeeded(DateTime.now());

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedRemindersKey());
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final reminders = decoded
          .map((item) => _reminderFromJson(Map<String, dynamic>.from(item)))
          .toList();

      bool changed = false;
      for (final due in dueItems) {
        final idx = reminders.indexWhere((r) {
          return r.medicineName.trim().toLowerCase() ==
                  due.reminder.medicineName.trim().toLowerCase() &&
              r.dosage.trim().toLowerCase() == due.reminder.dosage.trim().toLowerCase();
        });
        if (idx == -1) continue;
        reminders[idx].nextDose = nextDoseAfter(reminders[idx], DateTime.now());
        _takenMedicineKeysForDay.add(reminders[idx].medicineName.trim().toLowerCase());
        changed = true;
      }

      if (changed) {
        await prefs.setString(
          _scopedRemindersKey(),
          jsonEncode(reminders.map(_reminderToJson).toList()),
        );
        _takenCountForDay += dueItems.length;
        await _saveState();
        takenUpdates.value = takenUpdates.value + 1;
        summaryUpdates.value = summaryUpdates.value + 1;
      }
    } catch (_) {}
  }

  Future<Map<String, int>> getTodaySummary() async {
    _resetDailyStateIfNeeded(DateTime.now());
    return <String, int>{
      'taken': _takenCountForDay,
      'missed': 0,
      'snoozed': _snoozedUntilByReminder.length,
    };
  }

  Future<void> _showAlertForItems(List<DueReminderItem> items) async {
    if (!_isOwnerScope()) return;
    if (_isShowing || items.isEmpty) return;

    final navigator = _navigatorKey?.currentState;
    if (navigator == null || navigator.overlay == null) return;

    _isShowing = true;
    String? result;
    try {
      result = await navigator.push<String>(
        MaterialPageRoute(
          builder: (_) => ReminderAlertScreen(dueItems: items),
          fullscreenDialog: true,
        ),
      );
    } finally {
      _isShowing = false;
    }

    // Handle result for snoozed items
    if (result == 'snooze') {
      for (final item in items) {
        final key = item.uniqueKey;
        final count = (_snoozeCounts[key] ?? 0) + 1;
        _snoozeCounts[key] = count;
        _snoozedUntilByReminder[reminderIdentity(item.reminder)] =
            DateTime.now().add(const Duration(minutes: 10));
        await _careEventService.notifyCaregivers(
          action: 'snoozed',
          medicineName: item.reminder.medicineName,
          dosage: item.reminder.dosage,
          occurredAt: DateTime.now(),
        );
        await _saveState();
        if (count < 3) {
          Timer(const Duration(minutes: 10), () {
            _showAlertForItems([item]);
          });
        }
      }
      summaryUpdates.value = summaryUpdates.value + 1;
    } else if (result == 'taken') {
      for (final item in items) {
        _snoozeCounts.remove(item.uniqueKey);
        _snoozedUntilByReminder.remove(reminderIdentity(item.reminder));
        _takenMedicineKeysForDay.add(item.reminder.medicineName.trim().toLowerCase());
        await _careEventService.notifyCaregivers(
          action: 'taken',
          medicineName: item.reminder.medicineName,
          dosage: item.reminder.dosage,
          occurredAt: DateTime.now(),
        );
      }
      _takenCountForDay += items.length;
      await _saveState();
      takenUpdates.value = takenUpdates.value + 1;
      summaryUpdates.value = summaryUpdates.value + 1;
    }
  }

  Future<void> _tick() async {
    if (!_isOwnerScope()) return;
    if (_isShowing) return;

    final now = DateTime.now();
    _resetDailyStateIfNeeded(now);

    final dueItems = await _loadDueItems(now);
    final filteredItems = dueItems
        .where((item) => (_snoozeCounts[item.uniqueKey] ?? 0) < 3)
        .toList();
    if (filteredItems.isEmpty) return;

    final navigator = _navigatorKey?.currentState;
    if (navigator == null || navigator.overlay == null) return;

    for (final item in filteredItems) {
      _shownKeysForDay.add(item.uniqueKey);
    }

    _isShowing = true;
    String? result;
    try {
      result = await navigator.push<String>(
        MaterialPageRoute(
          builder: (_) => ReminderAlertScreen(dueItems: filteredItems),
          fullscreenDialog: true,
        ),
      );
    } finally {
      _isShowing = false;
    }

    // Handle result
    if (result == 'snooze') {
      for (final item in filteredItems) {
        final key = item.uniqueKey;
        final count = (_snoozeCounts[key] ?? 0) + 1;
        _snoozeCounts[key] = count;
        _snoozedUntilByReminder[reminderIdentity(item.reminder)] =
            DateTime.now().add(const Duration(minutes: 10));
        await _careEventService.notifyCaregivers(
          action: 'snoozed',
          medicineName: item.reminder.medicineName,
          dosage: item.reminder.dosage,
          occurredAt: DateTime.now(),
        );
        await _saveState();
        if (count < 3) {
          Timer(const Duration(minutes: 10), () {
            _showAlertForItems([item]);
          });
        }
      }
      summaryUpdates.value = summaryUpdates.value + 1;
    } else if (result == 'taken') {
      for (final item in filteredItems) {
        _snoozeCounts.remove(item.uniqueKey);
        _snoozedUntilByReminder.remove(reminderIdentity(item.reminder));
        _takenMedicineKeysForDay.add(item.reminder.medicineName.trim().toLowerCase());
        await _careEventService.notifyCaregivers(
          action: 'taken',
          medicineName: item.reminder.medicineName,
          dosage: item.reminder.dosage,
          occurredAt: DateTime.now(),
        );
      }
      _takenCountForDay += filteredItems.length;
      await _saveState();
      takenUpdates.value = takenUpdates.value + 1;
      summaryUpdates.value = summaryUpdates.value + 1;
    }
  }

  Future<List<DueReminderItem>> _loadDueItems(DateTime now) async {
    if (!_stateLoaded) {
      await _loadState();
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedRemindersKey());
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final reminders = decoded
          .map((item) => _reminderFromJson(Map<String, dynamic>.from(item)))
          .toList();

      final due = <DueReminderItem>[];
      for (final reminder in reminders) {
        if (!_isWithinReminderDateRange(now, reminder)) continue;

        for (final time in reminder.times) {
          if (time.hour == now.hour && time.minute == now.minute) {
            final item = DueReminderItem(
              reminder: reminder,
              time: time,
              triggerDate: DateTime(now.year, now.month, now.day),
            );
            if (!_shownKeysForDay.contains(item.uniqueKey)) {
              due.add(item);
            }
          }
        }
      }
      return due;
    } catch (_) {
      return const [];
    }
  }

  bool _isWithinReminderDateRange(DateTime now, Reminder reminder) {
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      reminder.startDate.year,
      reminder.startDate.month,
      reminder.startDate.day,
    );
    final end = DateTime(
      reminder.endDate.year,
      reminder.endDate.month,
      reminder.endDate.day,
    );

    return !today.isBefore(start) && !today.isAfter(end);
  }
}
