import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';
import 'package:honeypot/theme/honey_theme.dart';
import 'package:honeypot/core/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:honeypot/core/database_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
    debugPrint("Lock Policy Check: Enabled=$enabled, SessionUnlocked=$_sessionUnlocked, IsAuthenticating=$_isAuthenticating");
    
    if (!enabled) {
      setState(() => _isVaultLocked = false);
      return;
    }

    if (_sessionUnlocked || _isAuthenticating) {
      debugPrint("Lock Check Skipped: Already unlocked or authenticating.");
      return;
    }

    setState(() {
      _isVaultLocked = true;
    });
    _authenticateVault();
  }

  Future<void> _authenticateVault() async {
    if (_isAuthenticating) return;
    
    setState(() => _isAuthenticating = true);
    debugPrint("Starting Biometric Authentication...");
    
    try {
      final success = await SecurityService.authenticate();
      debugPrint("Authentication Result: $success");
      
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
    debugPrint("App Lifecycle State: $state");
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _lastPausedAt = DateTime.now();
    }
    
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
      
      // Only re-lock if:
      // 1. We aren't currently authenticating
      // 2. The app was away for more than 2 seconds (not just the biometric dialog)
      // 3. We didn't JUST succeed in authenticating (5s grace period)
      final now = DateTime.now();
      final isRecentlyAuthenticated = _lastAuthSuccessAt != null && 
          now.difference(_lastAuthSuccessAt!).inSeconds < 5;
      final isLongPause = _lastPausedAt == null || 
          now.difference(_lastPausedAt!).inSeconds > 2;

      if (!_isAuthenticating && isLongPause && !isRecentlyAuthenticated) {
        debugPrint("Significant resume detected. Re-locking vault...");
        setState(() {
          _sessionUnlocked = false;
        });
        _checkVaultLock();
      } else {
        debugPrint("Brief resume or auth grace period active. Skipping re-lock.");
      }
    }
  }

  Future<void> _checkPermission() async {
    final enabled = await NotificationService.isServiceEnabled();
    debugPrint("Permission Check Result: $enabled");
    if (mounted) {
      setState(() {
        _isServiceEnabled = enabled;
      });
    }
  }

  String? _historyFilterPackage;
  String? _historyFilterAppName;

  List<Widget> get _pages => [
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
            HapticFeedback.lightImpact();
          },
        ),
        const SettingsScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              HoneyTheme.honeyBlack,
              HoneyTheme.honeyBlack,
              HoneyTheme.honeySurface.withOpacity(0.8),
              HoneyTheme.amberPrimary.withOpacity(0.05),
            ],
            stops: const [0.0, 0.6, 0.8, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _pages[_selectedIndex],
            if (_isVaultLocked && _selectedIndex == 0)
              _buildVaultLockOverlay(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: HoneyTheme.honeySurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.history_rounded),
              label: 'History',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: 'Stats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVaultLockOverlay() {
    return Positioned.fill(
      child: Container(
        color: HoneyTheme.honeySurface.withOpacity(0.95),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_rounded, size: 80, color: HoneyTheme.amberPrimary)
                    .animate(onPlay: (controller) => controller.repeat(reverse: true))
                    .scale(begin: const Offset(0.8, 0.8), end: const Offset(1.1, 1.1), duration: 2.seconds),
                const SizedBox(height: 24),
                Text(
                  'Honey Vault Locked',
                  style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: HoneyTheme.amberPrimary),
                ),
                const SizedBox(height: 12),
                Text(
                  'Unlock to access your history',
                  style: GoogleFonts.outfit(color: Colors.grey),
                ),
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

  @override
  void initState() {
    super.initState();
    _selectedFilterPackage = widget.initialFilterPackage;
    _selectedFilterAppName = widget.initialFilterAppName;
    _refreshHistory();
    _subscription = NotificationService.onNotificationReceived.listen((_) {
      _refreshHistory();
    });
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
    super.dispose();
  }

  void _showClearAllConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: HoneyTheme.honeySurface,
        title: Text('Empty the Jar?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently delete all captured honey. Are you sure?',
          style: GoogleFonts.outfit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              await DatabaseService().clearAll();
              _refreshHistory();
              if (context.mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('EMPTY JAR'),
          ),
        ],
      ),
    );
  }

  void _refreshHistory() {
    setState(() {
      _notificationsFuture = DatabaseService().getNotifications(
        filterPackage: _selectedFilterPackage,
      );
    });
  }

  void _setFilter(String? package, String? appName) {
    setState(() {
      _selectedFilterPackage = package;
      _selectedFilterAppName = appName;
    });
    _refreshHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.notifications_active_rounded, color: HoneyTheme.amberPrimary),
          onPressed: () => NotificationService.openNotificationApp(),
          tooltip: 'System Notifications',
        ),
        title: Text('Honey History', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshHistory,
          ),
          IconButton(
            onPressed: () => _showClearAllConfirmation(context),
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.grey),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.isEnabled)
            _buildPermissionBanner(),
          if (_selectedFilterPackage != null)
            _buildFilterBar(),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _notificationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: HoneyTheme.amberPrimary));
                }
                final data = snapshot.data ?? [];
                if (data.isEmpty) {
                  return _buildEmptyState();
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final item = data[index];
                    return _buildNotificationCard(item);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: HoneyTheme.amberPrimary.withOpacity(0.1),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: HoneyTheme.amberPrimary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Notification Listener is disabled.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => NotificationService.requestPermission(),
            child: const Text('ENABLE'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      alignment: Alignment.centerLeft,
      child: Chip(
        avatar: const Icon(Icons.filter_list_rounded, size: 16, color: Colors.black),
        label: Text(
          'Viewing: ${_selectedFilterAppName ?? "Filter"}',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
        ),
        backgroundColor: HoneyTheme.amberPrimary,
        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Colors.black),
        onDeleted: () => _setFilter(null, null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ).animate().fadeIn().slideX(begin: -0.1, end: 0);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_rounded, size: 64, color: Colors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            'No notifications captured yet.',
            style: GoogleFonts.outfit(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getGradeInfo(int priority) {
    switch (priority) {
      case 3:
        return {'name': 'Royal Jelly', 'color': Colors.redAccent, 'icon': Icons.star_rounded};
      case 2:
        return {'name': 'Golden Honey', 'color': HoneyTheme.amberPrimary, 'icon': Icons.wb_sunny_rounded};
      case 1:
        return {'name': 'Amber Honey', 'color': HoneyTheme.amberPrimary.withOpacity(0.6), 'icon': Icons.opacity_rounded};
      default:
        return {'name': 'Crystallized', 'color': Colors.grey, 'icon': Icons.ac_unit_rounded};
    }
  }

  Widget _buildNotificationCard(Map<String, dynamic> item) {
    final timestamp = item['timestamp'];
    final date = timestamp is int ? DateTime.fromMillisecondsSinceEpoch(timestamp) : DateTime.now();
    final timeStr = DateFormat('HH:mm').format(date);
    final dateStr = DateFormat('dd/MM/yy').format(date);
    final count = item['count'] as int;
    final priority = item['priority'] as int? ?? 2;
    final grade = _getGradeInfo(priority);
    
    return Dismissible(
      key: Key('notif_group_${item['package_name']}_${item['title']}_${item['content']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
      ),
      onDismissed: (direction) async {
        await DatabaseService().deleteGroup(
          item['package_name'] ?? '',
          item['title'] ?? '',
          item['content'] ?? '',
        );
        await NotificationService.refreshStats();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count > 1 ? 'Honey cluster cleared.' : 'Honey cleared from jar.'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: HoneyTheme.honeySurface,
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: HoneyTheme.glassBlur, sigmaY: HoneyTheme.glassBlur),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: HoneyTheme.glassBackground,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (grade['color'] as Color).withOpacity(0.3),
                width: priority == 3 ? 1.5 : 1,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: (grade['color'] as Color).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: item['icon_byte_array'] != null
                        ? Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Image.memory(item['icon_byte_array'], fit: BoxFit.contain),
                          )
                        : Icon(Icons.notifications_rounded, color: grade['color'] as Color),
                  ),
                  if (item['count'] > 1)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: HoneyTheme.amberPrimary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${item['count']}',
                          style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      item['app_name'] ?? item['package_name']?.split('.').last ?? 'Unknown App',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: grade['color'] as Color,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (grade['color'] as Color).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(grade['icon'] as IconData, size: 10, color: grade['color'] as Color),
                        const SizedBox(width: 4),
                        Text(
                          grade['name'] as String,
                          style: GoogleFonts.outfit(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: grade['color'] as Color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    item['title'] ?? 'No Title',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
                  ),
                  Text(
                    item['content'] ?? 'No Content',
                    style: GoogleFonts.outfit(color: Colors.grey[400], fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            timeStr,
                            style: TextStyle(color: Colors.grey[400], fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            dateStr,
                            style: TextStyle(color: Colors.grey[600], fontSize: 10),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              onTap: () => _showDetails(item),
              onLongPress: () {
                _setFilter(item['package_name'], item['app_name']);
                HapticFeedback.heavyImpact();
              },
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).moveX(begin: 10, end: 0);
  }


  void _showDetails(Map<String, dynamic> item) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Details',
      barrierColor: Colors.black.withOpacity(0.7),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 60, left: 16, right: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: HoneyTheme.glassBackground,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: HoneyTheme.amberPrimary.withOpacity(0.2)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (item['icon_byte_array'] != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    item['icon_byte_array'],
                                    width: 24,
                                    height: 24,
                                  ),
                                )
                              else
                                const Icon(Icons.notifications_rounded, color: HoneyTheme.amberPrimary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  item['app_name']?.toUpperCase() ?? 'DETAILS',
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.bold,
                                    color: HoneyTheme.amberPrimary,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10),
                          const SizedBox(height: 16),
                          Flexible(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['title'] ?? 'Untitled',
                                    style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    item['content'] ?? '',
                                    style: GoogleFonts.outfit(fontSize: 16, color: Colors.grey[300], height: 1.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Package: ${item['package_name']}',
                                style: GoogleFonts.outfit(fontSize: 10, color: Colors.grey[700]),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item['timestamp'])),
                                    style: GoogleFonts.outfit(fontSize: 14, color: HoneyTheme.amberPrimary, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    DateFormat('dd/MM/yy').format(DateTime.fromMillisecondsSinceEpoch(item['timestamp'])),
                                    style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return SlideTransition(
          position: Tween(begin: const Offset(0, -1), end: const Offset(0, 0))
              .animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutBack)),
          child: child,
        );
      },
    );
  }
}

