import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Login_Screen/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_part/screens/OTP_screen/otp_page.dart';
import 'package:flutter_part/services/account_session_service.dart';

const Color kPrimaryColor = Color(0xFF2563EB);
const Color kPrimaryLightColor = Color(0xFF60A5FA);
const Color kBackgroundColor = Color(0xFFF4F8FB);
const Color kTextColor = Color(0xFF1F2937);

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _dobController = TextEditingController();

  String? _gender;
  String _roleValue = "caretaker";
  String _roleLabel = "Patient";

  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _databaseId = 'medguard-data';
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );

  bool _loading = false;
  bool _isNavigatingToOtp = false;

  /// Floating Circle Widget
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

  Future<void> _createUserProfile(String uid) async {
    final normalizedPhone = _normalizePhoneNumber(_phoneController.text.trim());

    await _firestore.collection('users').doc(uid).set({
      'firstName': _firstNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'email': _emailController.text.trim(),
      if (normalizedPhone != null) 'phone': normalizedPhone,
      'phoneVerified': false,
      'dob': _dobController.text.trim(),
      'gender': _gender,
      'role': _roleValue,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'not-found',
        message: 'User profile not written.',
      );
    }
  }

  Future<void> _signUpUser() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Passwords do not match")));
      return;
    }

    setState(() => _loading = true);

    try {
      // 1️⃣ Create email/password account
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final uid = userCredential.user!.uid;

      // 2️⃣ Save profile to Firestore
      await _createUserProfile(uid);
      await AccountSessionService().upsertFromUser(userCredential.user!);

      if (!mounted) return;

      // 3️⃣ Check if phone number exists
      final phoneNumber = _normalizePhoneNumber(_phoneController.text.trim());
      if (phoneNumber == null) {
        await AccountSessionService().setPendingLoginContext(
          email: _emailController.text.trim(),
          isSwitching: false,
        );
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                LoginScreen(initialEmail: _emailController.text.trim()),
          ),
        );
        return;
      }

      // 4️⃣ Trigger OTP verification
      _isNavigatingToOtp = false;
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),

        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification
          await userCredential.user!.linkWithCredential(credential);
          await userCredential.user!.reload();
          final refreshedUser = FirebaseAuth.instance.currentUser;
          if (refreshedUser != null) {
            await _firestore.collection('users').doc(refreshedUser.uid).set({
              'email': refreshedUser.email,
              'phone': refreshedUser.phoneNumber ?? phoneNumber,
              'phoneVerified': true,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            await AccountSessionService().upsertFromUser(refreshedUser);
          }
          await AccountSessionService().setPendingLoginContext(
            email: _emailController.text.trim(),
            isSwitching: false,
          );
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  LoginScreen(initialEmail: _emailController.text.trim()),
            ),
          );
        },

        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Phone verification failed: ${e.message}")),
          );
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
                  purpose: OtpPurpose.signup,
                  linkPhoneOnSuccess: true,
                ),
              ),
            );
          });
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          // Optional: handle timeout
        },
      );
    } on FirebaseAuthException catch (e) {
      String message = "Signup failed";
      if (e.code == 'email-already-in-use') {
        message = "Email already registered";
      } else if (e.code == 'weak-password') {
        message = "Password is too weak";
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on FirebaseException catch (e) {
      final message =
          e.message ??
          "Failed to save user profile. Check Firestore rules for medguard-data.";
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Signup failed")));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _normalizePhoneNumber(String rawPhone) {
    final digitsOnly = rawPhone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digitsOnly.isEmpty) return null;
    if (digitsOnly.startsWith('+') && digitsOnly.length >= 11) {
      return digitsOnly;
    }
    if (RegExp(r'^[0-9]{10}$').hasMatch(digitsOnly)) {
      return '+91$digitsOnly';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.width > 600;

    return Scaffold(
      backgroundColor: kBackgroundColor,

      body: Stack(
        children: [
          /// Floating circles background
          floatingCircle(80, 20, 120, kPrimaryColor),
          floatingCircle(220, size.width - 80, 90, kPrimaryLightColor),
          floatingCircle(size.height * 0.6, -40, 150, kPrimaryLightColor),
          floatingCircle(
            size.height * 0.75,
            size.width - 100,
            120,
            kPrimaryColor,
          ),

          Positioned(
            top: size.height * 0.05,
            left: size.width * 0.03,
            child: IconButton(
              icon: Icon(
                Icons.arrow_back,
                color: kTextColor,
                size: isTablet ? 34 : 28,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),

              child: Container(
                padding: EdgeInsets.all(size.width * 0.06),

                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 15,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),

                child: Form(
                  key: _formKey,

                  child: Column(
                    children: [
                      Text(
                        "SIGN UP",
                        style: TextStyle(
                          fontSize: isTablet ? 34 : size.width * 0.075,
                          fontWeight: FontWeight.bold,
                          color: kTextColor,
                        ),
                      ),

                      SizedBox(height: size.height * 0.01),

                      Text(
                        "Create your account",
                        style: TextStyle(color: Colors.grey[700]),
                      ),

                      SizedBox(height: size.height * 0.03),

                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              _firstNameController,
                              "First Name",
                              Icons.person,
                            ),
                          ),

                          SizedBox(width: size.width * 0.03),

                          Expanded(
                            child: _buildTextField(
                              _lastNameController,
                              "Last Name",
                              Icons.person,
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: size.height * 0.025),

                      _buildTextField(
                        _emailController,
                        "Email",
                        Icons.email,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "Required Field";
                          }
                          if (!_emailRegex.hasMatch(value.trim())) {
                            return "Enter a valid email";
                          }
                          return null;
                        },
                      ),

                      SizedBox(height: size.height * 0.025),

                      _buildTextField(
                        _phoneController,
                        "Phone",
                        Icons.call,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "Required Field";
                          }
                          if (_normalizePhoneNumber(value.trim()) == null) {
                            return "Enter a valid phone number";
                          }
                          return null;
                        },
                      ),

                      SizedBox(height: size.height * 0.025),

                      _buildTextField(
                        _passwordController,
                        "Password",
                        Icons.lock,
                        isPassword: true,
                      ),

                      SizedBox(height: size.height * 0.025),

                      _buildTextField(
                        _confirmPasswordController,
                        "Confirm Password",
                        Icons.lock,
                        isPassword: true,
                      ),

                      SizedBox(height: size.height * 0.025),

                      _buildDOBField(),

                      SizedBox(height: size.height * 0.025),

                      _buildDropdownField(
                        label: "Gender",
                        icon: Icons.person_outline,
                        value: _gender,
                        items: ['Male', 'Female', 'Other'],
                        onChanged: (val) => setState(() => _gender = val),
                      ),

                      SizedBox(height: size.height * 0.025),

                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Role",
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ),
                      SizedBox(height: size.height * 0.01),

                      _buildDropdownField(
                        label: "Role",
                        icon: Icons.badge,
                        value: _roleLabel,
                        items: ['Patient', 'Guardian'],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            if (val == 'Patient') {
                              _roleLabel = 'Patient';
                              _roleValue = 'caretaker';
                            } else {
                              _roleLabel = 'Guardian';
                              _roleValue = 'caregiver';
                            }
                          });
                        },
                      ),

                      SizedBox(height: size.height * 0.04),

                      SizedBox(
                        width: double.infinity,
                        height: isTablet ? 65 : 55,

                        child: ElevatedButton(
                          onPressed: _loading ? null : _signUpUser,

                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),

                          child: _loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  'SIGN UP',
                                  style: TextStyle(
                                    fontSize: 18,
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
            ),
          ),
        ],
      ),
    );
  }

  // TEXTFIELD
  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: keyboardType,
      validator:
          validator ??
          (value) {
            if (value == null || value.isEmpty) {
              return "Required Field";
            }
            return null;
          },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: kPrimaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
      ),
    );
  }

  // DOB
  Widget _buildDOBField() {
    return TextFormField(
      controller: _dobController,
      readOnly: true,
      decoration: InputDecoration(
        labelText: 'Date of Birth',
        prefixIcon: const Icon(
          Icons.calendar_month_outlined,
          color: kPrimaryColor,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
      ),
      onTap: () async {
        DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: DateTime(2000),
          firstDate: DateTime(1900),
          lastDate: DateTime.now(),
        );

        if (pickedDate != null) {
          _dobController.text =
              "${pickedDate.day}/${pickedDate.month}/${pickedDate.year}";
        }
      },
    );
  }

  // DROPDOWN
  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items
          .map((g) => DropdownMenuItem(value: g, child: Text(g)))
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: kPrimaryColor),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(25)),
      ),
    );
  }
}
