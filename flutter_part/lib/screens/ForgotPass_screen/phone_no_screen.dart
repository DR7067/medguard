import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_part/screens/Login_Screen/login_screen.dart';
import 'package:flutter_part/screens/OTP_screen/otp_page.dart';
import 'package:flutter_part/screens/floating_background.dart';

/// Colors
const Color kPrimaryColor = Color(0xFF1565C0);
const Color kPrimaryLightColor = Color(0xFF42A5F5);
const Color kBackgroundColor = Color(0xFFF4F8FB);
const Color kTextColor = Color(0xFF1A1A1A);

class PhoneNoScreen extends StatefulWidget {
  const PhoneNoScreen({super.key});

  @override
  State<PhoneNoScreen> createState() => _PhoneNoScreenState();
}

class _PhoneNoScreenState extends State<PhoneNoScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isSendingOtp = false;

  /// Validate inputs
  String? validateInput() {
    String email = _emailController.text.trim();
    String phone = _phoneController.text.trim();

    if (email.isEmpty && phone.isEmpty) {
      return 'Please enter email or phone number';
    }

    if (email.isNotEmpty && !email.contains('@')) {
      return 'Enter valid email';
    }

    if (phone.isNotEmpty && phone.length < 10) {
      return 'Enter valid phone number';
    }

    return null;
  }

  /// Normalize phone number
  String? _normalizePhoneNumber(String rawPhone) {
    final digitsOnly = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digitsOnly.startsWith('+') && digitsOnly.length >= 11)
      return digitsOnly;
    if (RegExp(r'^[0-9]{10}$').hasMatch(digitsOnly)) return '+91$digitsOnly';
    return null;
  }

  /// Main verification handler
  Future<void> _handleVerification() async {
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    final error = validateInput();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    /// EMAIL FLOW
    if (email.isNotEmpty && phone.isEmpty) {
      try {
        await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Password reset link sent to your email"),
          ),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Email not found. Please check and try again."),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? "Error sending email")),
          );
        }
      }

      return;
    }

    /// PHONE FLOW
    final normalizedPhone = _normalizePhoneNumber(phone);

    if (normalizedPhone == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter valid phone number")));
      return;
    }

    setState(() => _isSendingOtp = true);

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (_) {},
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message ?? "OTP Failed")));
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OtpPage(
                identifier: normalizedPhone,
                verificationId: verificationId,
                forceResendingToken: resendToken,
                purpose: OtpPurpose.resetPass,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final h = size.height;
    final w = size.width;

    return FloatingBackground(
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.06,
              vertical: h * 0.02,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// Back Button
                IconButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                  ),
                  icon: const Icon(
                    Icons.arrow_back,
                    size: 28,
                    color: kTextColor,
                  ),
                ),

                SizedBox(height: h * 0.01),

                /// Title
                const Text(
                  'Verify Your Account',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: kTextColor,
                  ),
                ),

                SizedBox(height: h * 0.008),

                const Text(
                  'Enter your email or phone number to receive OTP.',
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),

                SizedBox(height: h * 0.08),

                /// Card
                Container(
                  padding: EdgeInsets.all(w * 0.06),
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        /// Email Field
                        TextFormField(
                          controller: _emailController,
                          onChanged: (value) {
                            if (value.isNotEmpty &&
                                _phoneController.text.isNotEmpty) {
                              _phoneController.clear();
                              setState(() {});
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Email',
                            prefixIcon: const Icon(
                              Icons.mail_outline,
                              color: kPrimaryColor,
                            ),
                            filled: true,
                            fillColor: kPrimaryColor.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),

                        SizedBox(height: h * 0.025),

                        /// Divider
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey[400])),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey[400])),
                          ],
                        ),

                        SizedBox(height: h * 0.025),

                        /// Phone Field
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          onChanged: (value) {
                            if (value.isNotEmpty &&
                                _emailController.text.isNotEmpty) {
                              _emailController.clear();
                              setState(() {});
                            }
                          },
                          decoration: InputDecoration(
                            hintText: 'Phone No',
                            prefixIcon: const Icon(
                              Icons.call_outlined,
                              color: kPrimaryColor,
                            ),
                            filled: true,
                            fillColor: kPrimaryColor.withOpacity(0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(25),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),

                        SizedBox(height: h * 0.035),

                        /// Button
                        SizedBox(
                          width: double.infinity,
                          height: h * 0.065,
                          child: ElevatedButton(
                            onPressed: _isSendingOtp
                                ? null
                                : _handleVerification,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                              elevation: 5,
                            ),
                            child: _isSendingOtp
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.6,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Send OTP',
                                    style: TextStyle(
                                      fontSize: w * 0.045,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: h * 0.04),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
