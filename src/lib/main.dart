import 'package:flutter/material.dart';
import 'package:honeypot/theme/honey_theme.dart';
import 'package:honeypot/features/splash/splash_screen.dart';
import 'package:honeypot/features/onboarding/onboarding_screen.dart';
import 'package:honeypot/core/main_screen.dart';

import 'package:honeypot/core/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NotificationService.initialize();
  runApp(const HoneyPotApp());
}

class HoneyPotApp extends StatelessWidget {
  const HoneyPotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HoneyPot',
      debugShowCheckedModeBanner: false,
      theme: HoneyTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
        '/main': (context) => const MainScreen(),
      },
    );
  }
}