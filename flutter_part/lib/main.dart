import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_part/screens/onboarding_screen.dart';
import 'package:flutter_part/screens/splash.dart';
import 'auth_wrapper.dart';
import 'services/notification_service.dart';
import 'services/reminder_alert_service.dart';
import 'package:flutter/services.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  /// Initialize Firebase safely
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  /// Lock orientation
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    /// Init notifications (non-blocking)
    Future.microtask(() async {
      try {
        await NotificationService.init();
      } catch (e) {
        debugPrint("Notification init failed: $e");
      }
    });

    /// Start reminder service safely
    Future.microtask(() {
      ReminderAlertService.instance.start(appNavigatorKey);
    });

    _initDynamicLinks();
  }

  Future<void> _initDynamicLinks() async {
    // future use
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      title: "MEDGuard",
      theme: ThemeData(primarySwatch: Colors.blue),

      /// Splash handles routing
      home: const Splash(),

      routes: {
        '/auth': (context) => const AuthWrapper(),
        '/onboarding': (context) => const OnboardingScreen(),
      },
    );
  }
}
