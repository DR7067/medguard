import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Home_screen/recent_activity.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ActivityService {
  ActivityService._();
  static final ActivityService instance = ActivityService._();
  static const String _storageKey = 'recent_activities';
  static const int _maxActivities = 50;

  final ValueNotifier<List<RecentActivity>> activities =
      ValueNotifier<List<RecentActivity>>([]);
  bool _loaded = false;
  String? _scopeUid;

  String _scopedKey() {
    final uid = _scopeUid;
    if (uid == null || uid.isEmpty) return '${_storageKey}_guest';
    return '${_storageKey}_$uid';
  }

  Future<void> setScopeUid(String? uid) async {
    if (_scopeUid == uid && _loaded) return;
    _scopeUid = uid;
    _loaded = false;
    activities.value = [];
    await loadActivities();
  }

  Future<void> loadActivities() async {
    if (_loaded) return;
    _loaded = true;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey());
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      activities.value = decoded
          .map((item) => _fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      activities.value = [];
    }
  }

  void addActivity(RecentActivity activity) {
    final updated = [activity, ...activities.value];
    if (updated.length > _maxActivities) {
      updated.removeRange(_maxActivities, updated.length);
    }
    activities.value = updated;
    _saveActivities();
  }

  Future<void> _saveActivities() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(activities.value.map(_toJson).toList());
    await prefs.setString(_scopedKey(), raw);
  }

  Map<String, dynamic> _toJson(RecentActivity activity) {
    return {
      'description': activity.description,
      'timestamp': activity.timestamp.toIso8601String(),
      'type': activity.type.name,
    };
  }

  RecentActivity _fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? '').toString().toLowerCase();
    final type = ActivityType.values.firstWhere(
      (item) => item.name.toLowerCase() == rawType,
      orElse: () => ActivityType.general,
    );

    return RecentActivity(
      description: (json['description'] ?? '').toString(),
      timestamp:
          DateTime.tryParse((json['timestamp'] ?? '').toString()) ??
          DateTime.now(),
      type: type,
    );
  }
}
