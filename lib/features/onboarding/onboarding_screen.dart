import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:honeypot/core/notification_service.dart';
import 'package:honeypot/theme/honey_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  final PageController _controller = PageController();
  int _currentPage = 0;
  bool _isNotificationServiceEnabled = false;
  bool _areNotificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final serviceEnabled = await NotificationService.isServiceEnabled();
    final notificationsEnabled = await NotificationService.areNotificationsEnabled();
    if (mounted) {
      setState(() {
        _isNotificationServiceEnabled = serviceEnabled;
        _areNotificationsEnabled = notificationsEnabled;
      });
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            onPageChanged: (index) => setState(() => _currentPage = index),
            children: [
              _buildPage(
                title: 'Welcome to HoneyPot',
                description: 'Capture and archive every notification your phone receives, even after they are cleared.',
                icon: Icons.auto_awesome_rounded,
                color: HoneyTheme.amberPrimary,
              ),
              _buildPage(
                title: 'Capture Everything',
                description: 'We store title, text, and even media previews from your notification history.',
                icon: Icons.history_rounded,
                color: Colors.amber[600]!,
              ),
              _buildPermissionPage(),
            ],
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _completeOnboarding,
                  child: Text('SKIP', style: GoogleFonts.outfit(color: Colors.grey)),
                ),
                Row(
                  children: List.generate(3, (index) => _buildDot(index)),
                ),
                IconButton(
                  onPressed: () {
                    if (_currentPage < 2) {
                      _controller.nextPage(duration: 400.ms, curve: Curves.easeInOut);
                    } else {
                      _completeOnboarding();
                    }
                  },
                  icon: Icon(
                    _currentPage == 2 ? Icons.check_circle_rounded : Icons.arrow_forward_ios_rounded,
                    color: HoneyTheme.amberPrimary,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return AnimatedContainer(
      duration: 300.ms,
      margin: const EdgeInsets.only(right: 8),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index ? HoneyTheme.amberPrimary : Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildPage({required String title, required String description, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: HoneyTheme.glassBlur, sigmaY: HoneyTheme.glassBlur),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: HoneyTheme.glassBackground,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: HoneyTheme.glassBorder),
                ),
                child: Icon(icon, size: 80, color: color),
              ),
            ),
          )
              .animate()
              .fade(duration: 600.ms)
              .scale(delay: 200.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 48),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            description,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 16, color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionPage() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: HoneyTheme.glassBlur, sigmaY: HoneyTheme.glassBlur),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: HoneyTheme.glassBackground,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: HoneyTheme.glassBorder),
                ),
                child: const Icon(Icons.security_rounded, size: 80, color: HoneyTheme.amberPrimary),
              ),
            ),
          )
              .animate()
              .shake(duration: 800.ms),
          const SizedBox(height: 48),
          Text(
            'Keep Hive Active',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Grant these permissions to ensure HoneyPot captures every drop safely in the background.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(fontSize: 16, color: Colors.grey[400]),
          ),
          const SizedBox(height: 40),
          _buildPermissionButton(
            label: '1. NOTIFICATION ACCESS',
            icon: Icons.visibility_rounded,
            isDone: _isNotificationServiceEnabled,
            onPressed: () => NotificationService.requestPermission(),
          ),
          const SizedBox(height: 16),
          _buildPermissionButton(
            label: '2. SHOW STATS (MODERN ANDROID)',
            icon: Icons.notifications_active_rounded,
            isDone: _areNotificationsEnabled,
            onPressed: () => NotificationService.requestPostNotificationsPermission(),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionButton({
    required String label, 
    required IconData icon, 
    required bool isDone,
    required VoidCallback onPressed
  }) {
    return AnimatedContainer(
      duration: 400.ms,
      decoration: BoxDecoration(
        color: isDone ? Colors.green.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone ? Colors.green : Colors.transparent,
          width: 2,
        ),
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(isDone ? Icons.check_circle_outline_rounded : icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDone ? Colors.green : HoneyTheme.amberPrimary,
          foregroundColor: isDone ? Colors.white : Colors.black,
          minimumSize: const Size(double.infinity, 56),
          elevation: isDone ? 0 : 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
