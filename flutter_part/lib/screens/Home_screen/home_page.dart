import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Home_screen/recent_activity_page.dart';
import 'package:flutter_part/screens/Home_screen/app_drawer.dart';
import 'package:flutter_part/screens/Medicine_screen/reminder_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_part/screens/Home_screen/activity_service.dart';
import 'package:flutter_part/screens/Home_screen/recent_activity.dart';
import 'package:flutter_part/screens/Document_screen/document_screen.dart';
import 'package:flutter_part/screens/Medicine_screen/add_medicine.dart';
import 'package:flutter_part/screens/Medicine_screen/add_reminder.dart';
import 'package:flutter_part/screens/Medicine_screen/medicine_list.dart';
import 'package:flutter_part/screens/Medicine_screen/medicine.dart';
import 'package:flutter_part/screens/Medicine_screen/reminder.dart';
import 'package:flutter_part/services/native_alarm_service.dart';
import 'package:flutter_part/services/reminder_alert_service.dart';
import 'package:flutter_part/main.dart';
import 'package:flutter_part/screens/Login_screen/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_part/services/firestore_sync.dart';
import 'package:flutter_part/services/care_context_service.dart';
import 'package:flutter_part/services/notification_service.dart';
import 'package:flutter_part/screens/Profile_screen/care_link_screen.dart';
import 'package:flutter_part/services/account_session_service.dart';

