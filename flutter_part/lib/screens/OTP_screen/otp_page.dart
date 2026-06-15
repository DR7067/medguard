import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_part/screens/ForgotPass_screen/reset_pass_screen.dart';
import 'package:flutter_part/screens/Home_Screen/home_page.dart';
import 'package:flutter_part/services/account_session_service.dart';
import 'package:sms_autofill/sms_autofill.dart';

/// Colors
const Color kPrimaryColor = Color(0xFF1565C0);
const Color kPrimaryLightColor = Color(0xFF42A5F5);
const Color kBackgroundColor = Color(0xFFF4F8FB);
const Color kTextColor = Color(0xFF1A1A1A);

enum OtpPurpose { login, signup, resetPass }

class OtpPage extends StatefulWidget {
  final String identifier;
  final String verificationId;
  final int? forceResendingToken;
  final OtpPurpose purpose;
  final bool linkPhoneOnSuccess;

  const OtpPage({
    super.key,
    required this.identifier,
    required this.verificationId,
    this.forceResendingToken,
    required this.purpose,
    this.linkPhoneOnSuccess = false,
  });

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  static const String _databaseId = 'medguard-data';
  final AccountSessionService _accountSessionService = AccountSessionService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );
  int _secondsRemaining = 30;
  bool _canResend = false;
  Timer? _timer;
  String otp = "";
  bool _isVerifying = false;
  bool _isResending = false;
  late String _verificationId;
  int? _resendToken;

  @override
  void initState() {
    super.initState();
    startTimer();
    _verificationId = widget.verificationId;
    _resendToken = widget.forceResendingToken;

    /// Listen for incoming OTP automatically
    SmsAutoFill().listenForCode();
  }

  void startTimer() {
    _secondsRemaining = 30;
    _canResend = false;
    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        setState(() => _canResend = true);
        _timer?.cancel();
      }
    });
  }

  Future<void> verifyOtp() async {
    if (otp.length != 6) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter valid 6 digit OTP")));
      return;
    }

    setState(() => _isVerifying = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId,
        smsCode: otp,
      );

      await _handleVerifiedCredential(credential);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("OTP Verified Successfully")),
      );

      // REDIRECT BASED ON PURPOSE
      if (widget.purpose == OtpPurpose.login ||
          widget.purpose == OtpPurpose.signup) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } else if (widget.purpose == OtpPurpose.resetPass) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ResetPassScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "OTP verification failed")),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _handleVerifiedCredential(PhoneAuthCredential credential) async {
    if (widget.purpose == OtpPurpose.resetPass) {
      await FirebaseAuth.instance.signInWithCredential(credential);
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Please sign in with your email first.',
      );
    }

    if (widget.linkPhoneOnSuccess) {
      await currentUser.linkWithCredential(credential);
    } else {
      await currentUser.reauthenticateWithCredential(credential);
    }

    await currentUser.reload();
    final refreshedUser = FirebaseAuth.instance.currentUser;
    if (refreshedUser == null) return;

    await _firestore.collection('users').doc(refreshedUser.uid).set({
      'email': refreshedUser.email,
      'phone': refreshedUser.phoneNumber ?? widget.identifier,
      'phoneVerified': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _accountSessionService.upsertFromUser(refreshedUser);
  }

  Future<void> resendOtp() async {
    if (!_canResend || _isResending) return;

    setState(() => _isResending = true);
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: widget.identifier,
        forceResendingToken: _resendToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (_) {},
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? "Failed to resend OTP")),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          _verificationId = verificationId;
          _resendToken = resendToken;
          if (!mounted) return;
          startTimer();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("OTP Resent")));
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isResending = false);
      }
    }
  }

  Widget floatingCircle(double top, double left, double size, Color color) {
    return Positioned(
      top: top,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.15),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    SmsAutoFill().unregisterListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Size size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Stack(
        children: [
          /// Floating circles
          floatingCircle(80, 20, 110, kPrimaryColor),
          floatingCircle(220, size.width * 0.7, 80, kPrimaryLightColor),
          floatingCircle(420, 120, 130, kPrimaryColor),
          floatingCircle(540, size.width * 0.6, 70, kPrimaryLightColor),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Back button
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 30,
                      color: kTextColor,
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// Title
                  const Text(
                    "OTP Verification",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: kTextColor,
                    ),
                  ),

                  const SizedBox(height: 6),

                  /// Subtitle
                  Text(
                    "Enter the OTP sent to ${widget.identifier}",
                    style: const TextStyle(fontSize: 15, color: Colors.black54),
                  ),

                  /// Center card
                  Expanded(
                    child: Center(
                      child: Container(
                        width: size.width * 0.9,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 25,
                          vertical: 40,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(25),
                          boxShadow: [
                            BoxShadow(
                              color: kPrimaryColor.withOpacity(0.1),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            /// OTP Field
                            PinFieldAutoFill(
                              codeLength: 6,
                              currentCode: otp,
                              decoration: BoxLooseDecoration(
                                strokeColorBuilder: const FixedColorBuilder(
                                  kPrimaryColor,
                                ),
                                gapSpace: 10,
                              ),
                              onCodeChanged: (code) {
                                if (code != null) {
                                  setState(() {
                                    otp = code;
                                  });
                                }
                              },
                              onCodeSubmitted: (code) {
                                otp = code;
                                verifyOtp();
                              },
                            ),

                            const SizedBox(height: 30),

                            /// Verify button
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton(
                                onPressed: _isVerifying ? null : verifyOtp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(25),
                                  ),
                                  elevation: 4,
                                ),
                                child: _isVerifying
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.6,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Text(
                                        "Verify OTP",
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            /// Timer
                            Text(
                              _canResend
                                  ? "Didn't receive OTP?"
                                  : "Resend OTP in $_secondsRemaining seconds",
                              style: const TextStyle(color: Colors.grey),
                            ),

                            /// Resend
                            TextButton(
                              onPressed: _canResend ? resendOtp : null,
                              child: _isResending
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Text(
                                      "Resend OTP",
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: kPrimaryColor,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
