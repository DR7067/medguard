import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Login_screen/body.dart';

class LoginScreen extends StatelessWidget {
  final String? initialEmail;

  const LoginScreen({super.key, this.initialEmail});

  @override
  Widget build(BuildContext context) {
    return Body(initialEmail: initialEmail);
  }
}
