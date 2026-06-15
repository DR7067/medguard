import 'package:flutter/material.dart';

class UserNameField extends StatelessWidget {
  const UserNameField({
    super.key,
    required this.usernameController,
  });

  final TextEditingController usernameController;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: usernameController,
      decoration: InputDecoration(
        hintText: "Username",
        prefixIcon: Icon(Icons.person),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(29),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter username';
        }
        return null;
      },
    );
  }
}
