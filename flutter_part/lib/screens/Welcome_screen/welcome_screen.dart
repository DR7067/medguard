import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_part/screens/Home_screen/home_page.dart';

const Color kPrimaryColor = Color(0xFF1565C0);
const Color kPrimaryLightColor = Color(0xFF42A5F5);
const Color kBackgroundColor = Colors.white;
const Color kTextColor = Color(0xFF1A1A1A);

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _dobController = TextEditingController();

  String? _gender;
  String _roleValue = 'caretaker';
  String _roleLabel = 'Patient';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const String _databaseId = 'medguard-data';
  final FirebaseFirestore _firestore = FirebaseFirestore.instanceFor(
    app: Firebase.app(),
    databaseId: _databaseId,
  );

  Widget _floatingShape(double top, double left, double size, Color color) {
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

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: kPrimaryColor),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(30),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.width > 600;

    final double titleSize = isTablet ? 32 : size.width * 0.07;
    final double buttonHeight = size.height * 0.065;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Stack(
        children: [
          _floatingShape(
            size.height * 0.05,
            size.width * 0.05,
            size.width * 0.3,
            kPrimaryColor,
          ),

          _floatingShape(
            size.height * 0.25,
            size.width * 0.7,
            size.width * 0.2,
            kPrimaryLightColor,
          ),

          _floatingShape(
            size.height * 0.55,
            size.width * 0.1,
            size.width * 0.25,
            kPrimaryColor,
          ),

          Positioned(
            top: size.height * 0.05,
            left: size.width * 0.02,
            child: IconButton(
              icon: Icon(Icons.arrow_back, size: isTablet ? 34 : 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
              child: Container(
                padding: EdgeInsets.all(size.width * 0.06),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),

                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Text(
                        "Create Account",
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.bold,
                          color: kTextColor,
                        ),
                      ),

                      SizedBox(height: size.height * 0.03),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _firstNameController,
                              decoration: _inputDecoration(
                                "First Name",
                                Icons.person,
                              ),
                            ),
                          ),

                          SizedBox(width: size.width * 0.03),

                          Expanded(
                            child: TextFormField(
                              controller: _lastNameController,
                              decoration: _inputDecoration(
                                "Last Name",
                                Icons.person,
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: size.height * 0.02),

                      TextFormField(
                        controller: _emailController,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return "Email required";
                          }
                          if (!value.contains('@')) {
                            return "Enter valid email";
                          }
                          return null;
                        },
                        decoration: _inputDecoration(
                          "Email",
                          Icons.email_outlined,
                        ),
                      ),

                      SizedBox(height: size.height * 0.02),

                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.length != 10) {
                            return "Enter valid 10 digit number";
                          }
                          return null;
                        },
                        decoration: _inputDecoration(
                          "Phone",
                          Icons.phone_outlined,
                        ),
                      ),

                      SizedBox(height: size.height * 0.02),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.length < 6) {
                            return "Password must be 6 characters";
                          }
                          return null;
                        },
                        decoration: _inputDecoration(
                          "Password",
                          Icons.lock_outline,
                        ),
                      ),

                      SizedBox(height: size.height * 0.02),

                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: true,
                        validator: (value) {
                          if (value != _passwordController.text) {
                            return "Passwords do not match";
                          }
                          return null;
                        },
                        decoration: _inputDecoration(
                          "Confirm Password",
                          Icons.lock_outline,
                        ),
                      ),

                      SizedBox(height: size.height * 0.02),

                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _dobController,
                              readOnly: true,
                              decoration: _inputDecoration(
                                "Date of Birth",
                                Icons.calendar_month,
                              ),
                              onTap: () async {
                                DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime(2000),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );

                                if (picked != null) {
                                  _dobController.text =
                                      "${picked.day}/${picked.month}/${picked.year}";
                                }
                              },
                            ),
                          ),

                          SizedBox(width: size.width * 0.03),

                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _gender,
                              items: ["Male", "Female", "Other"]
                                  .map(
                                    (e) => DropdownMenuItem(
                                      value: e,
                                      child: Text(e),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _gender = value;
                                });
                              },
                              decoration: _inputDecoration("Gender", Icons.wc),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: size.height * 0.02),

                      DropdownButtonFormField<String>(
                        initialValue: _roleLabel,
                        items: const ["Patient", "Guardian"]
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            if (value == 'Guardian') {
                              _roleLabel = 'Guardian';
                              _roleValue = 'caregiver';
                            } else {
                              _roleLabel = 'Patient';
                              _roleValue = 'caretaker';
                            }
                          });
                        },
                        decoration: _inputDecoration("Role", Icons.badge),
                      ),

                      SizedBox(height: size.height * 0.03),

                      SizedBox(
                        width: double.infinity,
                        height: buttonHeight,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (!_formKey.currentState!.validate()) return;

                            try {
                              UserCredential userCredential = await _auth
                                  .createUserWithEmailAndPassword(
                                    email: _emailController.text.trim(),
                                    password: _passwordController.text.trim(),
                                  );

                              final uid = userCredential.user!.uid;

                              await _firestore.collection('users').doc(uid).set(
                                {
                                  'firstName': _firstNameController.text.trim(),
                                  'lastName': _lastNameController.text.trim(),
                                  'email': _emailController.text.trim(),
                                  'phone': _phoneController.text.trim(),
                                  'gender': _gender,
                                  'dob': _dobController.text.trim(),
                                  'role': _roleValue,
                                  'createdAt': FieldValue.serverTimestamp(),
                                },
                                SetOptions(merge: true),
                              );

                              final doc = await _firestore
                                  .collection('users')
                                  .doc(uid)
                                  .get();
                              if (!doc.exists) {
                                throw FirebaseException(
                                  plugin: 'cloud_firestore',
                                  code: 'not-found',
                                  message: 'User profile not written.',
                                );
                              }

                              if (!mounted) return;

                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const HomePage(),
                                ),
                              );
                            } on FirebaseAuthException catch (e) {
                              String message = "Signup failed";

                              if (e.code == 'email-already-in-use') {
                                message = "Email already registered";
                              } else if (e.code == 'weak-password') {
                                message = "Weak password";
                              }

                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text(message)));
                            } on FirebaseException catch (e) {
                              final message =
                                  e.message ??
                                  "Failed to save user profile. Check Firestore rules.";
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(message)),
                                );
                              }
                            } catch (_) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Signup failed"),
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            "SIGN UP",
                            style: TextStyle(
                              fontSize: isTablet ? 20 : 18,
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
}