// Colors
const Color kPrimaryColor = Color(0xFF2F6FED);
const Color kPrimaryLightColor = Color(0xFF4B7BFF);
const Color kPrimaryDark = Color(0xFF1D4ED8);
const Color kBackgroundColor = Color(0xFFF3F4F6);
const String kReminderVoiceLanguageKey = 'reminder_voice_language';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _medicinesStorageKey = 'saved_medicines';
  static const String _remindersStorageKey = 'saved_reminders';

  int _currentIndex = 0;
  final List<Medicine> _medicines = [];
  final List<Reminder> _reminders = [];
  int _takenToday = 0;
  int _missedToday = 0;
  int _snoozedToday = 0;
  Map<String, DateTime> _snoozedUntilByReminder = <String, DateTime>{};
  late final VoidCallback _summaryListener;
  final FirestoreSync _firestoreSync = FirestoreSync();
  final CareContextService _careContextService = CareContextService();
  final AccountSessionService _accountSessionService = AccountSessionService();
  StreamSubscription<List<Map<String, dynamic>>>? _medicinesCloudSub;
  StreamSubscription<List<Map<String, dynamic>>>? _remindersCloudSub;
  bool _isApplyingRemoteMedicines = false;
  bool _isApplyingRemoteReminders = false;
  String? _activeRecipientUid;
  static const String _lastSyncedMedicineDocIdsKey = 'synced_medicine_doc_ids';
  static const String _lastSyncedReminderDocIdsKey = 'synced_reminder_doc_ids';
  static const String _databaseId = 'medguard-data';
  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _careEventSub;
  static const String _careEventLastSeenKey = 'care_event_last_seen_ms';
  String? _currentUserRole;

  double _rs(
    BuildContext context, {
    required double base,
    required double min,
    required double max,
  }) {
    final width = MediaQuery.of(context).size.width;
    final scaled = base * (width / 390);
    return scaled.clamp(min, max).toDouble();
  }

  String _scopedKey(String key) {
    final uid = _activeRecipientUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return '${key}_guest';
    return '${key}_$uid';
  }

  Future<User?> _waitForFirebaseUser() async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) return current;
    try {
      return await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  void _showSyncError(String message) {
    debugPrint(message);
    if (!mounted) return;
    final isPermissionDenied = message.contains('permission-denied');
    final hasUser = FirebaseAuth.instance.currentUser != null;
    if (isPermissionDenied && !hasUser) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _sanitizeIdPart(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  String _medicineDocId(Medicine medicine) {
    final expiry = medicine.expiryDate.toIso8601String().split('T').first;
    return 'med_${_sanitizeIdPart(medicine.name)}_${_sanitizeIdPart(medicine.type.name)}_${_sanitizeIdPart(expiry)}_${_sanitizeIdPart(medicine.tags)}';
  }

  Map<String, dynamic> _medicineToJson(Medicine medicine) {
    return medicine.toJson();
  }

  Medicine _medicineFromJson(Map<String, dynamic> json) {
    return Medicine.fromJson(json);
  }

  String _reminderDocId(Reminder reminder) {
    final times = reminder.times
        .map(
          (t) =>
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
        )
        .join('-');
    final start = reminder.startDate.toIso8601String().split('T').first;
    final end = reminder.endDate.toIso8601String().split('T').first;
    final intervalStart = reminder.intervalStartTime == null
        ? 'none'
        : '${reminder.intervalStartTime!.hour.toString().padLeft(2, '0')}:${reminder.intervalStartTime!.minute.toString().padLeft(2, '0')}';
    return 'rem_${_sanitizeIdPart(reminder.medicineName)}_${_sanitizeIdPart(reminder.dosage)}_${_sanitizeIdPart(start)}_${_sanitizeIdPart(end)}_${_sanitizeIdPart(times)}_${reminder.isInterval ? 'interval' : 'fixed'}_${reminder.intervalHours ?? 0}_${_sanitizeIdPart(intervalStart)}';
  }

  Map<String, dynamic> _reminderToJson(Reminder reminder) {
    return reminder.toJson();
  }

  Reminder _reminderFromJson(Map<String, dynamic> json) {
    return Reminder.fromJson(json);
  }

  Future<void> _saveMedicinesLocalOnly() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_medicines.map(_medicineToJson).toList());
    await prefs.setString(_scopedKey(_medicinesStorageKey), raw);
  }

  Future<void> _saveRemindersLocalOnly() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_reminders.map(_reminderToJson).toList());
    await prefs.setString(_scopedKey(_remindersStorageKey), raw);
    await _syncReminderAlarms(_reminders);
  }

  Future<void> _syncReminderAlarms(List<Reminder> reminders) async {
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == null) return;

      // Only the account owner should receive local reminder alarms.
      if (_activeRecipientUid != null && _activeRecipientUid != currentUid) {
        await NativeAlarmService.syncReminderAlarms([]);
        return;
      }

      await NativeAlarmService.syncReminderAlarms(reminders);
    } catch (e) {
      debugPrint('Alarm sync failed: $e');
    }
  }

  Future<void> _syncMedicinesToCloud() async {
    if (_isApplyingRemoteMedicines) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final recipientUid = _activeRecipientUid ?? user.uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final previousIds =
          (prefs.getStringList(_scopedKey(_lastSyncedMedicineDocIdsKey)) ??
                  <String>[])
              .toSet();
      final currentIds = <String>{};
      final snapshot = List<Medicine>.from(_medicines);
      for (final medicine in snapshot) {
        final docId = _medicineDocId(medicine);
        currentIds.add(docId);
        await _firestoreSync.upsertMedicine(
          recipientUid: recipientUid,
          docId: docId,
          data: _medicineToJson(medicine),
        );
      }
      final removedIds = previousIds.difference(currentIds);
      for (final docId in removedIds) {
        await _firestoreSync.softDeleteMedicine(
          recipientUid: recipientUid,
          docId: docId,
        );
      }
      await prefs.setStringList(
        _scopedKey(_lastSyncedMedicineDocIdsKey),
        currentIds.toList(),
      );
    } catch (e) {
      _showSyncError('Medicine cloud sync failed: $e');
    }
  }

  Future<void> _syncRemindersToCloud() async {
    if (_isApplyingRemoteReminders) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final recipientUid = _activeRecipientUid ?? user.uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final previousIds =
          (prefs.getStringList(_scopedKey(_lastSyncedReminderDocIdsKey)) ??
                  <String>[])
              .toSet();
      final currentIds = <String>{};
      final snapshot = List<Reminder>.from(_reminders);
      for (final reminder in snapshot) {
        final docId = _reminderDocId(reminder);
        currentIds.add(docId);
        await _firestoreSync.upsertReminder(
          recipientUid: recipientUid,
          docId: docId,
          data: _reminderToJson(reminder),
        );
      }
      final removedIds = previousIds.difference(currentIds);
      for (final docId in removedIds) {
        await _firestoreSync.softDeleteReminder(
          recipientUid: recipientUid,
          docId: docId,
        );
      }
      await prefs.setStringList(
        _scopedKey(_lastSyncedReminderDocIdsKey),
        currentIds.toList(),
      );
    } catch (e) {
      _showSyncError('Reminder cloud sync failed: $e');
    }
  }

  Future<void> _startCloudSyncListeners() async {
    await _medicinesCloudSub?.cancel();
    await _remindersCloudSub?.cancel();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final recipientUid = _activeRecipientUid ?? user.uid;

    _medicinesCloudSub = _firestoreSync
        .watchMedicines(recipientUid: recipientUid)
        .listen((docs) async {
          final incoming = docs.map((d) => _medicineFromJson(d)).toList();
          final incomingRaw = jsonEncode(
            incoming.map(_medicineToJson).toList(),
          );
          final currentRaw = jsonEncode(
            _medicines.map(_medicineToJson).toList(),
          );
          if (incomingRaw == currentRaw) return;

          _isApplyingRemoteMedicines = true;
          _medicines
            ..clear()
            ..addAll(incoming);
          if (mounted) setState(() {});
          await _saveMedicinesLocalOnly();
          _isApplyingRemoteMedicines = false;
        }, onError: (e) => _showSyncError('Medicine listener failed: $e'));

    _remindersCloudSub = _firestoreSync
        .watchReminders(recipientUid: recipientUid)
        .listen((docs) async {
          final incoming = docs.map((d) => _reminderFromJson(d)).toList();
          final incomingRaw = jsonEncode(
            incoming.map(_reminderToJson).toList(),
          );
          final currentRaw = jsonEncode(
            _reminders.map(_reminderToJson).toList(),
          );
          if (incomingRaw == currentRaw) return;

          _isApplyingRemoteReminders = true;
          _reminders
            ..clear()
            ..addAll(incoming);
          if (mounted) setState(() {});
          await _saveRemindersLocalOnly();
          _isApplyingRemoteReminders = false;
        }, onError: (e) => _showSyncError('Reminder listener failed: $e'));
  }

  Future<void> _initializeHomeData() async {
    final user = await _waitForFirebaseUser();
    if (user == null) {
      _showSyncError('No Firebase session. Please login again.');
      return;
    }

    await _ensureUserProfile(user);
    await _loadCurrentUserRole();

    final storedRecipient = await _careContextService.getActiveRecipientUid();
    if (_activeRecipientUid == null) {
      if (_currentUserRole == 'caregiver') {
        _activeRecipientUid = user.uid;
      } else {
        _activeRecipientUid = storedRecipient ?? user.uid;
      }
    }
    _activeRecipientUid = await _validateActiveRecipient(user.uid);
    await _careContextService.setActiveRecipientUid(_activeRecipientUid!);

    await _loadMedicines();
    await _loadReminders();

    if (_activeRecipientUid == user.uid) {
      try {
        await _firestoreSync.writeSyncPing(recipientUid: _activeRecipientUid!);
      } catch (e) {
        _showSyncError('Firestore ping failed: $e');
      }
    }

    await _syncMedicinesToCloud();
    await _syncRemindersToCloud();
    await _startCloudSyncListeners();
    await _startCareEventListenerIfCaregiver();
    await _loadTodaySummary();
  }

  Future<void> _ensureUserProfile(User user) async {
    try {
      final doc = await _db.collection('users').doc(user.uid).get();
      if (doc.exists) return;

      final email = user.email ?? '';
      final displayName = (user.displayName ?? '').trim();
      final fallbackName = displayName.isNotEmpty
          ? displayName
          : (email.isNotEmpty ? email.split('@').first : 'User');

      await _db.collection('users').doc(user.uid).set({
        'firstName': fallbackName,
        'lastName': '',
        'email': email,
        'role': 'caretaker',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('User profile ensure failed: $e');
      _showSyncError('User profile create failed: $e');
    }
  }

  Future<String> _validateActiveRecipient(String currentUid) async {
    final candidate = _activeRecipientUid ?? currentUid;
    if (candidate == currentUid) return currentUid;

    try {
      final link = await _db
          .collection('users')
          .doc(candidate)
          .collection('caregivers')
          .doc(currentUid)
          .get();
      if (link.exists) return candidate;
    } catch (_) {}

    return currentUid;
  }

  Future<void> _loadCurrentUserRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final data = await _loadUserProfile(uid) ?? {};
    _currentUserRole = data['role']?.toString().toLowerCase();
  }

  Future<void> _startCareEventListenerIfCaregiver() async {
    await _careEventSub?.cancel();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_currentUserRole != 'caregiver') return;

    final prefs = await SharedPreferences.getInstance();
    final lastSeenMs = prefs.getInt(_careEventLastSeenKey);
    final since = lastSeenMs == null
        ? Timestamp.fromDate(
            DateTime.now().subtract(const Duration(minutes: 1)),
          )
        : Timestamp.fromMillisecondsSinceEpoch(lastSeenMs);

    _careEventSub = _db
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('createdAt', isGreaterThan: since)
        .orderBy('createdAt')
        .snapshots()
        .listen((snapshot) async {
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final caretakerName =
                data['caretakerName']?.toString() ?? 'Caretaker';
            final action = data['action']?.toString() ?? 'updated';
            final medicine = data['medicineName']?.toString() ?? 'medicine';
            final dosage = data['dosage']?.toString() ?? '';

            final title = '$caretakerName $action medicine';
            final body = dosage.isEmpty ? medicine : '$medicine ($dosage)';
            await NotificationService.showNotification(
              title: title,
              body: body,
            );

            final createdAt = data['createdAt'] as Timestamp?;
            if (createdAt != null) {
              await prefs.setInt(
                _careEventLastSeenKey,
                createdAt.millisecondsSinceEpoch,
              );
            }
          }
        });
  }

  Future<Map<String, dynamic>?> _loadUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  Future<List<Map<String, dynamic>>> _loadCareRecipients() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return <Map<String, dynamic>>[];

    final links = await _db
        .collection('users')
        .doc(uid)
        .collection('care_recipients')
        .get();

    if (links.docs.isEmpty) return <Map<String, dynamic>>[];

    final recipients = <Map<String, dynamic>>[];
    for (final doc in links.docs) {
      final recipientUid = doc.id;
      final profile = await _loadUserProfile(recipientUid) ?? {};
      recipients.add({
        'uid': recipientUid,
        'name': '${profile['firstName'] ?? ''} ${profile['lastName'] ?? ''}'
            .trim(),
        'email': profile['email']?.toString() ?? '',
      });
    }
    return recipients;
  }

  Future<void> _switchActiveRecipient(String uid) async {
    await _careContextService.setActiveRecipientUid(uid);
    _activeRecipientUid = uid;
    await _initializeHomeData();
  }

  Future<List<StoredAccount>> _loadSavedAccounts() async {
    return _accountSessionService.getAccounts();
  }

  Future<void> _startAccountLogin({
    String? email,
    required bool isSwitch,
  }) async {
    await _accountSessionService.setPendingLoginContext(
      email: email,
      isSwitching: isSwitch,
    );
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pop(context);
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginScreen(initialEmail: email)),
      (route) => false,
    );
  }

  Future<void> _showVoiceLanguageSettings(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final languages = <String, String>{
      'English (India)': 'en-IN',
      'Hindi': 'hi-IN',
      'Marathi': 'mr-IN',
    };

    final selected = prefs.getString(kReminderVoiceLanguageKey) ?? 'en-IN';
    String tempSelected = selected;

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reminder Voice Language',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: tempSelected,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: languages.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.value,
                            child: Text(entry.key),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() => tempSelected = value);
                    },
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await prefs.setString(
                          kReminderVoiceLanguageKey,
                          tempSelected,
                        );
                        if (!sheetContext.mounted) return;
                        Navigator.pop(sheetContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Voice language saved')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    ActivityService.instance.loadActivities();
    _summaryListener = () {
      _loadTodaySummary();
    };
    ReminderAlertService.instance.summaryUpdates.addListener(_summaryListener);
    ReminderAlertService.instance.start(appNavigatorKey);
    _initializeHomeData();
  }

  @override
  void dispose() {
    ReminderAlertService.instance.summaryUpdates.removeListener(
      _summaryListener,
    );
    _medicinesCloudSub?.cancel();
    _remindersCloudSub?.cancel();
    _careEventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadTodaySummary() async {
    final summary = await ReminderAlertService.instance.getTodaySummary();
    final snoozedMap = await ReminderAlertService.instance
        .getTodaySnoozedUntilMap();
    if (!mounted) return;
    final nextTaken = summary['taken'] ?? 0;
    final nextMissed = summary['missed'] ?? 0;
    final nextSnoozed = summary['snoozed'] ?? 0;
    final changed =
        _takenToday != nextTaken ||
        _missedToday != nextMissed ||
        _snoozedToday != nextSnoozed ||
        _snoozedUntilByReminder.length != snoozedMap.length ||
        !_snoozedUntilByReminder.keys.every(
          (k) => _snoozedUntilByReminder[k] == snoozedMap[k],
        );

    if (!changed) return;

    setState(() {
      _takenToday = nextTaken;
      _missedToday = nextMissed;
      _snoozedToday = nextSnoozed;
      _snoozedUntilByReminder = snoozedMap;
    });
  }

  void _showProfileDropdown(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    final radius = _rs(context, base: 36, min: 28, max: 40);
    final nameSize = _rs(context, base: 18, min: 15, max: 20);
    final mailSize = _rs(context, base: 14, min: 12, max: 15);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: screenH < 700 ? 0.72 : 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                // --- Profile Header ---
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: radius,
                      backgroundColor: kPrimaryColor,
                      child: FutureBuilder<Map<String, dynamic>?>(
                        future: _loadUserProfile(
                          FirebaseAuth.instance.currentUser?.uid ?? '',
                        ),
                        builder: (context, snapshot) {
                          final data = snapshot.data ?? {};
                          final first = (data['firstName']?.toString() ?? 'U')
                              .trim();
                          final initial = first.isNotEmpty
                              ? first.substring(0, 1).toUpperCase()
                              : 'U';
                          return Text(
                            initial,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: radius * 0.78,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<Map<String, dynamic>?>(
                      future: _loadUserProfile(
                        FirebaseAuth.instance.currentUser?.uid ?? '',
                      ),
                      builder: (context, snapshot) {
                        final data = snapshot.data ?? {};
                        final name =
                            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'
                                .trim();
                        return Text(
                          name.isEmpty ? 'User' : name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: nameSize,
                            color: kPrimaryDark,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 2),
                    FutureBuilder<Map<String, dynamic>?>(
                      future: _loadUserProfile(
                        FirebaseAuth.instance.currentUser?.uid ?? '',
                      ),
                      builder: (context, snapshot) {
                        final data = snapshot.data ?? {};
                        final email = data['email']?.toString() ?? '';
                        return Text(
                          email,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: mailSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CareLinkScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.link),
                    label: const Text('Care Links'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor.withOpacity(0.12),
                      foregroundColor: kPrimaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showVoiceLanguageSettings(context),
                    icon: const Icon(Icons.record_voice_over),
                    label: const Text('Voice Language'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor.withOpacity(0.12),
                      foregroundColor: kPrimaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(height: 32),

                // --- Saved Accounts Section ---
                const Text(
                  'Saved Accounts',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<StoredAccount>>(
                  future: _loadSavedAccounts(),
                  builder: (context, snapshot) {
                    final accounts = snapshot.data ?? <StoredAccount>[];
                    if (accounts.isEmpty) {
                      return const Text(
                        'No saved accounts yet',
                        style: TextStyle(color: Colors.grey),
                      );
                    }

                    final currentUid = FirebaseAuth.instance.currentUser?.uid;
                    return Column(
                      children: accounts.map((account) {
                        final isCurrent = account.uid == currentUid;
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            onTap: isCurrent
                                ? null
                                : () => _startAccountLogin(
                                    email: account.email,
                                    isSwitch: true,
                                  ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: _rs(
                                context,
                                base: 14,
                                min: 10,
                                max: 16,
                              ),
                              vertical: 2,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: kPrimaryColor,
                              child: Text(
                                account.initials,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              account.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              account.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: isCurrent
                                ? const Icon(Icons.check, color: kPrimaryColor)
                                : IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.redAccent,
                                    ),
                                    onPressed: () async {
                                      await _accountSessionService
                                          .removeAccount(account.uid);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () =>
                        _startAccountLogin(email: null, isSwitch: false),
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Add Account'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor.withOpacity(0.12),
                      foregroundColor: kPrimaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(height: 32),

                // --- Linked Users Section ---
                const Text(
                  'Linked Users',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadCareRecipients(),
                  builder: (context, snapshot) {
                    final items = snapshot.data ?? <Map<String, dynamic>>[];
                    if (items.isEmpty) {
                      return const Text(
                        'No linked patients yet',
                        style: TextStyle(color: Colors.grey),
                      );
                    }
                    return Column(
                      children: items.map((item) {
                        final uid = item['uid']?.toString() ?? '';
                        final name = (item['name']?.toString() ?? '').trim();
                        final email = item['email']?.toString() ?? '';
                        final isPrimary = uid == _activeRecipientUid;
                        return _linkedUserCard(
                          name.isEmpty ? 'Patient' : name,
                          email,
                          isPrimary,
                          context,
                          onTap: () async {
                            Navigator.pop(context);
                            await _switchActiveRecipient(uid);
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Divider(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (!mounted) return;
                      Navigator.pop(context);
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Linked user card with Edit/Delete menu
  Widget _linkedUserCard(
    String name,
    String email,
    bool isPrimary,
    BuildContext context, {
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(
          horizontal: _rs(context, base: 14, min: 10, max: 16),
          vertical: 2,
        ),
        leading: CircleAvatar(
          backgroundColor: kPrimaryColor,
          child: Text(name[0], style: const TextStyle(color: Colors.white)),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: isPrimary
            ? const Icon(Icons.check, color: kPrimaryColor)
            : null,
      ),
    );
  }

  void _editLinkedUser(
    BuildContext context,
    String oldName,
    String oldEmail,
  ) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        final nameController = TextEditingController(text: oldName);
        final emailController = TextEditingController(text: oldEmail);
        return AlertDialog(
          title: const Text("Edit Linked User"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Name"),
              ),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: "Email"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx, {
                  'name': nameController.text,
                  'email': emailController.text,
                });
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );

    if (result != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Linked user updated")));
    }
  }

  void _deleteLinkedUser(BuildContext context, String name, String email) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Linked User"),
        content: Text("Are you sure you want to delete $name?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text("$name deleted")));
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMedicines() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey(_medicinesStorageKey));

    if (raw == null || raw.isEmpty) {
      if (mounted) {
        setState(() => _medicines.clear());
      }
      return;
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final loaded = decoded
          .map((item) => Medicine.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      if (!mounted) return;
      setState(() {
        _medicines
          ..clear()
          ..addAll(loaded);
      });
    } catch (_) {
      await prefs.remove(_scopedKey(_medicinesStorageKey));
    }
  }

  Future<void> _saveMedicines() async {
    await _saveMedicinesLocalOnly();
    await _syncMedicinesToCloud();
  }

  Future<void> _loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scopedKey(_remindersStorageKey));

    if (raw == null || raw.isEmpty) {
      await _syncReminderAlarms([]);
      if (mounted) {
        setState(() => _reminders.clear());
      }
      return;
    }

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final loaded = decoded
          .map((item) => Reminder.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      if (!mounted) return;
      setState(() {
        _reminders
          ..clear()
          ..addAll(loaded);
      });
      await _syncReminderAlarms(_reminders);
    } catch (_) {
      await prefs.remove(_scopedKey(_remindersStorageKey));
    }
  }

  Future<void> _saveReminders() async {
    await _saveRemindersLocalOnly();
    await _syncRemindersToCloud();
  }

  // ===================== MEDICINE HANDLERS =====================
  void _editMedicine(Medicine med, int index) {
    _showMedicineForm(existing: med, index: index);
  }

  void _deleteMedicine(int index) {
    final deleted = _medicines[index];
    setState(() {
      _medicines.removeAt(index);
    });
    _saveMedicines();
    ActivityService.instance.addActivity(
      RecentActivity(
        description: "Deleted medicine ${deleted.name}",
        timestamp: DateTime.now(),
        type: ActivityType.medicine,
      ),
    );
  }

  Future<void> _showMedicineForm({Medicine? existing, int? index}) async {
    final result = await Navigator.push<Medicine>(
      context,
      MaterialPageRoute(
        builder: (_) => AddMedicine(existingMedicine: existing),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      if (index != null) {
        _medicines[index] = result;
        ActivityService.instance.addActivity(
          RecentActivity(
            description: "Updated medicine ${result.name}",
            timestamp: DateTime.now(),
            type: ActivityType.medicine,
          ),
        );
      } else {
        _medicines.add(result);
        ActivityService.instance.addActivity(
          RecentActivity(
            description: "Added medicine ${result.name}",
            timestamp: DateTime.now(),
            type: ActivityType.medicine,
          ),
        );
      }
      _currentIndex = 1;
    });
    _saveMedicines();
  }

  // ===================== REMINDER HANDLERS =====================
  void _editReminder(Reminder r, int index) {
    _showReminderForm(existing: r, index: index);
  }

  Future<void> _deleteReminder(int index) async {
    final deleted = _reminders[index];
    setState(() {
      _reminders.removeAt(index);
    });
    await _saveReminders();
    await _syncReminderAlarms(_reminders);
    ActivityService.instance.addActivity(
      RecentActivity(
        description: "Deleted reminder for ${deleted.medicineName}",
        timestamp: DateTime.now(),
        type: ActivityType.reminder,
      ),
    );
  }

  Future<void> _showReminderForm({Reminder? existing, int? index}) async {
    final result = await Navigator.push<Reminder>(
      context,
      MaterialPageRoute(
        builder: (_) => AddReminderScreen(existingReminder: existing),
      ),
    );

    if (result == null) return;

    setState(() {
      if (index != null) {
        _reminders[index] = result;
        ActivityService.instance.addActivity(
          RecentActivity(
            description: "Updated reminder for ${result.medicineName}",
            timestamp: DateTime.now(),
            type: ActivityType.reminder,
          ),
        );
      } else {
        _reminders.add(result);
        ActivityService.instance.addActivity(
          RecentActivity(
            description: "Added reminder for ${result.medicineName}",
            timestamp: DateTime.now(),
            type: ActivityType.reminder,
          ),
        );
      }
      _currentIndex = 2;
    });
    await _saveReminders();
    await _syncReminderAlarms(_reminders);
  }

  Future<void> _reactivateReminder(int index, DateTime newDate) async {
    final old = _reminders[index];
    final updated = Reminder(
      medicineName: old.medicineName,
      type: old.type,
      dosage: old.dosage,
      times: old.times,
      startDate: old.startDate,
      endDate: newDate,
      notes: old.notes,
      isInterval: old.isInterval,
      intervalHours: old.intervalHours,
      intervalStartTime: old.intervalStartTime,
    );

    setState(() {
      _reminders[index] = updated;
    });

    await _saveReminders();
    await _syncReminderAlarms(_reminders);
  }

  // ===================== FLOATING ACTION BAR =====================
  void _showBarOptions(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black26, // semi-transparent background
      builder: (_) => Stack(
        children: [
          Positioned(
            bottom: 100, // float above the FAB
            left: 24,
            right: 24,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _actionItem(
                      icon: Icons.medication,
                      label: "Add Medicine",
                      color: Colors.blueAccent,
                      onTap: () async {
                        Navigator.pop(context);
                        final newMed = await Navigator.push<Medicine>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddMedicine(),
                          ),
                        );
                        if (!mounted) return;
                        if (newMed != null) {
                          setState(() {
                            _medicines.add(newMed);
                            _currentIndex = 1;
                          });
                          await _saveMedicines();
                          ActivityService.instance.addActivity(
                            RecentActivity(
                              description: "Added medicine ${newMed.name}",
                              timestamp: DateTime.now(),
                              type: ActivityType.medicine,
                            ),
                          );
                        }
                      },
                    ),
                    _actionItem(
                      icon: Icons.alarm_add,
                      label: "Add Reminder",
                      color: Colors.blueAccent,
                      onTap: () async {
                        Navigator.pop(context);
                        final newReminder = await Navigator.push<Reminder>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddReminderScreen(),
                          ),
                        );
                        if (!mounted) return;
                        if (newReminder != null) {
                          setState(() {
                            _reminders.add(newReminder);
                            _currentIndex = 2;
                          });
                          await _saveReminders();
                          ActivityService.instance.addActivity(
                            RecentActivity(
                              description:
                                  "Added reminder for ${newReminder.medicineName}",
                              timestamp: DateTime.now(),
                              type: ActivityType.reminder,
                            ),
                          );
                        }
                      },
                    ),
                    _actionItem(
                      icon: Icons.insert_drive_file,
                      label: "Add Document",
                      color: Colors.blueAccent,
                      onTap: () async {
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DocumentScreen(),
                          ),
                        );
                        setState(() {
                          _currentIndex = 3;
                        });
                        ActivityService.instance.addActivity(
                          RecentActivity(
                            description: "Viewed documents",
                            timestamp: DateTime.now(),
                            type: ActivityType.document,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final iconBox = _rs(context, base: 54, min: 44, max: 60);
    final iconSize = _rs(context, base: 30, min: 24, max: 32);
    final labelSize = _rs(context, base: 13, min: 11, max: 14);
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(40),
          child: Container(
            width: iconBox,
            height: iconBox,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(fontSize: labelSize)),
      ],
    );
  }

  // ===================== TODAY'S PROGRESS WIDGET =====================
  Widget _todaysProgress() {
    final ringSize = _rs(context, base: 120, min: 95, max: 136);
    final percentSize = _rs(context, base: 26, min: 20, max: 30);
    final int taken = _takenToday;
    final int missed = _missedToday;
    final int snoozed = _snoozedToday;

    final total = taken + missed + snoozed;
    final double progress = total == 0 ? 0 : taken / total;

    Widget miniStat(String label, int value, Color color) {
      return Column(
        children: [
          Text(
            "$value",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Today's Progress",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kPrimaryColor,
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: ringSize,
                height: ringSize,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: _rs(context, base: 10, min: 8, max: 12),
                  backgroundColor: Colors.grey.shade200,
                  color: kPrimaryColor,
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "${(progress * 100).toInt()}%",
                    style: TextStyle(
                      fontSize: percentSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    "Adherence",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: miniStat("Taken", taken, Colors.green)),
            Expanded(child: miniStat("Missed", missed, Colors.red)),
            Expanded(child: miniStat("Snoozed", snoozed, Colors.orange)),
          ],
        ),
      ],
    );
  }

  // ===================== UPCOMING REMINDERS =====================
  Widget _upcomingReminders() {
    final now = DateTime.now();
    final upcoming =
        _reminders
            .map((r) {
              final next = _nextReminderTime(r, now);
              if (next == null) return null;
              final isToday =
                  next.year == now.year &&
                  next.month == now.month &&
                  next.day == now.day;
              if (!isToday) return null;
              return MapEntry(r, next);
            })
            .whereType<MapEntry<Reminder, DateTime>>()
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    if (upcoming.isEmpty) {
      return const Text(
        "No upcoming reminders",
        style: TextStyle(color: Colors.grey),
      );
    }

    Color getStatusColor(Duration diff) {
      if (diff.inMinutes <= 30) return Colors.red;
      if (diff.inHours < 4) return Colors.orange;
      return Colors.green;
    }

    String getStatusText(Duration diff) {
      if (diff.inMinutes <= 30) return "Coming Soon";
      if (diff.inHours < 4) return "Upcoming";
      return "Scheduled";
    }

    IconData getStatusIcon(Duration diff) {
      if (diff.inMinutes <= 30) return Icons.alarm_rounded; // urgent
      if (diff.inHours < 4) return Icons.schedule; // soon
      return Icons.medication; // scheduled
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Upcoming Reminder",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: kPrimaryColor,
          ),
        ),
        const SizedBox(height: 12),
        ...upcoming.take(3).map((entry) {
          final Reminder r = entry.key;
          final DateTime nextTime = entry.value;
          final diff = nextTime.difference(now);
          final statusColor = getStatusColor(diff);
          final statusText = getStatusText(diff);
          final statusIcon = getStatusIcon(diff);

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: _rs(context, base: 80, min: 64, max: 88),
                  height: _rs(context, base: 80, min: 64, max: 88),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        statusIcon,
                        color: Colors.white,
                        size: _rs(context, base: 28, min: 22, max: 32),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: _rs(context, base: 12, min: 10, max: 14),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.medicineName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: _rs(context, base: 16, min: 13, max: 17),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Dosage: ${r.dosage}",
                          style: TextStyle(
                            fontSize: _rs(context, base: 14, min: 12, max: 16),
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "At ${nextTime.hour.toString().padLeft(2, '0')}:${nextTime.minute.toString().padLeft(2, '0')}",
                          style: TextStyle(
                            fontSize: _rs(context, base: 14, min: 12, max: 16),
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  DateTime? _nextReminderTime(Reminder reminder, DateTime now) {
    final snoozeKey = ReminderAlertService.instance.reminderIdentity(reminder);
    final snoozedUntil = _snoozedUntilByReminder[snoozeKey];
    if (snoozedUntil != null && snoozedUntil.isAfter(now)) {
      return snoozedUntil;
    }

    final startDay = DateTime(
      reminder.startDate.year,
      reminder.startDate.month,
      reminder.startDate.day,
    );
    final endDay = DateTime(
      reminder.endDate.year,
      reminder.endDate.month,
      reminder.endDate.day,
      23,
      59,
      59,
    );

    if (now.isAfter(endDay)) return null;

    if (reminder.isInterval &&
        reminder.intervalStartTime != null &&
        (reminder.intervalHours ?? 0) > 0) {
      final intervalHours = reminder.intervalHours!;
      var candidate = DateTime(
        reminder.startDate.year,
        reminder.startDate.month,
        reminder.startDate.day,
        reminder.intervalStartTime!.hour,
        reminder.intervalStartTime!.minute,
      );
      while (!candidate.isAfter(endDay)) {
        if (candidate.isAfter(now)) return candidate;
        candidate = candidate.add(Duration(hours: intervalHours));
      }
      return null;
    }

    if (reminder.times.isEmpty) return null;
    final sortedTimes = [...reminder.times]
      ..sort(
        (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
      );

    var day = DateTime(now.year, now.month, now.day);
    if (day.isBefore(startDay)) day = startDay;

    while (!day.isAfter(endDay)) {
      for (final t in sortedTimes) {
        final candidate = DateTime(
          day.year,
          day.month,
          day.day,
          t.hour,
          t.minute,
        );
        if (candidate.isAfter(now)) return candidate;
      }
      day = day.add(const Duration(days: 1));
    }

    return null;
  }

  // ===================== RECENT ACTIVITIES =====================
  Widget _recentActivities() {
    final previewCount = 3;
    final activities = ActivityService.instance.activities.value;
    final previewActivities = activities.take(previewCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Recent Activities",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (activities.length > previewCount)
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RecentActivitiesPage(),
                    ),
                  );
                },
                child: const Text(
                  "View All",
                  style: TextStyle(
                    color: kPrimaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: previewActivities.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final RecentActivity activity = previewActivities[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(_activityIcon(activity.type), color: kPrimaryColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      activity.description,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  Text(
                    "${activity.timestamp.hour.toString().padLeft(2, '0')}:${activity.timestamp.minute.toString().padLeft(2, '0')}",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  IconData _activityIcon(ActivityType type) {
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

  // ===================== BUILD =====================
  @override
  Widget build(BuildContext context) {
    final horizontalPadding = _rs(context, base: 16, min: 12, max: 22);
    final appBarHeight = _rs(context, base: 120, min: 98, max: 132);
    final safeTop = MediaQuery.of(context).padding.top;
    final greetingSize = _rs(context, base: 20, min: 16, max: 22);
    final subtitleSize = _rs(context, base: 14, min: 12, max: 15);
    final navHeight = _rs(context, base: 62, min: 58, max: 70);
    final fabGap = _rs(context, base: 40, min: 34, max: 46);
    final List<Widget> screens = [
      ValueListenableBuilder<int>(
        valueListenable: ReminderAlertService.instance.summaryUpdates,
        builder: (context, _, __) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _loadTodaySummary();
            }
          });
          return SingleChildScrollView(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _todaysProgress(),
                const SizedBox(height: 24),
                _upcomingReminders(),
                const SizedBox(height: 24),
                _recentActivities(),
              ],
            ),
          );
        },
      ),
      MedicineList(
        medicines: _medicines,
        reminders: _reminders,
        onEdit: _editMedicine,
        onDelete: _deleteMedicine,
        onChanged: _saveMedicines,
      ),
      ReminderPage(
        reminders: _reminders,
        onEdit: _editReminder,
        onDelete: _deleteReminder,
        onReactivate: _reactivateReminder,
      ),
      const DocumentScreen(),
    ];

    return Scaffold(
      backgroundColor: kBackgroundColor,
      drawer: const AppDrawer(),
      appBar: _currentIndex == 0
          ? AppBar(
              automaticallyImplyLeading: false,
              elevation: 0,
              backgroundColor: Colors.transparent,
              toolbarHeight: appBarHeight,
              flexibleSpace: Container(
                padding: EdgeInsets.fromLTRB(
                  _rs(context, base: 24, min: 16, max: 28),
                  safeTop + _rs(context, base: 10, min: 8, max: 14),
                  _rs(context, base: 18, min: 12, max: 24),
                  _rs(context, base: 16, min: 10, max: 20),
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kPrimaryColor, kPrimaryLightColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryDark.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // LEFT SIDE (Greeting + Summary)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FutureBuilder<Map<String, dynamic>?>(
                            future: _loadUserProfile(
                              FirebaseAuth.instance.currentUser?.uid ?? '',
                            ),
                            builder: (context, snapshot) {
                              final data = snapshot.data ?? {};
                              final first =
                                  (data['firstName']?.toString() ?? '').trim();
                              final authUser =
                                  FirebaseAuth.instance.currentUser;
                              final fallback =
                                  (authUser?.displayName ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? authUser!.displayName!.trim()
                                  : (authUser?.email?.split('@').first ??
                                        'User');
                              final displayName = first.isEmpty
                                  ? fallback
                                  : first;
                              return Text(
                                "Hello, $displayName",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  fontSize: greetingSize,
                                ),
                              );
                            },
                          ),
                          SizedBox(
                            height: _rs(context, base: 6, min: 4, max: 8),
                          ),
                          Text(
                            "Stay consistent with your medicines",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: subtitleSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // RIGHT SIDE (Profile)
                    InkWell(
                      onTap: () {
                        _showProfileDropdown(context);
                      },
                      borderRadius: BorderRadius.circular(28),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: kPrimaryDark.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: _rs(context, base: 22, min: 18, max: 24),
                          backgroundColor: kPrimaryColor,
                          child: Icon(
                            Icons.person,
                            color: Colors.white,
                            size: _rs(context, base: 22, min: 18, max: 24),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: screens[_currentIndex],
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [kPrimaryColor, kPrimaryLightColor],
          ),
          boxShadow: [
            BoxShadow(
              color: kPrimaryColor.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton(
          backgroundColor: Colors.transparent,
          elevation: 0,
          onPressed: () => _showBarOptions(context),
          child: const Icon(Icons.add, size: 32),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 10,
        child: SizedBox(
          height: navHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(child: _navItem(Icons.home, "Home", 0)),
              Expanded(child: _navItem(Icons.description, "Documents", 3)),
              SizedBox(width: fabGap),
              Expanded(child: _navItem(Icons.medication, "Medicine", 1)),
              Expanded(child: _navItem(Icons.alarm, "Reminders", 2)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final bool selected = _currentIndex == index;
    final iconSize = _rs(context, base: 24, min: 20, max: 26);
    final fontSize = _rs(context, base: 11, min: 10, max: 12);

    return InkWell(
      onTap: () {
        setState(() => _currentIndex = index);
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: iconSize,
            color: selected ? kPrimaryColor : Colors.grey,
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              color: selected ? kPrimaryColor : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
