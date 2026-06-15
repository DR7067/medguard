import 'package:flutter/material.dart';

const Color kPrimaryColor = Color(0xFF1565C0);
const Color kPrimaryLightColor = Color(0xFF42A5F5);
const Color kBackgroundColor = Color(0xFFF4F8FB);

class FloatingBackground extends StatelessWidget {
  final Widget child;

  const FloatingBackground({super.key, required this.child});

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

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: Stack(
        clipBehavior: Clip.none,   // ⭐ Fix added here
        children: [

          floatingCircle(
              size.height * 0.08,
              size.width * 0.07,
              size.width * 0.28,
              kPrimaryColor),

          floatingCircle(
              size.height * 0.25,
              size.width * 0.65,
              size.width * 0.20,
              kPrimaryLightColor),

          floatingCircle(
              size.height * 0.55,
              size.width * 0.30,
              size.width * 0.33,
              kPrimaryColor),

          floatingCircle(
              size.height * 0.75,
              size.width * 0.70,
              size.width * 0.18,
              kPrimaryLightColor),

          SafeArea(child: child),
        ],
      ),
    );
  }
}