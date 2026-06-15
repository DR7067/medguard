import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_part/services/account_session_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _databaseId = 'medguard-data';
  final FirebaseFirestore _db = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );

  Future<void> _ensureProfile(User user) async {
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
  }

  Future<User?> login(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user != null) {
      await _ensureProfile(user);
      await AccountSessionService().upsertFromUser(user);
    }
    return user;
  }

  // ==============================
  // GOOGLE SIGN IN (FIX ADDED)
  // ==============================
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final result = await _auth.signInWithCredential(credential);
      if (result.user != null) {
        await _ensureProfile(result.user!);
        await AccountSessionService().upsertFromUser(result.user!);
      }
      return result;
    } catch (e) {
      print("Google Sign-In Error: $e");
      return null;
    }
  }

  // ==============================
  // EMAIL PASSWORD RESET
  // ==============================
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    }
  }

  // ==============================
  // PHONE OTP SEND
  // ==============================
  Future<void> sendPhoneOTP({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (_) {},
      verificationFailed: (e) => onError(e.message ?? "Verification failed"),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  // ==============================
  // VERIFY OTP
  // ==============================
  Future<String?> verifyOTP({
    required String verificationId,
    required String otp,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp,
      );
      await _auth.signInWithCredential(credential);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    }
  }

  // ==============================
  // UPDATE PASSWORD
  // ==============================
  Future<String?> updatePassword(String newPassword) async {
    try {
      await _auth.currentUser!.updatePassword(newPassword);
      await _auth.signOut();
      return null;
    } catch (_) {
      return "Password update failed";
    }
  }

  Future<String?> linkPhoneNumber({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      await FirebaseAuth.instance.currentUser!.linkWithCredential(credential);

      return null;
    } on FirebaseAuthException catch (e) {
      return e.message;
    }
  }
}
