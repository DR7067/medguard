import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class CareLinkService {
  static const String _databaseId = 'medguard-data';
  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );

  String get _uid {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('No authenticated user');
    }
    return user.uid;
  }

  Future<Map<String, dynamic>?> _getProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  String _randomCode() {
    final rng = Random.secure();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<String> createInviteCode() async {
    final profile = await _getProfile(_uid) ?? {};
    final code = _randomCode();
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    await _db.collection('invites').doc(code).set({
      'code': code,
      'caretakerUid': _uid,
      'caretakerName': profile['firstName'] ?? profile['name'] ?? 'Caretaker',
      'createdAt': Timestamp.fromDate(now),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'usedBy': null,
    });

    return code;
  }

  Future<String?> acceptInviteCode(String code) async {
    final snap = await _db.collection('invites').doc(code).get();
    if (!snap.exists) return 'Invalid code';
    final data = snap.data() ?? {};

    final usedBy = data['usedBy'];
    if (usedBy != null) return 'Code already used';

    final expiresAt = data['expiresAt'] as Timestamp?;
    if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
      return 'Code expired';
    }

    final caretakerUid = data['caretakerUid']?.toString();
    if (caretakerUid == null || caretakerUid.isEmpty) {
      return 'Invalid caretaker';
    }

    // Link both ways: caregiver sees caretaker, caretaker lists caregiver
    try {
      await _db
          .collection('users')
          .doc(_uid)
          .collection('care_recipients')
          .doc(caretakerUid)
          .set({
        'caretakerUid': caretakerUid,
        'linkedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      return 'Link failed (care_recipients): ${e.code}';
    }

    try {
      await _db
          .collection('users')
          .doc(caretakerUid)
          .collection('caregivers')
          .doc(_uid)
          .set({
        'caregiverUid': _uid,
        'linkedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      return 'Link failed (caregivers): ${e.code}';
    }

    try {
      await _db.collection('invites').doc(code).set({
        'usedBy': _uid,
        'usedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      return 'Link failed (invite update): ${e.code}';
    }

    return null;
  }
}
