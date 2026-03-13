import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BillingService {
  static final BillingService _instance = BillingService._internal();
  static const _channel = MethodChannel('com.example.honeypot/billing');

  factory BillingService() => _instance;

  final ValueNotifier<bool> isPro = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isChecking = ValueNotifier<bool>(true);
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  BillingService._internal() {
    _channel.setMethodCallHandler(_handleMethod);
    _loadPersistedProStatus().then((_) => checkProStatus());
  }

  Future<void> _loadPersistedProStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('debug_pro_override') == true) {
      isPro.value = true;
    }
  }

  Future<void> setProOverride(bool value) async {
    isPro.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('debug_pro_override', value);
  }

  Future<void> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'onProStatusChanged':
        final bool status = call.arguments as bool;
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('debug_pro_override') == true) {
          isPro.value = true;
        } else {
          isPro.value = status;
        }
        break;
      case 'onBillingError':
        final map = call.arguments as Map;
        error.value = map['message'] as String?;
        break;
    }
  }

  Future<void> checkProStatus() async {
    isChecking.value = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('debug_pro_override') == true) {
        isPro.value = true;
      } else {
        final status = await _channel.invokeMethod<bool>('isPro');
        isPro.value = status ?? false;
      }
    } catch (e) {
      debugPrint('Billing Error: $e');
    } finally {
      isChecking.value = false;
    }
  }

  Future<void> launchUpgrade() async {
    try {
      await _channel.invokeMethod('launchBillingFlow');
    } catch (e) {
      error.value = e.toString();
    }
  }

  Future<void> refreshStatus() async {
    try {
      await _channel.invokeMethod('checkProStatus');
    } catch (e) {
      debugPrint('Billing Refresh Error: $e');
    }
  }
}
