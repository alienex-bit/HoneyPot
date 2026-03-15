import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';
import 'package:honeypot/theme/honey_theme.dart';
import 'package:honeypot/core/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:honeypot/core/database_service.dart';
import 'package:honeypot/core/billing_service.dart';
import 'package:honeypot/core/app_info_service.dart';
import 'package:external_app_launcher/external_app_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:honeypot/core/security_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isServiceEnabled = false;
  int _historyTapCount = 0;
  DateTime? _lastHistoryTapTime;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _checkVaultLock();
  }

  bool _isVaultLocked = false;
  bool _isAuthenticating = false;
  bool _sessionUnlocked = false;
  DateTime? _lastPausedAt;
  DateTime? _lastAuthSuccessAt;

  Future<void> _checkVaultLock() async {
    final enabled = await SecurityService.isLockEnabled();
    if (!enabled) {
      setState(() => _isVaultLocked = false);
      return;
    }

    if (_sessionUnlocked || _isAuthenticating) return;

    setState(() => _isVaultLocked = true);
    _authenticateVault();
  }

  Future<void> _authenticateVault() async {
    if (_isAuthenticating) return;
    setState(() => _isAuthenticating = true);
    try {
      final success = await SecurityService.authenticate();
      if (success) {
        HapticFeedback.mediumImpact();
        setState(() {
          _isVaultLocked = false;
          _sessionUnlocked = true;
          _lastAuthSuccessAt = DateTime.now();
        });
      }
    } finally {
      setState(() => _isAuthenticating = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _lastPausedAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
      final now = DateTime.now();
      final isRecentlyAuthenticated = _lastAuthSuccessAt != null &&
          now.difference(_lastAuthSuccessAt!).inSeconds < 5;
      final isLongPause = _lastPausedAt == null || now.difference(_lastPausedAt!).inSeconds > 2;

      if (!_isAuthenticating && isLongPause && !isRecentlyAuthenticated) {
        setState(() => _sessionUnlocked = false);
        _checkVaultLock();
      }
    }
  }

  Future<void> _checkPermission() async {
    final enabled = await NotificationService.isServiceEnabled();
    if (mounted) setState(() => _isServiceEnabled = enabled);
  }

  String? _historyFilterPackage;
  String? _historyFilterAppName;



  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
        valueListenable: BillingService().isPro,
        builder: (context, isPro, _) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            body: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [HoneyTheme.honeyBlack, Colors.black],
                ),
              ),
              child: Stack(
                children: [
                  IndexedStack(
                    index: _selectedIndex,
                    children: [
                      HistoryPlaceholder(
                        isEnabled: _isServiceEnabled,
                        initialFilterPackage: _historyFilterPackage,
                        initialFilterAppName: _historyFilterAppName,
                      ),
                      StatsScreen(
                        onAppSelected: (package, appName) {
                          setState(() {
                            _historyFilterPackage = package;
                            _historyFilterAppName = appName;
                            _selectedIndex = 0;
                          });
                        },
                      ),
                      const InfoScreen(),
                      const SettingsScreen(),
                    ],
                  ),
                  if (_isVaultLocked && _selectedIndex == 0) _buildVaultLockOverlay(),
                ],
              ),
            ),
            bottomNavigationBar: Container(
              decoration: BoxDecoration(
                color: HoneyTheme.honeySurface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) {
                  if (index == 0) {
                    final now = DateTime.now();
                    if (_lastHistoryTapTime != null &&
                        now.difference(_lastHistoryTapTime!).inMilliseconds <
                            500) {
                      _historyTapCount++;
                    } else {
                      _historyTapCount = 1;
                    }
                    _lastHistoryTapTime = now;

                    if (_historyTapCount >= 5) {
                      BillingService().setProOverride(true);
                      HapticFeedback.heavyImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('PRO UNLOCKED (DEBUG)'),
                          backgroundColor: HoneyTheme.amberPrimary,
                        ),
                      );
                      _historyTapCount = 0;
                    }
                  } else {
                    _historyTapCount = 0;
                  }

                  if (index == 1 && !isPro) {
                    _showUpgradeDialog();
                    return;
                  }
                  setState(() => _selectedIndex = index);
                },
                type: BottomNavigationBarType.fixed,
                showSelectedLabels: true,
                showUnselectedLabels: true,
                items: const [
                  BottomNavigationBarItem(icon: Icon(Icons.history_rounded), label: 'History'),
                  BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: 'Stats'),
                  BottomNavigationBarItem(icon: Icon(Icons.info_outline_rounded), label: 'Info'),
                  BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
                ],
              ),
            ),
          );
        },
      );
  }

  void _showUpgradeDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Upgrade',
      barrierColor: Colors.black.withValues(alpha: 0.8),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: HoneyTheme.honeySurface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: HoneyTheme.amberPrimary.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 5)
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: HoneyTheme.amberPrimary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color:
                                    HoneyTheme.amberPrimary.withValues(alpha: 0.2)),
                          ),
                          child: const Icon(Icons.auto_awesome_rounded,
                              color: HoneyTheme.amberPrimary, size: 40),
                        ),
                        const SizedBox(height: 24),
                        Text('Level Up to PRO',
                            style: GoogleFonts.outfit(
                                fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text('Unlock the full power of the hive',
                            style:
                                GoogleFonts.outfit(fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 24),
                        _buildProFeatureRow(
                            Icons.history_toggle_off_rounded, 'Unlimited History'),
                        _buildProFeatureRow(
                            Icons.analytics_outlined, 'Advanced Honey Insights'),
                        _buildProFeatureRow(
                            Icons.verified_user_outlined, 'Priority Support'),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              BillingService().launchUpgrade();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: HoneyTheme.amberPrimary,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text('UPGRADE NOW',
                                style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('MAYBE LATER',
                              style: GoogleFonts.outfit(color: Colors.grey)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ).animate().scale(curve: Curves.easeOutBack, duration: 400.ms).fadeIn();
      },
    );
  }

  Widget _buildProFeatureRow(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: HoneyTheme.amberPrimary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: GoogleFonts.outfit(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildVaultLockOverlay() {
    return Positioned.fill(
      child: Container(
        color: HoneyTheme.honeySurface.withValues(alpha: 0.95),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_rounded, size: 80, color: HoneyTheme.amberPrimary)
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.1, 1.1), duration: 2.seconds),
                const SizedBox(height: 24),
                Text('Honey Vault Locked',
                    style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: HoneyTheme.amberPrimary)),
                const SizedBox(height: 12),
                Text('Unlock to access your history', style: GoogleFonts.outfit(color: Colors.grey)),
                const SizedBox(height: 40),
                ElevatedButton.icon(
                  onPressed: _authenticateVault,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('UNLOCK VAULT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HoneyTheme.amberPrimary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

class HistoryPlaceholder extends StatefulWidget {
  final bool isEnabled;
  final String? initialFilterPackage;
  final String? initialFilterAppName;

  const HistoryPlaceholder({
    super.key,
    required this.isEnabled,
    this.initialFilterPackage,
    this.initialFilterAppName,
  });

  @override
  State<HistoryPlaceholder> createState() => _HistoryPlaceholderState();
}

class _HistoryPlaceholderState extends State<HistoryPlaceholder> {
  late Future<List<Map<String, dynamic>>> _notificationsFuture;
  StreamSubscription? _subscription;
  String? _selectedFilterPackage;
  String? _selectedFilterAppName;
  int? _selectedPriority;
  bool _sortByPriority = false;

  @override
  void initState() {
    super.initState();
    _selectedFilterPackage = widget.initialFilterPackage;
    _selectedFilterAppName = widget.initialFilterAppName;
    _refreshHistory();
    _subscription = NotificationService.onNotificationReceived.listen((_) => _refreshHistory());
    BillingService().isPro.addListener(_refreshHistory);
  }

  @override
  void didUpdateWidget(HistoryPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilterPackage != oldWidget.initialFilterPackage ||
        widget.initialFilterAppName != oldWidget.initialFilterAppName) {
      setState(() {
        _selectedFilterPackage = widget.initialFilterPackage;
        _selectedFilterAppName = widget.initialFilterAppName;
      });
      _refreshHistory();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    BillingService().isPro.removeListener(_refreshHistory);
    super.dispose();
  }

  void _refreshHistory() {
    setState(() {
      _notificationsFuture = DatabaseService().getNotifications(
        filterPackage: _selectedFilterPackage,
        priority: _selectedPriority,
        sortByPriority: _sortByPriority,
        limit: BillingService().isPro.value ? null : 10,
      );
    });
  }

  void _setFilter(String? package, String? appName, {int? priority}) {
    setState(() {
      _selectedFilterPackage = package;
      _selectedFilterAppName = appName;
      if (priority != null || (priority == null && package == null && appName == null)) {
        _selectedPriority = priority;
      }
    });
    _refreshHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.notifications_active_rounded, color: HoneyTheme.amberPrimary),
          onPressed: () => NotificationService.openNotificationApp(),
        ),
        title: Text('Honey History', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
              _sortByPriority ? Icons.sort_rounded : Icons.access_time_rounded,
              color: _sortByPriority ? HoneyTheme.amberPrimary : Colors.grey,
            ),
            onPressed: () {
              setState(() => _sortByPriority = !_sortByPriority);
              _refreshHistory();
              HapticFeedback.lightImpact();
            },
          ),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _refreshHistory),
          IconButton(
            onPressed: () => _showClearAllConfirmation(),
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.grey),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.isEnabled) _buildPermissionBanner(),
          _buildPriorityCarousel(),
          if (_selectedFilterPackage != null || _selectedPriority != null) _buildFilterBar(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _notificationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: HoneyTheme.amberPrimary));
                }
                final data = snapshot.data ?? [];
                if (data.isEmpty) return _buildEmptyState();
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: data.length,
                  itemBuilder: (context, index) => _buildNotificationCard(data[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showClearAllConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HoneyTheme.honeySurface,
        title: Text('Empty the Jar?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('This will permanently delete all captured honey. Are you sure?', style: GoogleFonts.outfit()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              await DatabaseService().clearAll();
              _refreshHistory();
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('EMPTY JAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityCarousel() {
    final priorities = [3, 2, 1, 0];
    return Container(
      height: 90,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: priorities.map((p) {
          final grade = _getGradeInfo(p);
          final color = grade['color'] as Color;
          final isSelected = _selectedPriority == p;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _selectedPriority = isSelected ? null : p);
                _refreshHistory();
              },
              child: Container(
                margin: EdgeInsets.only(right: p != 0 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.2) : HoneyTheme.glassBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isSelected ? color : color.withValues(alpha: 0.3), width: isSelected ? 2 : 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(grade['icon'] as IconData, color: color, size: 24),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(grade['name'].toString().split(' ').first,
                          style: GoogleFonts.outfit(
                              fontSize: 11, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.grey[400])),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: HoneyTheme.amberPrimary.withValues(alpha: 0.1),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: HoneyTheme.amberPrimary),
          const SizedBox(width: 12),
          const Expanded(child: Text('Notification Listener is disabled.', style: TextStyle(fontSize: 13))),
          TextButton(onPressed: () => NotificationService.requestPermission(), child: const Text('ENABLE')),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        children: [
          if (_selectedFilterPackage != null)
            Chip(
              avatar: const Icon(Icons.filter_list_rounded, size: 16, color: Colors.black),
              label: Text('App: ${_selectedFilterAppName ?? "Filter"}',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
              backgroundColor: HoneyTheme.amberPrimary,
              onDeleted: () => _setFilter(null, null),
              deleteIconColor: Colors.black.withValues(alpha: 0.7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ).animate().fadeIn(),
          if (_selectedPriority != null)
            Chip(
              avatar: Icon(_getGradeInfo(_selectedPriority!)['icon'], size: 14, color: Colors.black),
              label: Text('Grade: ${_getGradeInfo(_selectedPriority!)['name']}',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
              backgroundColor: _getGradeInfo(_selectedPriority!)['color'],
              onDeleted: () => setState(() {
                _selectedPriority = null;
                _refreshHistory();
              }),
              deleteIconColor: Colors.black.withValues(alpha: 0.7),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ).animate().fadeIn(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No notifications captured yet.', style: GoogleFonts.outfit(color: Colors.grey)),
        ],
      ),
    );
  }

  Map<String, dynamic> _getGradeInfo(int priority) {
    switch (priority) {
      case 3:
        return {'name': 'Royal Jelly', 'color': HoneyTheme.royalJelly, 'icon': Icons.star_rounded};
      case 2:
        return {'name': 'Golden Honey', 'color': HoneyTheme.goldenHoney, 'icon': Icons.wb_sunny_rounded};
      case 1:
        return {'name': 'Amber Honey', 'color': HoneyTheme.amberHoney, 'icon': Icons.opacity_rounded};
      default:
        return {'name': 'Crystallized', 'color': Colors.grey[400]!, 'icon': Icons.ac_unit_rounded};
    }
  }

  Widget _buildNotificationCard(Map<String, dynamic> item) {
    final priority = item['priority'] as int? ?? 2;
    final grade = _getGradeInfo(priority);
    final gradeColor = grade['color'] as Color;
    final packageName = item['package_name'] as String? ?? '';
    final date = DateTime.fromMillisecondsSinceEpoch(item['timestamp'] ?? DateTime.now().millisecondsSinceEpoch);

    return Dismissible(
      key: Key('notif_${item['id'] ?? item['timestamp']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
      ),
      onDismissed: (_) async {
        await DatabaseService().deleteGroup(packageName, item['title'] ?? '');
        await NotificationService.refreshStats();
        _refreshHistory();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: HoneyTheme.glassBlur, sigmaY: HoneyTheme.glassBlur),
              child: GestureDetector(
                onTap: () => _showDetails(item),
                onLongPress: () {
                  _setFilter(packageName, item['app_name']);
                  HapticFeedback.heavyImpact();
                },
                child: Container(
                  height: 102,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: HoneyTheme.glassBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: gradeColor.withValues(alpha: 0.7), width: priority == 3 ? 2.0 : 1.2),
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          HapticFeedback.mediumImpact();
                          try {
                            await LaunchApp.openApp(
                              androidPackageName: packageName,
                              openStore: true, // Only if not found locally
                            );
                          } catch (e) {
                            debugPrint('Direct jump failed: $e');
                            // Second attempt with broader url launcher as fallback
                            final url = Uri.parse('package:$packageName');
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url);
                            }
                          }
                        },
                        child: Container(
                          width: 54, height: 54,
                          decoration: BoxDecoration(color: gradeColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                          child: item['icon_byte_array'] != null
                              ? Padding(padding: const EdgeInsets.all(8.0), child: Image.memory(item['icon_byte_array'], fit: BoxFit.contain))
                              : Icon(Icons.notifications_rounded, size: 20, color: gradeColor),
                        ),
                      ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(item['app_name'] ?? packageName.split('.').last, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: gradeColor)),
                        Text(item['title'] ?? 'No Title', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.white)),
                        Text(item['content'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showAppInfo(packageName, item['app_name'] ?? packageName.split('.').last);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: gradeColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.info_outline_rounded, size: 16, color: gradeColor.withValues(alpha: 0.8)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(DateFormat('HH:mm').format(date), style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey[400], fontWeight: FontWeight.w600)),
                        Text(DateFormat('dd/MM').format(date), style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey[600])),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
          // Grade badge pinned to top-left corner of card
          Positioned(
            top: 6,
            left: 6,
            child: Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: gradeColor,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 4)],
              ),
              child: Icon(grade['icon'] as IconData, size: 13, color: Colors.black),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  void _showAppInfo(String packageName, String appName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: HoneyTheme.honeySurface.withValues(alpha: 0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    await LaunchApp.openApp(androidPackageName: packageName);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: HoneyTheme.amberPrimary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.app_registration_rounded, color: HoneyTheme.amberPrimary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(appName, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text(packageName, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
                    ],
                   ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('About this App', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: HoneyTheme.amberPrimary)),
            const SizedBox(height: 12),
            FutureBuilder<String?>(
              future: AppInfoService().getAppDescription(packageName),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: CircularProgressIndicator(color: HoneyTheme.amberPrimary),
                    ),
                  );
                }
                
                final description = snapshot.data ?? 'No description available.';
                return Text(
                  description,
                  style: GoogleFonts.outfit(fontSize: 14, color: Colors.white.withValues(alpha: 0.8), height: 1.5),
                );
              },
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final url = Uri.parse('https://play.google.com/store/apps/details?id=$packageName');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                icon: const Icon(Icons.shop_rounded),
                label: const Text('OPEN IN PLAY STORE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HoneyTheme.amberPrimary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> item) {
    final priority = item['priority'] as int? ?? 2;
    final grade = _getGradeInfo(priority);
    final gradeColor = grade['color'] as Color;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Details',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: HoneyTheme.honeySurface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: gradeColor.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      )
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            HapticFeedback.mediumImpact();
                            final packageName = item['package_name'] as String? ?? '';
                            if (packageName.isNotEmpty) {
                              await LaunchApp.openApp(androidPackageName: packageName);
                            }
                          },
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: gradeColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: gradeColor.withValues(alpha: 0.2)),
                            ),
                            child: item['icon_byte_array'] != null
                                ? Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Image.memory(item['icon_byte_array']),
                                  )
                                : Icon(grade['icon'], color: gradeColor, size: 30),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          item['app_name'] ?? 'Notification',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: gradeColor,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['title'] ?? 'No Title',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            item['content'] ?? '',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.8),
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: gradeColor.withValues(alpha: 0.2),
                              foregroundColor: gradeColor,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: gradeColor.withValues(alpha: 0.4)),
                              ),
                            ),
                            child: Text(
                              'CLOSE',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ).animate().scale(curve: Curves.easeOutBack, duration: 400.ms).fadeIn(),
        );
      },
    );
  }
}

