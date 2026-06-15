import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageSelection extends StatelessWidget {
  const LanguageSelection({super.key});

  Future<void> saveLanguage(BuildContext context, String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', langCode);

    // Go to Login screen after selecting language
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 60),
            const Text(
              "Select Language",
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text("Choose your preferred language"),

            const SizedBox(height: 40),

            languageTile("English", "en", context),
            languageTile("हिंदी", "hi", context),
            languageTile("मराठी", "mr", context),
          ],
        ),
      ),
    );
  }

  Widget languageTile(String title, String code, BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontSize: 18)),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () => saveLanguage(context, code),
      ),
    );
  }
}
