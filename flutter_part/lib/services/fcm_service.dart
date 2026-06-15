import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FirebaseFirestore _db =
      FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'medguard-data',
      );
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    _messaging.onTokenRefresh.listen((token) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        debugPrint('FCM token refreshed: $token');
        await _saveTokenForUser(user.uid, token);
      }
    });

    FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) return;
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('FCM token: $token');
        await _saveTokenForUser(user.uid, token);
      }
    });
  }

  static Future<void> _saveTokenForUser(String uid, String token) async {
    final deviceId = await _getDeviceId();
    await _db.collection('users').doc(uid).collection('devices').doc(deviceId).set(
      {
        'fcmToken': token,
        'platform': Platform.operatingSystem,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('device_id');
    if (existing != null && existing.isNotEmpty) return existing;
    final newId = _randomId();
    await prefs.setString('device_id', newId);
    return newId;
  }

  static String _randomId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static void _handleForegroundMessage(RemoteMessage message) {
    final title =
        message.notification?.title ?? message.data['title'] ?? 'MEDGuard';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    if (body.isEmpty) return;
    NotificationService.showNotification(title: title, body: body);
  }
}
