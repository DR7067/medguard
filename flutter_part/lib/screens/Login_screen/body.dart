import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_part/screens/ForgotPass_screen/phone_no_screen.dart';
import 'package:flutter_part/screens/OTP_screen/otp_page.dart';
import 'package:flutter_part/services/auth_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_part/screens/Home_Screen/home_page.dart';
import 'package:flutter_part/screens/SignUp_Screen/signup_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_part/services/account_session_service.dart';

const Color kPrimaryColor = Color(0xFF2563EB);
const Color kTextColor = Color(0xFF1F2937);

class Body extends StatefulWidget {
  final String? initialEmail;

  const Body({super.key, this.initialEmail});

  @override
  State<Body> createState() => _BodyState();
}

class _BodyState extends State<Body> {
  static const String _databaseId = 'medguard-data';
  final _formKey = GlobalKey<FormState>();

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final AccountSessionService _accountSessionService = AccountSessionService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );

  bool _isLoading = false;
  bool _obscureText = true;
  bool _isNavigatingToOtp = false;

  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  @override
  void initState() {
    super.initState();
    _loadInitialEmail();
  }

  Future<void> _loadInitialEmail() async {
    if (widget.initialEmail != null && widget.initialEmail!.trim().isNotEmpty) {
      _usernameController.text = widget.initialEmail!.trim();
      return;
    }
    final pending = await _accountSessionService.consumePendingEmail();
    if (pending != null && pending.trim().isNotEmpty) {
      _usernameController.text = pending.trim();
    }
  }

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Manual/email-password login
      final user = await AuthService().login(
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );

      if (user != null && mounted) {
        String? phoneNumber = user.phoneNumber;
        bool linkPhoneOnSuccess = false;

        // If phone number not linked, ask user to enter one
        if (phoneNumber == null || phoneNumber.isEmpty) {
          phoneNumber = await _promptForPhoneNumber();
          if (phoneNumber == null) {
            setState(() => _isLoading = false);
            return;
          }
          linkPhoneOnSuccess = true;
        }

        // Always trigger OTP
        await _sendOtp(
          phoneNumber: phoneNumber,
          linkPhoneOnSuccess: linkPhoneOnSuccess,
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = "Login failed";
      if (e.code == 'user-not-found') message = "No account found.";
      if (e.code == 'wrong-password') message = "Incorrect password.";
      if (e.code == 'invalid-email') message = "Invalid email.";
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _googleLogin() async {
    final credential = await AuthService().signInWithGoogle();
    final user = credential?.user;

    if (user != null && mounted) {
      String? phoneNumber = user.phoneNumber;
      bool linkPhoneOnSuccess = false;

      // Prompt phone if missing
      if (phoneNumber == null || phoneNumber.isEmpty) {
        phoneNumber = await _promptForPhoneNumber();
        if (phoneNumber == null) return;
        linkPhoneOnSuccess = true;
      }

      // Always trigger OTP
      await _sendOtp(
        phoneNumber: phoneNumber,
        linkPhoneOnSuccess: linkPhoneOnSuccess,
      );
    }
  }

  /// Common method to send OTP
  Future<void> _sendOtp({
    required String phoneNumber,
    required bool linkPhoneOnSuccess,
  }) async {
    _isNavigatingToOtp = false;

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        if (_isNavigatingToOtp) return;

        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) return;

        if (linkPhoneOnSuccess) {
          await currentUser.linkWithCredential(credential);
          await currentUser.reload();
          final refreshedUser = FirebaseAuth.instance.currentUser;
          if (refreshedUser != null) {
            await _firestore.collection('users').doc(refreshedUser.uid).set({
              'email': refreshedUser.email,
              'phone': refreshedUser.phoneNumber ?? phoneNumber,
              'phoneVerified': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            await _accountSessionService.upsertFromUser(refreshedUser);
          }
        } else {
          await currentUser.reauthenticateWithCredential(credential);
        }

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomePage()),
          );
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Phone verification failed: ${e.message}")),
          );
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted || _isNavigatingToOtp) return;

        _isNavigatingToOtp = true;
        final navigator = Navigator.of(context, rootNavigator: true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          navigator.push(
            MaterialPageRoute(
              builder: (_) => OtpPage(
                identifier: phoneNumber,
                verificationId: verificationId,
                forceResendingToken: resendToken,
                purpose: OtpPurpose.login,
                linkPhoneOnSuccess: linkPhoneOnSuccess,
              ),
            ),
          );
        });
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  /// Prompt user to enter phone number if missing
  Future<String?> _promptForPhoneNumber() async {
    String? phone;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text("Enter Phone Number"),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(hintText: "+91 1234567890"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                final normalized = _normalizePhoneNumber(controller.text);
                if (normalized != null) {
                  phone = normalized;
                  Navigator.pop(context);
                }
              },
              child: const Text("Submit"),
            ),
          ],
        );
      },
    );
    return phone;
  }

  String? _normalizePhoneNumber(String rawPhone) {
    final digitsOnly = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digitsOnly.startsWith('+') && digitsOnly.length >= 11)
      return digitsOnly;
    if (RegExp(r'^[0-9]{10}$').hasMatch(digitsOnly)) return '+91$digitsOnly';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final bool isTablet = width > 600;

        final titleSize = isTablet ? 28.0 : width * 0.065;
        final subtitleSize = isTablet ? 16.0 : width * 0.035;

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1E40AF),
                  Color(0xFF2563EB),
                  Color(0xFF3B82F6),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  SizedBox(height: height * 0.04),

                  Icon(
                    Icons.local_hospital_rounded,
                    size: isTablet ? 60 : 45,
                    color: Colors.white,
                  ),

                  SizedBox(height: height * 0.01),

                  Text(
                    "MedGuard",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  Text(
                    "Secure Health Management",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: subtitleSize,
                    ),
                  ),

                  SizedBox(height: height * 0.04),

                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: width * 0.08,
                        vertical: height * 0.04,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(28),
                          topRight: Radius.circular(28),
                        ),
                      ),

                      child: SingleChildScrollView(
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Welcome Back",
                                style: TextStyle(
                                  fontSize: isTablet ? 24 : width * 0.055,
                                  fontWeight: FontWeight.w600,
                                  color: kTextColor,
                                ),
                              ),

                              SizedBox(height: height * 0.035),

                              const Text(
                                "Email Address",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),

                              const SizedBox(height: 6),

                              TextFormField(
                                controller: _usernameController,
                                decoration: InputDecoration(
                                  hintText: "Enter Email",
                                  prefixIcon: const Icon(Icons.person),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(29),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter email';
                                  }
                                  if (!_emailRegex.hasMatch(value.trim())) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),

                              SizedBox(height: height * 0.03),

                              const Text(
                                "Password",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey,
                                ),
                              ),

                              const SizedBox(height: 6),

                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscureText,
                                decoration: InputDecoration(
                                  hintText: "Password",
                                  prefixIcon: const Icon(Icons.lock),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureText
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureText = !_obscureText;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(29),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter password';
                                  }
                                  return null;
                                },
                              ),

                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PhoneNoScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    "Forgot Password?",
                                    style: TextStyle(color: kPrimaryColor),
                                  ),
                                ),
                              ),

                              SizedBox(height: height * 0.025),

                              SizedBox(
                                width: double.infinity,
                                height: isTablet ? 60 : 52,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _loginUser,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                      : const Text(
                                          "LOGIN",
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),

                              SizedBox(height: height * 0.02),

                              SizedBox(
                                width: double.infinity,
                                height: isTablet ? 58 : 48,
                                child: OutlinedButton(
                                  onPressed: _googleLogin,
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SvgPicture.asset(
                                        'assets/icons/google.svg',
                                        height: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        "Sign in with Google",
                                        style: TextStyle(color: Colors.black87),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              SizedBox(height: height * 0.035),

                              Divider(color: Colors.grey.shade300),

                              SizedBox(height: height * 0.015),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    "Don’t have an account? ",
                                    style: TextStyle(color: Colors.grey),
                                  ),

                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const SignupScreen(),
                                        ),
                                      );
                                    },
                                    child: const Text(
                                      "Sign up",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: kPrimaryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
