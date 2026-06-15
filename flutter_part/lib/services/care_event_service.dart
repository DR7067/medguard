import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class CareEventService {
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

  Future<void> notifyCaregivers({
    required String action,
    required String medicineName,
    required String dosage,
    DateTime? occurredAt,
  }) async {
    final caretakerUid = _uid;

    final profile = await _getProfile(caretakerUid) ?? {};
    final caretakerName =
        '${profile['firstName'] ?? ''} ${profile['lastName'] ?? ''}'.trim();
    final resolvedCaretaker =
        caretakerName.isEmpty ? 'Caretaker' : caretakerName;
    final title = '$resolvedCaretaker $action medicine';
    final body = dosage.isEmpty ? medicineName : '$medicineName ($dosage)';

    final now = occurredAt ?? DateTime.now();
    final payload = {
      'caretakerUid': caretakerUid,
      'caretakerName': resolvedCaretaker,
      'action': action,
      'medicineName': medicineName,
      'dosage': dosage,
      'title': title,
      'body': body,
      'createdAt': Timestamp.fromDate(now),
      'serverCreatedAt': FieldValue.serverTimestamp(),
      'actorUid': caretakerUid,
    };

    await _db
        .collection('users')
        .doc(caretakerUid)
        .collection('care_events')
        .add(payload);
  }
}
