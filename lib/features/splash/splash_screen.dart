import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:honeypot/theme/honey_theme.dart';

import 'package:honeypot/core/billing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    // Wait for at least 2 seconds and for billing check to finish
    await Future.wait([
      Future.delayed(const Duration(milliseconds: 2500)),
      _waitForBilling(),
    ]);

    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

    if (!mounted) return;
    if (onboardingComplete) {
      Navigator.pushReplacementNamed(context, '/main');
    } else {
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  Future<void> _waitForBilling() async {
    if (!BillingService().isChecking.value) return;
    
    final completer = Completer<void>();
    void listener() {
      if (!BillingService().isChecking.value) {
        BillingService().isChecking.removeListener(listener);
        completer.complete();
      }
    }
    BillingService().isChecking.addListener(listener);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 120,
            )
                .animate()
                .fade(duration: 800.ms)
                .scale(
                    delay: 200.ms, duration: 600.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            Text(
              'HoneyPot',
              style: GoogleFonts.outfit(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ).animate().fadeIn(delay: 800.ms).moveY(begin: 20, end: 0),
            const SizedBox(height: 8),
            ValueListenableBuilder<bool>(
              valueListenable: BillingService().isChecking,
              builder: (context, checking, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: BillingService().isPro,
                  builder: (context, isPro, _) {
                    String statusText = 'DETECTING LICENSE...';
                    Color statusColor = Colors.grey;

                    if (!checking) {
                      statusText = isPro ? 'PRO VERSION' : 'FREE VERSION';
                      statusColor = isPro
                          ? HoneyTheme.amberPrimary
                          : Colors.grey[400]!;
                    }

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        statusText,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: statusColor,
                        ),
                      ),
                    ).animate(target: checking ? 0 : 1).fadeIn();
                  },
                );
              },
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(HoneyTheme.amberPrimary),
            ).animate().fadeIn(delay: 1500.ms),
          ],
        ),
      ),
    );
  }
}

class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HoneyPot')),
      body: const Center(child: Text('Coming Soon...')),
    );
  }
}
