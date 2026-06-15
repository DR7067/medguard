import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Login_screen/login_screen.dart';

/// Theme Colors
const Color kPrimaryColor = Color(0xFF1E5EFF);
const Color kPrimaryLightColor = Color(0xFF6EA8FE);
const Color kButtonColor = Color(0xFF0047FF);
const Color kTextColor = Color(0xFF333333);
const Color kBackgroundColor = Color(0xFFF4F7FF);

class ResetPassScreen extends StatefulWidget {
  const ResetPassScreen({super.key});

  @override
  State<ResetPassScreen> createState() => _ResetPassScreenState();
}

class _ResetPassScreenState extends State<ResetPassScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPass = TextEditingController();
  final _confirmPass = TextEditingController();

  bool _obscureText = true;
  bool _obscureText1 = true;

  String newPass = '';

  /// Floating background circles
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
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    double width = size.width;
    double height = size.height;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Stack(
        children: [

          /// Floating circles (responsive positions)
          floatingCircle(height * 0.10, width * 0.05, width * 0.25, kPrimaryColor),
          floatingCircle(height * 0.25, width * 0.70, width * 0.18, kPrimaryLightColor),
          floatingCircle(height * 0.50, width * 0.20, width * 0.30, kPrimaryColor),
          floatingCircle(height * 0.70, width * 0.65, width * 0.15, kPrimaryLightColor),

          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.06,
                vertical: height * 0.02,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  /// Back Button
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.arrow_back,
                      size: width * 0.07,
                      color: Colors.black,
                    ),
                  ),

                  SizedBox(height: height * 0.01),

                  /// Title
                  Text(
                    "Reset Password",
                    style: TextStyle(
                      fontSize: width * 0.075,
                      fontWeight: FontWeight.bold,
                      color: kTextColor,
                    ),
                  ),

                  SizedBox(height: height * 0.005),

                  Text(
                    "Enter your new password below",
                    style: TextStyle(
                      fontSize: width * 0.035,
                      color: Colors.black54,
                    ),
                  ),

                  const Spacer(),

                  /// Center Card
                  Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: width > 600 ? 450 : width * 0.9,
                        ),
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: width * 0.07,
                            vertical: height * 0.04,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: kPrimaryLightColor.withOpacity(0.2),
                                blurRadius: 25,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),

                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [

                                /// New Password
                                TextFormField(
                                  controller: _newPass,
                                  obscureText: _obscureText,
                                  decoration: InputDecoration(
                                    labelText: "New Password",
                                    prefixIcon: const Icon(Icons.lock_outline),
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
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),

                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Password cannot be empty';
                                    }

                                    List<String> errors = [];

                                    if (value.length < 8) {
                                      errors.add('• Minimum 8 characters');
                                    }

                                    if (!RegExp(r'[A-Z]').hasMatch(value)) {
                                      errors.add('• One uppercase letter');
                                    }

                                    if (!RegExp(r'[a-z]').hasMatch(value)) {
                                      errors.add('• One lowercase letter');
                                    }

                                    if (!RegExp(r'[0-9]').hasMatch(value)) {
                                      errors.add('• One number');
                                    }

                                    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]')
                                        .hasMatch(value)) {
                                      errors.add('• One special character');
                                    }

                                    if (errors.isNotEmpty) {
                                      return 'Password must contain:\n${errors.join('\n')}';
                                    }

                                    return null;
                                  },

                                  onChanged: (value) {
                                    newPass = value;
                                  },
                                ),

                                SizedBox(height: height * 0.03),

                                /// Confirm Password
                                TextFormField(
                                  controller: _confirmPass,
                                  obscureText: _obscureText1,
                                  decoration: InputDecoration(
                                    labelText: "Confirm Password",
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscureText1
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscureText1 = !_obscureText1;
                                        });
                                      },
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),

                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please re-enter your password';
                                    }

                                    if (value != newPass) {
                                      return 'Passwords do not match';
                                    }

                                    return null;
                                  },
                                ),

                                SizedBox(height: height * 0.05),

                                /// Confirm Button
                                SizedBox(
                                  width: double.infinity,
                                  height: height * 0.07,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (_formKey.currentState!.validate()) {

                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Password reset successful',
                                            ),
                                          ),
                                        );

                                        Navigator.pushReplacement(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const LoginScreen(),
                                          ),
                                        );
                                      }
                                    },

                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kButtonColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(18),
                                      ),
                                      elevation: 3,
                                    ),

                                    child: Text(
                                      "Confirm",
                                      style: TextStyle(
                                        fontSize: width * 0.041,
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
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