class StatsScreen extends StatefulWidget {
  final Function(String, String)? onAppSelected;
  const StatsScreen({super.key, this.onAppSelected});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<Map<String, dynamic>> _statsFuture;
  int _statsViewMode = 0; // 0: Heatmap, 1: Clock, 2: Wave, 3: Stack

  @override
  void initState() { super.initState(); _loadStats(); }
  void _loadStats() { setState(() { _statsFuture = _fetchStats(); }); }
  Future<Map<String, dynamic>> _fetchStats() async {
    final dns = DatabaseService();
    final total = await dns.getTotalCount();
    final topApps = await dns.getStats();
    final distribution = await dns.getGradeDistribution();
    final heatmap = await dns.getHeatmapData();
    final peakHourData = await dns.getPeakHour(days: 30);
    final recentTimestamps = await dns.getRecentTimestamps(days: 2);

    // Calculate Focus Score (Longest Gap in last 24h)
    String focusScore = "0m";
    if (recentTimestamps.isNotEmpty) {
      int maxGapMs = 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Use 24h window for "Daily Focus" but include yesterday's data as requested
      final since = now - (24 * 3600000); 
      
      final relevantTimestamps = recentTimestamps.where((t) => t >= since).toList();
      
      if (relevantTimestamps.isNotEmpty) {
        // Gap between start of window and first notification
        maxGapMs = relevantTimestamps.first - since;
        
        // Gaps between notifications
        for (int i = 0; i < relevantTimestamps.length - 1; i++) {
          final gap = relevantTimestamps[i+1] - relevantTimestamps[i];
          if (gap > maxGapMs) maxGapMs = gap;
        }
        
        // Gap between last notification and now
        final finalGap = now - relevantTimestamps.last;
        if (finalGap > maxGapMs) maxGapMs = finalGap;
      }

      final hours = maxGapMs ~/ 3600000;
      final mins = (maxGapMs % 3600000) ~/ 60000;
      focusScore = hours > 0 ? "${hours}h ${mins}m" : "${mins}m";
    }

    String peakNoise = "N/A";
    if (peakHourData != null) {
      final hour = peakHourData['hour'] as int;
      final isPm = hour >= 12;
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      peakNoise = "$displayHour${isPm ? 'pm' : 'am'}";
    }

    return {
      'total': total,
      'topApps': topApps, 
      'distribution': distribution,
      'heatmap': heatmap,
      'peakNoise': peakNoise,
      'focusScore': focusScore,
      'stackedStats': await dns.getStackedHourlyStats(days: 14),
      'hourlyAggregate': _calculateHourlyAggregate(heatmap),
    };
  }