class StatsScreen extends StatefulWidget {
  final Function(String package, String appName)? onAppSelected;
  const StatsScreen({super.key, this.onAppSelected});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  late Future<Map<String, dynamic>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _loadStats() {
    setState(() {
      _statsFuture = _fetchStats();
    });
  }

  Future<Map<String, dynamic>> _fetchStats() async {
    final total = await DatabaseService().getTotalCount();
    final topApps = await DatabaseService().getStats();
    final weekly = await DatabaseService().getWeeklyStats();
    return {
      'total': total,
      'topApps': topApps,
      'weekly': weekly,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.bug_report_rounded, color: Colors.grey, size: 20),
          onPressed: () async {
            await DatabaseService().seedDebugData();
            await NotificationService.refreshStats();
            _loadStats();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Mock honey spawned! 🐝'),
                duration: Duration(milliseconds: 1500),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        title: Text('Honey Insights', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: HoneyTheme.amberPrimary));
          }
          final data = snapshot.data ?? {};
          final total = data['total'] as int? ?? 0;
          final topApps = data['topApps'] as List<Map<String, dynamic>>? ?? [];
          final weekly = data['weekly'] as List<Map<String, dynamic>>? ?? [];

          return RefreshIndicator(
            onRefresh: () async => _loadStats(),
            color: HoneyTheme.amberPrimary,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  _buildTotalCounter(total),
                  const SizedBox(height: 8),
                  Expanded(child: _buildActivityChart(weekly)),
                  const SizedBox(height: 8),
                  _buildTopSources(topApps),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTotalCounter(int total) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: HoneyTheme.glassBlur, sigmaY: HoneyTheme.glassBlur),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          decoration: BoxDecoration(
            color: HoneyTheme.amberPrimary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: HoneyTheme.amberPrimary.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Honey',
                    style: GoogleFonts.outfit(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    'Captured',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                total.toString(),
                style: GoogleFonts.outfit(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: HoneyTheme.amberPrimary,
                ),
              ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            ],
          ),
        ),
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
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Icon(Icons.star_rounded, size: 16, color: HoneyTheme.amberPrimary),
          ],
        ),
        const SizedBox(height: 12),
        if (apps.isEmpty)
          Text('No data to analyze yet.', style: GoogleFonts.outfit(color: Colors.grey))
        else
          SizedBox(
            height: 75,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: apps.length,
              itemBuilder: (context, index) => _buildAppStatCard(apps[index]),
            ),
          ),
      ],
    );
  }

  Widget _buildAppStatCard(Map<String, dynamic> app) {
    return GestureDetector(
      onTap: () {
        if (widget.onAppSelected != null) {
          widget.onAppSelected!(app['package_name'], app['app_name'] ?? 'Unknown');
        }
      },
      child: Container(
        width: 90,
        margin: const EdgeInsets.only(right: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                    decoration: const BoxDecoration(color: Colors.white10, shape: BoxShape.circle),
                    child: app['icon'] != null
                        ? ClipOval(child: Image.memory(app['icon'], fit: BoxFit.cover))
                        : const Icon(Icons.apps_rounded, size: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    app['app_name'] ?? 'Unknown',
                    style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${app['count']}',
                    style: GoogleFonts.outfit(fontSize: 12, color: HoneyTheme.amberPrimary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  } // End of _buildAppStatCard

  Widget _buildActivityChart(List<Map<String, dynamic>> weekly) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Weekly Bee Activity',
          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: CustomPaint(
              size: Size.infinite,
              painter: WeeklyActivityPainter(weekly),
            ),
          ),
        ),
      ],
    );
  }
}

class WeeklyActivityPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  WeeklyActivityPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final labelStyle = GoogleFonts.outfit(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold);
    final countStyle = GoogleFonts.outfit(color: HoneyTheme.amberPrimary, fontSize: 10, fontWeight: FontWeight.bold);

    // Grouping data by date and priority
    final Map<String, Map<int, int>> dailyPriorityMap = {};
    final Map<String, int> dailyTotalMap = {};

    for (var entry in data) {
      final date = entry['date_label'] as String;
      final priority = entry['priority'] as int? ?? 2;
      final count = entry['count'] as int;

      dailyPriorityMap.putIfAbsent(date, () => {});
      dailyPriorityMap[date]![priority] = (dailyPriorityMap[date]![priority] ?? 0) + count;
      dailyTotalMap[date] = (dailyTotalMap[date] ?? 0) + count;
    }

    final barWidth = size.width / 7;
    final spacing = 12.0;
    
    final now = DateTime.now();
    final List<DateTime> days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));

    double maxCount = 0;
    for (var d in days) {
      final key = DateFormat('yyyy-MM-dd').format(d);
      final total = dailyTotalMap[key] ?? 0;
      if (total > maxCount) maxCount = total.toDouble();
    }
    if (maxCount == 0) maxCount = 1;

    for (int i = 0; i < 7; i++) {
        final d = days[i];
        final key = DateFormat('yyyy-MM-dd').format(d);
        final total = dailyTotalMap[key] ?? 0;
        final priorities = dailyPriorityMap[key] ?? {};

        double currentY = size.height - 30;
        
        // Draw stacked bars for priorities 0 to 3
        for (int p = 0; p <= 3; p++) {
            final count = priorities[p] ?? 0;
            if (count == 0) continue;

            final segmentHeight = (count / maxCount) * (size.height - 40);
            
            final rect = Rect.fromLTWH(
                i * barWidth + spacing / 2,
                currentY - segmentHeight,
                barWidth - spacing,
                segmentHeight,
            );

            final paint = Paint()..style = PaintingStyle.fill;
            
            // Priority colors
            switch (p) {
                case 3: paint.color = Colors.redAccent; break;
                case 2: paint.color = HoneyTheme.amberPrimary; break;
                case 1: paint.color = HoneyTheme.amberPrimary.withOpacity(0.5); break;
                default: paint.color = Colors.grey.withOpacity(0.5); break;
            }

            // Draw rounded rect, but only on top for top segment and bottom for bottom segment?
            // For simplicity, just draw rect or use a path for the whole bar
            canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), paint);
            
            currentY -= segmentHeight;
        }

        // Date labels
        final textPainter = TextPainter(
            text: TextSpan(text: DateFormat('E').format(d), style: labelStyle),
            textDirection: ui.TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(i * barWidth + (barWidth - textPainter.width) / 2, size.height - 20));

        // Total count label on top
        if (total > 0) {
            final totalPainter = TextPainter(
                text: TextSpan(text: total.toString(), style: countStyle),
                textDirection: ui.TextDirection.ltr,
            )..layout();
            totalPainter.paint(canvas, Offset(i * barWidth + (barWidth - totalPainter.width) / 2, currentY - 15));
        }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
    final result = await db.rawQuery('SELECT COUNT(DISTINCT package_name) as count FROM notifications WHERE icon_byte_array IS NOT NULL');
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
        title: Text('Jar Settings', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('System Access'),
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
            onTap: () => NotificationService.requestIgnoreBatteryOptimizations(),
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
            color: Colors.white.withOpacity(0.03),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SwitchListTile(
              secondary: const Icon(Icons.lock_outline_rounded, color: HoneyTheme.amberPrimary),
              title: Text('Biometric Lock', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
              subtitle: Text('Secure your Honey History', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
              value: _isLockEnabled,
              activeColor: HoneyTheme.amberPrimary,
              onChanged: (value) async {
                final success = await SecurityService.authenticate();
                if (success) {
                  await SecurityService.setLockEnabled(value);
                  setState(() {
                    _isLockEnabled = value;
                  });
                  HapticFeedback.mediumImpact();
                } else {
                  // Authentication failed or was canceled, do not change the state
                  debugPrint("Security Policy change rejected: Authentication failed");
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
            color: Colors.white.withOpacity(0.03),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: HoneyTheme.amberPrimary),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HoneyPot v1.1.0', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                          Text('Author: Steve Watkins', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
                          Text('watkins.steve@gmail.com', style: GoogleFonts.outfit(fontSize: 12, color: HoneyTheme.amberPrimary.withOpacity(0.7))),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: Colors.white10),
                  Text(
                    'Crafted for privacy & insight on your S25 Ultra.',
                    style: GoogleFonts.outfit(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
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
        title: Text('Storage Management', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Jar Size: ${_dbSize.toStringAsFixed(2)} MB', style: GoogleFonts.outfit()),
            const SizedBox(height: 8),
            Text('• Textual Honey: ~${(_dbSize * 0.2).toStringAsFixed(2)} MB', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
            Text('• App Icons ($_iconCount): ~${(_dbSize * 0.8).toStringAsFixed(2)} MB', style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            Text(
              'Compacting the jar reclaims space from deleted honey. Icons are high-quality PNGs to keep your UI looking sweet!',
              style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
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
              await DatabaseService().vacuum();
              await _loadSettings();
              if (context.mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Jar compacted successfully!')),
              );
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
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return Card(
      color: Colors.white.withOpacity(0.03),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: Icon(icon, color: color ?? HoneyTheme.amberPrimary),
        title: Text(title, style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: GoogleFonts.outfit(fontSize: 12, color: Colors.grey)),
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
        title: Text('Empty Jar?', style: GoogleFonts.outfit(color: Colors.redAccent)),
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
            child: const Text('EMPTY JAR', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
