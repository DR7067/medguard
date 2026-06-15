import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_part/screens/Home_screen/home_page.dart';
import 'package:flutter_part/screens/Login_screen/login_screen.dart';
import 'package:flutter_part/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  bool _navigated = false; // prevents double navigation

  @override
  void initState() {
    super.initState();

    /// Animation
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();

    /// Start app logic AFTER short delay (reliable)
    Future.delayed(const Duration(seconds: 2), _handleAppStart);

    /// Fallback (prevents stuck screen)
    Future.delayed(const Duration(seconds: 5), () {
      if (!_navigated) {
        debugPrint("Fallback navigation triggered");
        _handleAppStart();
      }
    });
  }

  Future<void> _handleAppStart() async {
    if (_navigated) return;

    try {
      debugPrint("Splash: Checking app state...");

      final prefs = await SharedPreferences.getInstance();
      final onboardingCompleted = prefs.getBool('onboardingCompleted') ?? false;

      await Future.delayed(const Duration(milliseconds: 300));

      final firebaseUser = FirebaseAuth.instance.currentUser;

      debugPrint("Onboarding: $onboardingCompleted");
      debugPrint("User: $firebaseUser");

      if (!mounted) return;

      _navigated = true;

      /// FIRST TIME → ONBOARDING
      if (!onboardingCompleted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
        return;
      }

      /// LOGIN CHECK
      if (firebaseUser != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      debugPrint("Splash ERROR: $e");

      if (!mounted) return;

      _navigated = true;

      /// SAFE FALLBACK
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final logoSize = screenWidth * 0.35;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                /// LOGO
                Container(
                  width: logoSize,
                  height: logoSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    image: const DecorationImage(
                      image: AssetImage('assets/images/logo.jpeg'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                /// APP NAME
                Text(
                  'MEDGuard',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: screenWidth * 0.1,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                /// TAGLINE
                Text(
                  'Your Health Companion',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: screenWidth * 0.045,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
