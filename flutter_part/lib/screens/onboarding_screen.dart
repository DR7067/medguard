import 'package:flutter/material.dart';
import 'package:flutter_part/screens/Login_screen/login_screen.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int currentPage = 0;

  final List<Map<String, String>> onboardingData = [
    {
      "image": "assets/images/reminder.png",
      "title": "Welcome to MEDGuard",
      "desc":
          "Your personal health assistant to manage medications and stay healthy.",
    },
    {
      "image": "assets/images/reminder.png",
      "title": "Track Your Medications",
      "desc": "Get timely reminders so you never miss a dose.",
    },
    {
      "image": "assets/images/expiry.png",
      "title": "Scan & Analyze Reports",
      "desc":
          "Scan your medicine labels or prescriptions to get instant insights.",
    },
    {
      "image": "assets/images/expiry.png",
      "title": "Never Miss Expiry Dates",
      "desc":
          "Keep track of your medicine expiry dates and get alerts before they expire.",
    },
  ];

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboardingCompleted', true);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _skip() {
    _pageController.animateToPage(
      onboardingData.length - 1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _next() {
    if (currentPage < onboardingData.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  Widget onboardingPage(String image, String title, String desc) {
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.width > 600;

    final double imageHeight = isTablet
        ? size.height * 0.35
        : size.height * 0.28;
    final double titleSize = isTablet ? 30 : size.width * 0.07;
    final double descSize = isTablet ? 18 : size.width * 0.04;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: imageHeight,
            child: Image.asset(image, fit: BoxFit.contain),
          ),

          SizedBox(height: size.height * 0.05),

          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),

          SizedBox(height: size.height * 0.02),

          Text(
            desc,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: descSize,
              height: 1.6,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isTablet = size.width > 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          /// Top Decorative Circle
          Positioned(
            top: -size.height * 0.08,
            right: -size.width * 0.2,
            child: Container(
              height: size.width * 0.5,
              width: size.width * 0.5,
              decoration: BoxDecoration(
                // ignore: deprecated_member_use
                color: const Color(0xFF2563EB).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
            ),
          ),

          /// Bottom Decorative Circle
          Positioned(
            bottom: -size.height * 0.1,
            left: -size.width * 0.25,
            child: Container(
              height: size.width * 0.6,
              width: size.width * 0.6,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                /// Skip Button
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _skip,
                      child: Text(
                        "Skip",
                        style: TextStyle(
                          color: const Color(0xFF2563EB),
                          fontWeight: FontWeight.w500,
                          fontSize: isTablet ? 18 : 14,
                        ),
                      ),
                    ),
                  ),
                ),

                /// Pages
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: onboardingData.length,
                    onPageChanged: (index) {
                      setState(() {
                        currentPage = index;
                      });
                    },
                    itemBuilder: (context, index) {
                      return onboardingPage(
                        onboardingData[index]["image"]!,
                        onboardingData[index]["title"]!,
                        onboardingData[index]["desc"]!,
                      );
                    },
                  ),
                ),

                /// Indicator
                SmoothPageIndicator(
                  controller: _pageController,
                  count: onboardingData.length,
                  effect: WormEffect(
                    activeDotColor: const Color(0xFF2563EB),
                    dotColor: Colors.grey.shade300,
                    dotHeight: isTablet ? 10 : 6,
                    dotWidth: isTablet ? 10 : 6,
                  ),
                ),

                SizedBox(height: size.height * 0.03),

                /// Next Button
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
                  child: SizedBox(
                    width: double.infinity,
                    height: size.height * 0.065,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        currentPage == onboardingData.length - 1
                            ? "Get Started"
                            : "Next",
                        style: TextStyle(
                          fontSize: isTablet ? 20 : 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white, // 👈 ensures visibility
                        ),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: size.height * 0.05),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
