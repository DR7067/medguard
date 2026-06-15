import 'package:flutter/material.dart';

class CreateProfile extends StatelessWidget {
  const CreateProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
        actions: [CircleAvatar(radius: 18, backgroundColor: Colors.amber)],
      ),
      body: Column(children: [Text('Hello')]),
    );
  }
}