  List<double> _calculateHourlyAggregate(List<Map<String, dynamic>> heatmap) {
    List<double> hourly = List.filled(24, 0.0);
    for (var entry in heatmap) {
      final hour = entry['hour'] as int;
      final count = entry['count'] as int;
      hourly[hour] += count.toDouble();
    }
    // Normalize or just return counts? Painters can scale.
    return hourly;
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Honey Insights', style: GoogleFonts.outfit(fontWeight: FontWeight.bold))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: HoneyTheme.amberPrimary),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: HoneyTheme.amberPrimary,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load Honey Insights',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${snapshot.error}',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _loadStats,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data;
          if (data == null) {
            return Center(
              child: Text(
                'No insight data yet',
                style: GoogleFonts.outfit(color: Colors.grey),
              ),
            );
          }

          final total = data['total'] as int? ?? 0;
          final topApps = data['topApps'] as List<Map<String, dynamic>>? ?? [];
          final distribution = data['distribution'] as Map<int, int>? ?? {};
          final heatmap = data['heatmap'] as List<Map<String, dynamic>>? ?? [];
          final peakNoise = data['peakNoise'] as String? ?? "N/A";
          final focusScore = data['focusScore'] as String? ?? "0m";
          final stackedStats = data['stackedStats'] as List<Map<String, dynamic>>? ?? [];
          final hourlyAggregate = data['hourlyAggregate'] as List<double>? ?? List.filled(24, 0.0);

          return RefreshIndicator(
            onRefresh: () async => _loadStats(),
            color: HoneyTheme.amberPrimary,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildTotalCounter(total, peakNoise, focusScore),
                  const SizedBox(height: 20),
                  _buildGradeInsight(distribution),
                  const SizedBox(height: 20),
                  _buildVisualSection(heatmap, stackedStats, hourlyAggregate),
                  const SizedBox(height: 20),
                  _buildTopSources(topApps),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGradeInsight(Map<int, int> distribution) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Honey Grade Breakdown',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: GradeDonutPainter(distribution),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [3, 2, 1, 0].map((p) {
                    final info = _getGradeInfo(p);
                    final count = distribution[p] ?? 0;
                    return InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showGradeDetailsDialog(p);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        child: Row(
                          children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: info['color'], shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(info['name'], style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
                            const Spacer(),
                            Text(count.toString(), style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }



  Widget _buildVisualSection(List<Map<String, dynamic>> heatmap, List<Map<String, dynamic>> stackedStats, List<double> hourlyAggregate) {
    String title = "Hive Heatmap";
    String description = "Tap to cycle views";
    switch (_statsViewMode) {
      case 1:
        title = "Daily Routine";
        description = "Where your day bulges with noise";
        break;
      case 2:
        title = "Digital Rhythm";
        description = "The ebb and flow of focus";
        break;
      case 3:
        title = "Noise Composition";
        description = "Honey grades by hour";
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(description, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome_motion_rounded, color: HoneyTheme.amberPrimary),
              onPressed: () => setState(() => _statsViewMode = (_statsViewMode + 1) % 4),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() => _statsViewMode = (_statsViewMode + 1) % 4);
          },
          child: Container(
            height: 220,
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HoneyTheme.glassBackground,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: HoneyTheme.glassBorder),
            ),
            child: _buildCurrentChart(heatmap, stackedStats, hourlyAggregate),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentChart(List<Map<String, dynamic>> heatmap, List<Map<String, dynamic>> stackedStats, List<double> hourlyAggregate) {
    switch (_statsViewMode) {
      case 1:
        return CustomPaint(painter: ClockRadarPainter(hourlyAggregate));
      case 2:
        return CustomPaint(painter: SmoothWavePainter(hourlyAggregate));
      case 3:
        return CustomPaint(painter: StackedHourlyPainter(stackedStats));
      default:
        return _buildHeatmapGrid(heatmap);
    }
  }

  Widget _buildHeatmapGrid(List<Map<String, dynamic>> heatmap) {
    return CustomPaint(
      size: Size.infinite,
      painter: HiveHeatmapPainter(heatmap),
    );
  }

  Map<String, dynamic> _getGradeInfo(int priority) {
    switch (priority) {
      case 3:
        return {'name': 'Royal Jelly', 'color': HoneyTheme.royalJelly, 'icon': Icons.star_rounded};
      case 2:
        return {'name': 'Golden Honey', 'color': HoneyTheme.goldenHoney, 'icon': Icons.wb_sunny_rounded};
      case 1:
        return {'name': 'Amber Honey', 'color': HoneyTheme.amberHoney, 'icon': Icons.opacity_rounded};
      default:
        return {'name': 'Crystallized', 'color': Colors.grey[400]!, 'icon': Icons.ac_unit_rounded};
    }
  }

  Widget _buildTotalCounter(int total, String peakNoise, String focusScore) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
            sigmaX: HoneyTheme.glassBlur, sigmaY: HoneyTheme.glassBlur),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          decoration: BoxDecoration(
            color: HoneyTheme.amberPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: HoneyTheme.amberPrimary.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Honey',
                        style: GoogleFonts.outfit(color: Colors.grey, fontSize: 12),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.hive_rounded, color: HoneyTheme.amberPrimary, size: 24)
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 1.seconds),
                          const SizedBox(width: 8),
                          Text(
                            'Captured',
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    total.toString(),
                    style: GoogleFonts.outfit(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: HoneyTheme.amberPrimary,
                    ),
                  ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: HoneyTheme.amberPrimary.withValues(alpha: 0.1)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildMiniStat('Peak Noise', peakNoise, Icons.bolt_rounded, () {
                    _showStatInfoDialog(
                      'Peak Noise', 
                      'This is the hour of the day when the hive is most active. We analyzed your last 30 days of data to find your busiest "pollen" collection time.',
                      Icons.bolt_rounded
                    );
                  }),
                  _buildMiniStat('Focus Score', focusScore, Icons.timer_rounded, () {
                    _showStatInfoDialog(
                      'Focus Score', 
                      'This represents your longest period of uninterrupted digital peace in the last 24 hours. Higher scores mean better deep-work rhythm!',
                      Icons.timer_rounded
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStatInfoDialog(String title, String content, IconData icon) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HoneyTheme.honeySurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(icon, color: HoneyTheme.amberPrimary),
            const SizedBox(width: 12),
            Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(content, style: GoogleFonts.outfit(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('GOT IT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: HoneyTheme.amberPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: HoneyTheme.amberPrimary),
                const SizedBox(width: 4),
                Text(label, style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 4),
            Text(value, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void _showGradeDetailsDialog(int priority) async {
    final info = _getGradeInfo(priority);
    final topApps = await DatabaseService().getTopAppsByPriority(priority);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HoneyTheme.honeySurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(info['icon'] as IconData, color: info['color'] as Color),
            const SizedBox(width: 12),
            Text(info['name'] as String, style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top sources for this grade:', style: GoogleFonts.outfit(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 16),
            if (topApps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No data captured yet.', style: GoogleFonts.outfit(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey))),
              )
            else
              ...topApps.map((app) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        HapticFeedback.mediumImpact();
                        final pkg = app['package_name'] as String? ?? '';
                        if (pkg.isNotEmpty) {
                          await LaunchApp.openApp(androidPackageName: pkg);
                        }
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                        child: app['icon'] != null 
                          ? ClipOval(child: Image.memory(app['icon'], fit: BoxFit.cover))
                          : const Icon(Icons.apps_rounded, size: 16, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(app['app_name'] ?? 'Unknown App', style: GoogleFonts.outfit(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text('${app['count']}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: HoneyTheme.amberPrimary)),
                  ],
                ),
              )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CLOSE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: HoneyTheme.amberPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSources(List<Map<String, dynamic>> apps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Top Pollen Sources',
              style:
                  GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Icon(Icons.star_rounded,
                size: 16, color: HoneyTheme.amberPrimary),
          ],
        ),
        const SizedBox(height: 12),
        if (apps.isEmpty)
          Text('No data to analyze yet.',
              style: GoogleFonts.outfit(color: Colors.grey))
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.1,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: apps.length,
            itemBuilder: (context, index) => _buildAppStatCard(apps[index]),
          ),
      ],
    );
  }

  Widget _buildAppStatCard(Map<String, dynamic> app) {
    return GestureDetector(
      onTap: () {
        if (widget.onAppSelected != null) {
          widget.onAppSelected!(
              app['package_name'], app['app_name'] ?? 'Unknown');
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: HoneyTheme.glassBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HoneyTheme.glassBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                      color: Colors.white10, shape: BoxShape.circle),
                  child: app['icon'] != null
                      ? ClipOval(
                          child: Image.memory(app['icon'], fit: BoxFit.cover))
                      : const Icon(Icons.apps_rounded,
                          size: 10, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  app['app_name'] ?? 'Unknown',
                  style: GoogleFonts.outfit(
                      fontSize: 10, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${app['count']}',
                  style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: HoneyTheme.amberPrimary,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLockEnabled = false;
  double _dbSize = 0.0;
  int _iconCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await SecurityService.isLockEnabled();
    final size = await DatabaseService().getDatabaseSize();

    // Quick count of unique icons to explain size
    final db = await DatabaseService().database;
    final result = await db.rawQuery(
        'SELECT COUNT(DISTINCT package_name) as count FROM notifications WHERE icon_byte_array IS NOT NULL');
    final iconCount = result.first['count'] as int? ?? 0;

    setState(() {
      _isLockEnabled = enabled;
      _dbSize = size;
      _iconCount = iconCount;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Jar Settings',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: BillingService().isPro,
            builder: (context, isPro, _) {
              if (isPro) {
                return Card(
                  color: HoneyTheme.amberPrimary.withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                          color:
                              HoneyTheme.amberPrimary.withValues(alpha: 0.3))),
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome_rounded, color: HoneyTheme.amberPrimary),
                    title: Text('HoneyPot PRO Active', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: HoneyTheme.amberPrimary)),
                    subtitle: Text('Thank you for supporting the hive!', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
                    trailing: const Icon(Icons.verified_rounded, color: HoneyTheme.amberPrimary),
                  ),
                );
              }
              return _buildSettingsTile(
                icon: Icons.star_rounded,
                title: 'Upgrade to PRO',
                subtitle: 'Unlock unlimited history & stats',
                onTap: () => BillingService().launchUpgrade(),
                color: HoneyTheme.amberPrimary,
              );
            },
          ),
          const SizedBox(height: 16),
          _buildSettingsTile(
            icon: Icons.notifications_active_rounded,
            title: 'Notification Access',
            subtitle: 'Required to capture honey',
            onTap: () => NotificationService.requestPermission(),
          ),
          _buildSettingsTile(
            icon: Icons.battery_saver_rounded,
            title: 'Battery Optimization',
            subtitle: 'Prevent system from closing the jar',
            onTap: () =>
                NotificationService.requestIgnoreBatteryOptimizations(),
          ),
          _buildSettingsTile(
            icon: Icons.storage_rounded,
            title: 'Storage Usage',
            subtitle: '${_dbSize.toStringAsFixed(2)} MB of captured honey',
            onTap: () => _showStorageManagement(context),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('Security'),
          Card(
            color: Colors.white.withValues(alpha: 0.03),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SwitchListTile(
              secondary: const Icon(Icons.lock_outline_rounded,
                  color: HoneyTheme.amberPrimary),
              title: Text('Biometric Lock',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              subtitle: Text('Secure your Honey History',
                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
              value: _isLockEnabled,
              activeThumbColor: HoneyTheme.amberPrimary,
              onChanged: (value) async {
                final success = await SecurityService.authenticate();
                if (success) {
                  await SecurityService.setLockEnabled(value);
                  setState(() {
                    _isLockEnabled = value;
                  });
                  HapticFeedback.mediumImpact();
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Maintenance'),
          _buildSettingsTile(
            icon: Icons.delete_forever_rounded,
            title: 'Empty the Jar',
            subtitle: 'Permanently clear all history',
            color: Colors.redAccent,
            onTap: () => _confirmClear(context),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('About'),
          Card(
            color: Colors.white.withValues(alpha: 0.03),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: HoneyTheme.amberPrimary),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HoneyPot v1.1.0',
                              style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600)),
                          Text('Author: Steve Watkins',
                              style: GoogleFonts.outfit(
                                  fontSize: 12, color: Colors.grey)),
                          Text('watkins.steve@gmail.com',
                              style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: HoneyTheme.amberPrimary
                                      .withValues(alpha: 0.7))),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStorageManagement(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HoneyTheme.honeySurface,
        title: Text('Storage Management',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Jar Size: ${_dbSize.toStringAsFixed(2)} MB',
                style: GoogleFonts.outfit()),
            const SizedBox(height: 8),
            Text('• Textual Honey: ~${(_dbSize * 0.2).toStringAsFixed(2)} MB',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
            Text(
                '• App Icons ($_iconCount): ~${(_dbSize * 0.8).toStringAsFixed(2)} MB',
                style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            Text(
              'Compacting the jar reclaims space from deleted honey. Icons are high-quality PNGs to keep your UI looking sweet!',
              style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!context.mounted) return;
              await DatabaseService().vacuum();
              await _loadSettings();
              if (context.mounted) Navigator.pop(context);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Jar compacted successfully!')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: HoneyTheme.amberPrimary,
              foregroundColor: Colors.black,
            ),
            child: const Text('COMPACT JAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.outfit(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return Card(
      key: key,
      color: Colors.white.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, color: color ?? HoneyTheme.amberPrimary),
        title:
            Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HoneyTheme.honeySurface,
        title: Text('Empty Jar?',
            style: GoogleFonts.outfit(color: Colors.redAccent)),
        content: Text(
          'This will permanently delete all captured notifications. This action cannot be undone.',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () async {
              await DatabaseService().clearAll();
              await NotificationService.refreshStats();
              if (context.mounted) Navigator.pop(context);
              NotificationService.triggerRefresh();
            },
            child: const Text('EMPTY JAR',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}

class InfoScreen extends StatelessWidget {
  const InfoScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Honey Guide', style: GoogleFonts.outfit(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Column(
            children: [
              const Icon(Icons.hive_rounded, size: 60, color: HoneyTheme.amberPrimary),
              const SizedBox(height: 16),
              Text('Welcome to the Hive', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: HoneyTheme.amberPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: HoneyTheme.amberPrimary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, color: HoneyTheme.amberPrimary, size: 20),
                        const SizedBox(width: 8),
                        Text('Always-On Capture', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: HoneyTheme.amberPrimary)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'HoneyPot is your personal notification analyzer. It quietly captures and preserves every buzz, ensuring no data is lost—even when you clear your system notification shade. Your honey is safe in the jar!',
                      style: GoogleFonts.outfit(fontSize: 13, color: Colors.grey[300], height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text('Honey Grades', style: GoogleFonts.outfit(fontSize: 18, color: HoneyTheme.amberPrimary)),
          const SizedBox(height: 16),
          Column(
            children: [
              _buildGradeInfoTile(3),
              _buildGradeInfoTile(2),
              _buildGradeInfoTile(1),
              _buildGradeInfoTile(0),
            ],
          ),
          const SizedBox(height: 32),
          _buildInfoSection(
            title: 'Pro Tips',
            icon: Icons.lightbulb_outline_rounded,
            items: [
              'Tap an app icon to launch that app instantly.',
              'Long-press any notification to filter by that app.',
              'Tap a grade card in History to toggle filters.',
              'Keep the Jar open in stats to see real-time updates.',
            ],
          ),
          const SizedBox(height: 32),
          _buildInfoSection(
            title: 'How it Works',
            icon: Icons.auto_awesome_rounded,
            items: [
              'HoneyPot runs a background listener service.',
              'Data is stored 100% locally in an encrypted jar.',
              'No data ever leaves your device.',
              'Battery optimization is disabled to ensure capturing.',
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInfoSection({required String title, required IconData icon, required List<String> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: HoneyTheme.amberPrimary, size: 20),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: HoneyTheme.amberPrimary)),
          ],
        ),
        const SizedBox(height: 16),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(color: HoneyTheme.amberPrimary, fontWeight: FontWeight.bold)),
              Expanded(child: Text(item, style: GoogleFonts.outfit(color: Colors.grey[400], height: 1.4))),
            ],
          ),
        )),
      ],
    );
  }
  Widget _buildGradeInfoTile(int priority) {
    final names = ['Crystallized', 'Amber Honey', 'Golden Honey', 'Royal Jelly'];
    final colors = [
      Colors.grey[400]!,
      HoneyTheme.amberHoney,
      HoneyTheme.goldenHoney,
      HoneyTheme.royalJelly
    ];
    final icons = [
      Icons.ac_unit_rounded,
      Icons.opacity_rounded,
      Icons.wb_sunny_rounded,
      Icons.star_rounded
    ];
    final descs = [
      'Low priority or silent alerts.',
      'Standard ambient information.',
      'Important daily updates.',
      'Critical high-priority triggers.'
    ];
    final examples = [
      'Weather, background sync, silent apps.',
      'News, shopping promos, generic updates.',
      'WhatsApp, Gmail, Slack, social media.',
      'Missed calls, SMS, security alerts, alarms.'
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HoneyTheme.glassBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors[priority].withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icons[priority], color: colors[priority], size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  names[priority],
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold, color: colors[priority]),
                ),
                Text(
                  descs[priority],
                  style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  'Examples: ${examples[priority]}',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: colors[priority].withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GradeDonutPainter extends CustomPainter {
  final Map<int, int> distribution;
  GradeDonutPainter(this.distribution);

  @override
  void paint(Canvas canvas, Size size) {
    final total = distribution.values.fold(0, (sum, v) => sum + v);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    double startAngle = -3.14 / 2;
    for (int i = 3; i >= 0; i--) {
      final count = distribution[i] ?? 0;
      if (count == 0) continue;

      final sweptAngle = (count / total) * 2 * 3.14;
      paint.color = _getGradeColor(i);
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 6),
        startAngle,
        sweptAngle - 0.1, // Small gap
        false,
        paint,
      );
      startAngle += sweptAngle;
    }
  }

  Color _getGradeColor(int p) {
    if (p == 3) return HoneyTheme.royalJelly;
    if (p == 2) return HoneyTheme.goldenHoney;
    if (p == 1) return HoneyTheme.amberHoney;
    return Colors.grey[400]!;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class ClockRadarPainter extends CustomPainter {
  final List<double> hourlyData;
  ClockRadarPainter(this.hourlyData);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 10;
    final paint = Paint()
      ..color = HoneyTheme.amberPrimary.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw background circles
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * (i / 4), paint);
    }

    // Draw hour lines
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (int i = 0; i < 24; i++) {
      final angle = (i * 15 - 90) * (pi / 180);
      canvas.drawLine(center, center + Offset(cos(angle) * radius, sin(angle) * radius), linePaint);
    }

    // Draw radar shape
    final path = Path();
    double maxVal = hourlyData.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) maxVal = 1;

    for (int i = 0; i < 24; i++) {
      final angle = (i * 15 - 90) * (pi / 180);
      final r = (hourlyData[i] / maxVal) * radius;
      final point = center + Offset(cos(angle) * r, sin(angle) * r);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    final radarPaint = Paint()
      ..color = HoneyTheme.amberPrimary.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, radarPaint);

    final borderPaint = Paint()
      ..color = HoneyTheme.amberPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, borderPaint);

    // Labels (Bolder and More Reference Points)
    final textStyle = GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.bold);
    _drawLabel(canvas, center, "00", -90, radius + 12, textStyle);
    _drawLabel(canvas, center, "03", -45, radius + 12, textStyle);
    _drawLabel(canvas, center, "06", 0, radius + 12, textStyle);
    _drawLabel(canvas, center, "09", 45, radius + 12, textStyle);
    _drawLabel(canvas, center, "12", 90, radius + 12, textStyle);
    _drawLabel(canvas, center, "15", 135, radius + 12, textStyle);
    _drawLabel(canvas, center, "18", 180, radius + 12, textStyle);
    _drawLabel(canvas, center, "21", 225, radius + 12, textStyle);
  }

  void _drawLabel(Canvas canvas, Offset center, String text, double angleDeg, double r, TextStyle style) {
    final angle = angleDeg * (pi / 180);
    final pos = center + Offset(cos(angle) * r, sin(angle) * r);
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class SmoothWavePainter extends CustomPainter {
  final List<double> hourlyData;
  SmoothWavePainter(this.hourlyData);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [HoneyTheme.amberPrimary.withValues(alpha: 0.5), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    double maxVal = hourlyData.reduce((a, b) => a > b ? a : b);
    if (maxVal == 0) {
      maxVal = 1;
    }

    const double bottomMargin = 20;
    final double chartHeight = size.height - bottomMargin;
    final widthPerPoint = size.width / (hourlyData.length - 1);
    path.moveTo(0, chartHeight);

    for (int i = 0; i < hourlyData.length; i++) {
      final x = i * widthPerPoint;
      final y = chartHeight - (hourlyData[i] / maxVal) * (chartHeight - 10);
      
      if (i == 0) {
        path.lineTo(x, y);
      } else {
        final prevX = (i - 1) * widthPerPoint;
        final prevY = chartHeight - (hourlyData[i - 1] / maxVal) * (chartHeight - 10);
        path.cubicTo(
          prevX + widthPerPoint / 2, prevY,
          x - widthPerPoint / 2, y,
          x, y
        );
      }
    }

    path.lineTo(size.width, chartHeight);
    path.close();
    canvas.drawPath(path, paint);

    final linePaint = Paint()
      ..color = HoneyTheme.amberPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    final linePath = Path();
    for (int i = 0; i < hourlyData.length; i++) {
      final x = i * widthPerPoint;
      final y = chartHeight - (hourlyData[i] / maxVal) * (chartHeight - 10);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        final prevX = (i - 1) * widthPerPoint;
        final prevY = chartHeight - (hourlyData[i - 1] / maxVal) * (chartHeight - 10);
        linePath.cubicTo(prevX + widthPerPoint / 2, prevY, x - widthPerPoint / 2, y, x, y);
      }
    }
    canvas.drawPath(linePath, linePaint);

    // Draw Reference Times (X-axis) & Grid Lines
    final labelStyle = GoogleFonts.outfit(color: Colors.grey, fontSize: 10);
    final times = {0: '12am', 6: '6am', 12: '12pm', 18: '6pm', 23: '11pm'};
    final gridPaint = Paint()..color = Colors.white.withValues(alpha: 0.05)..strokeWidth = 1;
    
    for (final entry in times.entries) {
      final x = (entry.key / 23) * size.width;
      
      // Vertical grid line
      canvas.drawLine(Offset(x, 0), Offset(x, chartHeight), gridPaint);

      final textPainter = TextPainter(
        text: TextSpan(text: entry.value, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      
      final xPos = x - (textPainter.width / 2);
      textPainter.paint(canvas, Offset(xPos, size.height - bottomMargin + 4));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class StackedHourlyPainter extends CustomPainter {
  final List<Map<String, dynamic>> stackedData;
  StackedHourlyPainter(this.stackedData);

  @override
  void paint(Canvas canvas, Size size) {
    final Map<int, Map<int, int>> hourGroups = {};
    for (var entry in stackedData) {
      final h = entry['hour'] as int;
      final p = entry['priority'] as int;
      final c = entry['count'] as int;
      hourGroups.putIfAbsent(h, () => {})[p] = c;
    }

    double maxTotal = 0;
    for (int h = 0; h < 24; h++) {
      final g = hourGroups[h] ?? {};
      double total = g.values.fold(0, (a, b) => a + b).toDouble();
      if (total > maxTotal) maxTotal = total;
    }
    if (maxTotal == 0) maxTotal = 1;

    const double bottomMargin = 20;
    final chartHeight = size.height - bottomMargin;
    final barWidth = size.width / 24;
    final gap = barWidth * 0.2;

    for (int h = 0; h < 24; h++) {
      final g = hourGroups[h] ?? {};
      double currentY = chartHeight; 
      
      for (int p = 0; p <= 3; p++) {
        final count = g[p] ?? 0;
        if (count == 0) continue;

        final segmentHeight = (count / maxTotal) * (chartHeight - 10);
        final rect = Rect.fromLTWH(
          h * barWidth + gap / 2,
          currentY - segmentHeight,
          barWidth - gap,
          segmentHeight
        );

        canvas.drawRect(rect, Paint()..color = _getPriorityColor(p));
        currentY -= segmentHeight;
      }
    }

    // Draw Reference Times (X-axis)
    final labelStyle = GoogleFonts.outfit(color: Colors.grey, fontSize: 10);
    final times = {0: '12am', 6: '6am', 12: '12pm', 18: '6pm', 23: '11pm'};
    
    for (final entry in times.entries) {
      final textPainter = TextPainter(
        text: TextSpan(text: entry.value, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      
      final xPos = (entry.key * barWidth) + (barWidth / 2) - (textPainter.width / 2);
      textPainter.paint(canvas, Offset(xPos, size.height - bottomMargin + 4));
    }
  }

  Color _getPriorityColor(int p) {
    switch (p) {
      case 3: return HoneyTheme.royalJelly;
      case 2: return HoneyTheme.goldenHoney;
      case 1: return HoneyTheme.amberHoney;
      default: return Colors.grey[400]!;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class HiveHeatmapPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  HiveHeatmapPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    const double padding = 2;
    // Leave room for Y-axis labels (days)
    const double leftMargin = 30; 
    // Leave room for X-axis labels (times)
    const double bottomMargin = 20;

    final double gridWidth = size.width - leftMargin;
    final double gridHeight = size.height - bottomMargin;

    final double cellWidth = (gridWidth - (23 * padding)) / 24;
    final double cellHeight = (gridHeight - (6 * padding)) / 7;

    // Build map for fast lookup
    final Map<String, int> lookup = {};
    int maxCount = 1;
    for (var entry in data) {
      final day = entry['day'] as int;
      final hour = entry['hour'] as int;
      final count = entry['count'] as int;
      lookup['$day-$hour'] = count;
      if (count > maxCount) maxCount = count;
    }

    final paint = Paint()..style = PaintingStyle.fill;
    final labelStyle = GoogleFonts.outfit(color: Colors.grey, fontSize: 10);

    // Draw days (Y-axis)
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    for (int day = 0; day < 7; day++) {
      final textPainter = TextPainter(
        text: TextSpan(text: days[day], style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      
      final yPos = day * (cellHeight + padding) + (cellHeight - textPainter.height) / 2;
      textPainter.paint(canvas, Offset(0, yPos));

      for (int hour = 0; hour < 24; hour++) {
        final count = lookup['$day-$hour'] ?? 0;
        final intensity = count > 0 ? (0.2 + (count / maxCount) * 0.8) : 0.05;
        
        paint.color = HoneyTheme.amberPrimary.withValues(alpha: intensity);
        
        final rect = Rect.fromLTWH(
          leftMargin + hour * (cellWidth + padding),
          day * (cellHeight + padding),
          cellWidth,
          cellHeight,
        );
        
        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), paint);
      }
    }

    // Draw times (X-axis)
    final times = {0: '12am', 6: '6am', 12: '12pm', 18: '6pm'};
    for (final entry in times.entries) {
      final textPainter = TextPainter(
        text: TextSpan(text: entry.value, style: labelStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      
      final xPos = leftMargin + entry.key * (cellWidth + padding);
      textPainter.paint(canvas, Offset(xPos, size.height - bottomMargin + 4));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
