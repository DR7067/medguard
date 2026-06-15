import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StoredAccount {
  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final int lastUsedAtMs;

  const StoredAccount({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.lastUsedAtMs,
  });

  String get title {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      return displayName!.trim();
    }
    if (email != null && email!.trim().isNotEmpty) {
      return email!.trim();
    }
    return 'MedGuard User';
  }

  String get subtitle {
    if (email != null && email!.trim().isNotEmpty) {
      return email!.trim();
    }
    return 'No email linked';
  }

  String get initials {
    final source = title.trim();
    if (source.isEmpty) return 'M';

    final parts = source.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final list = parts.toList();
    if (list.isEmpty) return 'M';
    if (list.length == 1) {
      return list.first.substring(0, 1).toUpperCase();
    }

    return (list.first.substring(0, 1) + list.last.substring(0, 1))
        .toUpperCase();
  }

  StoredAccount copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    int? lastUsedAtMs,
  }) {
    return StoredAccount(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      lastUsedAtMs: lastUsedAtMs ?? this.lastUsedAtMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'lastUsedAtMs': lastUsedAtMs,
    };
  }

  factory StoredAccount.fromJson(Map<String, dynamic> json) {
    return StoredAccount(
      uid: (json['uid'] ?? '').toString(),
      email: json['email']?.toString(),
      displayName: json['displayName']?.toString(),
      photoUrl: json['photoUrl']?.toString(),
      lastUsedAtMs: (json['lastUsedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class AccountSessionService {
  static const String _accountsKey = 'saved_accounts_v1';
  static const String _activeUidKey = 'active_account_uid_v1';
  static const String _pendingEmailKey = 'pending_account_email_v1';
  static const String _pendingSwitchModeKey = 'pending_account_switch_v1';

  Future<List<StoredAccount>> getAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null || raw.isEmpty) return <StoredAccount>[];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final parsed = decoded
          .map((e) => StoredAccount.fromJson(Map<String, dynamic>.from(e)))
          .where((a) => a.uid.trim().isNotEmpty)
          .toList();
      parsed.sort((a, b) => b.lastUsedAtMs.compareTo(a.lastUsedAtMs));
      return parsed;
    } catch (_) {
      return <StoredAccount>[];
    }
  }

  Future<void> _saveAccounts(List<StoredAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(accounts.map((a) => a.toJson()).toList());
    await prefs.setString(_accountsKey, payload);
  }

  Future<void> upsertFromUser(User user) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final accounts = await getAccounts();
    final index = accounts.indexWhere((a) => a.uid == user.uid);

    final updated = StoredAccount(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoUrl: user.photoURL,
      lastUsedAtMs: now,
    );

    if (index == -1) {
      accounts.add(updated);
    } else {
      accounts[index] = accounts[index].copyWith(
        email: user.email ?? accounts[index].email,
        displayName: user.displayName ?? accounts[index].displayName,
        photoUrl: user.photoURL ?? accounts[index].photoUrl,
        lastUsedAtMs: now,
      );
    }

    await _saveAccounts(accounts);
    await setActiveAccount(user.uid);
  }

  Future<void> setActiveAccount(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeUidKey, uid);
  }

  Future<String?> getActiveUid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_activeUidKey);
  }

  Future<void> removeAccount(String uid) async {
    final accounts = await getAccounts();
    accounts.removeWhere((a) => a.uid == uid);
    await _saveAccounts(accounts);

    final prefs = await SharedPreferences.getInstance();
    final activeUid = prefs.getString(_activeUidKey);
    if (activeUid == uid) {
      await prefs.remove(_activeUidKey);
    }
  }

  Future<void> setPendingLoginContext({
    required String? email,
    required bool isSwitching,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (email == null || email.trim().isEmpty) {
      await prefs.remove(_pendingEmailKey);
    } else {
      await prefs.setString(_pendingEmailKey, email.trim());
    }
    await prefs.setBool(_pendingSwitchModeKey, isSwitching);
  }

  Future<String?> consumePendingEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_pendingEmailKey);
    await prefs.remove(_pendingEmailKey);
    return value;
  }

  Future<bool> consumePendingSwitchMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_pendingSwitchModeKey) ?? false;
    await prefs.remove(_pendingSwitchModeKey);
    return value;
  }
}
