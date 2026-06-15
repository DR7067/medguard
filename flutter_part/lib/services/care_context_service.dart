import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CareContextService {
  static const String _activeRecipientKey = 'active_care_recipient_uid';

  String _scopedKey() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return _activeRecipientKey;
    return '${_activeRecipientKey}_$uid';
  }

  Future<void> setActiveRecipientUid(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedKey(), uid);
  }

  Future<String?> getActiveRecipientUid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_scopedKey());
  }

  Future<void> clearActiveRecipient() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scopedKey());
  }
}
