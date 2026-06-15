import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class FirestoreSync {
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

  CollectionReference<Map<String, dynamic>> _medicinesRefFor(
    String recipientUid,
  ) =>
      _db.collection('users').doc(recipientUid).collection('medicines');

  CollectionReference<Map<String, dynamic>> _remindersRefFor(
    String recipientUid,
  ) =>
      _db.collection('users').doc(recipientUid).collection('reminders');

  Future<void> upsertMedicine({
    required String recipientUid,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    await _medicinesRefFor(recipientUid).doc(docId).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    }, SetOptions(merge: true));
  }

  Future<void> softDeleteMedicine({
    required String recipientUid,
    required String docId,
  }) async {
    await _medicinesRefFor(recipientUid).doc(docId).set({
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> upsertReminder({
    required String recipientUid,
    required String docId,
    required Map<String, dynamic> data,
  }) async {
    await _remindersRefFor(recipientUid).doc(docId).set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
      'isDeleted': false,
    }, SetOptions(merge: true));
  }

  Future<void> softDeleteReminder({
    required String recipientUid,
    required String docId,
  }) async {
    await _remindersRefFor(recipientUid).doc(docId).set({
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }


  Future<void> writeSyncPing({required String recipientUid}) async {
    await _db.collection('users').doc(recipientUid).set({
      'lastPingAt': FieldValue.serverTimestamp(),
      'databaseId': _databaseId,
      'lastSyncActorUid': _uid,
    }, SetOptions(merge: true));
  }

  Stream<List<Map<String, dynamic>>> watchMedicines({
    required String recipientUid,
  }) {
    return _medicinesRefFor(recipientUid).snapshots().map((snapshot) {
      return snapshot.docs
          .where((doc) => (doc.data()['isDeleted'] == true) == false)
          .map((doc) => {'docId': doc.id, ...doc.data()})
          .toList();
    });
  }

  Stream<List<Map<String, dynamic>>> watchReminders({
    required String recipientUid,
  }) {
    return _remindersRefFor(recipientUid).snapshots().map((snapshot) {
      return snapshot.docs
          .where((doc) => (doc.data()['isDeleted'] == true) == false)
          .map((doc) => {'docId': doc.id, ...doc.data()})
          .toList();
    });
  }
}
